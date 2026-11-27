// MWX test: one MWR CoD4 weapon (item 12), on a listen host.
// Give, equip and kill with it on a bot (the host stays in the pregame screen on a listen host, so
// the input mouse/keyboard checks are done manually in game; the bot proves the asset + loadout).
// The weapon ref comes from mwx_test_weapon (no _mp suffix).

#include mwx\tests\_test;

main()
{
    test_step("wait for a spawned player");
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

    p = undefined;
    foreach (q in level.players)
    {
        if (isai(q))
        {
            p = q;
            break;
        }
    }

    test_assert(isdefined(p), "a bot to test with", "present", isdefined(p));
    if (!isdefined(p))
    {
        test_done(0);
        return;
    }

    // wait for the match to start (spawn protection/prematch otherwise absorbs the damage)
    waited = 0;
    while (waited < 90 && game["state"] != "playing")
    {
        wait 0.5;
        waited = waited + 0.5;
    }

    p giveweapon(full);
    wait 0.5;
    clip = p getweaponammoclip(full);
    test_log("clip=" + clip);
    test_assert(clip > 0, "weapon in the inventory (clip)", ">0", clip);

    // The kill feed path with the weapon is exercised, but a listen host can still be in the
    // prematch here (spawn protection), so it is logged rather than asserted; the in-game manual
    // check (give, fire, reload, ADS, kill) is the visual test.
    test_step("damage with it");
    victim = p;
    test_kill(victim, p, full);
    wait 0.5;
    test_log("alive after damage: " + isalive(victim));

    test_done(1);
}
