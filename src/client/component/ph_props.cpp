#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"

#include "console.hpp"
#include "ph_props.hpp"
#include "stock_weapons.hpp"

#include <utils/memory.hpp>
#include <utils/io.hpp>

#include <cstring>
#include <cctype>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

// Prop Hunt reads its prop list as a string table:
//   maps\mp\gametypes\_hodgepodge_ph.gsc::populateproplist()
//   mp\ph_props_<map>.csv -> tablegetrowcount / tablelookupbyrow(..., col 0..8)
// MWR only ships that table for a handful of maps. tools/ph-props generates one per map
// from the zone's xmodels.txt (name filter + XModel bounds), and this component serves it
// through the asset lookup so the unchanged gametype script finds it.
//
// The generated file is a small CSV in GAME\mwx\ph_props\<map>.csv:
//   model,xsmall|small|medium|large,0
// (three columns = the ones populateproplist uses for a plain prop; the optional offset /
// angle columns stay at 0/undefined).
namespace ph_props
{
	namespace
	{
		constexpr auto asset_prefix = "mp/ph_props_";
		constexpr auto asset_suffix = ".csv";
		constexpr auto file_dir = "mwx/ph_props/";
		constexpr int column_count = 3;

		utils::memory::allocator allocator;
		std::mutex mutex;

		stock_weapons::hash_fn cached_hash = nullptr;

		struct table_entry
		{
			game::StringTable* table = nullptr;
			std::uint32_t size = 0;
			std::uint64_t stamp = 0;
			bool broken = false;
		};

		std::unordered_map<std::string, table_entry> tables;

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

		// "mp/ph_props_mp_rust.csv" -> "mp_rust"
		std::string map_from_asset(const char* name)
		{
			if (!name)
			{
				return {};
			}

			std::string value = name;
			for (auto& c : value)
			{
				c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
				if (c == '\\')
				{
					c = '/';
				}
			}

			const std::string prefix = asset_prefix;
			const std::string suffix = asset_suffix;
			if (value.size() <= prefix.size() + suffix.size() || value.compare(0, prefix.size(), prefix) != 0 ||
				value.compare(value.size() - suffix.size(), suffix.size(), suffix) != 0)
			{
				return {};
			}

			return value.substr(prefix.size(), value.size() - prefix.size() - suffix.size());
		}

		std::string trim(const std::string& value)
		{
			auto begin = value.find_first_not_of(" \t\r\n");
			if (begin == std::string::npos)
			{
				return {};
			}
			auto end = value.find_last_not_of(" \t\r\n");
			return value.substr(begin, end - begin + 1);
		}

		bool valid_size_class(const std::string& value)
		{
			return value == "xsmall" || value == "small" || value == "medium" || value == "large";
		}

		std::uint64_t file_stamp(const std::string& path)
		{
			WIN32_FILE_ATTRIBUTE_DATA data{};
			if (!GetFileAttributesExA(path.data(), GetFileExInfoStandard, &data))
			{
				return 0;
			}
			return (static_cast<std::uint64_t>(data.ftLastWriteTime.dwHighDateTime) << 32) |
				data.ftLastWriteTime.dwLowDateTime;
		}

