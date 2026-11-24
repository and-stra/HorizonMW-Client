#pragma once

// MWX: the RPC methods of the local debug interface (see docs/mcp.md and docs/testing.md).
// debug_server.cpp routes the HTTP requests here; mcp.cpp exposes it as MCP tools.

namespace debug_api
{
	// --- events -------------------------------------------------------------
	void push_event(const std::string& type, const std::string& source, nlohmann::json data);

	// events since a cursor: {cursor, events:[{id, time_ms, type, source, data}]}
	nlohmann::json events(const nlohmann::json& params);

	// waits (on this thread) for a game condition, no client polling:
	// state=main_menu|in_game|server_running|map_loaded|event|menu_open|player_count|dvar
	nlohmann::json wait(const nlohmann::json& params);

	// --- game state ---------------------------------------------------------
	nlohmann::json players();
	nlohmann::json entities(const nlohmann::json& params);
	nlohmann::json bots(const nlohmann::json& params);
	nlohmann::json gsc_eval(const nlohmann::json& params);
	nlohmann::json perf();
	nlohmann::json last_crash();

	// --- input --------------------------------------------------------------
	nlohmann::json input(const nlohmann::json& params);
}
