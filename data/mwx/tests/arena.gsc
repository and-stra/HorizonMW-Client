// MWX test: Arena. One life per round, the neutral flag spawns after scr_arena_flagtime seconds,
// and eliminating a team ends the round.

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

    test_step("the flag spawns when the round timer runs low");
    waited = 0;
    while (waited < 30 && !isdefined(level.ar_flag))
    {
        wait 0.5;
        waited = waited + 0.5;
    }

    flagspawned = 0;
    if (isdefined(level.ar_flag) && isdefined(level.ar_flag.model))
        flagspawned = 1;
    test_assert(flagspawned, "the arena flag spawned", "1", flagspawned);

    test_step("eliminating a team ends the round");

    waited = 0;
    while (waited < 90 && level.ingraceperiod)
    {
        wait 0.5;
        waited = waited + 0.5;
    }

    ended = 0;
    waited = 0;
    while (waited < 40 && !ended)
    {
        foreach (player in level.players)
        {
            if (!isdefined(player.team) || !isalive(player))
                continue;
            if (player.team == alive.team)
                continue;
            test_kill(player, alive, "h1_ak47_mp");
        }

        wait 1;
        waited = waited + 1;

        if (isdefined(level.gameending) && level.gameending)
            ended = 1;
        if (isdefined(level.finalkillcam_winner) && level.finalkillcam_winner == alive.team)
            ended = 1;
        if (isdefined(game["roundsWon"]) && isdefined(game["roundsWon"][alive.team]) &&
            game["roundsWon"][alive.team] > 0)
            ended = 1;
    }

    test_assert(ended, "the round ended by elimination", "1", ended);

    winner = "none";
    if (isdefined(level.finalkillcam_winner))
        winner = level.finalkillcam_winner;
    test_assert(winner == alive.team, "the surviving team won the round", alive.team, winner);

    test_done(1);
}
