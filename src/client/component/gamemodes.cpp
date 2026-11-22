#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "console.hpp"
#include "dvars.hpp"
#include "localized_strings.hpp"
#include "scheduler.hpp"
#include "stock_weapons.hpp"
#include "component/gsc/script_loading.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"

#include "gamemodes.hpp"

#include <utils/memory.hpp>
#include <utils/compression.hpp>
#include <utils/hook.hpp>

#include <algorithm>
#include <cstring>
#include <cctype>
#include <mutex>
#include <string>

namespace gamemodes
{
	namespace
	{
		constexpr mode modes[] =
		{
			{"ph", "war", 9, 0, "MWX_GAMETYPE_PH", "MWX_GAMETYPE_PH_DESC"},
			{"mprops", "war", 9, 1, "MWX_GAMETYPE_MPROPS", "MWX_GAMETYPE_MPROPS_DESC"},
			{"slasher", "war", 2, 0, "MWX_GAMETYPE_SLASHER", "MWX_GAMETYPE_SLASHER_DESC"},
			{"snipers", "war", 4, 0, "MWX_GAMETYPE_SNIPERS", "MWX_GAMETYPE_SNIPERS_DESC"},
			{"rpg", "war", 6, 0, "MWX_GAMETYPE_RPG", "MWX_GAMETYPE_RPG_DESC"},
		};

		struct objective_string
		{
			const char* ref;
			const char* text;
		};

		constexpr objective_string objectives[] =
		{
			{"ph", "Props hide, hunters seek. Survive the round or find every prop."},
			{"mprops", "Props hunt the soldiers. Eliminate every soldier to win."},
			{"slasher", "Survive the Slasher, or take the Slasher down."},
			{"snipers", "Gain points by eliminating enemy players. Sniper rifles only."},
			{"rpg", "Gain points by eliminating enemy players. RPGs only."},
		};

		constexpr auto gametype_list = "maps/mp/gametypes/_gametypes.txt";
		constexpr auto gametype_table = "mp/gametypesTable.csv";

		bool equals_ignore_case(const char* a, const char* b)
		{
			if (!a || !b)
			{
				return false;
			}

			for (; *a && *b; ++a, ++b)
			{
				if (std::tolower(static_cast<unsigned char>(*a)) != std::tolower(static_cast<unsigned char>(*b)))
				{
					return false;
				}
			}

			return *a == *b;
		}

		std::mutex cache_mutex;
		utils::memory::allocator allocator;

		game::RawFile* cached_rawfile_original = nullptr;
		game::RawFile* cached_rawfile = nullptr;

		struct cached_table_t
		{
			game::StringTable* original = nullptr;
			game::StringTable* result = nullptr;
			bool done = false;
		} cached_table;

		game::RawFile* build_rawfile(game::RawFile* original)
		{
			std::string data;
			if (original->compressedLen > 0)
			{
				const std::string compressed(original->buffer, static_cast<size_t>(original->compressedLen));
				data = utils::compression::zlib::decompress(compressed);
				if (data.empty())
				{
					return nullptr;
				}
			}
			else
			{
				data.assign(original->buffer, static_cast<size_t>(original->len));
			}

			if (!data.empty() && data.back() != '\n')
			{
				data.push_back('\n');
			}

			for (const auto& m : modes)
			{
				data += m.ref;
				data.push_back('\n');
			}

			auto* result = allocator.allocate<game::RawFile>();
			*result = *original;
			result->len = static_cast<int>(data.size());

			if (original->compressedLen > 0)
			{
				const auto compressed = utils::compression::zlib::compress(data);
				result->compressedLen = static_cast<int>(compressed.size());
				result->buffer = allocator.duplicate_string(compressed);
			}
			else
			{
				result->compressedLen = 0;
				auto* buffer = allocator.duplicate_string(data);
				buffer[data.size()] = '\0';
				result->buffer = buffer;
			}

			return result;
		}

