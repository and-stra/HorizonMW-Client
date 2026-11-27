#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "console.hpp"
#include "dvars.hpp"
#include "localized_strings.hpp"
#include "scheduler.hpp"
#include "stock_weapons.hpp"
#include "mods.hpp"
#include "component/gsc/script_loading.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"

#include "gamemodes.hpp"

#include <utils/memory.hpp>
#include <utils/compression.hpp>
#include <utils/hook.hpp>
#include <utils/string.hpp>

#include <algorithm>
#include <cstring>
#include <cctype>
#include <map>
#include <mutex>
#include <string>
#include <vector>

namespace gamemodes
{
	namespace
	{
		constexpr mode modes[] =
		{
			{"ph", "war", 9, 0, "MWX_GAMETYPE_PH", "MWX_GAMETYPE_PH_DESC"},
			{"mprops", "war", 9, 1, "MWX_GAMETYPE_MPROPS", "MWX_GAMETYPE_MPROPS_DESC"},
			{"slasher", "war", 2, 0, "MWX_GAMETYPE_SLASHER", "MWX_GAMETYPE_SLASHER_DESC"},
			{"rpg", "war", 6, 0, "MWX_GAMETYPE_RPG", "MWX_GAMETYPE_RPG_DESC"},
		};

		// Real extra gametypes (own GSC script, no translation): whitelist + table row if missing.
		struct extra_gametype
		{
			const char* ref;
			const char* template_ref; // gametypesTable row to copy image/flags from
			const char* name;
			const char* desc;
			// gametypesTable column 5 = class choice allowed (_utility::allowclasschoice). Fixed-loadout
			// modes need "0" like Infected: otherwise players and bots pick a custom class and
			// bypassclasschoicefunc (the gamemode loadout) never runs. nullptr = keep the template's value.
			const char* class_choice = nullptr;
		};

		constexpr extra_gametype extra_gametypes[] =
		{
			{"infect", "war", "MPUI_INFECT", "MENU_INFECT_DESC"},
			{"dz", "koth", "MPUI_DZ", "MWX_GAMETYPE_DZ_DESC"},
			{"oic", "dm", "MWX_GAMETYPE_OIC", "MWX_GAMETYPE_OIC_DESC", "0"},
			{"aon", "dm", "MWX_GAMETYPE_AON", "MWX_GAMETYPE_AON_DESC", "0"},
			{"cranked", "war", "MWX_GAMETYPE_CRANKED", "MWX_GAMETYPE_CRANKED_DESC"},
			// R4: the five new party modes (own scripts in data/mwx/maps/mp/gametypes)
			{"sharpshooter", "war", "MWX_GAMETYPE_SHRP", "MWX_GAMETYPE_SHRP_DESC", "0"},
			{"reinforce", "dom", "MWX_GAMETYPE_REINFORCE", "MWX_GAMETYPE_REINFORCE_DESC"},
			{"srescue", "sd", "MWX_GAMETYPE_SRESCUE", "MWX_GAMETYPE_SRESCUE_DESC"},
			{"mugger", "dm", "MWX_GAMETYPE_MUGGER", "MWX_GAMETYPE_MUGGER_DESC"},
			{"arena", "war", "MWX_GAMETYPE_ARENA", "MWX_GAMETYPE_ARENA_DESC"},
			// Sticks and Stones: native gametype (part C). It used to be the mods/sticksandstones
			// PoC; the mod is gone and the crossbow comes from hmw_aw_weapons.ff.
			{"sas", "dm", "MWX_GAMETYPE_SAS", "MWX_GAMETYPE_SAS_DESC", "0"},
		};

		// built-in extra gametypes + the ones the loaded mod declares in its mod.json
		std::vector<extra_gametype> all_extra_gametypes()
		{
			std::vector<extra_gametype> result(std::begin(extra_gametypes), std::end(extra_gametypes));
			for (const auto& g : mods::get_gametypes())
			{
				result.push_back({g.ref.data(), g.template_ref.data(), g.name_key.data(), g.desc_key.data(),
					g.class_choice ? nullptr : "0"});
			}
			return result;
		}

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
			{"rpg", "Gain points by eliminating enemy players. RPGs only."},
			{"oic", "Gain points by eliminating enemy players. Every kill gives one round. Three lives."},
			{"aon", "Empty pistol and a throwing knife. Reach 20 kills without dying for the bonus."},
			{"cranked", "Gain points by eliminating enemy players. Kills make you Cranked: keep killing to stay alive."},
			{"sharpshooter", "Team deathmatch. Everyone carries the same weapon; it rotates every 45 seconds. Kills at 5, 10 and 15 give a perk."},
			{"reinforce", "Rounds, one life. Capture the point to respawn your dead teammates, or eliminate the enemy team."},
			{"srescue", "Rounds, one life. A dead player drops a tag: a teammate revives by taking it, an enemy confirms the kill. Eliminate the enemy team."},
			{"mugger", "Free-for-all. Kills drop tags: grab them to bank them. Melee kills steal the victim's banked tags. 30 tags."},
			{"arena", "Rounds, one life. A neutral flag appears when the clock runs down or a team is down to one: capture it to win the round."},
		};

