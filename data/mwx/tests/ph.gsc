// MWX test: Prop Hunt (hodgepodge 9) on a generated or map-own prop list.
//
// What it checks (the M8 acceptance):
// - the defenders (props) get a prop model from level.proplist and lose their weapons
// - the attackers (hunters) keep a weapon
// - damaging a prop hurts/kills its owner (the prop entity's damage callback)
// - killing every prop ends the round with the hunters as the winner
//
// Diagnostics stay in the log: level.gametype, hodgepodge mode, the prop list size, the
// mwx_ph_fix flag, and the model of every prop.

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
    test_assert(level.hodgepodgemode == 9, "hodgepodge mode is prop hunt", "9", level.hodgepodgemode);
    proplistsize = -1;
    if (isdefined(level.proplist))
        proplistsize = level.proplist.size;
    test_assert(proplistsize > 0, "the prop list is not empty", ">0", proplistsize);

    test_step("wait for a prop and a hunter");

    prop = undefined;
    hunter = undefined;
    waited = 0;
    while (waited < 40 && (!isdefined(prop) || !isdefined(hunter)))
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
                mwx_test_log("ph: prop " + player.name + " model " + player.prop.model + " health " + player.health);
            }

            if (player.team == game["attackers"] && player getcurrentweapon() != "none")
            {
                hunter = player;
            }
        }
    }

    test_assert(isdefined(prop), "a defender got a prop model", "prop", "none");
    test_assert(isdefined(hunter), "a hunter has a weapon", "weapon", "none");

    if (!isdefined(prop) || !isdefined(hunter))
    {
        test_done(0);
        return;
    }

    test_step("prop loadout");

    test_assert(prop getcurrentweapon() == "none", "the prop has no weapon", "none", prop getcurrentweapon());
    primaries = prop getweaponslistprimaries();
    test_assert(primaries.size == 0, "the prop has no primary", "0", primaries.size);
    test_assert(hunter getcurrentweapon() != "none", "the hunter has a weapon", "!none", hunter getcurrentweapon());

    test_step("kill a prop");

    deaths_before = 0;
    if (isdefined(prop.deaths))
        deaths_before = prop.deaths;
    mwx_test_log("ph: " + hunter.name + " kills the prop player " + prop.name);
    test_kill(prop, hunter, "h1_ak47_mp");

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
    test_assert(died, "a hunter can kill a prop", "1", died);

    test_step("end the round: all props eliminated");

    ended = 0;
    waited = 0;
    while (waited < 25 && !ended)
    {
        foreach (player in level.players)
        {
            if (!isdefined(player.team) || player.team != game["defenders"])
                continue;
            if (!isalive(player))
                continue;
            test_kill(player, hunter, "h1_ak47_mp");
        }

        wait 1;
        waited = waited + 1;

        if (isdefined(level.gameended) && level.gameended)
            ended = 1;
        if (isdefined(game["roundsWon"]) && isdefined(game["roundsWon"][game["attackers"]]) &&
            game["roundsWon"][game["attackers"]] > 0)
            ended = 1;
        if (isdefined(level.finalkillcam_winner) && level.finalkillcam_winner == game["attackers"])
            ended = 1;
    }

    test_assert(ended, "the round ended", "1", ended);

    winner = "none";
    if (isdefined(level.finalkillcam_winner))
        winner = level.finalkillcam_winner;
    if (winner == "none" && isdefined(game["roundsWon"]) && isdefined(game["roundsWon"][game["attackers"]]) &&
        game["roundsWon"][game["attackers"]] > 0)
        winner = game["attackers"];
    test_assert(winner == game["attackers"], "the hunters won", game["attackers"], winner);

    test_step("mwx prop fix installed");
    test_assert(isdefined(level.mwx_ph_fix), "the prop fix ran", "1", "0");

    test_done(1);
}
