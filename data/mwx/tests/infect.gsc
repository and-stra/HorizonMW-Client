// MWX test: Infected (reference test, see docs/testing.md).
//
// Checks the first infected, the loadouts of both teams, that a survivor becomes infected with
// the right loadout, the team counts and the "survivors eliminated" win.
//
// Start it with run_test {name:"infect"}: that starts a dedicated server on mp_shipment with
// g_gametype infect, mwx_test=infect and 3 bots.

#include mwx\tests\_test;

// fills level.mwx_firstinfected / level.mwx_survivor / level.mwx_axis / level.mwx_allies
scanplayers()
{
    level.mwx_firstinfected = undefined;
    level.mwx_survivor = undefined;
    level.mwx_axis = 0;
    level.mwx_allies = 0;

    foreach (player in level.players)
    {
        if (!isdefined(player.team))
            continue;

        if (player.team == "axis")
        {
            level.mwx_axis++;
            if (!isdefined(level.mwx_firstinfected))
                level.mwx_firstinfected = player;
        }
        else if (player.team == "allies")
        {
            level.mwx_allies++;
            if (!isdefined(level.mwx_survivor))
                level.mwx_survivor = player;
        }
    }
}

main()
{
    test_step("wait for the first infected");

    // the gametype starts the first-infected countdown after the prematch
    waited = 0;
    while (waited < 120 && !isdefined(level.infect_chosefirstinfected))
    {
        wait 0.5;
        waited = waited + 0.5;
    }

    chosen = 0;
    if (isdefined(level.infect_chosefirstinfected))
        chosen = 1;

    if (!test_assert(chosen, "first infected chosen", "1", chosen))
    {
        test_done(0);
        return;
    }

    test_step("wait for the team change");

    // setfirstinfected starts the team change as a thread, so the axis player appears a moment
    // after level.infect_chosefirstinfected
    scanplayers();
    waited = 0;
    while (waited < 60 && (level.mwx_axis < 1 || level.mwx_allies < 1))
    {
        wait 0.25;
        waited = waited + 0.25;
        scanplayers();
    }

    test_assert(level.mwx_axis == 1, "exactly one first infected", "1", level.mwx_axis);
    test_assert(level.mwx_allies > 0, "at least one survivor", ">0", level.mwx_allies);

    if (level.mwx_axis < 1 || !isdefined(level.mwx_survivor))
    {
        test_done(0);
        return;
    }

    firstinfected = level.mwx_firstinfected;
    survivor = level.mwx_survivor;

    // the survivor loadout is checked first: the first infected can already kill a survivor while
    // the checks below poll for the infected's loadout
    test_step("check the survivor loadout");

    test_assert(survivor hasweapon("h2_spas12_mp"), "survivor primary", "h2_spas12_mp", "checked");
    test_assert(survivor hasweapon("h2_usp_mp"), "survivor secondary", "h2_usp_mp", "checked");
    test_assert(survivor hasweapon("h1_fraggrenade_mp"), "survivor lethal", "h1_fraggrenade_mp", "checked");
    test_assert(survivor hasweapon("h1_flashgrenade_mp"), "survivor tactical", "h1_flashgrenade_mp", "checked");

    scavenger = 0;
    if (isdefined(survivor.perks["specialty_scavenger"]) && survivor.perks["specialty_scavenger"])
        scavenger = 1;
    test_assert(scavenger, "survivor has scavenger", "1", scavenger);

    test_step("check the first infected");

    // the loadout and the move speed are applied by the gametype a moment after the team change
    waited = 0;
    speed = 0;
    while (waited < 15)
    {
        speed = mwx_movespeedscale(firstinfected);
        if (speed >= 1.1 && firstinfected hasweapon("h2_hatchet_mp") && firstinfected hasweapon("flare_mp"))
            break;
        wait 0.25;
        waited = waited + 0.25;
    }

    test_assert(firstinfected.team == "axis", "first infected team", "axis", firstinfected.team);
    test_assert(firstinfected hasweapon("h2_hatchet_mp"), "first infected has the hatchet",
        "h2_hatchet_mp", "checked");
    test_assert(firstinfected hasweapon("iw9_throwknife_mp"), "first infected has the throwing knife",
        "iw9_throwknife_mp", "checked");
    test_assert(firstinfected hasweapon("flare_mp"), "first infected has the tactical insertion",
        "flare_mp", "checked");
    test_assert(speed >= 1.1, "first infected move speed scale", ">=1.1", speed);

    test_step("infect a survivor");

    axisbefore = level.mwx_axis;
    // H1's 7 argument dodamage form does nothing in this build (probe: hp unchanged); the 2
    // argument form kills. The death is attributed to the world, which the gametype handles like
    // a suicide - allowed after the first infection.
    survivor dodamage(1000, survivor.origin);

    waited = 0;
    while (waited < 10 && survivor.team != "axis")
    {
        wait 0.25;
        waited = waited + 0.25;
    }

    infectedteam = "none";
    if (isdefined(survivor.team))
        infectedteam = survivor.team;

    test_assert(infectedteam == "axis", "killed survivor became infected", "axis", infectedteam);

    // the gametype applies the infected loadout a moment after the team change
    waited = 0;
    while (waited < 15 && !(survivor hasweapon("h2_hatchet_mp")))
    {
        wait 0.25;
        waited = waited + 0.25;
    }

    scanplayers();
    test_assert(level.mwx_axis == axisbefore + 1, "infected team count", axisbefore + 1, level.mwx_axis);
    test_assert(survivor hasweapon("h2_hatchet_mp"), "new infected has the hatchet", "h2_hatchet_mp", "checked");
    test_assert(survivor hasweapon("iw9_throwknife_mp"), "new infected has the throwing knife",
        "iw9_throwknife_mp", "checked");

    keepspistol = 0;
    if (survivor hasweapon("h2_usp_mp"))
        keepspistol = 1;
    test_assert(!keepspistol, "new infected has no usp", "0", keepspistol);

    test_step("no killstreak weapons");

    killstreak = 0;
    foreach (player in level.players)
    {
        foreach (weapon in player getweaponslistall())
        {
            if (issubstr(weapon, "killstreak") || issubstr(weapon, "airstrike") ||
                issubstr(weapon, "helicopter") || issubstr(weapon, "ac130"))
            {
                killstreak = 1;
            }
        }
    }
    test_assert(!killstreak, "no killstreak weapons", "0", killstreak);

    test_step("end the game: survivors eliminated");

    foreach (player in level.players)
    {
        if (isdefined(player.team) && player.team == "allies")
        {
            player dodamage(1000, player.origin);
        }
    }

    waited = 0;
    while (waited < 20 && !level.gameended)
    {
        wait 0.25;
        waited = waited + 0.25;
    }

    ended = 0;
    if (level.gameended)
        ended = 1;
    test_assert(ended, "game ended", "1", ended);

    winner = "?";
    if (isdefined(level.finalkillcam_winner))
        winner = level.finalkillcam_winner;
    test_assert(winner == "axis", "infected won", "axis", winner);

    test_done(1);
}
