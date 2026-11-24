// MWX test: generic mode smoke test (see docs/testing.md).
//
// Used for war, and as the loading/objective check for the other standard modes: players spawn,
// fights happen, the match ends normally and no script error is reported (the MCP counts those).
// With a short time limit (scr_<mode>_timelimit 1) the round end is part of the test.

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

    test_step("check the state right after spawn");

    menuloadout = 0;
    foreach (player in level.players)
    {
        if (!isdefined(player.hasspawned) || !player.hasspawned)
            continue;

        menuloadout++;
        weapon = player getcurrentweapon();
        found = 0;
        if (isdefined(weapon))
            found = 1;

        aliveplayer = 0;
        if (isalive(player))
            aliveplayer = 1;

        test_assert(found, "spawned player has a weapon (" + player.name + ")", "1", found);
        test_assert(aliveplayer, "spawned player is alive (" + player.name + ")", "1", aliveplayer);
    }

    test_assert(menuloadout >= 2, "checked players", ">=2", menuloadout);

    test_step("wait for a kill");

    waited = 0;
    kills = 0;
    while (waited < 120 && kills == 0)
    {
        wait 1;
        waited = waited + 1;

        kills = 0;
        foreach (player in level.players)
        {
            if (isdefined(player.kills) && player.kills > 0)
                kills = kills + player.kills;
        }
    }

    test_assert(kills > 0, "a player scored a kill", ">0", kills);

    test_step("wait for the round end");

    waited = 0;
    while (waited < 150 && !level.gameended)
    {
        wait 0.5;
        waited = waited + 0.5;
    }

    ended = 0;
    if (level.gameended)
        ended = 1;
    test_assert(ended, "the match ended normally", "1", ended);

    test_done(1);
}
