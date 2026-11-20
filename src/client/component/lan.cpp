#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "console.hpp"
#include "lan.hpp"
#include "scheduler.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"

#include <utils/cryptography.hpp>
#include <utils/string.hpp>

// MWX: LAN server discovery.
//
// Every server already answers the connectionless UDP packet "getInfo <challenge>" with
// "infoResponse\n<info string>" (party.cpp). We send that packet from our own UDP socket
// (so this never touches the game's network code or threads):
//   - as a broadcast on every active IPv4 interface (directed broadcast + 255.255.255.255),
//   - to 127.0.0.1 (a server on this PC),
//   - to every address in the mwx_servers dvar (for friends behind a VPN, where broadcasts
//     usually don't arrive), e.g.  set mwx_servers "100.64.0.5 192.168.1.20:27017"
// on the ports mwx_lan_port_min..mwx_lan_port_max, and collect the answers.

namespace lan
{
	namespace
	{
		constexpr std::uint16_t default_port_min = 27016;
		constexpr std::uint16_t default_port_max = 27030;

		game::dvar_t* mwx_servers = nullptr;
		game::dvar_t* mwx_lan_port_min = nullptr;
		game::dvar_t* mwx_lan_port_max = nullptr;

		struct winsock_init
		{
			winsock_init()
			{
				WSADATA data{};
				WSAStartup(MAKEWORD(2, 2), &data);
			}
		};

		std::string to_string(const sockaddr_in& addr)
		{
			char ip[INET_ADDRSTRLEN]{};
			inet_ntop(AF_INET, &addr.sin_addr, ip, sizeof(ip));
			return utils::string::va("%s:%u", ip, ntohs(addr.sin_port));
		}

		sockaddr_in make_addr(const in_addr ip, const std::uint16_t port)
		{
			sockaddr_in addr{};
			addr.sin_family = AF_INET;
			addr.sin_addr = ip;
			addr.sin_port = htons(port);
			return addr;
		}

		std::pair<std::uint16_t, std::uint16_t> get_port_range()
		{
			auto min = mwx_lan_port_min ? mwx_lan_port_min->current.integer : default_port_min;
			auto max = mwx_lan_port_max ? mwx_lan_port_max->current.integer : default_port_max;
			if (max < min)
			{
				std::swap(min, max);
			}
			max = std::min(max, min + 63); // keep the packet count sane
			return {static_cast<std::uint16_t>(min), static_cast<std::uint16_t>(max)};
		}

		// IPv4 address + broadcast address of every interface that is up (loopback excluded)
		std::vector<std::pair<in_addr, in_addr>> get_interfaces()
		{
			std::vector<std::pair<in_addr, in_addr>> result{};

			ULONG size = 16 * 1024;
			std::vector<std::uint8_t> buffer{};
			ULONG status = ERROR_BUFFER_OVERFLOW;
			for (auto i = 0; i < 3 && status == ERROR_BUFFER_OVERFLOW; ++i)
			{
				buffer.resize(size);
				status = GetAdaptersAddresses(AF_INET,
					GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
					nullptr, reinterpret_cast<PIP_ADAPTER_ADDRESSES>(buffer.data()), &size);
			}

			if (status != NO_ERROR)
			{
				return result;
			}

			for (auto* adapter = reinterpret_cast<PIP_ADAPTER_ADDRESSES>(buffer.data()); adapter; adapter = adapter->Next)
			{
				if (adapter->OperStatus != IfOperStatusUp || adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK)
				{
					continue;
				}

				for (auto* unicast = adapter->FirstUnicastAddress; unicast; unicast = unicast->Next)
				{
					if (!unicast->Address.lpSockaddr || unicast->Address.lpSockaddr->sa_family != AF_INET)
					{
						continue;
					}

					const auto ip = reinterpret_cast<sockaddr_in*>(unicast->Address.lpSockaddr)->sin_addr;
					const auto prefix = unicast->OnLinkPrefixLength;
					const auto mask = prefix == 0 ? 0u : htonl(0xFFFFFFFFu << (32 - std::min<ULONG>(prefix, 32)));

					in_addr broadcast{};
					broadcast.s_addr = (ip.s_addr & mask) | ~mask;
					result.emplace_back(ip, broadcast);
				}
			}

			return result;
		}

