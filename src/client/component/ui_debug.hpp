#pragma once

// MWX: LUI (menu) access for the test interface (see docs/mcp.md).
// The heavy lifting is in data/mwx/ui_scripts/mwx_debug/__init__.lua, which is only loaded
// with the other MWX ui_scripts and does nothing until one of these methods is called.

namespace ui_debug
{
	// visible menu elements as a tree: {menus:[{name, visible, focused, elements:[...]}]}
	nlohmann::json snapshot();

	// params: { id?: string, text?: string, index?: int } - the element's button_action path
	nlohmann::json click(const nlohmann::json& params);

	nlohmann::json back();

	// params: { name: string } - menu name as used by LUI.FlowManager.RequestAddMenu
	nlohmann::json open(const nlohmann::json& params);

	// params: { code: string } -> {ok, result, error}
	nlohmann::json lua_eval(const nlohmann::json& params);

	bool is_menu_open(const std::string& name);
}
