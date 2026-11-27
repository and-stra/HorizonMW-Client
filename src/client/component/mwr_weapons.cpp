#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "dvars.hpp"
#include "localized_strings.hpp"

#include "game/dvars.hpp"

#include <utility>

// Item 12: the MWR DLC/CoD4 weapons and melee weapons in Create-a-Class.
// The statstable/customweapons rows come from stock_weapons_data.hpp (stock_weapons.cpp adds them
// when the weapon assets exist); the GSC whitelist is data/mwx/scripts/mp/mwr_weapons.gsc. This
// component owns the switch dvar and the melee display names.

namespace mwr_weapons
{
	namespace
	{
		// The DLC guns ship their own WEAPON_* names in MWR; HMW's language table does not
		// necessarily carry them, and the D0 check ran without the weapon assets. Override them
		// with the same strings the MWR weapon definitions carry.
		constexpr std::pair<const char*, const char*> gun_names[] =
		{
			{"WEAPON_XMLAR", "XM-LAR"},
			{"WEAPON_BOS14", "BOS14"},
			{"WEAPON_LYNXCQ300", "Lynx CQ300"},
			{"WEAPON_MAC10", "MAC-10"},
			{"WEAPON_FANG45", "Fang 45"},
			{"WEAPON_PKPSD9", "PK-PSD9"},
			{"WEAPON_BEREDMK8", "Bered MK8"},
			{"WEAPON_KAM12", "Kamchatka-12"},
			{"WEAPON_STAC330", "S-Tac Aggressor"},
			{"WEAPON_PROKOLOT", "Prokolot"},
			{"WEAPON_BR9", "BR9"},
			{"WEAPON_G3", "G3"},
			{"WEAPON_M14", "M14"},
			{"WEAPON_MP44", "MP44"},
			{"WEAPON_SKORPION", "Skorpion"},
			{"WEAPON_M60E4", "M60E4"},
			{"WEAPON_SAW", "M249 SAW"},
			{"WEAPON_DRAGUNOV", "Dragunov"},
			{"WEAPON_REMINGTON700", "R700"},
		};

		constexpr std::pair<const char*, const char*> melee_names[] =
		{
			{"MWX_MWR_H1_MELEEAPR1", "Caveman"},
			{"MWX_MWR_H1_MELEEAPR2", "Machete"},
			{"MWX_MWR_H1_MELEEAPR3", "Diabolical"},
			{"MWX_MWR_H1_MELEEAPR4", "Sawtooth"},
			{"MWX_MWR_H1_MELEEAUG1", "Danger Close"},
			{"MWX_MWR_H1_MELEEAUG2", "Barber"},
			{"MWX_MWR_H1_MELEEAUG3", "Point Knife"},
			{"MWX_MWR_H1_MELEEAUG4", "Enforce"},
			{"MWX_MWR_H1_MELEEBAYONET", "CQB Bayonet"},
			{"MWX_MWR_H1_MELEEBLADE", "Scorpion"},
			{"MWX_MWR_H1_MELEEBOTTLE", "Brawler's Brew"},
			{"MWX_MWR_H1_MELEEFEB1", "Mechanic"},
			{"MWX_MWR_H1_MELEEFEB2", "Shamrock Blade"},
			{"MWX_MWR_H1_MELEEFEB3", "Samurai"},
			{"MWX_MWR_H1_MELEEFEB4", "Thug"},
			{"MWX_MWR_H1_MELEEFEB5", "Leprechaun"},
			{"MWX_MWR_H1_MELEEGLADIUS", "Gladiator"},
			{"MWX_MWR_H1_MELEEHATCHET", "Hatchetman"},
			{"MWX_MWR_H1_MELEEICEPICK", "Cliffhanger"},
			{"MWX_MWR_H1_MELEEJUN1", "Bludgeon"},
			{"MWX_MWR_H1_MELEEJUN2", "Cleaver"},
			{"MWX_MWR_H1_MELEEJUN3", "Nauticus"},
			{"MWX_MWR_H1_MELEEJUN4", "Tidal"},
			{"MWX_MWR_H1_MELEEJUN5", "Tribal"},
			{"MWX_MWR_H1_MELEEJUN6", "Sarsaparilla"},
			{"MWX_MWR_H1_MELEEPADDLE", "Omsk Hammer"},
			{"MWX_MWR_H1_MELEESHOVEL", "Gravedigger"},
			{"MWX_MWR_H1_MELEESICKLE", "Sickle"},
		};
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			for (const auto& [key, name] : gun_names)
			{
				localized_strings::override(key, name);
			}
			for (const auto& [key, name] : melee_names)
			{
				localized_strings::override(key, name);
			}

			// bool, so it can be registered in post_unpack (string dvars cannot)
			dvars::register_bool("hmw_mwr_weapons", true, game::DVAR_FLAG_NONE,
				"Show the MWR DLC/CoD4 guns and melee weapons in Create-a-Class");
		}
	};
}

REGISTER_COMPONENT(mwr_weapons::component)