		// "a.b.c.d" or "a.b.c.d:port" (host names are resolved too)
		std::vector<sockaddr_in> parse_targets(const std::string& list, const std::uint16_t port_min, const std::uint16_t port_max)
		{
			std::vector<sockaddr_in> result{};
			auto entries = utils::string::split(utils::string::replace(list, ",", " "), ' ');

			for (auto& entry : entries)
			{
				entry.erase(0, entry.find_first_not_of(" \t"));
				entry.erase(entry.find_last_not_of(" \t") + 1);
				if (entry.empty())
				{
					continue;
				}

				std::string host = entry;
				std::optional<std::uint16_t> port{};
				if (const auto colon = entry.find(':'); colon != std::string::npos)
				{
					host = entry.substr(0, colon);
					port = static_cast<std::uint16_t>(std::atoi(entry.substr(colon + 1).data()));
				}

				addrinfo hints{};
				hints.ai_family = AF_INET;
				hints.ai_socktype = SOCK_DGRAM;
				addrinfo* info = nullptr;
				if (getaddrinfo(host.data(), nullptr, &hints, &info) != 0 || !info)
				{
					console::warn("mwx_servers: can't resolve \"%s\"\n", host.data());
					continue;
				}

				const auto ip = reinterpret_cast<sockaddr_in*>(info->ai_addr)->sin_addr;
				freeaddrinfo(info);

				if (port.has_value())
				{
					result.emplace_back(make_addr(ip, *port));
				}
				else
				{
					for (auto p = port_min; p <= port_max; ++p)
					{
						result.emplace_back(make_addr(ip, p));
					}
				}
			}

			return result;
		}

		std::vector<server_response> run_query(const std::vector<sockaddr_in>& targets,
			const std::chrono::milliseconds timeout, const bool stop_after_first)
		{
			static winsock_init _;
			std::vector<server_response> responses{};

			const auto sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
			if (sock == INVALID_SOCKET)
			{
				console::error("lan: can't create socket (%d)\n", WSAGetLastError());
				return responses;
			}

			const auto _close = gsl::finally([&]()
			{
				closesocket(sock);
			});

			BOOL enable = TRUE;
			setsockopt(sock, SOL_SOCKET, SO_BROADCAST, reinterpret_cast<const char*>(&enable), sizeof(enable));

			in_addr any{};
			any.s_addr = INADDR_ANY;
			auto bind_addr = make_addr(any, 0);
			bind(sock, reinterpret_cast<sockaddr*>(&bind_addr), sizeof(bind_addr));

			const auto challenge = utils::cryptography::random::get_challenge();
			const auto packet = "\xFF\xFF\xFF\xFFgetInfo "s + challenge;

			const auto start = std::chrono::steady_clock::now();
			for (const auto& target : targets)
			{
				sendto(sock, packet.data(), static_cast<int>(packet.size()), 0,
					reinterpret_cast<const sockaddr*>(&target), sizeof(target));
			}

			std::unordered_set<std::string> seen{};
			char buffer[2048];

			while (true)
			{
				const auto elapsed = std::chrono::steady_clock::now() - start;
				if (elapsed >= timeout)
				{
					break;
				}

				const auto left = std::chrono::duration_cast<std::chrono::microseconds>(timeout - elapsed);
				timeval tv{};
				tv.tv_sec = static_cast<long>(left.count() / 1000000);
				tv.tv_usec = static_cast<long>(left.count() % 1000000);

				fd_set read_set{};
				FD_ZERO(&read_set);
				FD_SET(sock, &read_set);
				if (select(0, &read_set, nullptr, nullptr, &tv) <= 0)
				{
					break;
				}

				sockaddr_in from{};
				int from_len = sizeof(from);
				const auto len = recvfrom(sock, buffer, sizeof(buffer) - 1, 0, reinterpret_cast<sockaddr*>(&from), &from_len);
				if (len <= 4)
				{
					continue;
				}

				const std::string data(buffer, len);
				constexpr std::string_view header = "\xFF\xFF\xFF\xFFinfoResponse";
				if (data.size() <= header.size() + 1 || !data.starts_with(header))
				{
					continue;
				}

				const auto ping = std::chrono::duration_cast<std::chrono::milliseconds>(
					std::chrono::steady_clock::now() - start).count();

				server_response response{};
				response.info = utils::info_string{data.substr(header.size() + 1)};
				if (response.info.get("challenge") != challenge)
				{
					continue;
				}

				response.connect_address = to_string(from);
				if (!seen.emplace(response.connect_address).second)
				{
					continue;
				}

				if (!game::NET_StringToAdr(response.connect_address.data(), &response.address))
				{
					continue;
				}

				response.ping = static_cast<int>(std::min<long long>(ping, 999));
				responses.emplace_back(std::move(response));

				if (stop_after_first)
				{
					break;
				}
			}

			return responses;
		}
	}

