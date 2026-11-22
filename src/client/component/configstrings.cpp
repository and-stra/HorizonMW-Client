#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "console.hpp"
#include "scripting.hpp"

#include "game/game.hpp"

#include <utils/hook.hpp>

#include <mutex>
#include <unordered_map>

// MWX: warn before a configstring range overflows (custom content can exhaust ranges such as models,
// effects or localized strings; the game then drops with an error). Like the official HMW client,
// we only log. Indexes in a range are handed out in order, so the returned index shows the usage.
namespace configstrings
{
	namespace
	{
		utils::hook::detour g_find_configstring_index_hook;

		std::mutex mutex;
		std::unordered_map<int, int> highest_logged; // range start -> highest used count logged

		int g_find_configstring_index_stub(const char* string, const int start, const int max, const int create,
			const char* errormsg)
		{
			const auto index = g_find_configstring_index_hook.invoke<int>(string, start, max, create, errormsg);

			if (create && max > 0 && index >= start)
			{
				const auto used = index - start + 1;
				const auto warn_at = (max * 9) / 10;

				if (used >= warn_at)
				{
					std::lock_guard<std::mutex> _(mutex);
					auto& logged = highest_logged[start];
					if (used > logged)
					{
						logged = used;
						if (used >= max)
						{
							console::warn("[configstrings] range %d FULL (%d/%d) after adding '%s'\n", start, used, max,
								string ? string : "");
						}
						else
						{
							console::warn("[configstrings] range %d nearly full (%d/%d) adding '%s'\n", start, used, max,
								string ? string : "");
						}
					}
				}
			}

			return index;
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			g_find_configstring_index_hook.create(0x8B530_b, g_find_configstring_index_stub);

			scripting::on_shutdown([](bool, bool)
			{
				std::lock_guard<std::mutex> _(mutex);
				highest_logged.clear();
			});
		}
	};
}

REGISTER_COMPONENT(configstrings::component)
