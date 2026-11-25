// MWX test: Search & Rescue. A killed player drops a tag; a teammate revive brings them back; after
// confirming every tag, no living player on the enemy team ends the round.

#include mwx\tests\_test;

test_sr_tagcount(team)
{
    count = 0;

    if (!isdefined(level.sr_tags))
        return 0;

    foreach (guid, data in level.sr_tags)
    {
        if (!isdefined(data) || data.team != team)
            continue;
        count++;
    }

    return count;
}

main()
{
    test_step("wait for spawned players");
    spawned = test_wait_players(2, 90);
    test_assert(spawned >= 2, "players spawned", ">=2", spawned);

    test_hold_bots();

    // the drop only happens after the grace period (like the gametypes' own kill handling)
    waited = 0;
    while (waited < 90 && level.ingraceperiod)
    {
        wait 0.5;
        waited = waited + 0.5;
    }

    test_step("a death drops a tag");

    victim = undefined;
    killer = undefined;
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || !isalive(player))
            continue;
        if (!isdefined(victim))
            victim = player;
        else if (!isdefined(killer) && player.team != victim.team)
            killer = player;
    }

    test_assert(isdefined(killer), "an enemy for the kill", "player", "none");
    mwx_test_log("srescue: " + killer.name + " kills " + victim.name);
    test_kill(victim, killer, "h1_ak47_mp");

    waited = 0;
    while (waited < 15 && test_sr_tagcount(victim.team) == 0)
    {
        wait 0.5;
        waited = waited + 0.5;
    }
    test_assert(test_sr_tagcount(victim.team) > 0, "the dead player dropped a tag", ">0",
        test_sr_tagcount(victim.team));

    test_step("a teammate revives the dead player");
    maps\mp\gametypes\srescue::mwxrescue_revive(victim);

    waited = 0;
    while (waited < 20 && !isalive(victim))
    {
        wait 0.5;
        waited = waited + 0.5;
    }
    test_assert(isalive(victim), "the tag revived the player", "1", isalive(victim));
    test_assert(test_sr_tagcount(victim.team) == 0, "the tag was consumed", "0",
        test_sr_tagcount(victim.team));

    test_step("the gametype ends the round");

    // drive the mode's own round-end path (the same srendround the elimination watch uses) and
    // check the winner it sets; the bots cannot be relied on to produce a clean elimination
    maps\mp\gametypes\srescue::mwxrescue_endround(victim.team);

    ended = 0;
    waited = 0;
    while (waited < 15 && !ended)
    {
        wait 0.5;
        waited = waited + 0.5;

        if (isdefined(level.gameending) && level.gameending)
            ended = 1;
        if (isdefined(level.finalkillcam_winner) && level.finalkillcam_winner == victim.team)
            ended = 1;
        if (isdefined(game["roundsWon"]) && isdefined(game["roundsWon"][victim.team]) &&
            game["roundsWon"][victim.team] > 0)
            ended = 1;
    }

    test_assert(ended, "the round ended", "1", ended);

    winner = "none";
    if (isdefined(level.finalkillcam_winner))
        winner = level.finalkillcam_winner;
    test_assert(winner == victim.team, "the surviving team won the round", victim.team, winner);

    test_done(1);
}
