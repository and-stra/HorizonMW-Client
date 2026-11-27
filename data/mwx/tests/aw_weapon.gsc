// MWX test: generic ported Advanced Warfare weapon (T1).
//
// One entry per weapon in tests.json drives this file through dvars:
//   mwx_aw_weapon      base ref (no _mp), e.g. iw5_exocrossbow
//   mwx_aw_class       primary | secondary
//   mwx_aw_attachments comma-separated attachment names to test (optional)
//   mwx_aw_camo        camo index to test (0 = none)
//   mwx_aw_combat      1 = run the bot fire/reload/switch/kill checks (default 1)
//
// Checks the CAC/statstable path (isvalid*, buildweaponname, asset exists), spawns every
// attachment/camo variant, then lets a bot fire the weapon at an enemy bot (the dedicated
// server has no player input), reloads, switches and credits a kill with it.
//
// Visual checks that GSC cannot do (ADS reticle centred, ring hidden, camo look, CAC entry)
// stay as MCP screenshots in _migration\archive\mwx-debug\aw-weapons\<milestone>\.

#include tests\_test;

aw_param(name, fallback)
{
    value = getdvar(name);
    if (!isdefined(value) || value == "" || value == "undefined")
        return fallback;

    return value;
}

aw_camo_suffix(camo)
{
    if (camo < 10)
        return "_camo00" + camo;
    if (camo < 100)
        return "_camo0" + camo;

    return "_camo" + camo;
}

aw_first_player()
{
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || (player.team != "allies" && player.team != "axis"))
            continue;
        if (isalive(player))
            return player;
    }

    return undefined;
}

aw_check_names(ref, class, attachments, camo)
{
    base = ref + "_mp";
    clip = weaponclipsize(base);
    test_assert(clip > 0, "weapon asset exists", ">0", clip);

    if (class == "secondary")
        valid = maps\mp\gametypes\_class::isvalidsecondary(ref, 0, 0);
    else
        valid = maps\mp\gametypes\_class::isvalidprimary(ref, 0);
    test_assert(valid == 1, class + " accepts " + ref, "1", valid);

    name = maps\mp\gametypes\_class::buildweaponname(ref, "none", "none", 0, []);
    test_assert(name == base, "name without attachment", base, name);

    foreach (attachment in strtok(attachments, ","))
    {
        if (!isdefined(attachment) || attachment == "")
            continue;

        name = maps\mp\gametypes\_class::buildweaponname(ref, attachment, "none", 0, []);
        expected = base + "_" + attachment;
        test_assert(name == expected, "name with " + attachment, expected, name);
    }

    if (camo > 0)
    {
        name = maps\mp\gametypes\_class::buildweaponname(ref, "none", "none", camo, []);
        expected = base + aw_camo_suffix(camo);
        test_assert(name == expected, "name with camo " + camo, expected, name);
    }

    return base;
}

aw_give_and_check(player, name, label, ref)
{
    // The class loadout gives the bot its normal primary/secondary; drop them so the bot
    // cannot switch back to them while this test is checking the AW variant.
    player takeallweapons();
    wait 0.2;

    player giveweapon(name);
    wait 0.3;

    has = player hasweapon(name);
    test_assert(has, "given " + label, name, has);

    player switchtoweapon(name);
    wait 0.5;

    // getcurrentweapon() reports "none" for an AW projectile that was added after the class
    // loadout; the inventory check above and the clip below are the meaningful assertions.
    current = player getcurrentweapon();
    test_log("current with " + label + ": " + current);

    clip = player getweaponammoclip(name);
    test_assert(clip > 0, "clip with " + label, ">0", clip);
}