		game::StringTable* build_table(const std::string& map, const std::string& path)
		{
			std::string data{};
			if (!utils::io::read_file(path, &data))
			{
				return nullptr;
			}

			std::vector<std::vector<std::string>> rows;
			std::size_t pos = 0;
			while (pos <= data.size())
			{
				auto end = data.find('\n', pos);
				if (end == std::string::npos)
				{
					end = data.size();
				}

				auto line = data.substr(pos, end - pos);
				pos = end + 1;

				if (pos == 1 && line.size() >= 3 && static_cast<unsigned char>(line[0]) == 0xEF) // BOM
				{
					line = line.substr(3);
				}

				if (!line.empty() && line.back() == '\r')
				{
					line.pop_back();
				}

				auto first = line.find_first_not_of(" \t");
				if (first == std::string::npos || line[first] == '#')
				{
					continue;
				}

				std::vector<std::string> cells;
				std::size_t start = 0;
				for (;;)
				{
					const auto comma = line.find(',', start);
					cells.push_back(trim(line.substr(start, comma == std::string::npos ? std::string::npos : comma - start)));
					if (comma == std::string::npos)
					{
						break;
					}
					start = comma + 1;
				}

				if (cells.empty() || cells[0].empty())
				{
					continue;
				}
				if (cells.size() < 2 || !valid_size_class(cells[1]))
				{
					console::warn("ph_props: %s: bad row '%s' (expected model,size class)\n", path.data(), line.data());
					continue;
				}
				if (cells.size() < static_cast<std::size_t>(column_count))
				{
					cells.resize(column_count);
				}
				cells.resize(column_count);
				if (cells[2].empty())
				{
					cells[2] = "0";
				}

				rows.push_back(std::move(cells));
			}

			if (rows.empty())
			{
				return nullptr;
			}

			if (!cached_hash)
			{
				console::warn("ph_props: no string table hash known yet, %s not injected\n", path.data());
				return nullptr;
			}

			auto* table = allocator.allocate<game::StringTable>();
			table->name = allocator.duplicate_string(("mp/ph_props_" + map + ".csv").data());
			table->columnCount = column_count;
			table->rowCount = static_cast<int>(rows.size());
			table->values = allocator.allocate_array<game::StringTableCell>(
				static_cast<std::size_t>(column_count) * rows.size());

			for (std::size_t r = 0; r < rows.size(); ++r)
			{
				for (auto c = 0; c < column_count; ++c)
				{
					const auto text = rows[r][static_cast<std::size_t>(c)];
					auto& cell = table->values[r * column_count + c];
					cell.string = allocator.duplicate_string(text.data());
					cell.hash = static_cast<int>(cached_hash(cell.string));
				}
			}

			console::info("ph_props: injected %s (%i props) for %s\n", table->name, table->rowCount, map.data());
			return table;
		}
	}

	bool is_prop_table(const char* name)
	{
		return !map_from_asset(name).empty();
	}

	bool generated_table_exists(const char* name)
	{
		const auto map = map_from_asset(name);
		if (map.empty())
		{
			return false;
		}

		const auto path = std::string(file_dir) + "ph_props_" + map + ".csv";
		return file_stamp(path) != 0;
	}

	void note_stringtable(const game::StringTable* table)
	{
		if (cached_hash || !table || !table->values || table->columnCount < 1 || table->rowCount < 1)
		{
			return;
		}

		std::lock_guard<std::mutex> lock(mutex);
		if (!cached_hash)
		{
			cached_hash = stock_weapons::find_hash(table);
		}
	}

	game::StringTable* patch_stringtable(const char* name, game::StringTable* original)
	{
		if (name && std::strstr(name, "ph_props"))
		{
			console::debug("ph_props: lookup '%s' (rows %i, hash %s)\n", name, original ? original->rowCount : -1,
				cached_hash ? "yes" : "no");
		}

		if (original && original->rowCount > 0)
		{
			note_stringtable(original);
			return original;
		}

		if (original)
		{
			// a missing string table comes back as an empty "default" asset (allow_create_default);
			// the generated one replaces it
			note_stringtable(original);
		}

		const auto map = map_from_asset(name);
		if (map.empty())
		{
			return original;
		}

		std::lock_guard<std::mutex> lock(mutex);

		const auto path = std::string(file_dir) + "ph_props_" + map + ".csv";
		const auto stamp = file_stamp(path);
		if (stamp == 0)
		{
			return original;
		}

		auto& entry = tables[map];
		if (entry.table && entry.stamp == stamp)
		{
			return entry.table;
		}

		if (entry.broken && entry.stamp == stamp)
		{
			return original;
		}

		entry = {};
		entry.stamp = stamp;
		entry.table = build_table(map, path);
		entry.broken = entry.table == nullptr;
		return entry.table ? entry.table : original;
	}

	class component final : public component_interface
	{
	};
}

REGISTER_COMPONENT(ph_props::component)
