#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"

#include "console.hpp"
#include "factions.hpp"
#include "localized_strings.hpp"
#include "stock_weapons.hpp"

#include <utils/memory.hpp>

#include <cstring>
#include <cctype>
#include <vector>
#include <string>
#include <mutex>

// MWX: faction names for the ported Advanced Warfare maps (see factions.hpp).
// AW's MP maps use two factions: "marines" (allies) and "opfor" (axis). HMW's
// mp/factionTable.csv knows opfor but (at least in the tables the ports load) not marines,
// so the allies header on the scoreboard and the team-selection screen stayed empty.
namespace factions
{
	namespace
	{
		constexpr auto faction_table = "mp/factionTable.csv";

		utils::memory::allocator allocator;

		struct faction_row
		{
			const char* ref;          // ref used by the AW map scripts
			const char* template_ref; // existing row whose icons/colors/sounds are copied
			const char* name;         // localized full name (column 1)
			const char* short_name;   // localized short name (column 2)
		};

		constexpr faction_row faction_rows[] =
		{
			{"marines", "tf141", "MP_MARINES_NAME", "MPUI_MARINES_SHORT"},
			{"sas", "tf141", "MP_SAS_NAME", "MPUI_SAS_SHORT"},
		};

		bool equals_ignore_case(const char* a, const char* b)
		{
			if (!a || !b)
			{
				return false;
			}

			while (*a && *b)
			{
				if (std::tolower(static_cast<unsigned char>(*a)) != std::tolower(static_cast<unsigned char>(*b)))
				{
					return false;
				}
				++a;
				++b;
			}

			return *a == '\0' && *b == '\0';
		}

		struct cached_table
		{
			game::StringTable* original = nullptr;
			game::StringTable* result = nullptr;
			bool done = false;
		} cache;

		std::mutex cache_mutex;

		game::StringTable* build_stringtable(game::StringTable* original)
		{
			if (!original->name || original->columnCount < 3 || original->rowCount < 1)
			{
				return nullptr;
			}

			const auto hash = stock_weapons::find_hash(original);
			if (!hash)
			{
				console::warn("factions: cannot work out the cell hash of %s, not adding\n", faction_table);
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

			std::vector<faction_row> rows;
			for (const auto& row : faction_rows)
			{
				if (row_of(row.ref) < 0)
				{
					rows.push_back(row);
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
				auto template_row = row_of(row.template_ref);
				if (template_row < 0)
				{
					template_row = row_of("opfor");
				}
				if (template_row < 0)
				{
					template_row = 0; // any row is better than none for icons/colors
				}

				for (auto c = 0; c < cols; ++c)
				{
					const auto& src = original->values[static_cast<size_t>(template_row) * cols + c];
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
						text = row.short_name;
					}

					auto& cell = result->values[static_cast<size_t>(old_rows + static_cast<int>(n)) * cols + c];
					cell.string = allocator.duplicate_string(text);
					cell.hash = static_cast<int>(hash(text));
				}

				console::info("factions: added %s (template %s) to %s\n", row.ref,
					original->values[static_cast<size_t>(template_row) * cols].string, faction_table);
			}

			return result;
		}
	}

	game::StringTable* patch_stringtable(game::StringTable* original)
	{
		if (!original || !original->name || !equals_ignore_case(original->name, faction_table))
		{
			return original;
		}

		std::lock_guard<std::mutex> lock(cache_mutex);
		if (cache.original != original)
		{
			cache.original = original;
			cache.result = nullptr;
			cache.done = false;
		}

		if (cache.done)
		{
			return cache.result ? cache.result : original;
		}

		cache.result = build_stringtable(original);
		cache.done = true;
		return cache.result ? cache.result : original;
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			// The AW maps' faction refs; the values match MWR's own faction strings.
			localized_strings::override("MP_MARINES_NAME", "Marines");
			localized_strings::override("MPUI_MARINES_SHORT", "Marines");
			localized_strings::override("MP_MARINES_ELIMINATED", "Marines eliminated");
			localized_strings::override("MP_MARINES_FORFEITED", "Marines forfeited");
			localized_strings::override("MP_SAS_NAME", "SAS");
			localized_strings::override("MPUI_SAS_SHORT", "SAS");
		}
	};
}

REGISTER_COMPONENT(factions::component)
