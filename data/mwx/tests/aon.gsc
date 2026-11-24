// MWX test: All or Nothing (aon.gsc): USP with no ammo and a throwing knife, scavenger/fast reload/
// longer sprint, 20 kills end the match, the winner that never died gets the bonus.

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

main()
{
    test_step("wait for the players");

    players = test_wait_players(3, 120);
    test_assert(players >= 3, "players spawned", ">=3", players);

    test_step("loadout");

    first = undefined;
    badloadout = 0;
    badperks = 0;
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || !isalive(player))
            continue;

        if (!isdefined(first))
            first = player;

        if (!(player hasweapon("h2_usp_mp")))
            badloadout++;
        if (player getweaponammoclip("h2_usp_mp") != 0)
            badloadout++;
        if (player getweaponammostock("h2_usp_mp") != 0)
            badloadout++;
        if (!(player hasweapon("iw9_throwknife_mp")))
            badloadout++;

        if (!test_has_perk(player, "specialty_scavenger"))
            badperks++;
        if (!test_has_perk(player, "specialty_fastreload"))
            badperks++;
        if (!test_has_perk(player, "specialty_longersprint"))
            badperks++;
    }

    test_assert(badloadout == 0, "empty USP and a throwing knife", "0", badloadout);
    test_assert(badperks == 0, "scavenger, fast reload, longer sprint", "0", badperks);
    test_assert(getdvarint("scr_aon_scorelimit") == 20, "score limit 20", "20", getdvarint("scr_aon_scorelimit"));

    if (!isdefined(first))
    {
        test_done(0);
        return;
    }

    test_step("the 20th kill ends the match, never died bonus");

    winner = first;
    victim = first_alive(winner);
    test_assert(isdefined(victim), "victim", "player", isdefined(victim) ? victim.name : "none");
    if (!isdefined(victim))
    {
        test_done(0);
        return;
    }

    // 19 kills already, the next kill is the 20th
    winner.aon_kills = 19;
    deaths_before = winner.deaths;

    test_kill(victim, winner, "iw9_throwknife_mp");

    waited = 0;
    while (waited < 20 && !level.gameended)
    {
        wait 0.25;
        waited = waited + 0.25;
    }

    ended = 0;
    if (level.gameended)
        ended = 1;
    test_assert(ended, "game ended at 20 kills", "1", ended);
    test_assert(winner.aon_kills == 20, "twenty kills counted", "20", winner.aon_kills);
    test_assert(deaths_before == 0, "winner never died", "0", deaths_before);
    test_assert(maps\mp\gametypes\_rank::isregisteredevent("mwx_allornothing"),
        "never-died bonus awarded", "1", maps\mp\gametypes\_rank::isregisteredevent("mwx_allornothing"));

    test_done(1);
}
