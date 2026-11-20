#pragma once

namespace mcp
{
	// `mwx.exe -mcp`: runs an MCP server on stdin/stdout (for Claude, opencode, ...) that
	// starts/stops the game and talks to the debug interface of running instances.
	int run();
}