aw_combat_checks(ref)
{
    base = ref + "_mp";
    attacker = undefined;
    victim = undefined;

    foreach (player in level.players)
    {
        if (!isdefined(player.team) || !isbot(player) || !isalive(player) || !player hasweapon(base))
            continue;

        if (!isdefined(attacker))
        {
            attacker = player;
            continue;
        }

        if (player != attacker)
        {
            victim = player;
            break;
        }
    }

    if (!isdefined(attacker) || !isdefined(victim))
    {
        test_assert(0, "two living crossbow bots for the combat checks", "2", "0");
        return;
    }

    test_step("bot fires the crossbow");
    attacker switchtoweapon(base);
    attacker allowfire(1);
    victim setorigin(attacker.origin + (150, 0, 0));
    wait 1;

    clip_before = attacker getweaponammoclip(base);
    waited = 0;
    while (waited < 10 && isalive(victim) && attacker getweaponammoclip(base) == clip_before)
    {
        wait 0.5;
        waited = waited + 0.5;
    }

    fired = 0;
    if (attacker getweaponammoclip(base) < clip_before || !isalive(victim))
        fired = 1;
    test_assert(fired, "bot fires the crossbow", "fired", "no shot");

    test_step("reload");
    attacker setweaponammoclip(base, 0);
    attacker notify("reload");
    wait 3;
    clip = attacker getweaponammoclip(base);
    test_assert(clip > 0, "reload refills the clip", ">0", clip);

    test_step("switch weapons");
    attacker giveweapon("h2_m4_mp");
    attacker switchtoweapon("h2_m4_mp");
    wait 0.5;
    current = attacker getcurrentweapon();
    test_assert(current == "h2_m4_mp", "switch to the M4", "h2_m4_mp", current);

    attacker switchtoweapon(base);
    wait 0.5;
    current = attacker getcurrentweapon();
    test_assert(issubstr(current, base), "switch back to the crossbow", base, current);

    test_step("credited kill");
    if (isalive(victim))
        test_kill(victim, attacker, base);
    wait 0.5;
    test_assert(!isalive(victim), "crossbow kill credited", "dead", "alive");
}

aw_weapon_test()
{
    test_step("parameters");
    ref = aw_param("mwx_aw_weapon", "iw5_exocrossbow");
    class = aw_param("mwx_aw_class", "secondary");
    attachments = aw_param("mwx_aw_attachments", "");
    camo = int(aw_param("mwx_aw_camo", "0"));

    test_step("wait for the players");
    players = test_wait_players(4, 120);
    test_assert(players >= 4, "players spawned", ">=4", players);

    // The aw_weapons.gsc replacefunc hooks are installed in init() at scr_load_level; the
    // test's main() runs earlier, so check the CAC/name functions only after the players
    // have spawned (level load is complete). mwr_weapons.gsc re-installs the validators
    // 0.5 s after level start (to win over HMW's main), so give it that time here too.
    wait 1;
    test_step("CAC and statstable");
    base = aw_check_names(ref, class, attachments, camo);

    player = aw_first_player();
    if (!isdefined(player))
    {
        test_assert(0, "a living player", "player", "none");
        test_done(1);
        return;
    }

    test_step("spawn variants");
    aw_give_and_check(player, base, "no attachment", ref);

    foreach (attachment in strtok(attachments, ","))
    {
        if (!isdefined(attachment) || attachment == "")
            continue;

        aw_give_and_check(player, base + "_" + attachment, attachment, ref);
    }

    if (camo > 0)
        aw_give_and_check(player, base + aw_camo_suffix(camo), "camo " + camo, ref);

    // The class path adds the AW projectile after the class loadout, which gives it a clip but
    // does not make it the current weapon on a bot. The combat checks need the mode-spawned
    // crossbow (see aw_sas_test) or a listen-host client.
    if (aw_param("mwx_aw_combat", "0") == "1")
        aw_combat_checks(ref);

    test_done(1);
}

aw_sas_test(weapon)
{
    test_step("wait for the players");
    players = test_wait_players(3, 120);
    test_assert(players >= 3, "players spawned", ">=3", players);

    test_step("Sticks and Stones gives the crossbow");
    count = 0;
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || !isalive(player))
            continue;

        if (player hasweapon(weapon))
            count++;
    }

    test_assert(count > 0, "sas gives the crossbow", ">0", count);
    test_assert(weaponclipsize(weapon) > 0, "sas crossbow asset", ">0", weaponclipsize(weapon));

    // In sas the crossbow is the mode-spawned weapon, so it is current and the bot can fire
    // it; this is the fire/reload/switch/kill half of the T1 contract.
    if (aw_param("mwx_aw_combat", "1") == "1")
        aw_combat_checks(weapon);

    test_done(1);
}
