#pragma once
#include "game/game.hpp"

#include <string>

namespace gamemodes
{
	struct mode
	{
		const char* ref;
		const char* base;
		int hodgepodge;
		int madprops;
		const char* name;
		const char* desc;
	};

	// The virtual party game modes in one place.
	const mode* find(const std::string& ref);

	// Appends the virtual refs to maps/mp/gametypes/_gametypes.txt.
	game::RawFile* patch_rawfile(game::RawFile* original);

	// Appends one row per virtual mode to mp/gameTypesTable.csv.
	game::StringTable* patch_stringtable(game::StringTable* original);
}
