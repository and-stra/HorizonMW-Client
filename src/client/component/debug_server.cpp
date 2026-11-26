#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "command.hpp"
#include "console.hpp"
#include "debug_api.hpp"
#include "debug_server.hpp"
#include "party.hpp"
#include "scheduler.hpp"
#include "screenshot.hpp"
#include "ui_debug.hpp"

#include "game/game.hpp"

#include <utils/flags.hpp>
#include <utils/io.hpp>
#include <utils/string.hpp>

#include <mongoose.h>

// MWX: a small local debug interface (127.0.0.1 only) so tools (the MCP bridge in
// `mwx.exe -mcp`, opencode, curl) can look at the running game.
//
//   POST http://127.0.0.1:27099/rpc   {"method": "...", "params": {...}}
//   -> {"result": ...} or {"error": "..."}
//
// Methods: status, get_dvar, set_dvar, command, console, load_times.
// Game state is read on the game's main thread (2 s timeout while the game is busy loading).

namespace debug_server
{
	namespace
	{
		using json = nlohmann::json;
		const auto started = std::chrono::steady_clock::now();

		std::atomic_bool stop{false};
		std::thread server_thread;

		// runs `fn` on `pipeline` and waits for it
		json on_pipeline(const scheduler::pipeline pipeline, const std::function<json()>& fn,
			const std::chrono::milliseconds timeout)
		{
			auto promise = std::make_shared<std::promise<json>>();
			auto future = promise->get_future();

			scheduler::once([promise, fn]()
			{
				try
				{
					promise->set_value(fn());
				}
				catch (const std::exception& e)
				{
					promise->set_value(json{{"error", e.what()}});
				}
			}, pipeline);

			if (future.wait_for(timeout) != std::future_status::ready)
			{
				return json{{"error", "the game's main thread is busy (loading?), try again"}};
			}

			return future.get();
		}

		// runs `fn` on the game's main thread and waits for it
		json on_main_thread(const std::function<json()>& fn, const std::chrono::milliseconds timeout = 2000ms)
		{
			return on_pipeline(scheduler::pipeline::main, fn, timeout);
		}

		bool is_busy(const json& result)
		{
			return result.is_object() && result.contains("error") && result["error"].is_string()
				&& result["error"].get<std::string>().find("main thread is busy") != std::string::npos;
		}

		// --- cached game status: answered even while the main thread is loading a zone ---

		std::mutex status_mutex;
		json status_cache = json::object();
		std::chrono::steady_clock::time_point status_time{};
		bool status_valid = false;

		void store_status(const json& status)
		{
			std::lock_guard<std::mutex> lock(status_mutex);
			status_cache = status;
			status_time = std::chrono::steady_clock::now();
			status_valid = true;
		}

		json cached_status(long long& age_ms)
		{
			std::lock_guard<std::mutex> lock(status_mutex);
			if (!status_valid)
			{
				age_ms = -1;
				return json::object();
			}

			age_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
				std::chrono::steady_clock::now() - status_time).count();
			return status_cache;
		}

		// --- waiting for menu actions (ui_click / ui_open / ui_back / wait_ready) ---

		int action_count()
		{
			const auto value = ui_debug::actions();
			return value.is_array() ? static_cast<int>(value.size()) : 0;
		}

		// true when the main thread answers a no-op: no zone load in progress. A menu can be
		// visible while the scene behind it still loads; clicking into that state crashed HMW.
		bool wait_engine_ready(const std::chrono::milliseconds timeout)
		{
			const auto deadline = std::chrono::steady_clock::now() + timeout;

			for (;;)
			{
				const auto value = on_pipeline(scheduler::pipeline::main, [] { return json::object(); }, 400ms);
				if (!is_busy(value))
				{
					return true;
				}

				if (std::chrono::steady_clock::now() >= deadline)
				{
					return false;
				}

				std::this_thread::sleep_for(20ms);
			}
		}

