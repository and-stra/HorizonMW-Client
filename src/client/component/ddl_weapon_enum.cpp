#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "console.hpp"
#include "ddl_weapon_enum.hpp"
#include "dvars.hpp"
#include "scheduler.hpp"
#include "stock_weapons_data.hpp"

#include "game/game.hpp"
#include "game/dvars.hpp"

#include <utils/memory.hpp>
#include <utils/string.hpp>

#include <cctype>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

// Why this exists
// --------------
// `Cac.SelectEquippedWeapon` writes a class slot with Engine.SetPlayerData
// ("weaponSetups", 0, "weapon", <name>). The value is an 8 bit index into the
// playerdata DDL enum "Weapon" (228 members); a name that is not a member makes
// SetPlayerData return false, so the pick silently does nothing. The ported
// weapons (h1_* MWR, iw5_* AW) are not members.
//
// The enum has no free indices (228 of 256 used) and it must stay index stable:
// saved classes store the index. But it repeats names at separate indices
// ("none" three times, camo016..camo062 twice, ...). A repeated index is
// unreachable through the name hash (lookups resolve to the first occurrence),
// so it is a free slot that can carry one of the ported names.

namespace ddl_weapon_enum
{
	namespace
	{
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
			for (; *s; ++s)
			{
				h ^= static_cast<unsigned char>(std::tolower(static_cast<unsigned char>(*s)));
				h *= 0x1000193u;
			}
			return h;
		}

		unsigned int hash_sdbm(const char* s)
		{
			unsigned int h = 0;
			for (; *s; ++s)
				h = static_cast<unsigned char>(std::tolower(static_cast<unsigned char>(*s))) + (h << 6) + (h << 16) - h;
			return h;
		}

		unsigned int hash_mul31(const char* s)
		{
			unsigned int h = 0;
			for (; *s; ++s) h = h * 31 + static_cast<unsigned char>(std::tolower(static_cast<unsigned char>(*s)));
			return h;
		}

		struct hash_candidate
		{
			const char* name;
			unsigned int (*fn)(const char*);
		};

		const hash_candidate candidates[] = {
			{"djb2", hash_djb2},
			{"fnv1a", hash_fnv1a},
			{"sdbm", hash_sdbm},
			{"mul31", hash_mul31},
		};

		// Match the enum's own hash entries against the candidates. An entry is
		// {hash, index}; the member at that index must hash to that value.
		const hash_candidate* detect_hash(const game::DDLEnum& e)
		{
			if (!e.hashTable.list || e.hashTable.count <= 0)
			{
				return nullptr;
			}

			for (const auto& candidate : candidates)
			{
				auto checked = 0;
				auto ok = true;
				for (auto i = 0; i < e.hashTable.count && checked < 64; ++i)
				{
					const auto& entry = e.hashTable.list[i];
					if (entry.hash == 0)
					{
						continue;
					}
					if (entry.index < 0 || entry.index >= e.memberCount || !e.members[entry.index])
					{
						continue;
					}
					++checked;
					if (candidate.fn(e.members[entry.index]) != entry.hash)
					{
						ok = false;
						break;
					}
				}
				if (ok && checked > 0)
				{
					return &candidate;
				}
			}
			return nullptr;
		}

		// The enum hash table is a compact array of `count` entries **sorted by hash**
		// (lookup is a binary search; `max` is the allocation capacity). The first
		// attempt used open addressing (hash % max) and broke every name lookup.
		bool insert_hash(game::DDLEnum& e, unsigned int hash, int index)
		{
			auto& table = e.hashTable;
			if (!table.list || table.max <= 0)
			{
				return false;
			}

			if (table.count >= table.max)
			{
				const auto new_max = table.max * 2;
				auto* list = allocator.allocate_array<game::DDLHash>(static_cast<size_t>(new_max));
				std::memcpy(list, table.list, sizeof(game::DDLHash) * static_cast<size_t>(table.count));
				table.list = list;
				table.max = new_max;
			}

			auto lo = 0;
			auto hi = table.count;
			while (lo < hi)
			{
				const auto mid = (lo + hi) / 2;
				if (table.list[mid].hash < hash)
				{
					lo = mid + 1;
				}
				else
				{
					hi = mid;
				}
			}

			std::memmove(&table.list[lo + 1], &table.list[lo],
				sizeof(game::DDLHash) * static_cast<size_t>(table.count - lo));
			table.list[lo].hash = hash;
			table.list[lo].index = index;
			++table.count;
			return true;
		}

