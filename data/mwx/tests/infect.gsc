// MWX test: Infected (reference test, see docs/testing.md).
//
// Checks the first infected, the loadouts of both teams, that a survivor becomes infected with
// the right loadout, the team counts and the "survivors eliminated" win.
//
// Start it with run_test {name:"infect"}: that sets mwx_test=infect and the scr_* dvars that
// shorten the first-infected timer, loads mp_crash and waits for test_done.

#include mwx\tests\_test;

main()
{
    test_step("wait for the first infected");

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

    test_step("check the first infected");

    firstinfected = undefined;
    survivor = undefined;
    survivorcount = 0;

    foreach (player in level.players)
    {
        if (isdefined(player.isinitialinfected) && player.isinitialinfected)
        {
            firstinfected = player;
        }
        else if (isdefined(player.team) && player.team == "allies")
        {
            survivorcount++;
            if (!isdefined(survivor))
                survivor = player;
        }
    }

    // the flag is cleared as soon as a second player is infected; right after the countdown the
    // first infected is the only axis player
    if (!isdefined(firstinfected))
    {
        foreach (player in level.players)
        {
            if (isdefined(player.team) && player.team == "axis")
            {
                if (!isdefined(firstinfected))
                    firstinfected = player;
            }
        }
    }

    axisatstart = 0;
    if (isdefined(level.infect_teamscores) && isdefined(level.infect_teamscores["axis"]))
        axisatstart = level.infect_teamscores["axis"];

    havefirst = 0;
    if (isdefined(firstinfected))
        havefirst = 1;
    havesurvivor = 0;
    if (isdefined(survivor))
        havesurvivor = 1;

    if (axisatstart > 1)
        havefirst = 0;

    test_assert(havefirst, "exactly one first infected", "1", axisatstart);
    test_assert(havesurvivor, "at least one survivor", ">0", survivorcount);

    if (!havefirst || !havesurvivor)
    {
        test_done(0);
        return;
    }

    test_assert(firstinfected.team == "axis", "first infected team", "axis", firstinfected.team);
    test_assert(firstinfected hasweapon("h2_hatchet_mp"), "first infected has the hatchet",
        "h2_hatchet_mp", "checked");
    test_assert(firstinfected hasweapon("iw9_throwknife_mp"), "first infected has the throwing knife",
        "iw9_throwknife_mp", "checked");
    test_assert(firstinfected hasweapon("flare_mp"), "first infected has the tactical insertion",
        "flare_mp", "checked");

    speed = 0;
    if (isdefined(firstinfected.movespeedscale))
        speed = firstinfected.movespeedscale;
    test_assert(speed >= 1.1, "first infected move speed scale", ">=1.1", speed);

    test_step("check the survivor loadout");

    test_assert(survivor hasweapon("h2_spas12_mp"), "survivor primary", "h2_spas12_mp", "checked");
    test_assert(survivor hasweapon("h2_usp_mp"), "survivor secondary", "h2_usp_mp", "checked");
    test_assert(survivor hasweapon("h1_fraggrenade_mp"), "survivor lethal", "h1_fraggrenade_mp", "checked");
    test_assert(survivor hasweapon("h1_flashgrenade_mp"), "survivor tactical", "h1_flashgrenade_mp", "checked");

    scavenger = 0;
    if (isdefined(survivor.perks["specialty_scavenger"]) && survivor.perks["specialty_scavenger"])
        scavenger = 1;
    test_assert(scavenger, "survivor has scavenger", "1", scavenger);

    test_step("infect a survivor");

    axisbefore = level.infect_teamscores["axis"];
    survivor dodamage(1000, firstinfected, firstinfected, "MOD_PISTOL_BULLET", "h2_hatchet_mp",
        (0, 0, 0), "torso_upper");

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
    test_assert(level.infect_teamscores["axis"] == axisbefore + 1, "infected team count",
        axisbefore + 1, level.infect_teamscores["axis"]);
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
            player dodamage(1000, firstinfected, firstinfected, "MOD_PISTOL_BULLET", "h2_hatchet_mp",
                (0, 0, 0), "torso_upper");
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
