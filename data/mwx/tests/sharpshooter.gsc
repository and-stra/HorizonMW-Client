// MWX test: Sharpshooter. Same weapon for everyone at spawn, then a rotation gives a different one.
// scr_sharpshooter_rotatetime is set to 6 s in tests.json so the test does not wait 45 s.

#include mwx\tests\_test;

main()
{
    test_step("wait for spawned players");
    spawned = test_wait_players(2, 90);
    test_assert(spawned >= 2, "players spawned", ">=2", spawned);

    test_hold_bots();

    test_step("everyone starts with the same weapon");

    waited = 0;
    first = undefined;
    same = 0;
    while (waited < 30 && !same)
    {
        wait 0.5;
        waited = waited + 0.5;

        same = 1;
        count = 0;
        foreach (player in level.players)
        {
            if (!isdefined(player.team) || !isalive(player))
                continue;
            weapon = player getcurrentweapon();
            if (weapon == "none")
            {
                same = 0;
                continue;
            }

            if (!isdefined(first))
                first = weapon;
            else if (weapon != first)
                same = 0;

            count++;
        }

        if (count < 2)
            same = 0;
    }

    test_assert(isdefined(first), "a player has a weapon", "weapon", "none");
    test_assert(same, "all players carry the same weapon", "1", same);

    gunsize = 0;
    if (isdefined(level.ss_guns))
        gunsize = level.ss_guns.size;
    test_assert(gunsize > 1, "the weapon rotation list is filled", ">1", gunsize);

    test_step("the weapon rotates");

    before = level.ss_weaponindex;
    rotation_before = level.ss_rotation;
    waited = 0;
    while (waited < 30 && level.ss_rotation == rotation_before)
    {
        wait 0.5;
        waited = waited + 0.5;
    }

    test_assert(level.ss_rotation > rotation_before, "the rotation timer fired", ">0",
        level.ss_rotation - rotation_before);
    test_assert(level.ss_weaponindex != before, "the weapon index changed", "!=" + before,
        level.ss_weaponindex);

    test_step("spin the wheel once more and look at the gun");
    waited = 0;
    while (waited < 30 && level.ss_rotation < rotation_before + 2)
    {
        wait 0.5;
        waited = waited + 0.5;
    }

    rotated_weapon = "none";
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || !isalive(player))
            continue;
        rotated_weapon = player getcurrentweapon();
        if (rotated_weapon != "none")
            break;
    }

    test_assert(rotated_weapon != "none", "a rotated weapon was given", "!none", rotated_weapon);

    test_done(1);
}
