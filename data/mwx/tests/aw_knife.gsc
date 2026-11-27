// MWX test: AW pilot combat knife (iw5_combatknife).
// Melee weapons go into the melee slot, so the inventory check is hasweapon (switchtoweapon does
// not make one current). Also checks the melee whitelist and kills a bot with it.

#include mwx\tests\_test;

main()
{
    test_step("wait for the spawned player");
    spawned = test_wait_players(2, 90);
    test_assert(spawned >= 2, "players spawned", ">=2", spawned);

    // mwr_weapons.gsc re-installs the class validators 0.5 s after level start
    wait 1;

    weapon = "iw5_combatknife_mp";

    test_step("whitelist");
    valid = maps\mp\gametypes\_class::isvalidmeleeweapon("iw5_combatknife", 0);
    test_assert(valid == 1, "melee whitelist accepts the combat knife", "1", valid);

    p = getentbynum(0);
    test_assert(isdefined(p) && isplayer(p), "local player", "host", isdefined(p) && isplayer(p));
    if (!isdefined(p))
    {
        test_done(0);
        return;
    }

    test_step("give and equip");
    p giveweapon(weapon);
    wait 0.3;
    test_assert(p hasweapon(weapon), "combat knife in the loadout", "1", p hasweapon(weapon));

    test_step("kill a bot");
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
        test_kill(bot, p, weapon);
        wait 0.5;
        test_assert(!isalive(bot), "bot killed", "dead", isalive(bot));
    }
    else
    {
        test_assert(0, "a bot to kill", "present", "none");
    }

    test_done(1);
}
