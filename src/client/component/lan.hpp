#pragma once

#include "game/game.hpp"
#include <utils/info_string.hpp>

// MWX: finding and querying game servers on the local network (UDP), replacing
// HorizonMW's master server and HTTP /getInfo.
namespace lan
{
	struct server_response
	{
		game::netadr_s address{};
		std::string connect_address; // "ip:port"
		utils::info_string info;
		int ping = 999;
	};

	// Broadcasts getInfo on every network interface (and to the addresses in the
	// mwx_servers dvar) and collects the answers until the timeout.
	std::vector<server_response> discover(std::chrono::milliseconds timeout = 1000ms);

	// Asks one server for its info. Empty if it doesn't answer in time.
	std::optional<server_response> query(const game::netadr_s& address, std::chrono::milliseconds timeout = 1500ms);

	// The info as JSON, with the same keys HorizonMW's HTTP /getInfo had (all values strings, plus "ping").
	nlohmann::json to_json(const server_response& response);
}
