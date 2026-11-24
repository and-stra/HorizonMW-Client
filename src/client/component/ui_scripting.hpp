#pragma once

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
}
