#pragma once

// (nlohmann::json comes from the PCH, like debug_api.hpp)

// The CAC stores a class slot as an index into the playerdata DDL "Weapon" enum
// (8 bit). Names that are not members cannot be saved (Engine.SetPlayerData
// returns false) - this is why the ported h1_* / iw5_* weapons could not be
// selected. The enum has no free slots, but it contains duplicate names at
// separate indices ("none" three times, camo016..camo062 twice, ...); those
// indices are unreachable through the name hash and can hold the ported names.
namespace ddl_weapon_enum
{
	// Adds the custom weapon names (stock_weapons::rows) to the playerdata Weapon enum.
	// Safe to call repeatedly; returns a report: {added, present, skipped, free, hash}.
	nlohmann::json extend();
}
