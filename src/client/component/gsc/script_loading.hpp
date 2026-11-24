#pragma once
#include <xsk/gsc/engine/h1.hpp>

namespace gsc
{
	struct col_line_t
	{
		std::uint16_t line;
		std::uint16_t column;
	};

	extern std::unique_ptr<xsk::gsc::h1::context> gsc_ctx;

	void load_main_handles();
	void load_init_handles();

	game::ScriptFile* find_script(game::XAssetType type, const char* name, int allow_create_default);

	std::optional<std::map<std::uint32_t, col_line_t>*> get_script_devmap(const std::string& name);

	// Called after the GSC compiler context was initialised for a script load: builtins that do
	// not exist in H1 (MWX test interface) have to be added here, every time.
	void on_context_ready(const std::function<void()>& callback);

	// The compiler context only lives between Scr_BeginLoadScripts and Scr_EndLoadScripts.
	// Scripts loaded at runtime (the test interface) need their own begin/end around the load.
	void begin_runtime_compile();
	void end_runtime_compile();
}
