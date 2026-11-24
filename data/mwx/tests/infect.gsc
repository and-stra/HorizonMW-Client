// MWX test: Infected (reference test, see docs/testing.md).
//
// Checks the first infected, the loadouts of both teams, that a killed survivor becomes infected
// with the right loadout, the team counts, a late joiner's loadout, the scavenger bag that drops
// on a kill, and both endings (survivors eliminated / time limit with survivors alive).
//
// Start it with run_test {name:"infect"} (or run_all_tests): that starts a dedicated server on
// mp_shipment with g_gametype infect, mwx_test=infect and 4 bots.
// The ending "B" run is the manifest entry infect_time (mwx_test_time_end=1).

#include mwx\tests\_test;

// fills level.mwx_firstinfected / level.mwx_survivor / level.mwx_axis / level.mwx_allies
scanplayers()
{
    level.mwx_firstinfected = undefined;
    level.mwx_survivor = undefined;
    level.mwx_axis = 0;
    level.mwx_allies = 0;

    foreach (player in level.players)
    {
        if (!isdefined(player.team))
            continue;

        if (player.team == "axis")
        {
            level.mwx_axis++;
            if (!isdefined(level.mwx_firstinfected))
                level.mwx_firstinfected = player;
        }
        else if (player.team == "allies")
        {
            level.mwx_allies++;
            if (!isdefined(level.mwx_survivor))
                level.mwx_survivor = player;
        }
    }
}

find_scavenger_trigger(origin)
{
    best = undefined;
    bestdist = 100000;

    foreach (trigger in getentarray("trigger_radius", "classname"))
    {
        if (!isdefined(trigger.bag_model))
            continue;

        d = distance(trigger.origin, origin);
        if (d < bestdist)
        {
            bestdist = d;
            best = trigger;
        }
    }

    return best;
}

// diagnostics: the round state and every player at a step (the 2026-11-24 run 1 failure had
// "new infected has no loadout" + "no late joiner" and the run was 136 s, over the 2 minute limit)
log_state(label)
{
    scanplayers();

    ended = 0;
    if (isdefined(level.gameended) && level.gameended)
        ended = 1;

    state = "state " + label + ": gameended=" + ended + " axis=" + level.mwx_axis + " allies=" + level.mwx_allies;
    if (isdefined(level.roundlimit))
        state = state + " round=" + level.roundlimit;
    test_log(state);

    foreach (player in level.players)
    {
        team = "none";
        if (isdefined(player.team))
            team = player.team;

        test_log("  " + player.name + " team=" + team + " alive=" + isalive(player) + " bot=" + isbot(player));
    }
}

// keep the infected bots from ending the round while the checks run (they only stop targeting and
// firing; the test still kills them itself)
hold_infected()
{
    level.mwx_heldbots = [];

    foreach (player in level.players)
    {
        if (!isdefined(player.team) || player.team != "axis" || !isbot(player))
            continue;

        player.ignoreall = 1;
        player allowfire(0);
        level.mwx_heldbots[level.mwx_heldbots.size] = player;
    }

    test_log("held " + level.mwx_heldbots.size + " infected bots");
}

release_infected()
{
    if (!isdefined(level.mwx_heldbots))
        return;

    foreach (player in level.mwx_heldbots)
    {
        if (!isdefined(player))
            continue;

        player.ignoreall = 0;
        player allowfire(1);
    }

    level.mwx_heldbots = undefined;
}

find_new_player_any(names)
{
    foreach (player in level.players)
    {
        if (!isdefined(player.team))
            continue;

        if (!test_contains_name(names, player.name))
            return player;
    }

    return undefined;
}

