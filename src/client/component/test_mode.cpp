#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "console.hpp"
#include "dvars.hpp"
#include "scheduler.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"

#include <utils/io.hpp>

// MWX: settings for automated runs (see docs/guides/testing.md).
//
//   mwx_test_mode 1  - windowed 960x540, muted, no mouse capture, never paused
//
// The MCP start_client/start_server set it by default. Nothing changes without the dvar, so a
// normal game is not affected.

namespace test_mode
{
	namespace
	{
		void set(const char* name, const char* value)
		{
			if (game::Dvar_FindVar(name) == nullptr)
			{
				return;
			}

			game::Dvar_SetFromStringByNameFromSource(name, value, game::DVAR_SOURCE_INTERNAL);
		}

		void apply()
		{
			if (!game::environment::is_dedi())
			{
				// small windowed resolution: the game keeps rendering when another window has focus
				set("r_fullscreen", "0");
				set("r_mode", "-1");
				set("r_customwidth", "960");
				set("r_customheight", "540");
				set("r_aspectRatio", "1");

				// NOTE: do not set in_mouse 0 here! It does not only disable the mouse, it also
				// stops the client from building usercmds at all, so injected keys (+forward,
				// +attack, ...) stop working. The mouse is not captured while the game window is
				// not focused, which is the case for automated runs.

				// muted
				set("snd_volume", "0");
				set("snd_master_volume", "0");
			}

			// never pause (a paused server would stop the match while tests run in the background)
			set("cl_paused", "0");
			set("cl_force_paused", "0");
			set("sv_paused", "0");

			console::info("[test_mode] applied (windowed 960x540, muted)\n");
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			scheduler::once([]
			{
				dvars::register_bool("mwx_test_mode", false, game::DVAR_FLAG_NONE,
					"Automated run: windowed 960x540, muted, never paused");

				if (const auto* dvar = game::Dvar_FindVar("mwx_test_mode"); dvar && dvar->current.enabled)
				{
					apply();
				}
			}, scheduler::pipeline::main);
		}
	};
}

REGISTER_COMPONENT(test_mode::component)
