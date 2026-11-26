#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "localized_strings.hpp"

// Item 13: ported Advanced Warfare weapons. The weapon assets live in hmw_aw_weapons.ff (loaded by
// patches.cpp after the HMW zones); the statstable rows are in stock_weapons_data.hpp and the CAC
// glue is data/mwx/ui_scripts/aw_weapons + data/mwx/scripts/mp/aw_weapons.gsc.

namespace aw_weapons
{
	namespace
	{
		constexpr std::pair<const char*, const char*> names[] =
		{
			{"WEAPON_EXPLOSIVE_EXO_CROSSBOW", "Crossbow"},
		};

		constexpr std::pair<const char*, const char*> descriptions[] =
		{
			{"WEAPON_EXPLOSIVE_EXO_CROSSBOW_DESC",
				"Bolt-action crossbow. Fires explosive bolts that stick and detonate."},
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
