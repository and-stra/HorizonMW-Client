#pragma once

namespace debug_server
{
	// Local port of the debug interface: client 27099, dedicated server 27098, or -debugport <n>
	constexpr std::uint16_t default_client_port = 27099;
	constexpr std::uint16_t default_server_port = 27098;
}
