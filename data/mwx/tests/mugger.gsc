// MWX test: Mugger. A kill drops a tag; picking it up banks it; a melee kill steals the victim's
// banked tags.

#include mwx\tests\_test;

test_mugger_tagcount()
{
    count = 0;

    if (!isdefined(level.mugger_tags))
        return 0;

    foreach (guid, data in level.mugger_tags)
    {
        if (!isdefined(data))
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

    test_step("a kill drops a tag and picking it up banks it");

    victim = undefined;
    killer = undefined;
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || !isalive(player))
            continue;
        if (!isdefined(victim))
            victim = player;
        else if (!isdefined(killer))
            killer = player;
    }

    test_assert(isdefined(killer), "a second player", "player", "none");
    mwx_test_log("mugger: " + killer.name + " kills " + victim.name);
    test_kill(victim, killer, "h1_ak47_mp");

    waited = 0;
    while (waited < 15 && test_mugger_tagcount() == 0)
    {
        wait 0.5;
        waited = waited + 0.5;
    }
    test_assert(test_mugger_tagcount() > 0, "the kill dropped a tag", ">0", test_mugger_tagcount());

    banked_before = 0;
    if (isdefined(killer.mugger_banked))
        banked_before = killer.mugger_banked;

    picked = maps\mp\gametypes\mugger::mwxmugger_pickup(killer);
    test_assert(picked == 1, "the tag could be picked up", "1", picked);

    waited = 0;
    while (waited < 5 && (!isdefined(killer.mugger_banked) || killer.mugger_banked <= banked_before))
    {
        wait 0.25;
        waited = waited + 0.25;
    }

    test_assert(isdefined(killer.mugger_banked) && killer.mugger_banked > banked_before,
        "the tag was banked", ">" + banked_before, killer.mugger_banked);

    test_step("a melee kill steals the bank");

    // wait for the victim to respawn (mugger has unlimited lives)
    waited = 0;
    while (waited < 20 && !isalive(victim))
    {
        wait 0.5;
        waited = waited + 0.5;
    }
    test_assert(isalive(victim), "the victim respawned", "1", isalive(victim));

    victim.mugger_banked = 5;
    stolen_before = 0;
    if (isdefined(killer.mugger_banked))
        stolen_before = killer.mugger_banked;

    victim dodamage(1000, victim.origin, killer, killer, "MOD_MELEE", "h1_meleeslash_mp");

    waited = 0;
    while (waited < 5 && (!isdefined(killer.mugger_banked) || killer.mugger_banked < stolen_before + 5))
    {
        wait 0.25;
        waited = waited + 0.25;
    }

    test_assert(killer.mugger_banked >= stolen_before + 5, "the melee kill stole the bank",
        ">=" + (stolen_before + 5), killer.mugger_banked);
    test_assert(victim.mugger_banked == 0, "the victim's bank is empty", "0", victim.mugger_banked);

    test_done(1);
}
