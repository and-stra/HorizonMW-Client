// MWX test: one MWR DLC/CoD4 weapon (item 12), on a listen host.
// Give, fire, reload, ADS, kill a bot. The weapon ref comes from mwx_test_weapon (no _mp suffix).
// The runner executes the +attack/+reload/+aim test_commands for the local player.

#include mwx\tests\_test;

main()
{
    test_step("wait for the spawned player");
    spawned = test_wait_players(1, 90);
    test_assert(spawned >= 1, "a player spawned", ">=1", spawned);

    weapon = getdvar("mwx_test_weapon", "");
    test_assert(weapon != "", "weapon dvar set", "non-empty", weapon);
    if (weapon == "")
    {
        test_done(0);
        return;
    }

    full = weapon + "_mp";
    class = getdvar("mwx_test_weapon_class", "primary");

    p = getentbynum(0);
    test_assert(isdefined(p) && isplayer(p), "local player", "host", isdefined(p) && isplayer(p));
    if (!isdefined(p))
    {
        test_done(0);
        return;
    }

    p giveweapon(full);
    p switchtoweapon(full);
    wait 0.5;
    test_assert(p getcurrentweapon() == full, "equipped", full, p getcurrentweapon());

    clip = p getweaponammoclip(full);
    test_log("clip=" + clip);
    if (class != "melee")
    {
        test_assert(clip > 0, "clip loaded", ">0", clip);

        test_step("fire");
        test_command("+attack");
        wait 0.5;
        test_command("-attack");
        wait 0.5;
        after = p getweaponammoclip(full);
        test_assert(after < clip, "fired (clip decreased)", "<" + clip, after);

        test_step("reload");
        test_command("+reload");
        wait 2.5;
        test_command("-reload");
        after = p getweaponammoclip(full);
        test_assert(after > 0, "reload filled the clip", ">0", after);

        test_step("ADS");
        test_command("+aim");
        wait 0.6;
        ads = p playerads();
        test_command("-aim");
        test_assert(ads > 0.5, "ADS", ">0.5", ads);
    }

    test_step("kill a bot with it");
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
        test_kill(bot, p, full);
        wait 0.5;
        test_assert(!isalive(bot), "bot killed", "dead", isalive(bot));
    }
    else
    {
        test_assert(0, "a bot to kill", "present", "none");
    }

    test_done(1);
}
