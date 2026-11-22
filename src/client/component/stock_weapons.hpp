#pragma once
#include "game/game.hpp"


namespace stock_weapons
{
	using hash_fn = unsigned int (*)(const char*);

	// Detects the cell hash used by a string table (nullptr when none matches).
	hash_fn find_hash(const game::StringTable* table);

	// Appends the stock MWR (h1_*) weapon rows to HMW's weapon tables
	// (mp/statstable.csv, mp/customweapons.csv) for the weapons whose files are
	// loaded. Returns the table to use (the original when nothing is added).
	game::StringTable* patch(game::StringTable* original);
}
