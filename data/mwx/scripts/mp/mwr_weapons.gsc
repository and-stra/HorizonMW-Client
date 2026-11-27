// MWX item 12: the MWR DLC/CoD4 guns and melee weapons in Create-a-Class.
//
// HMW's scripts/mp_patches/custom_weapons.gsc replaces the _class validators with hardcoded h2_*
// switches, so the h1_* refs the MWR rows add to mp/statstable.csv and mp/customweapons.csv are
// rejected. This script installs the same validators again, with the MWR refs added. It waits so it
// always wins over HMW's main() (both run from load_init_handles/load_main_handles in map order).
//
// hmw_mwr_weapons 0 leaves HMW's whitelist untouched (the CAC lists are exactly as before).

main()
{
    level thread mwx_mwr_weapons_apply();
}

mwx_mwr_weapons_apply()
{
    wait 0.5;

    if (!getdvarint("hmw_mwr_weapons", 1))
    {
        logprint("mwx mwr weapons: disabled (hmw_mwr_weapons 0)");
        return;
    }

    replacefunc(maps\mp\gametypes\_class::isvalidprimary, ::mwx_isvalidprimary);
    replacefunc(maps\mp\gametypes\_class::isvalidsecondary, ::mwx_isvalidsecondary);
    replacefunc(maps\mp\gametypes\_class::isvalidmeleeweapon, ::mwx_isvalidmeleeweapon);

    logprint("mwx mwr weapons: CAC whitelist installed");
}

mwx_isvalidprimary(weapon, flag)
{
    switch (weapon)
    {
        // HMW
        case "h2_m4":
        case "h2_famas":
        case "h2_scar":
        case "h2_tavor":
        case "h2_fal":
        case "h2_m16":
        case "h2_masada":
        case "h2_fn2000":
        case "h2_ak47":
        case "h2_mp5k":
        case "h2_ump45":
        case "h2_kriss":
        case "h2_p90":
        case "h2_uzi":
        case "h2_ak74u":
        case "h2_cheytac":
        case "h2_barrett":
        case "h2_wa2000":
        case "h2_m21":
        case "h2_m40a3":
        case "h2_sa80":
        case "h2_rpd":
        case "h2_mg4":
        case "h2_aug":
        case "h2_m240":
        case "h2_inspect":
        // AW pilot (D): M1 Garand (iw5_dlcgun23) and MP40 (iw5_dlcgun18)
        case "iw5_dlcgun23":
        case "iw5_dlcgun18":
        // MWR DLC (11, duplicates excluded)
        case "h1_xmlar":
        case "h1_aprast":
        case "h1_augast":
        case "h1_febsmg":
        case "h1_aprsmg":
        case "h1_augsmg":
        case "h1_junlmg":
        case "h1_kam12":
        case "h1_junsnp":
        // MWR CoD4 (8)
        case "h1_g3":
        case "h1_m14":
        case "h1_mp44":
        case "h1_skorpion":
        case "h1_m60e4":
        case "h1_saw":
        case "h1_dragunov":
        case "h1_remington700":
            return 1;
        default:
            return 0;
    }

    return 0;
}

mwx_isvalidsecondary(weapon, flag, isdefault)
{
    switch (weapon)
    {
        case "none":
        // HMW
        case "h2_pp2000":
        case "h2_glock":
        case "h2_beretta393":
        case "h2_tmp":
        case "h2_usp":
        case "h2_coltanaconda":
        case "h2_m9":
        case "h2_colt45":
        case "h2_deserteagle":
        case "h2_spas12":
        case "h2_aa12":
        case "h2_striker":
        case "h2_ranger":
        case "h2_winchester1200":
        case "h2_m1014":
        case "h2_model1887":
        case "at4":
        case "h2_m79":
        case "stinger":
        case "javelin":
        case "h2_rpg":
        case "h2_shovel":
        case "h2_karambit":
        case "h2_hatchet":
        case "h2_icepick":
        case "h2_sickle":
        // MWR DLC pistols
        case "h1_aprpst":
        case "h1_augpst":
        // the MWR launcher
        case "h1_rpg":
        // item 13: the ported AW crossbow (the AW script also adds it; this whitelist is the one
        // that survives both replacefunc calls, so it must know the AW refs too)
        case "iw5_exocrossbow":
            return 1;
        default:
            return 0;
    }

    return 0;
}

mwx_isvalidmeleeweapon(weapon, flag)
{
    switch (weapon)
    {
        case "none":
        case "specialty_combathigh":
        case "specialty_copycat":
        case "specialty_finalstand":
        case "specialty_grenadepulldeath":
        // AW pilot (D): combat knife
        case "iw5_combatknife":
        // MWR DLC melee (CQB Bayonet once: h1_meleebayonet)
        case "h1_meleeapr1":
        case "h1_meleeapr2":
        case "h1_meleeapr3":
        case "h1_meleeapr4":
        case "h1_meleeaug1":
        case "h1_meleeaug2":
        case "h1_meleeaug3":
        case "h1_meleeaug4":
        case "h1_meleebayonet":
        case "h1_meleeblade":
        case "h1_meleebottle":
        case "h1_meleefeb1":
        case "h1_meleefeb2":
        case "h1_meleefeb3":
        case "h1_meleefeb4":
        case "h1_meleefeb5":
        case "h1_meleegladius":
        case "h1_meleehatchet":
        case "h1_meleeicepick":
        case "h1_meleejun1":
        case "h1_meleejun2":
        case "h1_meleejun3":
        case "h1_meleejun4":
        case "h1_meleejun5":
        case "h1_meleejun6":
        case "h1_meleepaddle":
        case "h1_meleeshovel":
        case "h1_meleesickle":
            return 1;
        default:
            if (maps\mp\_utility::is_true(flag))
            {
                maps\mp\gametypes\_class::foundinfraction("Replacing invalid melee weapon: " + weapon);
            }

            return 0;
    }
}