		std::string current_menu()
		{
			const auto value = ui_debug::menu();
			if (value.is_object() && value.contains("menu") && value["menu"].is_string())
			{
				return value["menu"].get<std::string>();
			}
			return {};
		}

		// waits until the queued click has actually run (the Lua queue appends a result)
		bool wait_action(const int before, const std::chrono::milliseconds timeout)
		{
			const auto deadline = std::chrono::steady_clock::now() + timeout;

			for (;;)
			{
				const auto value = on_pipeline(scheduler::pipeline::lui,
					[] { return json{{"result", action_count()}}; }, 400ms);

				if (!is_busy(value) && value.contains("result") && value["result"].is_number_integer()
					&& value["result"].get<int>() > before)
				{
					return true;
				}

				if (std::chrono::steady_clock::now() >= deadline)
				{
					return false;
				}

				std::this_thread::sleep_for(10ms);
			}
		}

		// waits for a menu name and/or an element; `menu_out` gets the last menu seen
		bool wait_menu(const std::string& expect_menu, const std::string& expect_element,
			const std::chrono::milliseconds timeout, std::string& menu_out)
		{
			const auto deadline = std::chrono::steady_clock::now() + timeout;

			for (;;)
			{
				const auto value = on_pipeline(scheduler::pipeline::lui, [&]
				{
					json info{{"menu", current_menu()}};
					if (!expect_element.empty())
					{
						info["found"] = ui_debug::has_element(expect_element).value("found", false);
					}
					return json{{"result", info}};
				}, 500ms);

				if (!is_busy(value) && value.contains("result"))
				{
					const auto& info = value["result"];
					menu_out = info.value("menu", "");

					const auto menu_ok = expect_menu.empty() || menu_out == expect_menu;
					const auto element_ok = expect_element.empty() || info.value("found", false);
					if (menu_ok && element_ok)
					{
						return true;
					}
				}

				if (std::chrono::steady_clock::now() >= deadline)
				{
					return false;
				}

				std::this_thread::sleep_for(20ms);
			}
		}

		int int_param(const json& params, const char* name, const int fallback, const int minimum, const int maximum)
		{
			if (!params.contains(name) || !params[name].is_number_integer())
			{
				return fallback;
			}
			return std::clamp(params[name].get<int>(), minimum, maximum);
		}

		std::string dvar_string(const char* name)
		{
			auto* dvar = game::Dvar_FindVar(name);
			if (!dvar)
			{
				return {};
			}

			const auto* value = game::Dvar_ValueToString(dvar, true, dvar->current);
			return value ? value : "";
		}

		const char* team_name(const int team)
		{
			switch (team)
			{
			case game::TEAM_AXIS: return "axis";
			case game::TEAM_ALLIES: return "allies";
			case game::TEAM_SPECTATOR: return "spectator";
			default: return "free";
			}
		}

