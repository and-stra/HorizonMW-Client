#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "localized_strings.hpp"

// Ported Advanced Warfare weapons. The weapon assets live in hmw_aw_weapons.ff (loaded by
// patches.cpp after the HMW zones); the statstable rows are in stock_weapons_data.hpp and the CAC
// glue is data/mwx/ui_scripts/aw_weapons + data/mwx/scripts/mp/aw_weapons.gsc.
// The AW weapon definitions carry localization keys such as MDLC6_DLCGUN23; the rows use
// WEAPON_AW_* keys so the real-world name shows in Create-a-Class and the kill feed.

namespace aw_weapons
{
	namespace
	{
		constexpr std::pair<const char*, const char*> names[] =
		{
			{"WEAPON_EXPLOSIVE_EXO_CROSSBOW", "Crossbow"},
			{"WEAPON_AW_M1GARAND", "M1 Garand"},
			{"WEAPON_AW_MP40", "MP40"},
			{"WEAPON_AW_COMBATKNIFE", "Combat Knife"},
		};

		constexpr std::pair<const char*, const char*> descriptions[] =
		{
			{"WEAPON_EXPLOSIVE_EXO_CROSSBOW_DESC",
				"Bolt-action crossbow. Fires explosive bolts that stick and detonate."},
			{"WEAPON_AW_M1GARAND_DESC",
				"Semi-automatic rifle. The classic M1 Garand."},
			{"WEAPON_AW_MP40_DESC",
				"Fully automatic submachine gun. The classic MP40."},
			{"WEAPON_AW_COMBATKNIFE_DESC",
				"Combat knife."},
		};
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			for (const auto& [key, value] : names)
			{
				localized_strings::override(key, value);
			}

			for (const auto& [key, value] : descriptions)
			{
				localized_strings::override(key, value);
			}
		}
	};
}

REGISTER_COMPONENT(aw_weapons::component)
