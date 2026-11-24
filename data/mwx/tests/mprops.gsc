// MWX test: Mad Props (hodgepodge 9 + scr_game_madprops 1).
//
// Same disguise path as Prop Hunt but the roles are reversed: the props hunt the soldiers.
// Checks: madprops mode is on, defenders get a prop model and no weapon, the soldiers have
// weapons, damaging a prop kills its owner, and eliminating every soldier ends the round
// with the props as the winner.

#include mwx\tests\_test;

main()
{
    test_step("wait for spawned players");

    waited = 0;
    spawned = 0;
    while (waited < 90 && spawned < 2)
    {
        wait 0.5;
        waited = waited + 0.5;

        spawned = 0;
        foreach (player in level.players)
        {
            if (isdefined(player.hasspawned) && player.hasspawned)
                spawned++;
        }
    }

    test_assert(spawned >= 2, "players spawned", ">=2", spawned);
    test_assert(level.hodgepodgemode == 9, "hodgepodge mode is mad props", "9", level.hodgepodgemode);
    test_assert(level.madpropsmode == 1, "mad props mode", "1", level.madpropsmode);

    test_step("wait for a prop and a soldier");

    prop = undefined;
    soldier = undefined;
    waited = 0;
    while (waited < 40 && (!isdefined(prop) || !isdefined(soldier)))
    {
        wait 0.5;
        waited = waited + 0.5;

        foreach (player in level.players)
        {
            if (!isdefined(player.hasspawned) || !player.hasspawned || !isalive(player))
                continue;
            if (!isdefined(player.team))
                continue;

            if (player.team == game["defenders"] && isdefined(player.prop) && isdefined(player.prop.model))
            {
                prop = player;
                mwx_test_log("mprops: prop " + player.name + " model " + player.prop.model);
            }

            if (player.team == game["attackers"] && player getcurrentweapon() != "none")
                soldier = player;
        }
    }

    test_assert(isdefined(prop), "a defender got a prop model", "prop", "none");
    test_assert(isdefined(soldier), "a soldier has a weapon", "weapon", "none");

    if (!isdefined(prop) || !isdefined(soldier))
    {
        test_done(0);
        return;
    }

    test_step("prop loadout");

    test_assert(prop getcurrentweapon() == "none", "the prop has no weapon", "none", prop getcurrentweapon());
    test_assert(soldier getcurrentweapon() != "none", "the soldier has a weapon", "!none",
        soldier getcurrentweapon());

    test_step("kill a prop");

    deaths_before = 0;
    if (isdefined(prop.deaths))
        deaths_before = prop.deaths;
    test_kill(prop, soldier, "h1_ak47_mp");

    waited = 0;
    while (waited < 10 && isalive(prop) && (!isdefined(prop.deaths) || prop.deaths <= deaths_before))
    {
        wait 0.5;
        waited = waited + 0.5;
    }

    died = 0;
    if (!isalive(prop))
        died = 1;
    if (isdefined(prop.deaths) && prop.deaths > deaths_before)
        died = 1;
    test_assert(died, "a soldier can kill a prop", "1", died);

    test_step("end the round: all soldiers eliminated");

    // soldiers have scr_*_numlives lives (4 in mad props); keep killing them until the
    // gametype ends the round through ondeadevent("attackers")
    ended = 0;
    waited = 0;
    while (waited < 90 && !ended)
    {
        foreach (player in level.players)
        {
            if (!isdefined(player.team) || player.team != game["attackers"])
                continue;
            if (!isalive(player))
                continue;
            test_kill(player, prop, "h1_ak47_mp");
        }

        wait 2;
        waited = waited + 2;

        if (isdefined(level.gameended) && level.gameended)
            ended = 1;
        if (isdefined(game["roundsWon"]) && isdefined(game["roundsWon"][game["defenders"]]) &&
            game["roundsWon"][game["defenders"]] > 0)
            ended = 1;
        if (isdefined(level.finalkillcam_winner) && level.finalkillcam_winner == game["defenders"])
            ended = 1;
    }

    test_assert(ended, "the round ended", "1", ended);

    winner = "none";
    if (isdefined(level.finalkillcam_winner))
        winner = level.finalkillcam_winner;
    if (winner == "none" && isdefined(game["roundsWon"]) && isdefined(game["roundsWon"][game["defenders"]]) &&
        game["roundsWon"][game["defenders"]] > 0)
        winner = game["defenders"];
    test_assert(winner == game["defenders"], "the props won", game["defenders"], winner);

    test_done(1);
}