		json get_status()
		{
			json result{};
			result["mode"] = game::environment::is_dedi() ? "dedicated" : "client";
			result["uptime_ms"] = std::chrono::duration_cast<std::chrono::milliseconds>(
				std::chrono::steady_clock::now() - started).count();
			result["map"] = dvar_string("mapname");
			result["gametype"] = dvar_string("g_gametype");
			result["hostname"] = dvar_string("sv_hostname");
			result["net_port"] = dvar_string("net_port");
			const auto* sv_running = game::Dvar_FindVar("sv_running");
			result["sv_running"] = sv_running && sv_running->current.enabled;

			const auto vlobby = game::VirtualLobby_Loaded();
			// HMW's offline/LAN menu is the LUI frontend: it is shown without loading the
			// virtual lobby (virtualLobbyActive stays 0) and Com_InFrontend() stays false.
			// The LUI Lua state + a ready database mean the menu is up and the game is usable.
			const auto frontend = game::Com_InFrontend();
			const auto lui = *game::hks::lua_state != nullptr;
			const auto db_ready = game::Sys_IsDatabaseReady2();
			const auto in_game = !game::environment::is_dedi() && game::CL_IsCgameInitialized() && !vlobby;
			result["virtual_lobby"] = vlobby;
			result["frontend"] = frontend;
			result["lui"] = lui;
			result["db_ready"] = db_ready;
			// A dedicated server always runs a map; its LUI state must not count as a menu.
			result["main_menu"] = !game::environment::is_dedi() && !in_game
				&& (vlobby || frontend || (lui && db_ready));

			if (!game::environment::is_dedi())
			{
				result["in_game"] = in_game;
				const auto state = party::get_server_connection_state();
				if (state.hostDefined)
				{
					result["server"] = utils::string::va("%u.%u.%u.%u:%u", state.host.ip[0], state.host.ip[1],
						state.host.ip[2], state.host.ip[3], ntohs(state.host.port));
				}
			}

			// players: only known where the server runs (dedicated server or the host of a match)
			json players = json::array();
			const auto* clients = *game::svs_clients;
			if (clients && result["sv_running"].get<bool>() && !vlobby)
			{
				const auto count = std::min(*game::svs_numclients, 32);
				for (auto i = 0; i < count; ++i)
				{
					const auto& client = clients[i];
					if (client.header.state < 5 || !client.gentity || !client.gentity->client)
					{
						continue;
					}

					const auto* ent = client.gentity;
					json player{};
					player["num"] = i;
					player["name"] = client.name;
					player["bot"] = game::SV_BotIsBot(i);
					player["team"] = team_name(ent->client->team);
					player["score"] = game::G_GetClientScore(i);
					player["ping"] = game::SV_GetClientPing(i);
					player["origin"] = {ent->origin[0], ent->origin[1], ent->origin[2]};
					players.emplace_back(std::move(player));
				}
			}

			result["players"] = std::move(players);
			return result;
		}

