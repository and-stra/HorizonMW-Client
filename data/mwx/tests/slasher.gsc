// MWX test: Slasher (hodgepodge mode 2 on top of war.gsc, see data/mwx/scripts/mp/mwx_hodgepodge.gsc).
//
// Checks: one life, exactly one slasher, survivor bots may fire (the MWX fix), the last survivor
// gets the slasher powers, and the match ends when all survivors are dead.

#include mwx\tests\_test;

first_alive(team, ignore)
{
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || player.team != team || !isalive(player))
            continue;

        if (isdefined(ignore) && player == ignore)
            continue;

        return player;
    }

    return undefined;
}

main()
{
    test_step("wait for the slasher");

    waited = 0;
    while (waited < 120 && !isdefined(level.slasher))
    {
        wait 0.5;
        waited = waited + 0.5;
    }

    chosen = 0;
    if (isdefined(level.slasher))
        chosen = 1;

    if (!test_assert(chosen, "slasher chosen", "1", chosen))
    {
        test_done(0);
        return;
    }

    slasher = level.slasher;

    // the full weapon names, built the same way _hodgepodge::switchtostartweapon builds them (the bare
    // refs are no weapon names; the kill log showed the Colt as h2_colt45_mp)
    shovel = maps\mp\gametypes\_class::buildweaponname("h1_meleeshovel");
    colt = maps\mp\gametypes\_class::buildweaponname("h1_colt45");
    test_log("slasher weapons: " + shovel + ", " + colt);

    test_step("rules");

    test_assert(slasher.team == "axis", "slasher is on axis", "axis", slasher.team);
    test_assert(level.mm_teamscores["axis"] == 1, "exactly one slasher", "1", level.mm_teamscores["axis"]);
    test_assert(level.mm_teamscores["allies"] >= 2, "survivors", ">=2", level.mm_teamscores["allies"]);
    test_assert(getdvarint("scr_war_numlives") == 1, "one life", "1", getdvarint("scr_war_numlives"));
    test_assert(isdefined(slasher.isslasher) && slasher.isslasher == 1, "slasher flag", "1",
        isdefined(slasher.isslasher) ? slasher.isslasher : "undefined");
    test_assert(slasher hasweapon(shovel), "slasher has the shovel", "h1_meleeshovel", "checked");

    test_step("survivor loadout");

    survivor = first_alive("allies");
    test_assert(isdefined(survivor), "a living survivor", "player", isdefined(survivor) ? survivor.name : "none");

    if (isdefined(survivor))
    {
        waited = 0;
        while (waited < 10 && !(survivor hasweapon(colt)))
        {
            wait 0.25;
            waited = waited + 0.25;
        }
        test_assert(survivor hasweapon(colt), "survivor has the colt", "h1_colt45", "checked");
    }

    // MWX fix: onmmspawnplayer turns firing off for every bot; slasher_botfire turns it back on for
    // survivors and records mwx_botfire (no direct allowfire query in GSC)
    botfire = 0;
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || player.team != "allies" || !isbot(player))
            continue;

        if (isdefined(player.mwx_botfire) && player.mwx_botfire)
            botfire++;
    }
    test_assert(botfire > 0, "survivor bots may fire (MWX fix)", ">0", botfire);

    test_step("last survivor gets the slasher powers");

    // the MWX kill handler recounts the living survivors, so the final survivor is detected after
    // every kill (the stock counter stayed too high)
    tries = 0;
    while (test_alive_on_team("allies") > 1 && tries < 10)
    {
        victim = first_alive("allies");
        if (!isdefined(victim))
            break;

        test_kill(victim, slasher, shovel);
        tries++;
        wait 3;
    }

    lastsurvivor = first_alive("allies");
    alivecount = test_alive_on_team("allies");
    test_assert(alivecount == 1, "one survivor left", "1", alivecount);

    if (isdefined(lastsurvivor))
    {
        waited = 0;
        while (waited < 15 && !(isdefined(lastsurvivor.isslasher) && lastsurvivor.isslasher == 1))
        {
            wait 0.25;
            waited = waited + 0.25;
        }

        powered = 0;
        if (isdefined(lastsurvivor.isslasher) && lastsurvivor.isslasher == 1)
            powered = 1;
        test_assert(powered, "last survivor got the slasher powers", "1", powered);
        test_assert(lastsurvivor hasweapon(shovel), "last survivor has the shovel",
            "h1_meleeshovel", "checked");
    }

    test_step("all survivors dead -> slasher wins");

    if (isdefined(lastsurvivor))
        test_kill(lastsurvivor, slasher, shovel);

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
    test_assert(winner == "axis", "slasher won", "axis", winner);

    test_done(1);
}
