#pragma once

// MWX: native frame capture (see docs/mcp.md).
//
// The frame is copied from the D3D11 swapchain at Present, so it also works while the game
// window is not focused or is behind other windows.

namespace screenshot
{
	// params: { scale?: 0.5, region?: {x, y, width, height}, path?: "..." }
	// result: { path, width, height, png_base64 }
	nlohmann::json capture(const nlohmann::json& params);
}
