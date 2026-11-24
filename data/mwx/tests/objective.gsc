// MWX test: objective modes (sd, dom, dz - see docs/testing.md).
//
// Same smoke test as war.gsc, plus: the objective entities of the mode exist on this map.
// If a mode has no objectives on mp_shipment, tests.json runs it on mp_crash instead (noted in
// the report).

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

    test_step("objectives exist");

    objectives = 0;
    foreach (entity in getentarray())
    {
        if (!isdefined(entity))
            continue;

        if (!isdefined(entity.classname))
            continue;

        if (entity.classname == "trigger_use" || entity.classname == "trigger_multiple" ||
            entity.classname == "trigger_radius")
        {
            if (isdefined(entity.targetname) && entity.targetname != "")
                objectives++;
        }
    }

    test_assert(objectives > 0, "objective entities spawned", ">0", objectives);

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
