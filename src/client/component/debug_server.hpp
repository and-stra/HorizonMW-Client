#pragma once

#include "scheduler.hpp"

namespace debug_server
{
	// Local port of the debug interface: client 27099, dedicated server 27098, or -debugport <n>
	constexpr std::uint16_t default_client_port = 27099;
	constexpr std::uint16_t default_server_port = 27098;

	// Runs `fn` on the given scheduler pipeline (main by default) and waits for the result.
	// Used by the debug RPC methods that must touch game state (see component/debug_api.cpp).
	nlohmann::json run_on(const std::function<nlohmann::json()>& fn,
		scheduler::pipeline pipeline = scheduler::pipeline::main,
		std::chrono::milliseconds timeout = 2000ms);
}
