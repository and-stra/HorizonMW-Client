// MWX test: cycle the 28 MWR DLC melee weapons (item 12), on a listen host.
// Every ref must give + equip (the statstable/customweapons row and the whitelist are in place).
// The last one is also used for a kill.

#include mwx\tests\_test;

main()
{
    test_step("wait for the spawned player");
    spawned = test_wait_players(1, 90);
    test_assert(spawned >= 1, "a player spawned", ">=1", spawned);

    melee = [
        "h1_meleeapr1", "h1_meleeapr2", "h1_meleeapr3", "h1_meleeapr4",
        "h1_meleeaug1", "h1_meleeaug2", "h1_meleeaug3", "h1_meleeaug4",
        "h1_meleebayonet", "h1_meleeblade", "h1_meleebottle",
        "h1_meleefeb1", "h1_meleefeb2", "h1_meleefeb3", "h1_meleefeb4", "h1_meleefeb5",
        "h1_meleegladius", "h1_meleehatchet", "h1_meleeicepick",
        "h1_meleejun1", "h1_meleejun2", "h1_meleejun3", "h1_meleejun4", "h1_meleejun5", "h1_meleejun6",
        "h1_meleepaddle", "h1_meleeshovel", "h1_meleesickle"
    ];

    p = getentbynum(0);
    test_assert(isdefined(p) && isplayer(p), "local player", "host", isdefined(p) && isplayer(p));
    if (!isdefined(p))
    {
        test_done(0);
        return;
    }

    equipped = 0;
    foreach (ref in melee)
    {
        full = ref + "_mp";
        p giveweapon(full);
        p switchtoweapon(full);
        wait 0.15;
        if (p getcurrentweapon() == full)
        {
            equipped++;
        }
        else
        {
            test_log("FAIL equip " + ref + " (got " + p getcurrentweapon() + ")");
        }
    }

    test_assert(equipped == melee.size, "every melee weapon equips", melee.size, equipped);

    test_step("kill a bot with the last melee weapon");
    bot = undefined;
    foreach (q in level.players)
    {
        if (q != p && isai(q))
        {
            bot = q;
            break;
        }
    }

    if (isdefined(bot))
    {
        test_kill(bot, p, melee[melee.size - 1] + "_mp");
        wait 0.5;
        test_assert(!isalive(bot), "bot killed", "dead", isalive(bot));
    }
    else
    {
        test_assert(0, "a bot to kill", "present", "none");
    }

    test_done(1);
}
