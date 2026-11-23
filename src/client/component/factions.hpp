#pragma once
#include "game/game.hpp"


namespace factions
{
	// MWX: the ported Advanced Warfare maps set game["allies"] = "marines". Retail H1's
	// mp/factionTable.csv has that row, HMW's table may not, which left the allies team
	// without a name on the scoreboard (OpFor showed, the other team did not). Adds the
	// missing rows by copying a suitable MWR faction row.
	game::StringTable* patch_stringtable(game::StringTable* original);
}