main()
{
    if (getdvarint("mwx_test_time_end", 0))
    {
        level thread time_end();
        return;
    }

    test_step("wait for the first infected");

    // the gametype starts the first-infected countdown after the prematch
    waited = 0;
    while (waited < 120 && level.infect_chosefirstinfected != 1)
    {
        wait 0.5;
        waited = waited + 0.5;
    }

    chosen = 0;
    if (level.infect_chosefirstinfected == 1)
        chosen = 1;

    if (!test_assert(chosen, "first infected chosen", "1", chosen))
    {
        test_done(0);
        return;
    }

    test_step("wait for the team change");

    // setfirstinfected starts the team change as a thread, so the axis player appears a moment
    // after level.infect_chosefirstinfected
    scanplayers();
    waited = 0;
    while (waited < 60 && (level.mwx_axis < 1 || level.mwx_allies < 2))
    {
        wait 0.25;
        waited = waited + 0.25;
        scanplayers();
    }

    test_assert(level.mwx_axis == 1, "exactly one first infected", "1", level.mwx_axis);
    test_assert(level.mwx_allies >= 2, "at least two survivors", ">=2", level.mwx_allies);
    log_state("after team change");

    if (level.mwx_axis < 1 || !isdefined(level.mwx_survivor))
    {
        test_done(0);
        return;
    }

    firstinfected = level.mwx_firstinfected;
    survivor = level.mwx_survivor;

    // the survivor loadout is checked first: the first infected can already kill a survivor while
    // the checks below poll for the infected's loadout
    test_step("check the survivor loadout");

    test_assert(survivor hasweapon("h2_spas12_mp"), "survivor primary", "h2_spas12_mp", "checked");
    test_assert(survivor hasweapon("h2_usp_mp"), "survivor secondary", "h2_usp_mp", "checked");
    test_assert(survivor hasweapon("h1_fraggrenade_mp"), "survivor lethal", "h1_fraggrenade_mp", "checked");
    test_assert(survivor hasweapon("h1_flashgrenade_mp"), "survivor tactical", "h1_flashgrenade_mp", "checked");
    test_assert(test_has_perk(survivor, "specialty_scavenger"), "survivor has scavenger", "1",
        test_has_perk(survivor, "specialty_scavenger"));

    test_step("check the first infected");

    // the loadout and the move speed are applied by the gametype a moment after the team change
    waited = 0;
    speed = 0;
    while (waited < 15)
    {
        speed = mwx_movespeedscale(firstinfected);
        if (speed >= 1.1 && firstinfected hasweapon("h2_hatchet_mp") && firstinfected hasweapon("flare_mp"))
            break;
        wait 0.25;
        waited = waited + 0.25;
    }

    test_assert(firstinfected.team == "axis", "first infected team", "axis", firstinfected.team);
    test_assert(firstinfected hasweapon("h2_hatchet_mp"), "first infected has the hatchet",
        "h2_hatchet_mp", "checked");
    test_assert(firstinfected hasweapon("iw9_throwknife_mp"), "first infected has the throwing knife",
        "iw9_throwknife_mp", "checked");
    test_assert(firstinfected hasweapon("flare_mp"), "first infected has the tactical insertion",
        "flare_mp", "checked");
    test_assert(speed >= 1.1, "first infected move speed scale", ">=1.1", speed);

    test_step("infect a survivor");

    axisbefore = level.mwx_axis;
    // dodamage(damage, point, attacker, inflictor, mod, weapon): the attacker is the third
    // argument; the kill counts for the gametype (and drops a scavenger bag like a real kill).
    survivor dodamage(1000, survivor.origin, firstinfected, firstinfected, "MOD_MELEE", "h2_hatchet_mp");

    waited = 0;
    while (waited < 10 && survivor.team != "axis")
    {
        wait 0.25;
        waited = waited + 0.25;
    }

    infectedteam = "none";
    if (isdefined(survivor.team))
        infectedteam = survivor.team;

    test_assert(infectedteam == "axis", "killed survivor became infected", "axis", infectedteam);

    log_state("after infect");
    // the first infected can keep infecting the other survivors while the loadout checks run; the
    // round then ends and the late joiner/scavenger steps fail. Hold the infected bots.
    hold_infected();

    // the gametype applies the infected loadout a moment after the team change
    waited = 0;
    while (waited < 15 && !(survivor hasweapon("h2_hatchet_mp")))
    {
        wait 0.25;
        waited = waited + 0.25;
    }

    // the loadout can be re-applied once more right after the team change (a leftover pistol was
    // seen when the check ran in between)
    waited = 0;
    while (waited < 10 && survivor hasweapon("h2_usp_mp"))
    {
        wait 0.25;
        waited = waited + 0.25;
    }

    scanplayers();
    // a bot can infect a second survivor while this check runs, so the count only has to grow
    test_assert(level.mwx_axis >= axisbefore + 1, "infected team count", ">=" + (axisbefore + 1), level.mwx_axis);
    test_assert(survivor hasweapon("h2_hatchet_mp"), "new infected has the hatchet", "h2_hatchet_mp", "checked");
    test_assert(survivor hasweapon("iw9_throwknife_mp"), "new infected has the throwing knife",
        "iw9_throwknife_mp", "checked");
    log_state("after infected loadout");

    keepspistol = 0;
    if (survivor hasweapon("h2_usp_mp"))
        keepspistol = 1;
    test_assert(!keepspistol, "new infected has no usp", "0", keepspistol);

    // ---------------------------------------------------------------- late joiner
    test_step("late joiner");
    log_state("before late joiner");

    names = [];
    foreach (player in level.players)
        names[names.size] = player.name;

    test_command("spawnBot 1");

    latejoiner = undefined;
    waited = 0;
    while (waited < 45 && !isdefined(latejoiner))
    {
        wait 0.5;
        waited = waited + 0.5;
        latejoiner = find_new_player_any(names);
    }

    joinerteam = "none";
    if (isdefined(latejoiner) && isdefined(latejoiner.team))
        joinerteam = latejoiner.team;

    test_log("late joiner: " + (isdefined(latejoiner) ? latejoiner.name : "none") + " team=" + joinerteam);
    log_state("after late joiner");
    test_assert(isdefined(latejoiner) && joinerteam == "allies", "late joiner joined as survivor",
        "allies", isdefined(latejoiner) ? joinerteam : "none");

    if (isdefined(latejoiner) && joinerteam == "allies")
    {
        // the loadout is applied a moment after the spawn
        waited = 0;
        while (waited < 15 && !(latejoiner hasweapon("h2_spas12_mp")))
        {
            wait 0.25;
            waited = waited + 0.25;
        }

        test_assert(latejoiner hasweapon("h2_spas12_mp"), "late joiner primary", "h2_spas12_mp", "checked");
        test_assert(latejoiner hasweapon("h2_usp_mp"), "late joiner secondary", "h2_usp_mp", "checked");
        test_assert(test_has_perk(latejoiner, "specialty_scavenger"), "late joiner has scavenger", "1",
            test_has_perk(latejoiner, "specialty_scavenger"));
    }

    // ---------------------------------------------------------------- scavenger bag
    test_step("scavenger bag");

    scanplayers();
    killer = undefined;
    victim = undefined;
    foreach (player in level.players)
    {
        if (!isdefined(player.team))
            continue;

        if (player.team == "allies" && !isdefined(killer) && test_has_perk(player, "specialty_scavenger"))
            killer = player;
        else if (player.team == "axis" && !isdefined(victim))
            victim = player;
    }

    if (!isdefined(killer) || !isdefined(victim))
    {
        test_assert(0, "survivor and infected for the scavenger bag", "both", "missing");
        test_done(0);
        return;
    }

    // make room in the stock so a pickup has a visible effect
    killer setweaponammostock("h2_spas12_mp", 0);
    wait 0.1;

    deathorigin = victim.origin;
    victim dodamage(1000, victim.origin, killer, killer, "MOD_RIFLE_BULLET", "h2_spas12_mp");

    // HMW drops the bag and a trigger 80/160 units around it
    waited = 0;
    trigger = undefined;
    while (waited < 10 && !isdefined(trigger))
    {
        wait 0.25;
        waited = waited + 0.25;
        trigger = find_scavenger_trigger(deathorigin);
    }

    test_assert(isdefined(trigger), "scavenger bag dropped", "trigger", isdefined(trigger) ? "found" : "none");

    if (isdefined(trigger))
    {
        ammo_before = killer getweaponammostock("h2_spas12_mp");

        // the engine fires this notify when a player touches the bag; standing in it does the same
        killer setorigin(trigger.origin);
        waited = 0;
        while (waited < 5)
        {
            wait 0.25;
            waited = waited + 0.25;
            if (killer getweaponammostock("h2_spas12_mp") > ammo_before)
                break;
        }

        if (killer getweaponammostock("h2_spas12_mp") <= ammo_before)
        {
            // fallback: the pickup path itself (trigger -> handlescavengerbagpickup)
            trigger notify("trigger", killer);
            wait 0.5;
        }

        ammo_after = killer getweaponammostock("h2_spas12_mp");
        test_assert(ammo_after > ammo_before, "scavenger bag refills ammo", ">" + ammo_before, ammo_after);
    }

    // ---------------------------------------------------------------- no killstreaks
    release_infected();
    test_step("no killstreak weapons");

    killstreak = 0;
    foreach (player in level.players)
    {
        foreach (weapon in player getweaponslistall())
        {
            if (issubstr(weapon, "killstreak") || issubstr(weapon, "airstrike") ||
                issubstr(weapon, "helicopter") || issubstr(weapon, "ac130"))
            {
                killstreak = 1;
            }
        }
    }
    test_assert(!killstreak, "no killstreak weapons", "0", killstreak);
    test_assert(getdvarint("scr_game_hardpoints") == 0, "killstreaks disabled in the gametype", "0",
        getdvarint("scr_game_hardpoints"));

    // ---------------------------------------------------------------- ending A
    test_step("end the game: survivors eliminated");

    foreach (player in level.players)
    {
        if (isdefined(player.team) && player.team == "allies")
        {
            player dodamage(1000, player.origin, level.mwx_firstinfected, level.mwx_firstinfected,
                "MOD_MELEE", "h2_hatchet_mp");
        }
    }

    waited = 0;
    while (waited < 20 && !level.gameended)
    {
        wait 0.25;
        waited = waited + 0.25;
    }

    ended = 0;
    if (level.gameended)
        ended = 1;
    test_assert(ended, "game ended", "1", ended);

    winner = "?";
    if (isdefined(level.finalkillcam_winner))
        winner = level.finalkillcam_winner;
    test_assert(winner == "axis", "infected won", "axis", winner);

    log_state("final");
    test_done(1);
}

