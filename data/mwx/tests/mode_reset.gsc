// MWX test: a party mode's global rule dvars do not leak into the next normal match (B1).
//
// Runs on a normal war map. The g_gametype callback applies the party dvars without a map load,
// so the whole ph -> war -> slasher -> war sequence is one match:
//   - baseline: the values the normal game has
//   - ph / mprops: scr_player_healthregen 0, scr_game_hardpoints 0, g_oldschool 0
//   - slasher: scr_game_hardpoints 0, scr_game_mmUavTime 30, g_oldschool 1
//   - back to war: every one of them restored to the baseline
// (The mp_shipment ph branch - timelimit 2.2 + oldschool - is asserted by the ph test on
// mp_shipment, because it needs a real ph map load.)

#include mwx\tests\_test;

kv(name)
{
    return getdvarint(name, -999);
}

kf(name)
{
    return getdvarfloat(name, -999);
}

main()
{
    test_step("wait for a spawned player");
    spawned = test_wait_players(1, 90);
    test_assert(spawned >= 1, "a player spawned", ">=1", spawned);

    test_assert(getdvar("g_gametype") == "war", "the match starts as war", "war", getdvar("g_gametype"));

    base_health = kv("scr_player_healthregen");
    // the dvar does not exist in a normal match; gamemodes.cpp restores 1 (= regen on) when the
    // party mode created it, so the expected baseline for the comparison is 1
    if (base_health == -999)
        base_health = 1;
    base_hardpoints = kv("scr_game_hardpoints");
    base_uav = kf("scr_game_mmUavTime");
    base_oldschool = kv("g_oldschool");
    mwx_test_log("mode_reset baseline: healthregen=" + base_health + " hardpoints=" + base_hardpoints +
        " uav=" + base_uav + " oldschool=" + base_oldschool);

    test_step("ph sets the party values");
    setdvar("g_gametype", "ph");
    wait 1;

    test_assert(kv("scr_player_healthregen") == 0, "ph: no health regen", "0", kv("scr_player_healthregen"));
    test_assert(kv("scr_game_hardpoints") == 0, "ph: no hardpoints", "0", kv("scr_game_hardpoints"));
    test_assert(kv("g_oldschool") == 0, "ph: oldschool off on a normal map", "0", kv("g_oldschool"));

    test_step("back to war restores the baseline");
    setdvar("g_gametype", "war");
    wait 1;

    test_assert(kv("scr_player_healthregen") == base_health, "health regen restored",
        base_health, kv("scr_player_healthregen"));
    test_assert(kv("scr_game_hardpoints") == base_hardpoints, "hardpoints restored",
        base_hardpoints, kv("scr_game_hardpoints"));
    test_assert(kv("g_oldschool") == base_oldschool, "oldschool restored",
        base_oldschool, kv("g_oldschool"));

    test_step("mprops does not leak either");
    setdvar("g_gametype", "mprops");
    wait 1;
    test_assert(kv("scr_game_hardpoints") == 0, "mprops: no hardpoints", "0", kv("scr_game_hardpoints"));

    setdvar("g_gametype", "war");
    wait 1;
    test_assert(kv("scr_game_hardpoints") == base_hardpoints, "hardpoints restored after mprops",
        base_hardpoints, kv("scr_game_hardpoints"));

    test_step("slasher sets mmUav/oldschool and war restores them");
    setdvar("g_gametype", "slasher");
    wait 1;
    test_assert(kf("scr_game_mmUavTime") == 30, "slasher: mmUav 30", "30", kf("scr_game_mmUavTime"));
    test_assert(kv("g_oldschool") == 1, "slasher: oldschool on", "1", kv("g_oldschool"));

    setdvar("g_gametype", "war");
    wait 1;
    test_assert(kf("scr_game_mmUavTime") == base_uav, "mmUav restored", base_uav, kf("scr_game_mmUavTime"));
    test_assert(kv("g_oldschool") == base_oldschool, "oldschool restored after slasher",
        base_oldschool, kv("g_oldschool"));

    test_done(1);
}