	std::vector<server_response> discover(const std::chrono::milliseconds timeout)
	{
		const auto [port_min, port_max] = get_port_range();
		const auto interfaces = get_interfaces();

		std::vector<sockaddr_in> targets{};
		std::unordered_set<std::uint32_t> broadcasts{};

		in_addr limited_broadcast{};
		limited_broadcast.s_addr = INADDR_BROADCAST;
		broadcasts.emplace(limited_broadcast.s_addr);

		in_addr loopback{};
		inet_pton(AF_INET, "127.0.0.1", &loopback);

		for (const auto& [ip, broadcast] : interfaces)
		{
			broadcasts.emplace(broadcast.s_addr);
		}

		for (auto port = port_min; port <= port_max; ++port)
		{
			for (const auto broadcast : broadcasts)
			{
				in_addr addr{};
				addr.s_addr = broadcast;
				targets.emplace_back(make_addr(addr, port));
			}

			targets.emplace_back(make_addr(loopback, port));
		}

		if (mwx_servers && mwx_servers->current.string && *mwx_servers->current.string)
		{
			const auto extra = parse_targets(mwx_servers->current.string, port_min, port_max);
			targets.insert(targets.end(), extra.begin(), extra.end());
		}

		auto responses = run_query(targets, timeout, false);

		// A server on this PC answers on 127.0.0.1 and on our LAN address. Keep the LAN
		// address (friends can use it too) and drop the loopback duplicate.
		std::unordered_set<std::string> own_addresses{};
		for (const auto& [ip, _] : interfaces)
		{
			char text[INET_ADDRSTRLEN]{};
			inet_ntop(AF_INET, &ip, text, sizeof(text));
			own_addresses.emplace(text);
		}

		std::unordered_set<std::string> own_ports_seen{};
		for (const auto& response : responses)
		{
			const auto colon = response.connect_address.find(':');
			const auto host = response.connect_address.substr(0, colon);
			if (own_addresses.contains(host))
			{
				own_ports_seen.emplace(response.connect_address.substr(colon + 1));
			}
		}

		std::erase_if(responses, [&](const server_response& response)
		{
			const auto colon = response.connect_address.find(':');
			return response.connect_address.substr(0, colon) == "127.0.0.1"
				&& own_ports_seen.contains(response.connect_address.substr(colon + 1));
		});

		return responses;
	}

	std::optional<server_response> query(const game::netadr_s& address, const std::chrono::milliseconds timeout)
	{
		sockaddr_in target{};
		target.sin_family = AF_INET;
		std::memcpy(&target.sin_addr, address.ip, 4);
		target.sin_port = address.port; // netadr_s keeps the port in network byte order

		if (address.type == game::NA_LOOPBACK)
		{
			inet_pton(AF_INET, "127.0.0.1", &target.sin_addr);
		}

		auto responses = run_query({target}, timeout, true);
		if (responses.empty())
		{
			return {};
		}

		return std::move(responses.front());
	}

	nlohmann::json to_json(const server_response& response)
	{
		nlohmann::json json = nlohmann::json::object();
		for (const auto& [key, value] : response.info.get_all())
		{
			json[key] = value;
		}

		json["ping"] = std::to_string(response.ping);
		json["connect_address"] = response.connect_address;
		return json;
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_dedi())
			{
				return;
			}

			// String dvars keep their value as a script string, so they can only be registered
			// once the game is up (registering in post_unpack fails with MT_AllocIndex).
			scheduler::once([]()
			{
				mwx_servers = dvars::register_string("mwx_servers", "", game::DVAR_FLAG_SAVED,
					"Extra server addresses for the server browser, separated by spaces (\"ip\" or \"ip:port\"), e.g. friends behind a VPN");
				mwx_lan_port_min = dvars::register_int("mwx_lan_port_min", default_port_min, 1, 65535, game::DVAR_FLAG_SAVED,
					"Lowest port the server browser searches on the LAN");
				mwx_lan_port_max = dvars::register_int("mwx_lan_port_max", default_port_max, 1, 65535, game::DVAR_FLAG_SAVED,
					"Highest port the server browser searches on the LAN");
			}, scheduler::pipeline::main);
		}
	};
}

REGISTER_COMPONENT(lan::component)