		game::StringTable* build_stringtable(game::StringTable* original)
		{
			if (original->columnCount < 3 || original->rowCount < 1)
			{
				return nullptr;
			}

			const auto hash = stock_weapons::find_hash(original);
			if (!hash)
			{
				console::warn("gamemodes: cannot work out the cell hash of %s, not adding\n", gametype_table);
				return nullptr;
			}

			auto war_row = -1;
			for (auto r = 0; r < original->rowCount; ++r)
			{
				const auto* id = original->values[static_cast<size_t>(r) * original->columnCount].string;
				if (id && std::strcmp(id, "war") == 0)
				{
					war_row = r;
					break;
				}
			}

			if (war_row < 0)
			{
				return nullptr;
			}

			const auto cols = original->columnCount;
			const auto old_rows = original->rowCount;
			constexpr auto count = static_cast<int>(sizeof(modes) / sizeof(modes[0]));
			const auto new_rows = old_rows + count;

			auto* result = allocator.allocate<game::StringTable>();
			*result = *original;
			result->rowCount = new_rows;
			result->values = allocator.allocate_array<game::StringTableCell>(static_cast<size_t>(cols) * new_rows);
			std::memcpy(result->values, original->values, sizeof(game::StringTableCell) * cols * old_rows);

			for (auto n = 0; n < count; ++n)
			{
				const auto& m = modes[n];
				for (auto c = 0; c < cols; ++c)
				{
					const auto& src = original->values[static_cast<size_t>(war_row) * cols + c];
					const char* text = src.string ? src.string : "";
					if (c == 0)
					{
						text = m.ref;
					}
					else if (c == 1)
					{
						text = m.name;
					}
					else if (c == 2)
					{
						text = m.desc;
					}

					auto& cell = result->values[static_cast<size_t>(old_rows + n) * cols + c];
					cell.string = allocator.duplicate_string(text);
					cell.hash = static_cast<int>(hash(text));
				}
			}

			return result;
		}
	}

	const mode* find(const std::string& ref)
	{
		for (const auto& m : modes)
		{
			if (ref == m.ref)
			{
				return &m;
			}
		}

		return nullptr;
	}

	namespace
	{
		bool debug_enabled()
		{
			const auto* dvar = game::Dvar_FindVar("mwx_debug_gamemodes");
			return dvar && dvar->current.enabled;
		}

		utils::hook::detour ui_get_game_type_display_name_hook;

		const mode* active_mode_for(const char* base)
		{
			// the running match wins over a lobby selection
			for (const auto* dvar_name : {"mwx_gamemode", "mwx_party_mode"})
			{
				const auto* dvar = game::Dvar_FindVar(dvar_name);
				const auto* value = dvar && dvar->current.string ? dvar->current.string : nullptr;
				if (!value || !*value)
				{
					continue;
				}

				const auto* mode = find(value);
				if (mode && std::strcmp(mode->base, base) == 0)
				{
					return mode;
				}
			}

			return nullptr;
		}

		const char* ui_get_game_type_display_name_stub(const char* gametype)
		{
			if (debug_enabled())
			{
				console::info("[gamemodes] display name for '%s'\n", gametype ? gametype : "");
			}

			if (gametype)
			{
				if (const auto* mode = find(gametype))
				{
					return game::UI_SafeTranslateString(mode->name);
				}

				if (const auto* mode = active_mode_for(gametype))
				{
					return game::UI_SafeTranslateString(mode->name);
				}
			}

			return ui_get_game_type_display_name_hook.invoke<const char*>(gametype);
		}

		void on_ui_gametype(game::dvar_value* value)
		{
			if (!value || !value->string)
			{
				return;
			}

			if (debug_enabled())
			{
				console::info("[gamemodes] ui_gametype <- %s\n", value->string);
			}

			const auto* party_dvar = game::Dvar_FindVar("mwx_party_mode");
			if (!party_dvar || !party_dvar->current.string || !*party_dvar->current.string)
			{
				return;
			}

			const auto* mode = find(party_dvar->current.string);
			if (mode && std::strcmp(value->string, mode->base) == 0)
			{
				game::Dvar_SetFromStringByNameFromSource("ui_gametype", mode->ref, game::DVAR_SOURCE_INTERNAL);
			}
		}

		void on_party_mode(game::dvar_value* value)
		{
			if (!value || !value->string)
			{
				return;
			}

			const auto* mode = find(value->string);
			if (!mode)
			{
				return;
			}

			const auto* gametype_dvar = game::Dvar_FindVar("ui_gametype");
			if (gametype_dvar && gametype_dvar->current.string &&
				std::strcmp(gametype_dvar->current.string, mode->base) == 0)
			{
				game::Dvar_SetFromStringByNameFromSource("ui_gametype", mode->ref, game::DVAR_SOURCE_INTERNAL);
			}
		}
	}

	game::RawFile* patch_rawfile(game::RawFile* original)
	{
		if (!original || !original->name || std::strcmp(original->name, gametype_list) != 0)
		{
			return original;
		}

		std::lock_guard<std::mutex> lock(cache_mutex);
		if (cached_rawfile_original != original)
		{
			cached_rawfile = build_rawfile(original);
			cached_rawfile_original = original;
		}

		return cached_rawfile ? cached_rawfile : original;
	}

	game::StringTable* patch_stringtable(game::StringTable* original)
	{
		if (!original || !original->name || !equals_ignore_case(original->name, gametype_table))
		{
			return original;
		}

		std::lock_guard<std::mutex> lock(cache_mutex);
		if (cached_table.original != original)
		{
			cached_table = {};
			cached_table.original = original;
		}
		if (cached_table.done)
		{
			return cached_table.result ? cached_table.result : original;
		}

		auto* result = build_stringtable(original);
		if (result)
		{
			cached_table.result = result;
			cached_table.done = true;
			return cached_table.result;
		}

		return original;
	}