		json handle(const std::string& method, const json& params)
		{
			if (method == "status")
			{
				// answer from the cache unless it is older than the 1 s updater; only then
				// ask the main thread, and fall back to the (stale) cache while it loads
				long long age_ms = -1;
				auto cache = cached_status(age_ms);
				if (!cache.empty() && age_ms >= 0 && age_ms <= 1000)
				{
					return json{{"result", cache}};
				}

				auto result = on_main_thread([] { return json{{"result", get_status()}}; }, 250ms);

				if (!is_busy(result))
				{
					if (result.contains("result"))
					{
						store_status(result["result"]);
					}
					return result;
				}

				if (!cache.empty())
				{
					cache["stale_ms"] = age_ms;
					return json{{"result", cache}};
				}

				return result;
			}

			if (method == "get_dvar")
			{
				const auto name = params.value("name", "");
				return on_main_thread([name]
				{
					auto* dvar = game::Dvar_FindVar(name.data());
					if (!dvar)
					{
						return json{{"error", "no such dvar: " + name}};
					}
					return json{{"result", {{"name", name}, {"value", dvar_string(name.data())}}}};
				});
			}

			if (method == "set_dvar")
			{
				const auto name = params.value("name", "");
				const auto value = params.value("value", "");
				if (name.empty() || name.find_first_of(" ;\"\n") != std::string::npos)
				{
					return json{{"error", "invalid dvar name"}};
				}
				command::execute(utils::string::va("set %s \"%s\"", name.data(), value.data()), false);
				return json{{"result", "ok"}};
			}

			if (method == "command")
			{
				const auto cmd = params.value("command", "");
				if (cmd.empty())
				{
					return json{{"error", "command is empty"}};
				}
				command::execute(cmd, false);
				return json{{"result", "queued: " + cmd}};
			}

			if (method == "console")
			{
				const auto lines = params.value("lines", 100);
				const auto filter = utils::string::to_lower(params.value("filter", ""));
				json result = json::array();
				for (auto& line : console::get_recent_lines(std::clamp(lines, 1, 1000)))
				{
					if (!filter.empty() && utils::string::to_lower(line).find(filter) == std::string::npos)
					{
						continue;
					}
					while (!line.empty() && (line.back() == '\n' || line.back() == '\r'))
					{
						line.pop_back();
					}
					result.emplace_back(line);
				}
				return json{{"result", result}};
			}

			if (method == "load_times")
			{
				std::string data{};
				utils::io::read_file("mwx-logs/load_times.log", &data);
				// only the latest start
				if (const auto pos = data.rfind("==== MWX start"); pos != std::string::npos)
				{
					data = data.substr(pos);
				}
				return json{{"result", data}};
			}

			// --- MWX test interface (docs/mcp.md) ---

			if (method == "screenshot")
			{
				return json{{"result", screenshot::capture(params)}};
			}

			if (method == "ui_snapshot")
			{
				return on_pipeline(scheduler::pipeline::lui, [] { return json{{"result", ui_debug::snapshot()}}; }, 5000ms);
			}

			if (method == "ui_click")
			{
				const auto wait = params.value("wait", true);
				const auto timeout = std::chrono::milliseconds(int_param(params, "timeout_ms", 15000, 100, 50000));
				const auto expect_timeout = std::chrono::milliseconds(int_param(params, "expect_timeout_ms", 8000, 100, 20000));
				const auto started = std::chrono::steady_clock::now();

				if (wait)
				{
					wait_engine_ready(timeout);
				}

				int before = 0;
				const auto count = on_pipeline(scheduler::pipeline::lui,
					[] { return json{{"result", action_count()}}; }, timeout);
				if (is_busy(count))
				{
					return count;
				}
				if (count.contains("result") && count["result"].is_number_integer())
				{
					before = count["result"].get<int>();
				}

				auto result = on_pipeline(scheduler::pipeline::lui,
					[params] { return json{{"result", ui_debug::click(params)}}; }, timeout);
				if (!wait || is_busy(result) || !result.contains("result"))
				{
					return result;
				}

				auto info = result["result"];
				const auto processed = wait_action(before, expect_timeout);

				std::string menu;
				auto expected = true;
				if (processed)
				{
					expected = wait_menu(params.value("expect_menu", ""), params.value("expect_element", ""),
						expect_timeout, menu);
				}

				const auto engine_ready = processed && wait_engine_ready(expect_timeout);

				info["processed"] = processed;
				info["expect_met"] = expected;
				info["engine_ready"] = engine_ready;
				info["menu"] = menu;
				info["waited_ms"] = std::chrono::duration_cast<std::chrono::milliseconds>(
					std::chrono::steady_clock::now() - started).count();
				return json{{"result", info}};
			}

			if (method == "ui_back")
			{
				const auto wait = params.value("wait", true);
				const auto timeout = std::chrono::milliseconds(int_param(params, "timeout_ms", 15000, 100, 50000));
				const auto expect_timeout = std::chrono::milliseconds(int_param(params, "expect_timeout_ms", 8000, 100, 20000));
				const auto started = std::chrono::steady_clock::now();

				if (wait)
				{
					wait_engine_ready(timeout);
				}

				int before = 0;
				std::string previous_menu;
				const auto initial = on_pipeline(scheduler::pipeline::lui, [&]
				{
					return json{{"result", {{"count", action_count()}, {"menu", current_menu()}}}};
				}, timeout);
				if (is_busy(initial))
				{
					return initial;
				}
				if (initial.contains("result"))
				{
					before = initial["result"].value("count", 0);
					previous_menu = initial["result"].value("menu", "");
				}

				auto result = on_pipeline(scheduler::pipeline::lui,
					[] { return json{{"result", ui_debug::back()}}; }, timeout);
				if (!wait || is_busy(result) || !result.contains("result"))
				{
					return result;
				}

				auto info = result["result"];
				const auto processed = wait_action(before, expect_timeout);

				std::string menu = previous_menu;
				const auto deadline = std::chrono::steady_clock::now() + expect_timeout;
				while (processed && std::chrono::steady_clock::now() < deadline)
				{
					const auto value = on_pipeline(scheduler::pipeline::lui,
						[] { return json{{"result", current_menu()}}; }, 500ms);
					if (!is_busy(value) && value.contains("result"))
					{
						menu = value["result"].get<std::string>();
						if (menu != previous_menu)
						{
							break;
						}
					}
					std::this_thread::sleep_for(20ms);
				}

				info["processed"] = processed;
				info["menu"] = menu;
				info["engine_ready"] = processed && wait_engine_ready(expect_timeout);
				info["waited_ms"] = std::chrono::duration_cast<std::chrono::milliseconds>(
					std::chrono::steady_clock::now() - started).count();
				return json{{"result", info}};
			}

			if (method == "ui_open")
			{
				const auto wait = params.value("wait", true);
				const auto name = params.value("name", "");
				if (name.empty())
				{
					return json{{"error", "name is required"}};
				}
				const auto timeout = std::chrono::milliseconds(int_param(params, "timeout_ms", 15000, 100, 50000));
				const auto expect_timeout = std::chrono::milliseconds(int_param(params, "expect_timeout_ms", 8000, 100, 20000));
				const auto started = std::chrono::steady_clock::now();

				if (wait)
				{
					wait_engine_ready(timeout);
				}

				int before = 0;
				const auto count = on_pipeline(scheduler::pipeline::lui,
					[] { return json{{"result", action_count()}}; }, timeout);
				if (is_busy(count))
				{
					return count;
				}
				if (count.contains("result") && count["result"].is_number_integer())
				{
					before = count["result"].get<int>();
				}

				auto result = on_pipeline(scheduler::pipeline::lui,
					[params] { return json{{"result", ui_debug::open(params)}}; }, timeout);
				if (!wait || is_busy(result) || !result.contains("result"))
				{
					return result;
				}

				auto info = result["result"];
				const auto processed = wait_action(before, expect_timeout);

				std::string menu;
				auto opened = false;
				if (processed)
				{
					opened = wait_menu(name, params.value("expect_element", ""), expect_timeout, menu);
				}

				info["processed"] = processed;
				info["opened"] = opened;
				info["engine_ready"] = processed && wait_engine_ready(expect_timeout);
				info["menu"] = menu;
				info["waited_ms"] = std::chrono::duration_cast<std::chrono::milliseconds>(
					std::chrono::steady_clock::now() - started).count();
				return json{{"result", info}};
			}

			if (method == "wait_ready")
			{
				const auto timeout = std::chrono::milliseconds(int_param(params, "timeout_ms", 10000, 100, 55000));
				const auto started = std::chrono::steady_clock::now();
				const auto deadline = started + timeout;

				for (;;)
				{
					const auto value = on_pipeline(scheduler::pipeline::lui,
						[] { return json{{"result", ui_debug::menu()}}; }, 400ms);

					if (!is_busy(value))
					{
						auto info = value.contains("result") ? value["result"] : json::object();
						info["ready"] = true;
						info["waited_ms"] = std::chrono::duration_cast<std::chrono::milliseconds>(
							std::chrono::steady_clock::now() - started).count();
						return json{{"result", info}};
					}

					if (std::chrono::steady_clock::now() >= deadline)
					{
						long long age_ms = -1;
						const auto cache = cached_status(age_ms);
						json info{{"ready", false}, {"waited_ms", timeout.count()}};
						if (!cache.empty())
						{
							info["status"] = cache;
							info["stale_ms"] = age_ms;
						}
						return json{{"result", info}};
					}

					std::this_thread::sleep_for(50ms);
				}
			}

			if (method == "lua_eval")
			{
				return on_pipeline(scheduler::pipeline::lui, [params] { return json{{"result", ui_debug::lua_eval(params)}}; }, 10000ms);
			}

			if (method == "gsc_eval")
			{
				return on_pipeline(scheduler::pipeline::server, [params] { return json{{"result", debug_api::gsc_eval(params)}}; }, 30000ms);
			}

			if (method == "players")
			{
				return on_pipeline(scheduler::pipeline::server, [] { return json{{"result", debug_api::players()}}; }, 10000ms);
			}

			if (method == "entities")
			{
				return on_pipeline(scheduler::pipeline::server, [params] { return json{{"result", debug_api::entities(params)}}; }, 10000ms);
			}

			if (method == "model_bounds")
			{
				return on_pipeline(scheduler::pipeline::server, [params] { return json{{"result", debug_api::model_bounds(params)}}; }, 30000ms);
			}

			if (method == "bots")
			{
				return on_pipeline(scheduler::pipeline::server, [params] { return json{{"result", debug_api::bots(params)}}; }, 15000ms);
			}

			if (method == "input")
			{
				return on_main_thread([params] { return json{{"result", debug_api::input(params)}}; });
			}

			if (method == "events")
			{
				return json{{"result", debug_api::events(params)}};
			}

			if (method == "wait")
			{
				return debug_api::wait(params);
			}

			if (method == "perf")
			{
				return on_main_thread([] { return json{{"result", debug_api::perf()}}; });
			}

			if (method == "last_crash")
			{
				return json{{"result", debug_api::last_crash()}};
			}

			return json{{"error", "unknown method: " + method}};
		}

