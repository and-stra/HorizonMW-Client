// MWX test: Cranked (cranked.gsc): a kill makes you cranked for 30 s, every further kill resets the
// timer and scores double for the team, the explosion at 0 s is a suicide without score loss.

#include mwx\tests\_test;

first_alive(ignore)
{
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || !isalive(player))
            continue;

        if (isdefined(ignore) && player == ignore)
            continue;

        return player;
    }

    return undefined;
}

wait_alive(player, timeout)
{
    waited = 0;
    while (waited < timeout)
    {
        if (isalive(player))
            return 1;

        wait 0.25;
        waited = waited + 0.25;
    }

    return 0;
}

main()
{
    test_step("wait for the players");

    players = test_wait_players(4, 120);
    test_assert(players >= 4, "players spawned", ">=4", players);

    attacker = first_alive();
    victim = first_alive(attacker);
    if (!isdefined(attacker) || !isdefined(victim))
    {
        test_assert(0, "attacker and victim", "players", "missing");
        test_done(0);
        return;
    }

    team = attacker.team;
    score0 = game["teamScores"][team];

    test_step("a kill makes you cranked");

    test_kill(victim, attacker, "h2_m4_mp");

    waited = 0;
    while (waited < 5 && !isdefined(attacker.cranked))
    {
        wait 0.25;
        waited = waited + 0.25;
    }

    cranked = 0;
    if (isdefined(attacker.cranked) && attacker.cranked)
        cranked = 1;
    test_assert(cranked, "killer is cranked", "1", cranked);

    remaining = 0;
    if (isdefined(attacker.cranked_end_time))
        remaining = attacker.cranked_end_time - gettime();
    test_assert(remaining > 25000 && remaining <= 30500, "30 s timer", "~30000", remaining);

    wait 0.5;
    delta1 = game["teamScores"][team] - score0;
    test_assert(delta1 == 1, "team score +1 for the first kill", "1", delta1);
    test_assert(test_has_perk(attacker, "specialty_fastreload"), "cranked perks", "1",
        test_has_perk(attacker, "specialty_fastreload"));

    test_step("a cranked kill resets the timer and scores double");

    wait_alive(victim, 15);
    wait 0.5;

    end_before = attacker.cranked_end_time;
    score1 = game["teamScores"][team];
    test_kill(victim, attacker, "h2_m4_mp");
    wait 0.5;

    end_after = attacker.cranked_end_time;
    test_assert(end_after >= end_before, "timer reset by the kill", ">=" + end_before, end_after);
    test_assert(end_after - gettime() > 25000, "timer back at 30 s", "~30000", end_after - gettime());

    delta2 = game["teamScores"][team] - score1;
    test_assert(delta2 == 2, "team score +2 for a cranked kill", "2", delta2);

    test_step("the explosion at 0 s is a suicide without score loss");

    test_assert(isdefined(level.gametweaks["suicidepointloss"]) && level.gametweaks["suicidepointloss"].value == 0,
        "suicide point loss disabled", "0",
        isdefined(level.gametweaks["suicidepointloss"]) ? level.gametweaks["suicidepointloss"].value : "missing");

    deaths_before = attacker.deaths;
    score_before = game["teamScores"][team];

    // let the timer run out in a moment instead of waiting 30 s
    attacker.cranked_end_time = gettime() + 300;

    waited = 0;
    while (waited < 10 && isalive(attacker))
    {
        wait 0.25;
        waited = waited + 0.25;
    }

    exploded = 0;
    if (!isalive(attacker))
        exploded = 1;
    test_assert(exploded, "cranked player exploded", "1", exploded);
    test_assert(attacker.deaths == deaths_before + 1, "the explosion counts as a death",
        deaths_before + 1, attacker.deaths);

    wait 1;
    test_assert(game["teamScores"][team] == score_before, "no score loss from the explosion",
        score_before, game["teamScores"][team]);

    stillcranked = 0;
    if (isdefined(attacker.cranked))
        stillcranked = 1;
    test_assert(!stillcranked, "cranked state cleared", "0", stillcranked);

    test_done(1);
}
