// MWX test: One in the Chamber (oic.gsc): revolver with 1 round, +1 round per kill, 3 lives, the
// last player alive wins.

#include mwx\tests\_test;

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

alivecount()
{
    count = 0;
    foreach (player in level.players)
    {
        if (isdefined(player.team) && isalive(player))
            count++;
    }

    return count;
}

// oic diagnosis: the full run failed to end the match while a lone run passed. Kills during the
// spawn grace period do not consume lives (H1 _gamelogic::default_ondeadevent returns early while
// level.ingraceperiod is set), so the state is logged and kills wait for the grace period.
log_state(label)
{
    grace = "undef";
    if (isdefined(level.ingraceperiod))
        grace = level.ingraceperiod;

    ended = "undef";
    if (isdefined(level.gameended))
        ended = level.gameended;

    test_log("state " + label + ": grace=" + grace + " gameended=" + ended +
        " numlives=" + maps\mp\_utility::getgametypenumlives() +
        " potential=" + maps\mp\_utility::getpotentiallivingplayers().size);

    foreach (player in level.players)
    {
        lives = "undef";
        if (isdefined(player.pers) && isdefined(player.pers["lives"]))
            lives = player.pers["lives"];

        session = "undef";
        if (isdefined(player.sessionstate))
            session = player.sessionstate;

        test_log("  " + player.name + " alive=" + isalive(player) + " sessionstate=" + session +
            " lives=" + lives);
    }
}

// returns the waited time; 0 = the grace period was already over
wait_grace(timeout)
{
    waited = 0;
    while (waited < timeout && isdefined(level.ingraceperiod) && level.ingraceperiod)
    {
        wait 0.25;
        waited = waited + 0.25;
    }

    return waited;
}

first_alive(ignore1, ignore2)
{
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || !isalive(player))
            continue;

        if (isdefined(ignore1) && player == ignore1)
            continue;
        if (isdefined(ignore2) && player == ignore2)
            continue;

        return player;
    }

    return undefined;
}

ammo_total(player)
{
    return player getweaponammoclip(player.oic_weapon) + player getweaponammostock(player.oic_weapon);
}

// kills `victim` until it stops respawning (oic: 3 lives) and returns 1 when it is gone
eliminate(attacker, victim)
{
    tries = 0;

    while (tries < 8)
    {
        tries++;

        if (!wait_alive(victim, 10))
            return 1;

        // kills during the grace period do not take a life (see log_state)
        wait_grace(20);
        wait 0.5;
        test_kill(victim, attacker, attacker.oic_weapon);

        // wait for the death, then for the respawn window
        waited = 0;
        while (waited < 5 && isalive(victim))
        {
            wait 0.25;
            waited = waited + 0.25;
        }
        wait 1.5;

        log_state("after kill " + victim.name + " try " + tries);
    }

    if (isalive(victim))
        return 0;

    return 1;
}

main()
{
    test_step("wait for the players");

    players = test_wait_players(4, 120);
    test_assert(players >= 4, "players spawned", ">=4", players);

    test_step("loadout");

    first = undefined;
    badloadout = 0;
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || !isalive(player))
            continue;

        if (!isdefined(first))
            first = player;

        if (!isdefined(player.oic_weapon))
        {
            badloadout++;
            continue;
        }

        if (!(player hasweapon(player.oic_weapon)))
            badloadout++;
        if (player getweaponammoclip(player.oic_weapon) > 1)
            badloadout++;
        if (player getweaponammostock(player.oic_weapon) != 0)
            badloadout++;
    }

    test_assert(badloadout == 0, "revolver with one round, no stock", "0", badloadout);
    test_assert(getdvarint("scr_oic_numlives") == 3, "three lives", "3", getdvarint("scr_oic_numlives"));

    if (!isdefined(first))
    {
        test_done(0);
        return;
    }

    test_step("a kill gives one round");

    attacker = first;
    victim = first_alive(attacker);
    test_assert(isdefined(victim), "victim", "player", isdefined(victim) ? victim.name : "none");
    if (!isdefined(victim))
    {
        test_done(0);
        return;
    }

    attacker setweaponammoclip(attacker.oic_weapon, 0);
    attacker setweaponammostock(attacker.oic_weapon, 0);
    wait 0.2;

    test_kill(victim, attacker, attacker.oic_weapon);
    wait 1;

    after = ammo_total(attacker);
    test_assert(after == 1, "one kill, one round", "1", after);

    test_step("lives");

    // bots can kill each other (and consume lives) between the test's kills, which made the final
    // "one left" check flaky; hold them for the elimination phase
    test_hold_bots();

    // the spawn grace period is over before any kill counts (H1 ignores deaths during it)
    waited = wait_grace(30);
    test_log("grace waited " + waited + " s");
    log_state("before kills");

    // two more kills: the victim respawns twice and is gone after the third death
    eliminated = eliminate(attacker, victim);
    test_assert(eliminated, "victim eliminated after three deaths", "1", eliminated);
    log_state("after first elimination");

    test_step("last player alive wins");

    round = 0;
    while (round < 3 && alivecount() > 1)
    {
        other = first_alive(attacker);
        if (!isdefined(other))
            break;

        eliminated = eliminate(attacker, other);
        test_assert(eliminated, "player eliminated", "1", eliminated);
        log_state("after elimination round " + round);
        round++;
    }

    // the last death starts the endgame in a thread; wait for it before checking the winner
    waited = 0;
    while (waited < 20 && !level.gameended)
    {
        wait 0.25;
        waited = waited + 0.25;
    }

    log_state("final");

    ended = 0;
    if (level.gameended)
        ended = 1;
    test_assert(ended, "game ended when one player was left", "1", ended);
    test_assert(alivecount() == 1, "exactly one player alive", "1", alivecount());

    test_release_bots();
    test_done(1);
}