		// Item 6: HMW's frontend localization table has no stock OBJECTIVES_* entries (they load
		// with the MP gametype zones). The private-match UI and the in-game mode display build
		// "OBJECTIVES_<gametype>" and "OBJECTIVES_<gametype>_SCORE" from the lowercase ref, so in
		// the frontend those keys came back raw ("OBJECTIVES_war_SCORE"). Register the stock texts
		// here as well; &&1 is the score-limit argument the UI passes. The texts are the strings
		// the engine itself shows in game. Also keeps SAS/Infected/Drop Zone covered when their
		// gametype zones (and the mod's lowercase strings) are not loaded.
		struct stock_objective
		{
			const char* ref;
			const char* text;
			const char* score;
			const char* hint;
		};

		constexpr stock_objective stock_objectives[] =
		{
			{"war", "Gain points by eliminating enemy players.",
				"Gain points by eliminating enemy players.  First team to &&1 wins.",
				"Eliminate enemy players."},
			{"dm", "Gain points by eliminating other players.",
				"Gain points by eliminating other players.  First player to &&1 points wins.",
				"Eliminate other players."},
			{"dom", "Capture and defend the flags.",
				"Capture and defend the flags.  First team to &&1 wins.",
				"Capture the flags and defend them."},
			{"sd", "Take turns destroying and defending A and B bomb sites.",
				"Take turns destroying and defending A and B bomb sites.",
				"Destroy target A or B."},
			{"sab", "Recover the explosives and plant them at the enemy target, while protecting your own.",
				"Recover the explosives and plant them at the enemy target, while protecting your own. First team to &&1 wins.",
				"Destroy the enemy target."},
			{"koth", "Gain points by holding the headquarters.",
				"Gain points by holding the headquarters.  First team to &&1 points wins.",
				"Hold the headquarters."},
			{"ctf", "Gain points by stealing the enemy flag and then touching your flag at your base.",
				"Gain points by stealing the enemy flag and then touching your flag at your base. First team with &&1 captures wins.",
				"Capture the enemy flag."},
			{"dd", "Teams alternate in attacking and defending two bomb sites, both of which must be destroyed by the attacking team equipped with bombs.",
				"Teams alternate in attacking and defending two bomb sites, both of which must be destroyed by the attacking team equipped with bombs.",
				"Destroy targets A and B."},
			{"conf", "Recover Dog Tags to score for your team and deny enemy scores.",
				"Recover Dog Tags to score for your team and deny enemy score.  First team to &&1 wins.",
				"Recover Dog Tags for the win."},
			{"hp", "Capture and hold the hardpoints.",
				"Capture the Hardpoint and hold it to score points. First team to &&1 points wins.",
				"Hardpoint location will move after set amount of time."},
			{"gun", "Kill players with your weapon to advance to the next weapon.",
				"Kill players with your weapon to advance to the next weapon. First to get a kill with all &&1 weapons wins.",
				"Eliminate other players."},
			// MWX gametypes whose own strings are registered uppercase by the mode scripts; the UI
			// builds the lowercase ref. Keep both texts the same in every case.
			{"sas", "Get kills with the crossbow and the knife.",
				"Highest score when the time runs out wins.",
				"A throwing knife kill or a suicide resets the score to 0."},
			{"infect", "Survivors: stay alive. Infected: infect the survivors.",
				"Infect everyone, or survive the game to win.",
				"Survivors: stay alive. Infected: infect the survivors."},
			{"dz", "Hold the Drop Zone for Team Points and Care Packages. First team to 7500 points wins",
				"Hold the Drop Zone for Team Points and Care Packages. First team to 7500 points wins",
				"Get to the Drop Zone!"},
		};

