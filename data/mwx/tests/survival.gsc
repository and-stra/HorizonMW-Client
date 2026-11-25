// MWX test: Survival prototype (R6c). Wave 1 spawns 5 agents; killing them starts wave 2.

#include mwx\tests\_test;

test_survival_agents()
{
    count = 0;

    foreach (player in level.players)
    {
        if (!isdefined(player) || !isai(player))
            continue;
        if (!isdefined(player.team) || player.team != "axis")
            continue;
        if (!isalive(player))
            continue;
        count++;
    }

    return count;
}

main()
{
    test_step("wait for the match to start");
    spawned = test_wait_players(1, 90);
    test_assert(spawned >= 1, "a human player spawned", ">=1", spawned);

    test_step("wave 1 spawns agents");
    waited = 0;
    while (waited < 90 && (!isdefined(level.survival_wave) || level.survival_wave < 1))
    {
        wait 1;
        waited = waited + 1;
    }

    test_assert(isdefined(level.survival_wave) && level.survival_wave >= 1, "wave 1 started", ">=1",
        level.survival_wave);

    waited = 0;
    while (waited < 60 && test_survival_agents() < 5)
    {
        wait 1;
        waited = waited + 1;
    }

    agents = test_survival_agents();
    test_assert(agents >= 5, "wave 1 spawned 5 agents", ">=5", agents);

    test_step("killing all agents starts wave 2");
    wave = level.survival_wave;
    waived = 0;
    while (waived < 90 && level.survival_wave == wave)
    {
        foreach (player in level.players)
        {
            if (!isdefined(player) || !isai(player))
                continue;
            if (!isdefined(player.team) || player.team != "axis")
                continue;
            if (!isalive(player))
                continue;
            test_kill(player, player, "h1_ak47_mp");
        }

        wait 1;
        waived = waived + 1;
    }

    test_assert(level.survival_wave > wave, "wave 1 cleared and wave 2 started", ">1", level.survival_wave);

    test_done(1);
}
