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

	// M4: the party refs are real gametypes whose script is the base gametype's script under another
	// name. Returns the real script name to load for `name` ("maps/mp/gametypes/<ref>" ->
	// "maps/mp/gametypes/war"), or nullptr when `name` is not a party ref.
	const char* script_alias(const char* name);

	// Sets scr_game_hodgepodgeMode / scr_game_madprops / mwx_gamemode for a g_gametype value.
	void apply_gametype(const char* gametype);

	// Appends the virtual refs to maps/mp/gametypes/_gametypes.txt.
	game::RawFile* patch_rawfile(game::RawFile* original);

	// Appends one row per virtual mode to mp/gameTypesTable.csv.
	game::StringTable* patch_stringtable(game::StringTable* original);
}
