// MWX test: Sticks and Stones (native gametype sas): crossbow from hmw_aw_weapons.ff, melee weapon
// and throwing knife; a throwing knife kill bankrupts the victim and a suicide bankrupts the player.

#include mwx\tests\_test;

first_alive(ignore)
{
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || !isalive(player))
            continue;

        if (isdefined(ignore) && player == ignore)
            continue;

        return player;
    }

    return undefined;
}

wait_alive(player, timeout)
{
    waited = 0;
    while (waited < timeout)
    {
        if (isalive(player))
            return 1;

        wait 0.25;
        waited = waited + 0.25;
    }

    return 0;
}

set_score(player, value)
{
    // _setplayerscore takes (player, value) - calling it as a method passes the value as the player
    maps\mp\gametypes\_gamescore::_setplayerscore(player, value);
    return player.pers["score"];
}

main()
{
    test_step("wait for the players");

    players = test_wait_players(3, 120);
    test_assert(players >= 3, "players spawned", ">=3", players);

    test_step("loadout");

    weapon = getdvar("sas_weapon");
    test_assert(weapon == "iw5_exocrossbow_mp", "the crossbow is the weapon", "iw5_exocrossbow_mp", weapon);

    first = undefined;
    badloadout = 0;
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || !isalive(player))
            continue;

        if (!isdefined(first))
            first = player;

        if (!(player hasweapon(weapon)))
            badloadout++;
        if (!(player hasweapon("iw9_throwknife_mp")))
            badloadout++;
        if (!(player hasweapon("h2_hatchet_mp")))
            badloadout++;
    }

    test_assert(badloadout == 0, "crossbow, hatchet and throwing knife", "0", badloadout);

    if (!isdefined(first))
    {
        test_done(0);
        return;
    }

    attacker = first;
    victim = first_alive(attacker);
    test_assert(isdefined(victim), "victim", "player", isdefined(victim) ? victim.name : "none");
    if (!isdefined(victim))
    {
        test_done(0);
        return;
    }

    test_step("a throwing knife kill bankrupts the victim");

    startscore = set_score(victim, 100);
    test_assert(startscore == 100, "victim score set", "100", startscore);

    test_kill(victim, attacker, "iw9_throwknife_mp");

    waited = 0;
    while (waited < 10 && victim.pers["score"] > 0)
    {
        wait 0.25;
        waited = waited + 0.25;
    }

    banked = victim.pers["score"];
    test_assert(banked == 0, "throwing knife kill bankrupted the victim", "0", banked);

    test_step("a suicide bankrupts the player");

    if (wait_alive(victim, 15))
    {
        startscore = set_score(victim, 50);
        test_assert(startscore == 50, "victim score set", "50", startscore);

        // no attacker: the gametype treats it as a suicide. test_kill would substitute the victim
        // as the attacker, so use the 2 argument dodamage (credits the world).
        victim dodamage(1000, victim.origin);

        waited = 0;
        while (waited < 10 && victim.pers["score"] > 0)
        {
            wait 0.25;
            waited = waited + 0.25;
        }

        banked = victim.pers["score"];
        test_assert(banked == 0, "suicide bankrupted the player", "0", banked);
    }
    else
    {
        test_assert(0, "victim respawned for the suicide check", "alive", "dead");
    }

    test_done(1);
}
