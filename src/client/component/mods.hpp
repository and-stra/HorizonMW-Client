#pragma once

#include <optional>
#include <string>
#include <vector>

namespace mods
{
	// A gametype a mod brings (mod.json "gametypes"): registered like the built-in extra gametypes
	// (allowed-gametype list, gametypes table row, PARTY list in the menu).
	struct mod_gametype
	{
		std::string ref;
		std::string template_ref; // gametypes table row to copy the icon and flags from (dm, war, ...)
		std::string name_key;     // localized name key (MWXMOD_<REF>)
		std::string desc_key;     // localized description key (MWXMOD_<REF>_DESC)
		bool class_choice;        // false = fixed gamemode loadout, like Infected
	};

	// path is relative to the game folder ("mods/<name>"), "" = no mod
	void set_mod(const std::string& path, bool change_fs_game = true);
	std::optional<std::string> get_mod();

	const std::vector<mod_gametype>& get_gametypes();

	// "path\tname\tdescription\n" per mod folder in mods/ (for the MODS menu)
	std::string list_mods();
}
