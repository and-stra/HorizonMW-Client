#pragma once

#include "game/ui_scripting/script_value.hpp"

namespace ui_scripting
{
	template <class... Args, std::size_t... I>
	auto wrap_function(const std::function<void(Args...)>& f, std::index_sequence<I...>)
	{
		return [f](const function_arguments& args)
		{
			f(args[I]...);
			return arguments{{}};
		};
	}

	template <class... Args, std::size_t... I>
	auto wrap_function(const std::function<arguments(Args...)>& f, std::index_sequence<I...>)
	{
		return [f](const function_arguments& args)
		{
			return f(args[I]...);
		};
	}

	template <typename R, class... Args, std::size_t... I>
	auto wrap_function(const std::function<R(Args...)>& f, std::index_sequence<I...>)
	{
		return [f](const function_arguments& args)
		{
			return arguments{f(args[I]...)};
		};
	}

	template <typename R, class... Args>
	auto wrap_function(const std::function<R(Args...)>& f)
	{
		return wrap_function(f, std::index_sequence_for<Args...>{});
	}

	template <class F>
	auto wrap_function(F f)
	{
		return wrap_function(std::function(f));
	}

	table get_globals();

	template <typename F>
	game::hks::cclosure* convert_function(F f);

	// MWX: runs `code` in the LUI state. Results are converted with Lua's tostring, so a Lua
	// helper can return JSON text. Returns false and fills `error` on compile/runtime errors.
	bool eval(const std::string& code, std::vector<std::string>* results, std::string* error);

	bool lui_running();

	// True while the frontend/LUI is being (re)loaded: the hks_start script load or a DB zone
	// load. Lua must not run then (Engine.* from a chunk crashed at 0x1400BCB13).
	void set_loading(bool loading);
	bool is_loading();

	// M6: shut the frontend LUI down and start it again (globals rebuild + scripts), then open
	// the main menu. Used to pick up a new mod's ui_scripts / gametype list without a relaunch.
	// on_menu_opened runs after the main menu was opened (for timing/logging).
	void restart(const std::function<void()>& on_menu_opened = {});
}
