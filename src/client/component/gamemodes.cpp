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
			{"snipers", "war", 4, 0, "MWX_GAMETYPE_SNIPERS", "MWX_GAMETYPE_SNIPERS_DESC"},
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
			{"snipers", "Gain points by eliminating enemy players. Sniper rifles only."},
			{"rpg", "Gain points by eliminating enemy players. RPGs only."},
			{"oic", "Gain points by eliminating enemy players. Every kill gives one round. Three lives."},
			{"aon", "Empty pistol and a throwing knife. Reach 20 kills without dying for the bonus."},
			{"cranked", "Gain points by eliminating enemy players. Kills make you Cranked: keep killing to stay alive."},
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
			return;
		}

		// normal gametype: a later match must not inherit a party mode's dvars
		game::Dvar_SetFromStringByNameFromSource("scr_game_hodgepodgeMode", "0", game::DVAR_SOURCE_INTERNAL);
		game::Dvar_SetFromStringByNameFromSource("scr_game_madprops", "0", game::DVAR_SOURCE_INTERNAL);
		game::Dvar_SetFromStringByNameFromSource("mwx_gamemode", "", game::DVAR_SOURCE_INTERNAL);
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

		// ---------------------------------------------------------------- GSC getdvar override
		// M4: the party ref stays in g_gametype (loading screen, scoreboard, menus show it), while the
		// shipped GSC compares getdvar("g_gametype") with the base gametype ("war"). The H1 builtin
		// table is an array of { const char* name; void (*func)(); int type; }; the entry for getdvar is
		// found by looking for the name string and a pointer to it followed by a code pointer, then its
		// function is detoured. Only the "g_gametype" name is rewritten.
		struct memory_range
		{
			uintptr_t begin = 0;
			uintptr_t end = 0;
			bool executable = false;
		};

		std::vector<memory_range> module_ranges()
		{
			std::vector<memory_range> ranges;
			const auto* base = reinterpret_cast<const std::uint8_t*>(GetModuleHandleA(nullptr));
			if (!base)
			{
				return ranges;
			}

			const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
			if (dos->e_magic != IMAGE_DOS_SIGNATURE)
			{
				return ranges;
			}

			const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
			if (nt->Signature != IMAGE_NT_SIGNATURE)
			{
				return ranges;
			}

			const auto* section = IMAGE_FIRST_SECTION(nt);
			for (unsigned i = 0; i < nt->FileHeader.NumberOfSections; ++i)
			{
				const auto size = static_cast<uintptr_t>(std::max(section[i].Misc.VirtualSize, section[i].SizeOfRawData));
				if (size == 0)
				{
					continue;
				}

				memory_range range{};
				range.begin = reinterpret_cast<uintptr_t>(base + section[i].VirtualAddress);
				range.end = range.begin + size;
				range.executable = (section[i].Characteristics & IMAGE_SCN_MEM_EXECUTE) != 0;
				ranges.push_back(range);
			}

			return ranges;
		}

		bool range_executable(const std::vector<memory_range>& ranges, const uintptr_t address)
		{
			for (const auto& range : ranges)
			{
				if (range.executable && address >= range.begin && address + 1 <= range.end)
				{
					return true;
				}
			}
			return false;
		}

		utils::hook::detour getdvar_hook;
		bool getdvar_hooked = false;

		// H1's builtin function table: an array of function pointers, indexed by the compiler's builtin
		// id (xsk's h1_func.cpp: getdvar = 0x39). The names are not in the exe, so the table is found by
		// its shape: a run of ~778 code pointers, with getdvar/getdvarint/getdvarfloat (0x39..0x3B) all
		// valid. If that is not unique the override stays off.
		constexpr auto h1_builtin_count = 778;
		constexpr auto h1_getdvar_id = 0x39;

		void getdvar_stub()
		{
			const auto* name = game::Scr_GetString(0);
			if (name && std::strcmp(name, "g_gametype") == 0)
			{
				const auto* gametype = game::Dvar_FindVar("g_gametype");
				if (gametype && gametype->current.string && find(gametype->current.string))
				{
					game::Scr_AddString(find(gametype->current.string)->base);
					return;
				}
			}

			if (getdvar_hooked)
			{
				getdvar_hook.invoke<void>();
			}
		}

		void install_getdvar_override()
		{
			const auto ranges = module_ranges();
			if (ranges.empty())
			{
				console::warn("[gamemodes] cannot find the module ranges, GSC getdvar override off\n");
				return;
			}

			std::vector<uintptr_t> tables;

			for (const auto& range : ranges)
			{
				if (range.executable)
				{
					continue;
				}

				auto start = range.begin;
				auto count = 0u;

				for (auto addr = range.begin; addr + sizeof(uintptr_t) <= range.end; addr += sizeof(uintptr_t))
				{
					const auto value = *reinterpret_cast<const uintptr_t*>(addr);
					const auto valid = value == 0 || range_executable(ranges, value);

					if (valid)
					{
						if (count == 0)
						{
							start = addr;
						}
						count++;
						continue;
					}


					if (count == h1_builtin_count &&
						range_executable(ranges, *reinterpret_cast<const uintptr_t*>(start + (h1_getdvar_id + 1) * sizeof(uintptr_t))) &&
						range_executable(ranges, *reinterpret_cast<const uintptr_t*>(start + (h1_getdvar_id + 2) * sizeof(uintptr_t))))
					{
						tables.push_back(start);
					}

					count = 0;
				}

				if (count == h1_builtin_count &&
					range_executable(ranges, *reinterpret_cast<const uintptr_t*>(start + (h1_getdvar_id + 1) * sizeof(uintptr_t))) &&
					range_executable(ranges, *reinterpret_cast<const uintptr_t*>(start + (h1_getdvar_id + 2) * sizeof(uintptr_t))))
				{
					tables.push_back(start);
				}
			}

			if (tables.size() != 1)
			{
				// H1 may store { u32 name-hash, u32 type, void (*func)(); } (16 bytes per entry): then only
				// every second qword is a code pointer and the 8-byte scan above finds nothing.
				std::vector<uintptr_t> stride_tables;
				std::vector<int> stride_offsets;

				for (const auto& range : ranges)
				{
					if (range.executable)
					{
						continue;
					}

					for (auto func_offset = 0; func_offset <= 8; func_offset += 8)
					{
						auto start = range.begin;
						auto count = 0u;

						for (auto addr = range.begin; addr + 16 <= range.end; addr += 16)
						{
							const auto function = *reinterpret_cast<const uintptr_t*>(addr + func_offset);
							const auto other = *reinterpret_cast<const uintptr_t*>(addr + (func_offset == 0 ? 8 : 0));
							const auto valid = range_executable(ranges, function) && !range_executable(ranges, other);

							if (valid)
							{
								if (count == 0)
								{
									start = addr;
								}
								count++;
								continue;
							}

							if (count == h1_builtin_count)
							{
								stride_tables.push_back(start);
								stride_offsets.push_back(func_offset);
							}

							count = 0;
						}

						if (count == h1_builtin_count)
						{
							stride_tables.push_back(start);
							stride_offsets.push_back(func_offset);
						}
					}
				}

				if (stride_tables.size() != 1)
				{
					console::warn("[gamemodes] %zu/%zu builtin tables, GSC getdvar override off\n",
						tables.size(), stride_tables.size());
					return;
				}

				const auto function = *reinterpret_cast<const uintptr_t*>(
					stride_tables.front() + h1_getdvar_id * 16 + stride_offsets.front());
				if (!range_executable(ranges, function))
				{
					console::warn("[gamemodes] stride getdvar slot is not code, GSC getdvar override off\n");
					return;
				}

				getdvar_hook.create(reinterpret_cast<void*>(function), getdvar_stub);
				getdvar_hooked = true;
				console::info("[gamemodes] GSC getdvar(g_gametype) override on (stride table 0x%llX, getdvar 0x%llX)\n",
					static_cast<unsigned long long>(stride_tables.front()),
					static_cast<unsigned long long>(function));
				return;
			}

			const auto function = *reinterpret_cast<const uintptr_t*>(tables.front() + h1_getdvar_id * sizeof(uintptr_t));
			if (!range_executable(ranges, function))
			{
				console::warn("[gamemodes] getdvar slot is not code, GSC getdvar override off\n");
				return;
			}

			getdvar_hook.create(reinterpret_cast<void*>(function), getdvar_stub);
			getdvar_hooked = true;
			console::info("[gamemodes] GSC getdvar(g_gametype) override on (table 0x%llX, getdvar 0x%llX)\n",
				static_cast<unsigned long long>(tables.front()), static_cast<unsigned long long>(function));
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
			localized_strings::override("MWX_GAMETYPE_OIC", "One in the Chamber");
			localized_strings::override("MWX_GAMETYPE_OIC_DESC",
				"Free-for-all with a single revolver round. Every kill gives one more round. Three lives.");
			localized_strings::override("MWX_GAMETYPE_AON", "All or Nothing");
			localized_strings::override("MWX_GAMETYPE_AON_DESC",
				"Free-for-all with an empty pistol, a throwing knife and Scavenger. 20 kills, 10 minutes.");
			localized_strings::override("MWX_GAMETYPE_CRANKED", "Cranked");
			localized_strings::override("MWX_GAMETYPE_CRANKED_DESC",
				"Team Deathmatch. A kill starts a 30 second fuse; keep killing to reset it, or explode.");
			localized_strings::override("MWX_PARTY_CAPS", "PARTY");

			// real extra gametypes: Infected (our port), Drop Zone (HMW's dz.gsc)
			localized_strings::override("MPUI_INFECT", "Infected");
			localized_strings::override("MPUI_INFECT_CAPS", "INFECTED");
			localized_strings::override("INFECT", "INFECTED");
			localized_strings::override("OBJECTIVES_INFECT", "Survivors: stay alive. Infected: infect the survivors.");
			localized_strings::override("OBJECTIVES_INFECT_SCORE", "Infect everyone, or survive the game to win.");
			localized_strings::override("OBJECTIVES_INFECT_HINT", "Survivors: stay alive. Infected: infect the survivors.");
			localized_strings::override("MPUI_DZ", "Drop Zone");
			localized_strings::override("MPUI_DZ_CAPS", "DROP ZONE");
			localized_strings::override("DZ", "DROP ZONE");
			localized_strings::override("MWX_GAMETYPE_DZ_DESC", "Capture the drop zone to earn points and care packages.");

			// caps names in the setup/pre-match menus
			localized_strings::override("MWX_GAMETYPE_PH_CAPS", "PROP HUNT");
			localized_strings::override("MWX_GAMETYPE_MPROPS_CAPS", "MAD PROPS");
			localized_strings::override("MWX_GAMETYPE_SLASHER_CAPS", "SLASHER");
			localized_strings::override("MWX_GAMETYPE_SNIPERS_CAPS", "SNIPERS ONLY");
			localized_strings::override("MWX_GAMETYPE_RPG_CAPS", "RPGS ONLY");
			localized_strings::override("MWX_GAMETYPE_OIC_CAPS", "ONE IN THE CHAMBER");
			localized_strings::override("MWX_GAMETYPE_AON_CAPS", "ALL OR NOTHING");
			localized_strings::override("MWX_GAMETYPE_CRANKED_CAPS", "CRANKED");

			// loadscreen names ("@" .. upper(ui_gametype))
			localized_strings::override("PH", "PROP HUNT");
			localized_strings::override("MPROPS", "MAD PROPS");
			localized_strings::override("SLASHER", "SLASHER");
			localized_strings::override("SNIPERS", "SNIPERS ONLY");
			localized_strings::override("RPG", "RPGS ONLY");
			localized_strings::override("OIC", "ONE IN THE CHAMBER");
			localized_strings::override("AON", "ALL OR NOTHING");
			localized_strings::override("CRANKED", "CRANKED");

			// HUD and splash strings of the One in the Chamber / All or Nothing / Cranked scripts
			localized_strings::override("MWX_OIC_LIVES_3", "LIVES: 3");
			localized_strings::override("MWX_OIC_LIVES_2", "LIVES: 2");
			localized_strings::override("MWX_OIC_LIVES_1", "LIVES: 1");
			localized_strings::override("MWX_OIC_LIVES_0", "LIVES: 0");
			localized_strings::override("MWX_AON_ONE_KILL", "1 KILL LEFT");
			localized_strings::override("MWX_AON_BONUS", "ALL OR NOTHING!");
			localized_strings::override("MWX_CRANKED", "CRANKED!");

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

			// M4: the party ref is the gametype; the mode dvars follow it (both on the server and on a
			// listen host/client, so a dedicated server with +set g_gametype slasher works too)
			dvars::callback::on_new_value("g_gametype", on_g_gametype);
			install_getdvar_override();
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

			scheduler::once([]()
			{
				dvars::register_string("mwx_gamemode", "", game::DVAR_FLAG_NONE,
					"Current MWX party game mode (empty for normal modes)");
				dvars::register_bool("mwx_gsc_print", false, game::DVAR_FLAG_NONE, "Print GSC print()/println() output to the console (release builds)");
				dvars::register_bool("mwx_debug_gamemodes", false, game::DVAR_FLAG_NONE,
					"Log gamemode dvar writes and the loading screen menu");
			}, scheduler::pipeline::main);
		}
	};
}

REGISTER_COMPONENT(gamemodes::component)
