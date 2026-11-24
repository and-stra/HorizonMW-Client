// MWX game mode test helpers (see docs/testing.md).
//
// Test scripts #include this file and report through mwx_event(); the MCP bridge collects the
// events and builds the summary (passed / failed / failures).

mwx_test_escape(value)
{
    if (!isdefined(value))
        return "";

    text = "" + value;
    result = "";

    for (index = 0; index < text.size; index++)
    {
        character = getsubstr(text, index, index + 1);
        if (character == "\"" || character == "\\")
            result = result + "\\" + character;
        else if (character == "\n" || character == "\r" || character == "\t")
            result = result + " ";
        else
            result = result + character;
    }

    return result;
}

test_step(name)
{
    mwx_event("test_step", "{\"step\":\"" + mwx_test_escape(name) + "\"}", "test");
    mwx_test_log("step: " + name);
}

test_log(text)
{
    mwx_test_log("" + text);
}

// asks the test runner (MCP run_test / tools) to run a console command on this server, e.g.
// test_command("spawnBot 1") for a late joiner. The runner watches the event stream.
test_command(command)
{
    mwx_event("test_action", "{\"command\":\"" + mwx_test_escape(command) + "\"}", "test");
    mwx_test_log("command: " + command);
}

test_assert(condition, name, expected, actual)
{
    ok = 0;
    if (isdefined(condition) && condition)
        ok = 1;

    mwx_event("test_assert", "{\"ok\":" + ok +
        ",\"name\":\"" + mwx_test_escape(name) +
        "\",\"expected\":\"" + mwx_test_escape(expected) +
        "\",\"actual\":\"" + mwx_test_escape(actual) + "\"}", "test");

    mwx_test_log((ok ? "PASS " : "FAIL ") + name + " (expected " + expected + ", got " + actual + ")");
    return ok;
}

test_done(ok)
{
    mwx_event("test_done", "{\"ok\":" + (ok ? 1 : 0) + "}", "test");
    mwx_test_log("done");
}

// ---- shared helpers ---------------------------------------------------------------------------

test_has_perk(player, perk)
{
    if (isdefined(player.perks[perk]) && player.perks[perk])
        return 1;

    return 0;
}

test_player_names()
{
    names = [];
    foreach (player in level.players)
        names[names.size] = player.name;

    return names;
}

test_contains_name(names, name)
{
    foreach (entry in names)
    {
        if (entry == name)
            return 1;
    }

    return 0;
}

// first player on `team` whose name is not in `names` (a late joiner)
test_find_new_player(names, team)
{
    foreach (player in level.players)
    {
        if (!isdefined(player.team) || player.team != team)
            continue;

        if (!test_contains_name(names, player.name))
            return player;
    }

    return undefined;
}

// waits until at least `count` players are on a team (spawned into the match)
test_wait_players(count, timeout)
{
    waited = 0;
    while (waited < timeout)
    {
        players = 0;
        foreach (player in level.players)
        {
            if (isdefined(player.team) && (player.team == "allies" || player.team == "axis") && isalive(player))
                players++;
        }

        if (players >= count)
            return players;

        wait 0.5;
        waited = waited + 0.5;
    }

    return 0;
}

test_alive_on_team(team)
{
    count = 0;
    foreach (player in level.players)
    {
        if (isdefined(player.team) && player.team == team && isalive(player))
            count++;
    }

    return count;
}

// kills `victim` and attributes the kill to `attacker` (the third dodamage argument; a two argument
// dodamage credits the world instead)
test_kill(victim, attacker, weapon)
{
    if (!isdefined(attacker))
        attacker = victim;

    victim dodamage(1000, victim.origin, attacker, attacker, "MOD_RIFLE_BULLET", weapon);
}