// ending B: the time limit runs out with survivors alive -> survivors win (manifest: infect_time)
time_end()
{
    test_step("wait for the first infected");

    waited = 0;
    while (waited < 120 && level.infect_chosefirstinfected != 1)
    {
        wait 0.5;
        waited = waited + 0.5;
    }

    scanplayers();
    test_assert(level.infect_chosefirstinfected == 1, "first infected chosen", "1", level.infect_chosefirstinfected);
    test_assert(level.mwx_allies >= 2, "survivors alive at the time limit", ">=2", level.mwx_allies);
    test_assert(level.mwx_axis == 1, "one infected at the time limit", "1", level.mwx_axis);

    test_step("time limit");

    // the gametype extends its clock dynamically (gametimer: minutes passed + 2), so a short
    // scr_infect_timelimit does not end the match on its own. The test calls the gametype's own
    // time-limit handler: winner, reason and end flow are the real ones.
    if (!level.gameended)
        [[level.ontimelimit]]();

    waited = 0;
    while (waited < 20 && !level.gameended)
    {
        wait 0.25;
        waited = waited + 0.25;
    }

    ended = 0;
    if (level.gameended)
        ended = 1;
    test_assert(ended, "game ended", "1", ended);

    winner = "?";
    if (isdefined(level.finalkillcam_winner))
        winner = level.finalkillcam_winner;
    test_assert(winner == "allies", "survivors won", "allies", winner);

    alive = 0;
    foreach (player in level.players)
    {
        if (isdefined(player.team) && player.team == "allies" && isalive(player))
            alive++;
    }
    test_assert(alive > 0, "survivors were alive", ">0", alive);

    test_done(1);
}