		void on_http(mg_connection* c, const int ev, void* ev_data)
		{
			if (ev != MG_EV_HTTP_MSG)
			{
				return;
			}

			auto* hm = static_cast<mg_http_message*>(ev_data);
			if (!mg_match(hm->uri, mg_str("/rpc"), nullptr))
			{
				mg_http_reply(c, 404, "Content-Type: application/json\r\n", "%s", R"({"error":"use POST /rpc"})");
				return;
			}

			json response{};
			try
			{
				const auto request = json::parse(std::string(hm->body.buf, hm->body.len));
				response = handle(request.value("method", ""), request.value("params", json::object()));
			}
			catch (const std::exception& e)
			{
				response = json{{"error", std::string("bad request: ") + e.what()}};
			}

			const auto body = response.dump(-1, ' ', false, json::error_handler_t::replace);
			mg_http_reply(c, 200, "Content-Type: application/json\r\n", "%s", body.data());
		}

		std::uint16_t get_port()
		{
			if (const auto flag = utils::flags::get_flag("debugport"); flag.has_value())
			{
				return static_cast<std::uint16_t>(std::atoi(flag->data()));
			}

			return game::environment::is_dedi() ? default_server_port : default_client_port;
		}
	}

	json run_on(const std::function<json()>& fn, const scheduler::pipeline pipeline,
		const std::chrono::milliseconds timeout)
	{
		return on_pipeline(pipeline, fn, timeout);
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			const auto port = get_port();
			if (port == 0)
			{
				return;
			}

			server_thread = std::thread([port]()
			{
				mg_mgr mgr{};
				mg_mgr_init(&mgr);

				const auto url = utils::string::va("http://127.0.0.1:%u", port);
				if (!mg_http_listen(&mgr, url, on_http, nullptr))
				{
					console::warn("debug server: can't listen on %s\n", url);
					mg_mgr_free(&mgr);
					return;
				}

				console::info("debug server: %s/rpc\n", url);
				while (!stop)
				{
					mg_mgr_poll(&mgr, 100);
				}

				mg_mgr_free(&mgr);
			});

			// The status cache is filled by successful status calls (see handle("status")).
			// No background sampler: calling get_status() on a timer during the first seconds
			// of a start raced engine initialization (0xC0000005 at offset 0, no dump).
		}

		void pre_destroy() override
		{
			stop = true;
			if (server_thread.joinable())
			{
				server_thread.join();
			}
		}
	};
}

REGISTER_COMPONENT(debug_server::component)
