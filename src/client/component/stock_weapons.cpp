#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "console.hpp"
#include "game/game.hpp"

#include "stock_weapons.hpp"
#include "stock_weapons_data.hpp"

#include <utils/memory.hpp>
#include <utils/string.hpp>

#include <cctype>
#include <cstring>
#include <algorithm>
#include <functional>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace stock_weapons
{
	namespace
	{
		struct cached
		{
			game::StringTable* original;
			game::StringTable* result;
			int last_try;
			bool done;
		};

		std::mutex tables_mutex;
		std::unordered_map<std::string, cached> tables;
		utils::memory::allocator allocator;

		unsigned int hash_djb2(const char* s)
		{
			unsigned int h = 5381;
			for (; *s; ++s) h = h * 33 + static_cast<unsigned char>(std::tolower(static_cast<unsigned char>(*s)));
			return h;
		}

		unsigned int hash_fnv1a(const char* s)
		{
			unsigned int h = 0x811C9DC5u;
			for (; *s; ++s) { h ^= static_cast<unsigned char>(std::tolower(static_cast<unsigned char>(*s))); h *= 0x1000193u; }
			return h;
		}

		unsigned int hash_sdbm(const char* s)
		{
			unsigned int h = 0;
			for (; *s; ++s) h = static_cast<unsigned char>(std::tolower(static_cast<unsigned char>(*s))) + (h << 6) + (h << 16) - h;
			return h;
		}

		unsigned int hash_31(const char* s)
		{
			unsigned int h = 0;
			for (; *s; ++s) h = h * 31 + static_cast<unsigned char>(std::tolower(static_cast<unsigned char>(*s)));
			return h;
		}

		// The cell hash the engine uses is found by checking candidates against
		// the table's own cells; nothing is added when none of them matches.
		hash_fn find_hash_internal(const game::StringTable* table)
		{
			const hash_fn candidates[] = { hash_djb2, hash_fnv1a, hash_sdbm, hash_31 };
			const auto cells = table->columnCount * table->rowCount;
			for (const auto fn : candidates)
			{
				auto checked = 0;
				auto ok = true;
				for (auto i = 0; i < cells && checked < 200; ++i)
				{
					const auto& cell = table->values[i];
					if (!cell.string || !cell.string[0])
					{
						continue;
					}
					++checked;
					if (static_cast<unsigned int>(cell.hash) != fn(cell.string))
					{
						ok = false;
						break;
					}
				}
				if (ok && checked > 0)
				{
					return fn;
				}
			}
			return nullptr;
		}

		bool weapon_loaded(const std::string& ref)
		{
			const auto name = ref + "_mp";
			return game::DB_XAssetExists(game::ASSET_TYPE_WEAPON, name.data()) != 0 &&
				!game::DB_IsXAssetDefault(game::ASSET_TYPE_WEAPON, name.data());
		}

		// mp/customweapons.csv is (name, class, type); the type is the Cac.Weapons group
		// (Primary/Secondary/Lethal/Tactical). The statstable rows only carry the class.
		const char* customweapon_type(const char* weapon_class)
		{
			if (!weapon_class)
			{
				return "";
			}

			if (!std::strcmp(weapon_class, "weapon_assault") ||
				!std::strcmp(weapon_class, "weapon_smg") ||
				!std::strcmp(weapon_class, "weapon_sniper") ||
				!std::strcmp(weapon_class, "weapon_heavy") ||
				!std::strcmp(weapon_class, "weapon_shotgun"))
			{
				return "Primary";
			}

			if (!std::strcmp(weapon_class, "equipment_lethal"))
			{
				return "Lethal";
			}

			if (!std::strcmp(weapon_class, "equipment_tactical"))
			{
				return "Tactical";
			}

			// pistols, machine pistols, secondary shotguns, launchers and melee
			return "Secondary";
		}

		bool id_exists(const game::StringTable* table, const char* id)
		{
			for (auto r = 0; r < table->rowCount; ++r)
			{
				const auto text = table->values[static_cast<size_t>(r) * table->columnCount].string;
				if (text && std::strcmp(text, id) == 0)
				{
					return true;
				}
			}
			return false;
		}

		game::StringTable* build(game::StringTable* original, const std::string& name, bool* complete)
		{
			const auto is_stats = name == "mp/statstable.csv";
			// MWX: HMW's current statstable has 67 columns; the stock rows carry one extra empty
			// trailing column, which is simply cut off (everything before it lines up).
			constexpr int table_columns = 67;
			if (is_stats && original->columnCount != table_columns)
			{
				// MWX: dump the real table once so the missing column can be identified
				static bool dumped = false;
				if (!dumped)
				{
					dumped = true;
					CreateDirectoryA("mwx-logs", nullptr);
					if (FILE* f = fopen("mwx-logs/statstable_dump.csv", "w"))
					{
						for (auto r = 0; r < original->rowCount; ++r)
						{
							for (auto c = 0; c < original->columnCount; ++c)
							{
								const auto& cell = original->values[static_cast<size_t>(r) * original->columnCount + c];
								fprintf(f, "%s\"%s\"", c ? "," : "", cell.string ? cell.string : "");
							}
							fputc('\n', f);
						}
						fclose(f);
					}
				}
				console::warn("stock weapons: %s has %i columns (need %i), not adding\n",
					name.data(), original->columnCount, table_columns);
				return nullptr;
			}
			if (!is_stats && original->columnCount < 1)
			{
				return nullptr;
			}

			const auto hash = find_hash_internal(original);
			if (!hash)
			{
				console::warn("stock weapons: cannot work out the cell hash of %s, not adding\n", name.data());
				return nullptr;
			}

			// item 12: the 28 melee rows are new; with hmw_mwr_weapons 0 the CAC stays as before
			const auto* mwr_weapons_dvar = game::Dvar_FindVar("hmw_mwr_weapons");
			const bool mwr_weapons_on = !mwr_weapons_dvar || mwr_weapons_dvar->current.enabled;

			std::vector<int> add;
			std::vector<std::string> missing;
			for (auto i = 0; i < row_count; ++i)
			{
				if (!mwr_weapons_on && std::strcmp(rows[i][2], "weapon_melee") == 0)
				{
					continue;
				}

				const std::string ref = rows[i][4];
				if (is_stats && id_exists(original, rows[i][0]))
				{
					missing.push_back(ref); // the weapon id is already used by an HMW weapon
					continue;
				}
				if (weapon_loaded(ref))
				{
					add.push_back(i);
				}
				else
				{
					missing.push_back(ref);
				}
			}

			if (add.empty())
			{
				return nullptr;
			}

			const auto cols = original->columnCount;
			const auto old_rows = original->rowCount;

			// The customweapons row order is the CAC display order. Put our weapons at the
			// top of their list (AW before MWR), otherwise they sit past the visible rows.
			const bool prepend = !is_stats && name == "mp/customweapons.csv";
			if (prepend)
			{
				std::stable_sort(add.begin(), add.end(), [](int a, int b)
				{
					const std::string ra = rows[a][4];
					const std::string rb = rows[b][4];
					const bool aw_a = ra.rfind("iw5_", 0) == 0;
					const bool aw_b = rb.rfind("iw5_", 0) == 0;
					return aw_a != aw_b ? aw_a : a < b;
				});
			}

			const auto result = allocator.allocate<game::StringTable>();
			*result = *original;

			// Hide rows whose weapon asset does not exist (HMW's table lists h2_fmg9, h2_mp412,
			// h2_pm9, h2_mp7 with no weapon asset): display filter only, the ids and the
			// statstable rows stay as they are. A row that is only missing because its zone has
			// not loaded yet counts as missing, so the table is rebuilt when it does.
			auto kept_rows = old_rows;
			if (!is_stats)
			{
				kept_rows = 0;
				for (auto r = 0; r < old_rows; ++r)
				{
					const auto* ref = original->values[static_cast<size_t>(r) * cols].string;
					if (ref != nullptr && ref[0] != '\0' && !weapon_loaded(ref))
					{
						// HMW's own table rows for weapons that have no asset at all: drop them
						// for good, they can never load (unlike our appended rows, which wait).
						continue;
					}
					++kept_rows;
				}
			}

			const auto first_new = prepend ? 0 : kept_rows;
			const auto originals_at = prepend ? static_cast<int>(add.size()) : 0;
			const auto new_rows = kept_rows + static_cast<int>(add.size());
			result->rowCount = new_rows;
			result->values = allocator.allocate_array<game::StringTableCell>(static_cast<size_t>(cols) * new_rows);

			if (is_stats)
			{
				std::memcpy(result->values, original->values, sizeof(game::StringTableCell) * cols * old_rows);
			}
			else
			{
				auto out = 0;
				for (auto r = 0; r < old_rows; ++r)
				{
					const auto* ref = original->values[static_cast<size_t>(r) * cols].string;
					if (ref != nullptr && ref[0] != '\0' && !weapon_loaded(ref))
					{
						continue;
					}
					std::memcpy(result->values + static_cast<size_t>(originals_at + out) * cols,
						original->values + static_cast<size_t>(r) * cols, sizeof(game::StringTableCell) * cols);
					++out;
				}
			}

			for (size_t n = 0; n < add.size(); ++n)
			{
				const auto& src = rows[add[n]];
				for (auto c = 0; c < cols; ++c)
				{
					const char* text = "";
					if (is_stats)
					{
						text = src[c];
					}
					else if (c == 0)
					{
						text = src[4]; // the weapon ref
					}
					else if (c == 1)
					{
						text = src[2]; // its class (weapon_assault, ...)
					}
					else if (c == 2)
					{
						text = customweapon_type(src[2]); // Cac.Weapons group
					}
					auto& cell = result->values[static_cast<size_t>(first_new + static_cast<int>(n)) * cols + c];
					cell.string = allocator.duplicate_string(text);
					cell.hash = static_cast<int>(hash(text));
				}
			}

			// a weapon zone that loads later still needs its row: only stop rebuilding when every
			// row is in (rows skipped as duplicates stay missing, so that case rebuilds on demand)
			if (complete != nullptr)
			{
				*complete = missing.empty();
			}

			console::info("stock weapons: %s: added %i stock weapons (%i not loaded)\n",
				name.data(), static_cast<int>(add.size()), static_cast<int>(missing.size()));
			return result;
		}
	}

	hash_fn find_hash(const game::StringTable* table)
	{
		return find_hash_internal(table);
	}

	game::StringTable* patch(game::StringTable* original)
	{
		if (!original || !original->name)
		{
			return original;
		}

		const std::string name = original->name;
		if (name != "mp/statstable.csv" && name != "mp/customweapons.csv")
		{
			return original;
		}

		std::lock_guard<std::mutex> lock(tables_mutex);
		auto& entry = tables[name];
		if (entry.original != original)
		{
			entry = {original, nullptr, 0, false};
		}
		if (entry.done)
		{
			return entry.result ? entry.result : original;
		}

		// (Weapon zones may not be loaded yet: try again later, not every call.)
		const auto now = game::Sys_Milliseconds();
		if (entry.last_try != 0 && now - entry.last_try < 2000)
		{
			return entry.result ? entry.result : original;
		}
		entry.last_try = now;

		auto complete = false;
		const auto result = build(original, name, &complete);
		if (result)
		{
			entry.result = result;
			entry.done = complete;
			return result;
		}
		return entry.result ? entry.result : original;
	}
}