		void override_both_cases(const std::string& key, const char* value)
		{
			localized_strings::override(key, value);

			std::string upper = key;
			std::transform(upper.begin(), upper.end(), upper.begin(),
				[](const unsigned char c) { return static_cast<char>(std::toupper(c)); });
			if (upper != key)
			{
				localized_strings::override(upper, value);
			}
		}

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

			std::vector<std::string> listed;
			{
				std::string line;
				for (const auto c : data)
				{
					if (c == '\n' || c == '\r')
					{
						if (!line.empty()) listed.push_back(line);
						line.clear();
					}
					else
					{
						line.push_back(c);
					}
				}
				if (!line.empty()) listed.push_back(line);
			}

			const auto append = [&](const char* ref)
			{
				if (std::find(listed.begin(), listed.end(), ref) == listed.end())
				{
					data += ref;
					data.push_back('\n');
					listed.emplace_back(ref);
				}
			};

			for (const auto& m : modes)
			{
				append(m.ref);
			}

			for (const auto& g : all_extra_gametypes())
			{
				append(g.ref);
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

			const auto cols = original->columnCount;
			const auto old_rows = original->rowCount;

			const auto row_of = [&](const char* ref) -> int
			{
				for (auto r = 0; r < old_rows; ++r)
				{
					const auto* id = original->values[static_cast<size_t>(r) * cols].string;
					if (id && std::strcmp(id, ref) == 0)
					{
						return r;
					}
				}
				return -1;
			};

			struct new_row
			{
				const char* ref;
				int template_row;
				const char* name;
				const char* desc;
				const char* class_choice;
			};

			std::vector<new_row> rows;
			const auto war_row = row_of("war");
			if (war_row < 0)
			{
				return nullptr;
			}

			for (const auto& m : modes)
			{
				if (row_of(m.ref) < 0)
				{
					rows.push_back({m.ref, war_row, m.name, m.desc, nullptr});
				}
			}

			for (const auto& g : all_extra_gametypes())
			{
				if (row_of(g.ref) < 0)
				{
					const auto template_row = row_of(g.template_ref);
					rows.push_back({g.ref, template_row >= 0 ? template_row : war_row, g.name, g.desc, g.class_choice});
				}
			}

			if (rows.empty())
			{
				return nullptr;
			}

			const auto new_rows = old_rows + static_cast<int>(rows.size());

			auto* result = allocator.allocate<game::StringTable>();
			*result = *original;
			result->rowCount = new_rows;
			result->values = allocator.allocate_array<game::StringTableCell>(static_cast<size_t>(cols) * new_rows);
			std::memcpy(result->values, original->values, sizeof(game::StringTableCell) * cols * old_rows);

			// Refs whose row already exists in the stock table (e.g. "mugger") keep the stock
			// description key, and that key has no text in HMW's localization -> empty description.
			// Give every MWX-owned ref its own description, existing row or not.
			const auto fill_desc = [&](const char* ref, const char* desc)
			{
				if (!desc)
				{
					return;
				}

				const auto row_index = row_of(ref);
				if (row_index < 0)
				{
					return;
				}

				auto& cell = result->values[static_cast<size_t>(row_index) * cols + 2];
				cell.string = allocator.duplicate_string(desc);
				cell.hash = static_cast<int>(hash(desc));
			};

			for (const auto& m : modes)
			{
				fill_desc(m.ref, m.desc);
			}

			for (const auto& g : all_extra_gametypes())
			{
				fill_desc(g.ref, g.desc);
			}

			for (size_t n = 0; n < rows.size(); ++n)
			{
				const auto& row = rows[n];
				for (auto c = 0; c < cols; ++c)
				{
					const auto& src = original->values[static_cast<size_t>(row.template_row) * cols + c];
					const char* text = src.string ? src.string : "";
					if (c == 0)
					{
						text = row.ref;
					}
					else if (c == 1)
					{
						text = row.name;
					}
					else if (c == 2)
					{
						text = row.desc;
					}
					else if (c == 5 && row.class_choice)
					{
						text = row.class_choice;
					}

					auto& cell = result->values[static_cast<size_t>(old_rows + static_cast<int>(n)) * cols + c];
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

	const char* script_alias(const char* name)
	{
		constexpr auto prefix = "maps/mp/gametypes/";
		constexpr auto prefix_len = sizeof("maps/mp/gametypes/") - 1;

		if (!name || std::strncmp(name, prefix, prefix_len) != 0)
		{
			return nullptr;
		}

		const auto* mode = find(name + prefix_len);
		if (!mode)
		{
			return nullptr;
		}

		// war.gsc contains the whole game logic (labels included); loading it under the party ref's
		// name is what makes g_gametype=<ref> work without switching the dvar.
		return utils::string::va("maps/mp/gametypes/%s", mode->base);
	}

	namespace
	{
		bool on_map(const char* mapname)
		{
			const auto* dvar = game::Dvar_FindVar("mapname");
			return dvar && dvar->current.string && std::strcmp(dvar->current.string, mapname) == 0;
		}

		// R1: H1's war.gsc main() registers its watched rule dvars as scr_<level.gametype>_*
		// (getdvarint(name, default) at registration time). A party ref ("ph", "mprops",
		// "slasher") has no engine-registered scr_<ref>_* dvars, so war.gsc saw the default 0:
		// numlives 0 = unlimited lives, and a Prop Hunt round could never end by elimination.
		// Create/overwrite the rule dvars with the mode's own setupdvars() values before the map
		// loads. Numeric dvars can be registered late (the string-dvar crash does not apply).
		void set_rule_int(const char* name, const int value, const int min, const int max)
		{
			if (game::Dvar_FindVar(name) == nullptr)
			{
				game::Dvar_RegisterInt(game::generateHashValue(name), name, value, min, max,
					game::DVAR_FLAG_NONE);
				console::info("[gamemodes] registered %s = %i\n", name, value);
				return;
			}

			const auto text = std::to_string(value);
			game::Dvar_SetFromStringByNameFromSource(name, text.data(), game::DVAR_SOURCE_INTERNAL);
		}

		void set_rule_float(const char* name, const float value, const float min, const float max)
		{
			if (game::Dvar_FindVar(name) == nullptr)
			{
				game::Dvar_RegisterFloat(game::generateHashValue(name), name, value, min, max,
					game::DVAR_FLAG_NONE);
				console::info("[gamemodes] registered %s = %f\n", name, value);
				return;
			}

			const auto text = std::to_string(value);
			game::Dvar_SetFromStringByNameFromSource(name, text.data(), game::DVAR_SOURCE_INTERNAL);
		}

		void set_rule_bool(const char* name, const bool value)
		{
			if (game::Dvar_FindVar(name) == nullptr)
			{
				game::Dvar_RegisterBool(game::generateHashValue(name), name, value, game::DVAR_FLAG_NONE);
				console::info("[gamemodes] registered %s = %i\n", name, value ? 1 : 0);
				return;
			}

			game::Dvar_SetFromStringByNameFromSource(name, value ? "1" : "0", game::DVAR_SOURCE_INTERNAL);
		}

		// string rule dvar (scr_<gametype>_maxagents is a string the exe parses with atoi; an int
		// dvar would be read as a char pointer). Only called from the main pipeline: string dvars
		// cannot be registered in post_unpack (AGENTS.md).
		void set_rule_string(const char* name, const char* value)
		{
			if (game::Dvar_FindVar(name) == nullptr)
			{
				game::Dvar_RegisterString(game::generateHashValue(name), name, value, game::DVAR_FLAG_NONE);
				console::info("[gamemodes] registered %s = %s\n", name, value);
				return;
			}

			game::Dvar_SetFromStringByNameFromSource(name, value, game::DVAR_SOURCE_INTERNAL);
		}

		// B1: the party modes change global (non scr_<ref>_) rule dvars that the stock engine
		// registered once, e.g. scr_player_healthregen, scr_game_hardpoints, scr_game_mmUavTime
		// and g_oldschool. Those keep their party value after the match, so the next normal match
		// had no health regen and no killstreaks. Remember the value the dvar had before the first
		// party mode touched it and restore it in reset_mode_dvars().
		std::map<std::string, std::string> saved_globals;

		std::string dvar_value_string(const game::dvar_t* dvar)
		{
			switch (dvar->type)
			{
			case game::dvar_type::boolean:
			case game::dvar_type::boolean_hashed:
				return dvar->current.enabled ? "1" : "0";
			case game::dvar_type::integer:
			case game::dvar_type::integer_hashed:
			case game::dvar_type::enumeration:
				return std::to_string(dvar->current.integer);
			case game::dvar_type::value:
			case game::dvar_type::value_hashed:
				return std::to_string(dvar->current.value);
			default:
				return dvar->current.string ? dvar->current.string : "";
			}
		}

		void remember_global(const char* name, const char* fallback = nullptr)
		{
			if (saved_globals.contains(name))
			{
				return;
			}

			const auto* dvar = game::Dvar_FindVar(name);
			if (!dvar)
			{
				// the engine owns these normally; a party mode may create one that did not exist
				// before (scr_player_healthregen is created by the Prop Hunt GSC). Without a
				// fallback there is nothing to restore; with one, restore the normal value.
				if (fallback)
				{
					saved_globals[name] = fallback;
				}
				return;
			}

			saved_globals[name] = dvar_value_string(dvar);
		}

		void restore_globals()
		{
			for (const auto& [name, value] : saved_globals)
			{
				game::Dvar_SetFromStringByNameFromSource(name.data(), value.data(), game::DVAR_SOURCE_INTERNAL);
			}

			saved_globals.clear();
		}

		// maps/mp/gametypes/_hodgepodge_ph.gsc setupdvars(), with the mode's own dvar prefix.
		// B2: the map-specific branch (mp_shipment: timelimit 2.2, g_oldschool 1) is done in GSC
		// (ph_setupdvars_stub uses getmapname()); on_map() in the g_gametype callback still sees
		// the PREVIOUS map.
		void apply_prop_hunt_dvars(const bool madprops)
		{
			const auto prefix = std::string("scr_") + (madprops ? "mprops" : "ph") + "_";

			remember_global("scr_game_hardpoints");
			set_rule_int("scr_game_hardpoints", 0, 0, 10);
			set_rule_float((prefix + "timelimit").data(), 4.0f, 0.0f, 60.0f);
			set_rule_int((prefix + "scorelimit").data(), 0, 0, 10000);
			set_rule_int((prefix + "roundlimit").data(), 4, 0, 20);
			set_rule_int((prefix + "winlimit").data(), 3, 0, 20);
			set_rule_int((prefix + "numlives").data(), madprops ? 4 : 1, 0, 20);
			set_rule_int((prefix + "roundswitch").data(), 1, 0, 9);
			set_rule_int((prefix + "halftime").data(), 0, 0, 1);

			// the H1 script only does this for the non-madprops round
			if (!madprops)
			{
				// not registered in a normal match; the normal value is regen on (the dvar is
				// only created by the Prop Hunt GSC, so the pre-ph state is "absent" = on)
				remember_global("scr_player_healthregen", "1");
				set_rule_int("scr_player_healthregen", 0, 0, 100);
			}

			// a later party mode must not inherit the oldschool rule from the previous one; the GSC
			// stub switches it back on for mp_shipment
			remember_global("g_oldschool");
			set_rule_bool("g_oldschool", false);
		}

		// maps/mp/gametypes/_hodgepodge.gsc setupdvarsmm()
		void apply_slasher_dvars()
		{
			remember_global("scr_game_hardpoints");
			set_rule_int("scr_game_hardpoints", 0, 0, 10);
			set_rule_float("scr_slasher_timelimit", 10.0f, 0.0f, 60.0f);
			set_rule_int("scr_slasher_numlives", 1, 0, 20);
			remember_global("scr_game_mmUavTime");
			set_rule_float("scr_game_mmUavTime", 30.0f, 0.0f, 600.0f);
			remember_global("g_oldschool");
			set_rule_bool("g_oldschool", true);
		}

		// maps/mp/gametypes/_hodgepodge.gsc setupdvarsrpg(): no limits, but g_oldschool has to be
		// in place before the map load too (_gamelogic::init reads it)
		void apply_rpg_dvars()
		{
			remember_global("g_oldschool");
			set_rule_bool("g_oldschool", true);
		}

		void reset_mode_dvars()
		{
			const auto* previous = game::Dvar_FindVar("mwx_gamemode");
			const auto had_mode = previous && previous->current.string && *previous->current.string;

			game::Dvar_SetFromStringByNameFromSource("scr_game_hodgepodgeMode", "0", game::DVAR_SOURCE_INTERNAL);
			game::Dvar_SetFromStringByNameFromSource("scr_game_madprops", "0", game::DVAR_SOURCE_INTERNAL);
			game::Dvar_SetFromStringByNameFromSource("mwx_gamemode", "", game::DVAR_SOURCE_INTERNAL);

			// the global rule dvars a party mode changed go back to the value the normal game had
			// before the party mode (B1). restore also when the mode flag is already empty, so a
			// leaked value from an earlier match is cleaned up on the next normal gametype.
			if (had_mode || !saved_globals.empty())
			{
				restore_globals();
			}
		}
	}

	void apply_gametype(const char* gametype)
	{
		if (!gametype)
		{
			return;
		}

		const auto* mode = find(gametype);
		if (mode)
		{
			game::Dvar_SetFromStringByNameFromSource("scr_game_hodgepodgeMode",
				std::to_string(mode->hodgepodge).data(), game::DVAR_SOURCE_INTERNAL);
			game::Dvar_SetFromStringByNameFromSource("scr_game_madprops",
				std::to_string(mode->madprops).data(), game::DVAR_SOURCE_INTERNAL);
			game::Dvar_SetFromStringByNameFromSource("mwx_gamemode", mode->ref, game::DVAR_SOURCE_INTERNAL);

			if (std::strcmp(mode->ref, "ph") == 0)
			{
				apply_prop_hunt_dvars(false);
			}
			else if (std::strcmp(mode->ref, "mprops") == 0)
			{
				apply_prop_hunt_dvars(true);
			}
			else if (std::strcmp(mode->ref, "slasher") == 0)
			{
				apply_slasher_dvars();
			}
			else if (std::strcmp(mode->ref, "rpg") == 0)
			{
				apply_rpg_dvars();
			}

			return;
		}

		// normal gametype: a later match must not inherit a party mode's dvars
		reset_mode_dvars();
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
			const auto* dvar = game::Dvar_FindVar("mwx_gamemode");
			const auto* value = dvar && dvar->current.string ? dvar->current.string : nullptr;
			if (!value || !*value)
			{
				return nullptr;
			}

			const auto* mode = find(value);
			if (mode && std::strcmp(mode->base, base) == 0)
			{
				return mode;
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

		utils::hook::detour cbuf_add_text_hook;

		std::atomic_bool enforcing_ui_gametype{false};

		// M4b: the game setup restore writes the engine's match-rules gametype ("war") back into
		// ui_gametype after the pick. Keep the picked ref while a private match is being set up;
		// the start path and the loadscreen read ui_gametype.
		void on_ui_gametype(game::dvar_value* value)
		{
			if (enforcing_ui_gametype)
			{
				return;
			}

			const auto* selected = game::Dvar_FindVar("mwx_selected_gametype");
			if (selected == nullptr || selected->current.string == nullptr || *selected->current.string == '\0')
			{
				return;
			}

			const auto* private_match = game::Dvar_FindVar("xblive_privatematch");
			if (private_match == nullptr || !private_match->current.enabled)
			{
				return;
			}

			const auto* current = value != nullptr && value->string != nullptr ? value->string : nullptr;
			if (current != nullptr && std::strcmp(current, selected->current.string) == 0)
			{
				return;
			}

			enforcing_ui_gametype = true;
			game::Dvar_SetFromStringByNameFromSource("ui_gametype", selected->current.string,
				game::DVAR_SOURCE_INTERNAL);
			enforcing_ui_gametype = false;
		}

		// M4b: the private match start (xpartygo) reads ui_gametype, but the game setup restore writes
		// the engine's match-rules gametype ("war") back into it. Re-apply the gametype picked in the
		// menu right before the start command runs.
		void cbuf_add_text_stub(const int local_client_num, const int controller, const char* text)
		{
			if (text != nullptr && std::strstr(text, "xpartygo") != nullptr)
			{
				const auto* selected = game::Dvar_FindVar("mwx_selected_gametype");
				if (selected != nullptr && selected->current.string != nullptr && *selected->current.string != '\0')
				{
					enforcing_ui_gametype = true;
					game::Dvar_SetFromStringByNameFromSource("ui_gametype", selected->current.string,
						game::DVAR_SOURCE_INTERNAL);
					enforcing_ui_gametype = false;
				}
			}

			cbuf_add_text_hook.invoke<void>(local_client_num, controller, text);
		}

		void on_g_gametype(game::dvar_value* value)
		{
			if (!value || !value->string)
			{
				return;
			}

			if (debug_enabled())
			{
				console::info("[gamemodes] g_gametype <- %s\n", value->string);
			}

			apply_gametype(value->string);
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

		// built once per table (nullptr = nothing to add or not possible)
		cached_table.result = build_stringtable(original);
		cached_table.done = true;
		return cached_table.result ? cached_table.result : original;
	}

	void invalidate()
	{
		std::lock_guard<std::mutex> lock(cache_mutex);
		cached_rawfile_original = nullptr;
		cached_rawfile = nullptr;
		cached_table = {};
		console::info("[gamemodes] gametype table and whitelist cache cleared\n");
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
			localized_strings::override("MWX_GAMETYPE_RPG", "RPGs Only");
			localized_strings::override("MWX_GAMETYPE_RPG_DESC", "Team Deathmatch with RPGs only.");
			localized_strings::override("MWX_GAMETYPE_OIC", "One in the Chamber");
			localized_strings::override("MWX_GAMETYPE_OIC_DESC",
				"Free-for-all with a single revolver round. Every kill gives one more round. Three lives.");
			localized_strings::override("MWX_GAMETYPE_AON", "All or Nothing");
			localized_strings::override("MWX_GAMETYPE_AON_DESC",
				"Free-for-all with an empty pistol, a throwing knife and Scavenger. 20 kills, 10 minutes.");
			localized_strings::override("MWX_GAMETYPE_CRANKED", "Cranked");
			localized_strings::override("MWX_GAMETYPE_CRANKED_DESC",
				"Team Deathmatch. A kill starts a 30 second fuse; keep killing to reset it, or explode.");
			localized_strings::override("MWX_GAMETYPE_SHRP", "Sharpshooter");
			localized_strings::override("MWX_GAMETYPE_SHRP_DESC",
				"Team Deathmatch. Everyone carries the same weapon, rotating every 45 seconds. Killstreak perks at 5, 10 and 15 kills.");
			localized_strings::override("MWX_GAMETYPE_REINFORCE", "Reinforce");
			localized_strings::override("MWX_GAMETYPE_REINFORCE_DESC",
				"Rounds with one life. Capture the point to bring your dead teammates back, or eliminate the enemy team.");
			localized_strings::override("MWX_GAMETYPE_SRESCUE", "Search & Rescue");
			localized_strings::override("MWX_GAMETYPE_SRESCUE_DESC",
				"Search & Destroy with tags. A dead player drops a tag; a teammate can revive them, an enemy confirms the kill.");
			localized_strings::override("MWX_GAMETYPE_MUGGER", "Mugger");
			localized_strings::override("MWX_GAMETYPE_MUGGER_DESC",
				"Free-for-all. Kills drop tags, grab them to bank them. Melee kills steal the victim's tags.");
			localized_strings::override("MWX_GAMETYPE_ARENA", "Arena");
			localized_strings::override("MWX_GAMETYPE_ARENA_DESC",
				"Rounds with one life. A neutral flag appears late in the round or when a team is down to one; capture it to win.");
			localized_strings::override("MWX_GAMETYPE_SAS", "Sticks and Stones");
			localized_strings::override("MWX_GAMETYPE_SAS_DESC",
				"Free-for-all with the crossbow, a knife and a throwing knife. A throwing knife kill or a suicide bankrupts the victim.");
			localized_strings::override("MWX_GAMETYPE_SAS_CAPS", "STICKS AND STONES");
			localized_strings::override("SAS", "STICKS AND STONES");
			// SAS objectives are in stock_objectives (both cases).
			localized_strings::override("MWX_SAS_BANKRUPTED", "BANKRUPTED!");
			localized_strings::override("MWX_SAS_BANKRUPT_ENEMY", "BANKRUPTED AN ENEMY!");
			localized_strings::override("MWX_PARTY_CAPS", "PARTY");

			// real extra gametypes: Infected (our port), Drop Zone (HMW's dz.gsc)
			localized_strings::override("MPUI_INFECT", "Infected");
			localized_strings::override("MPUI_INFECT_CAPS", "INFECTED");
			localized_strings::override("INFECT", "INFECTED");
			// Infected objectives are in stock_objectives (both cases).
			localized_strings::override("MPUI_DZ", "Drop Zone");
			localized_strings::override("MPUI_DZ_CAPS", "DROP ZONE");
			localized_strings::override("DZ", "DROP ZONE");
			localized_strings::override("MWX_GAMETYPE_DZ_DESC", "Capture the drop zone to earn points and care packages.");

			// caps names in the setup/pre-match menus
			localized_strings::override("MWX_GAMETYPE_PH_CAPS", "PROP HUNT");
			localized_strings::override("MWX_GAMETYPE_MPROPS_CAPS", "MAD PROPS");
			localized_strings::override("MWX_GAMETYPE_SLASHER_CAPS", "SLASHER");
			localized_strings::override("MWX_GAMETYPE_RPG_CAPS", "RPGS ONLY");
			localized_strings::override("MWX_GAMETYPE_OIC_CAPS", "ONE IN THE CHAMBER");
			localized_strings::override("MWX_GAMETYPE_AON_CAPS", "ALL OR NOTHING");
			localized_strings::override("MWX_GAMETYPE_CRANKED_CAPS", "CRANKED");
			localized_strings::override("MWX_GAMETYPE_SHRP_CAPS", "SHARPSHOOTER");
			localized_strings::override("MWX_GAMETYPE_REINFORCE_CAPS", "REINFORCE");
			localized_strings::override("MWX_GAMETYPE_SRESCUE_CAPS", "SEARCH & RESCUE");
			localized_strings::override("MWX_GAMETYPE_MUGGER_CAPS", "MUGGER");
			localized_strings::override("MWX_GAMETYPE_ARENA_CAPS", "ARENA");

			// loadscreen names ("@" .. upper(ui_gametype))
			localized_strings::override("PH", "PROP HUNT");
			localized_strings::override("MPROPS", "MAD PROPS");
			localized_strings::override("SLASHER", "SLASHER");
			localized_strings::override("RPG", "RPGS ONLY");
			localized_strings::override("OIC", "ONE IN THE CHAMBER");
			localized_strings::override("AON", "ALL OR NOTHING");
			localized_strings::override("CRANKED", "CRANKED");
			localized_strings::override("SHARPSHOOTER", "SHARPSHOOTER");
			localized_strings::override("REINFORCE", "REINFORCE");
			localized_strings::override("SRESCUE", "SEARCH & RESCUE");
			localized_strings::override("MUGGER", "MUGGER");
			localized_strings::override("ARENA", "ARENA");

			// HUD and splash strings of the One in the Chamber / All or Nothing / Cranked scripts
			localized_strings::override("MWX_OIC_LIVES_3", "LIVES: 3");
			localized_strings::override("MWX_OIC_LIVES_2", "LIVES: 2");
			localized_strings::override("MWX_OIC_LIVES_1", "LIVES: 1");
			localized_strings::override("MWX_OIC_LIVES_0", "LIVES: 0");
			localized_strings::override("MWX_AON_ONE_KILL", "1 KILL LEFT");
			localized_strings::override("MWX_AON_BONUS", "ALL OR NOTHING!");
			localized_strings::override("MWX_CRANKED", "CRANKED!");
			localized_strings::override("MWX_SHRP_WEAPON", "WEAPON");
			localized_strings::override("MWX_ARENA_FLAG_SPAWNED", "ARENA FLAG SPAWNED");

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

			// item 6: the stock gametypes' objective strings, so the private-match screens do not
			// show the raw key before the gametype's localization zone is loaded
			for (const auto& objective : stock_objectives)
			{
				const std::string base = std::string("OBJECTIVES_") + objective.ref;
				override_both_cases(base, objective.text);
				override_both_cases(base + "_SCORE", objective.score);
				override_both_cases(base + "_HINT", objective.hint);
			}

			// M4: the party ref is the gametype; the mode dvars follow it (both on the server and on a
			// listen host/client, so a dedicated server with +set g_gametype slasher works too)
			dvars::callback::on_new_value("g_gametype", on_g_gametype);
			dvars::callback::on_new_value("ui_gametype", on_ui_gametype);
			scheduler::once([]()
			{
				// the command line (+set g_gametype ...) is applied before the callback exists
				const auto* gametype = game::Dvar_FindVar("g_gametype");
				if (gametype && gametype->current.string)
				{
					apply_gametype(gametype->current.string);
				}
			}, scheduler::pipeline::main);

			ui_get_game_type_display_name_hook.create(game::UI_GetGameTypeDisplayName,
				ui_get_game_type_display_name_stub);

			cbuf_add_text_hook.create(game::Cbuf_AddText, cbuf_add_text_stub);

			scheduler::once([]()
			{
				dvars::register_string("mwx_gamemode", "", game::DVAR_FLAG_NONE,
					"Current MWX party game mode (empty for normal modes)");
				dvars::register_string("mwx_selected_gametype", "", game::DVAR_FLAG_NONE,
					"Gametype picked in the private match game setup (applied when xpartygo starts)");
				dvars::register_bool("mwx_gsc_print", false, game::DVAR_FLAG_NONE, "Print GSC print()/println() output to the console (release builds)");
				dvars::register_bool("mwx_debug_gamemodes", false, game::DVAR_FLAG_NONE,
					"Log gamemode dvar writes and the loading screen menu");
			}, scheduler::pipeline::main);
		}
	};
}

REGISTER_COMPONENT(gamemodes::component)