	void on_level_load()
	{
		if (!gsc::translated_this_load())
		{
			return;
		}

		const auto* gamemode_dvar = game::Dvar_FindVar("mwx_gamemode");
		if (!gamemode_dvar || !gamemode_dvar->current.string || !*gamemode_dvar->current.string)
		{
			return;
		}

		const auto* mode = find(gamemode_dvar->current.string);
		if (!mode)
		{
			return;
		}

		game::Dvar_SetFromStringByNameFromSource("g_gametype", mode->ref, game::DVAR_SOURCE_INTERNAL);
		console::info("[gamemodes] g_gametype restored to %s\n", mode->ref);
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			localized_strings::override("MWX_GAMETYPE_PH", "Prop Hunt");
			localized_strings::override("MWX_GAMETYPE_PH_DESC",
				"One team hides as props, the other hunts them. Survive the round as a prop or find them all.");
			localized_strings::override("MWX_GAMETYPE_MPROPS", "Mad Props");
			localized_strings::override("MWX_GAMETYPE_MPROPS_DESC",
				"Props hunt the soldiers. Props win by eliminating every soldier.");
			localized_strings::override("MWX_GAMETYPE_SLASHER", "Slasher");
			localized_strings::override("MWX_GAMETYPE_SLASHER_DESC",
				"One player is the Slasher with a shovel and a pistol. Survive until time runs out or take the Slasher down.");
			localized_strings::override("MWX_GAMETYPE_SNIPERS", "Snipers Only");
			localized_strings::override("MWX_GAMETYPE_SNIPERS_DESC", "Team Deathmatch with sniper rifles only.");
			localized_strings::override("MWX_GAMETYPE_RPG", "RPGs Only");
			localized_strings::override("MWX_GAMETYPE_RPG_DESC", "Team Deathmatch with RPGs only.");
			localized_strings::override("MWX_PARTY_CAPS", "WEEKEND WARFARE");

			// caps names in the setup/pre-match menus
			localized_strings::override("MWX_GAMETYPE_PH_CAPS", "PROP HUNT");
			localized_strings::override("MWX_GAMETYPE_MPROPS_CAPS", "MAD PROPS");
			localized_strings::override("MWX_GAMETYPE_SLASHER_CAPS", "SLASHER");
			localized_strings::override("MWX_GAMETYPE_SNIPERS_CAPS", "SNIPERS ONLY");
			localized_strings::override("MWX_GAMETYPE_RPG_CAPS", "RPGS ONLY");

			// loadscreen names ("@" .. upper(ui_gametype))
			localized_strings::override("PH", "PROP HUNT");
			localized_strings::override("MPROPS", "MAD PROPS");
			localized_strings::override("SLASHER", "SLASHER");
			localized_strings::override("SNIPERS", "SNIPERS ONLY");
			localized_strings::override("RPG", "RPGS ONLY");

			// objective strings: the UI builds OBJECTIVES_<ref>(_SCORE|_HINT) with the ref as it is
			for (const auto& objective : objectives)
			{
				std::string upper = objective.ref;
				std::transform(upper.begin(), upper.end(), upper.begin(),
					[](const unsigned char c) { return static_cast<char>(std::toupper(c)); });

				for (const auto& ref : {std::string(objective.ref), upper})
				{
					localized_strings::override("OBJECTIVES_" + ref + "_SCORE", objective.text);
					localized_strings::override("OBJECTIVES_" + ref, objective.text);
					localized_strings::override("OBJECTIVES_" + ref + "_HINT", objective.text);
				}
			}

			if (!game::environment::is_dedi())
			{
				dvars::callback::on_new_value("ui_gametype", on_ui_gametype);
				dvars::callback::on_new_value("mwx_party_mode", on_party_mode);
			}

			ui_get_game_type_display_name_hook.create(game::UI_GetGameTypeDisplayName,
				ui_get_game_type_display_name_stub);

			scheduler::once([]()
			{
				dvars::register_string("mwx_gamemode", "", game::DVAR_FLAG_NONE,
					"Current MWX party game mode (empty for normal modes)");
				dvars::register_string("mwx_party_mode", "", game::DVAR_FLAG_NONE,
					"Selected MWX party game mode (base gametype stays unchanged)");
				dvars::register_bool("mwx_gsc_print", false, game::DVAR_FLAG_NONE, "Print GSC print()/println() output to the console (release builds)");
				dvars::register_bool("mwx_debug_gamemodes", false, game::DVAR_FLAG_NONE,
					"Log gamemode dvar writes and the loading screen menu");
			}, scheduler::pipeline::main);
		}
	};
}

REGISTER_COMPONENT(gamemodes::component)
