#pragma once
#include "game/game.hpp"

// MWX: Prop Hunt prop lists for maps whose fastfile has no mp/ph_props_<map>.csv.
// tools/ph-props generates them from the zone's xmodel list + the XModel asset bounds;
// they live in GAME\mwx\ph_props\<map>.csv and are injected as a string table here
// (same place as the factionTable / stock weapon patches).
namespace ph_props
{
	// remembers the cell hash used by the loaded tables (nullptr until one was seen)
	void note_stringtable(const game::StringTable* table);

	// returns a synthesized table for "mp/ph_props_<map>.csv" when the asset is missing
	// and a generated file exists; otherwise `original`
	game::StringTable* patch_stringtable(const char* name, game::StringTable* original);

	// true when a generated table exists for this asset name (for DB_XAssetExists)
	bool generated_table_exists(const char* name);

	// true when this asset name is one of the generated prop lists
	bool is_prop_table(const char* name);
}
