// MWX test: Reinforce. One life per round; a capture brings a dead teammate back; eliminating the
// enemy team ends the round. Capturing is done through the gametype's own mwxreinforcecapture hook
// (bots cannot walk into the zone reliably).

#include mwx\tests\_test;

main()
{
    test_step("wait for spawned players");
    spawned = test_wait_players(2, 90);
    test_assert(spawned >= 2, "players spawned", ">=2", spawned);

    test_hold_bots();

    test_step("one life per round");
    alive = undefined;
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || !isalive(player))
            continue;
        alive = player;
        break;
    }

    test_assert(isdefined(alive), "an alive player", "player", "none");
    test_assert(isdefined(alive.pers["lives"]) && alive.pers["lives"] == 0, "the spawn used the one life",
        "0", alive.pers["lives"]);

    test_step("a capture respawns the dead");

    victim = undefined;
    killer = undefined;
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || !isalive(player))
            continue;
        if (!isdefined(victim))
            victim = player;
        else if (isdefined(killer) == 0 && player.team != victim.team)
            killer = player;
    }

    test_assert(isdefined(killer), "an enemy for the kill", "player", "none");
    mwx_test_log("reinforce: " + killer.name + " kills " + victim.name);
    test_kill(victim, killer, "h1_ak47_mp");

    waited = 0;
    while (waited < 10 && isalive(victim))
    {
        wait 0.5;
        waited = waited + 0.5;
    }
    test_assert(!isalive(victim), "the teammate is dead", "0", isalive(victim));

    maps\mp\gametypes\reinforce::mwxreinforcecapture(victim.team);

    waited = 0;
    while (waited < 20 && !isalive(victim))
    {
        wait 0.5;
        waited = waited + 0.5;
    }
    test_assert(isalive(victim), "the capture respawned the dead teammate", "1", isalive(victim));

    test_step("eliminating a team ends the round");

    // kills in the grace period do not run updategameevents (H1 returns early); wait for the match
    waited = 0;
    while (waited < 90 && level.ingraceperiod)
    {
        wait 0.5;
        waited = waited + 0.5;
    }

    // keep killing every living enemy (the round uses one life)
    ended = 0;
    waited = 0;
    while (waited < 40 && !ended)
    {
        foreach (player in level.players)
        {
            if (!isdefined(player.team) || !isalive(player))
                continue;
            if (player.team == victim.team)
                continue;
            test_kill(player, victim, "h1_ak47_mp");
        }

        wait 1;
        waited = waited + 1;

        if (isdefined(level.gameending) && level.gameending)
            ended = 1;
        if (isdefined(level.finalkillcam_winner) && level.finalkillcam_winner == victim.team)
            ended = 1;
        if (isdefined(game["roundsWon"]) && isdefined(game["roundsWon"][victim.team]) &&
            game["roundsWon"][victim.team] > 0)
            ended = 1;
    }

    test_assert(ended, "the round ended by elimination", "1", ended);

    winner = "none";
    if (isdefined(level.finalkillcam_winner))
        winner = level.finalkillcam_winner;
    test_assert(winner == victim.team, "the surviving team won the round", victim.team, winner);

    test_done(1);
}