		game::DDLEnum* find_weapon_enum(game::DDLDef* def)
		{
			for (auto e = 0; e < def->enumCount; ++e)
			{
				auto& enumeration = def->enumList[e];
				if (enumeration.name && std::strcmp(enumeration.name, "Weapon") == 0)
				{
					return &enumeration;
				}
			}
			return nullptr;
		}
	}

	nlohmann::json extend()
	{
		game::DDLContext context{};
		const auto stats_source = game::LiveStorage_GetActiveStatsSource(0);
		if (!game::CL_PlayerData_GetDDLBuffer(&context, 0, 0, stats_source) || !context.def)
		{
			return nlohmann::json{{"error", "no playerdata ddl"}};
		}

		auto* enumeration = find_weapon_enum(const_cast<game::DDLDef*>(context.def));
		if (!enumeration)
		{
			return nlohmann::json{{"error", "no Weapon enum"}};
		}

		// names already in the enum -> first index
		std::unordered_map<std::string, int> first_index;
		first_index.reserve(static_cast<size_t>(enumeration->memberCount) * 2);
		std::vector<int> free_slots;
		for (auto i = 0; i < enumeration->memberCount; ++i)
		{
			const auto* member = enumeration->members[i];
			if (member == nullptr || member[0] == '\0')
			{
				free_slots.push_back(i);
				continue;
			}
			const auto inserted = first_index.emplace(member, i);
			if (!inserted.second)
			{
				// a repeated name: this index is unreachable through the hash
				free_slots.push_back(i);
			}
		}

		const auto* hash = detect_hash(*enumeration);

		// our weapon base names (the class stores the name without _mp)
		std::vector<std::string> wanted;
		std::unordered_map<std::string, bool> seen;
		for (const auto& row : stock_weapons::rows)
		{
			const auto* ref = row[4];
			if (!ref || !ref[0] || seen[ref])
			{
				continue;
			}
			seen[ref] = true;
			wanted.emplace_back(ref);
		}

		nlohmann::json added = nlohmann::json::array();
		nlohmann::json present = nlohmann::json::array();
		nlohmann::json skipped = nlohmann::json::array();
		auto duplicates_used = 0;
		auto appended = 0;

		// The class slot is an 8 bit enum index, so the enum can hold at most 256
		// members. Repeated names give 51 free indices; the rest is appended until 256.
		constexpr auto enum_capacity = 256;

		// write into one new array so the game's own member list stays untouched
		std::vector<const char*> members(enumeration->members, enumeration->members + enumeration->memberCount);

		for (const auto& name : wanted)
		{
			if (first_index.find(name) != first_index.end())
			{
				present.push_back(name);
				continue;
			}

			int slot = -1;
			if (duplicates_used < static_cast<int>(free_slots.size()))
			{
				slot = free_slots[duplicates_used++];
			}
			else if (static_cast<int>(members.size()) < enum_capacity)
			{
				slot = static_cast<int>(members.size());
				members.push_back(nullptr);
				++appended;
			}
			else
			{
				skipped.push_back(name);
				continue;
			}

			members[slot] = allocator.duplicate_string(name);
			first_index[name] = slot;
			added.push_back(name);

			if (hash)
			{
				insert_hash(*enumeration, hash->fn(name.c_str()), slot);
			}
		}

		if (!added.empty())
		{
			auto* array = allocator.allocate_array<const char*>(members.size());
			std::memcpy(array, members.data(), sizeof(const char*) * members.size());
			enumeration->members = array;
			enumeration->memberCount = static_cast<int>(members.size());
		}

		return nlohmann::json{
			{"enum_count", enumeration->memberCount},
			{"free_slots", free_slots.size()},
			{"appended", appended},
			{"capacity", enum_capacity},
			{"hash", hash ? hash->name : "none"},
			{"added", std::move(added)},
			{"present", std::move(present)},
			{"skipped", std::move(skipped)},
		};
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			dvars::register_bool("mwx_cac_enum", true, game::DVAR_FLAG_NONE,
				"Add the ported weapon names to the playerdata Weapon enum (CAC storage)");

			// The playerdata DDL only exists once the stats source is up (entering the
			// lobby), so poll on the main pipeline until the first successful extension.
			scheduler::loop([]
			{
				static auto done = false;
				if (done)
				{
					return;
				}
				const auto* enabled = game::Dvar_FindVar("mwx_cac_enum");
				if (!enabled || !enabled->current.enabled)
				{
					return;
				}
				const auto report = extend();
				if (!report.contains("enum_count"))
				{
					return;
				}
				done = true;
				console::info("[ddl] weapon enum: %i members, %i free slots, hash %s, added %i, skipped %i\n",
					report["enum_count"].get<int>(), report["free_slots"].get<int>(),
					report["hash"].get<std::string>().data(),
					static_cast<int>(report["added"].size()), static_cast<int>(report["skipped"].size()));
			}, scheduler::pipeline::main, std::chrono::seconds(2));
		}
	};
}

REGISTER_COMPONENT(ddl_weapon_enum::component)
