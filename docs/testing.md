# Game mode tests

MWX has logic tests for the game modes. They run on a dedicated server (no rendering), report
through the debug interface and are collected by the MCP bridge, so a full run needs nothing but
`run_all_tests` (or `tools\test\run-tests.ps1` without the MCP, see below).

```
run_all_tests -> a background job; for every entry in mwx\tests\tests.json:
                   start_server (+map, +set g_gametype, +set mwx_test=<script>, test dvars, -mod)
                   wait for sv_running, spawn the bots
                   follow the event stream: test_action -> run its console command
                                            test_done   -> stop
                   stop_instance
                 -> test_status {job} -> {tests: [...], passed, failed}
```

A run takes ~1.5 min per test (most of it is the map load), so the full set is ~20-25 minutes.
`run_test` / `run_all_tests` return a job id at once; a single MCP tool call must stay under the
client's request timeout (~60 s), so the result is polled with `test_status`.

## Parallel runs (`-Parallel N`)

`tools\test\run-tests.ps1 -Parallel N` (and `run_all_tests {parallel: N}`) runs up to N dedicated
servers at the same time. Every test keeps its own debug port, its own net port and its own log
file; the per-test result JSONs are merged into the one `test-results-<time>.json` in manifest
order. `-Parallel 1` is the default.

Two processes must **not** run their early startup at the same time: the engine exits the second
one with no console output and no crash dump while the first is still initialising its zones (the
window is ~15 s; a 6 s gap was not enough, a fixed 30 s gap worked most of the time but still
flaked). This is fixed in two places:

- The client serialises its init phase with the named mutex `Local\mwx-startup-lock`
  (`load_timing::acquire_startup_lock`, released on the first main-thread frame, with a 45 s
  watchdog and a 180 s wait timeout). Four clients started in the same second now all reach the
  menu; the measured `---- startup lock acquired after N ms ----` lines show the queue.
- `run-tests.ps1` starts the next parallel worker only after the previous game answers the debug
  RPC (no fixed sleep), and both this runner and `menu-smoke.ps1` retry a silent startup exit once.

The parent also waits for a free net port before each start.

Measured full runs (26 tests, commit `1ca2854e` + the parallel runner):

| N | wall time | green | notes |
|---|---|---|---|
| 1 | 38:04 | 24/26 | `srescue` hit net port 27036 (Steam holds it); `survival` known (pre-B5) |
| 4 | **15:10** | 24/26 | same two: `srescue` port 27036, `survival` known |

N=4 is the default: 2.5x faster with the identical result. `-Parallel 1` stays available for
load-time-sensitive runs. The net-port picker skips ports that another program owns (Steam's
27036), so a fixed conflict cannot fail a test.

## Writing a test

A test is a GSC script in `data/mwx/tests/<name>.gsc` with a `main()` function:

```gsc
#include mwx\tests\_test;

main()
{
    test_step("what is being checked");

    test_assert(condition, "name", expected, actual);

    test_done(1);   // 1 = the test finished, not "everything passed"
}
```

`_test.gsc` provides:

| function | effect |
|---|---|
| `test_step(name)` | marks a step (event `test_step`) |
| `test_assert(condition, name, expected, actual)` | one check (event `test_assert`, `ok` = condition) |
| `test_done(ok)` | ends the test (event `test_done`) |
| `test_command("spawnBot 1")` | asks the runner to run a console command on the server (event `test_action`); used for a late joiner, a map change, ... |
| `test_has_perk(player, perk)` | `player.perks[perk]` as 0/1 |
| `test_kill(victim, attacker, weapon)` | `dodamage` with the attacker as the third argument (see "Damage in tests") |
| `test_wait_players(count, timeout)` | waits until `count` players are spawned on a team |
| `test_alive_on_team(team)` | living players of a team |
| `test_player_names()` / `test_find_new_player(names, team)` | late joiner detection |
| `mwx_test_escape(text)` | escapes text for the JSON the events carry |

The bridge builds the summary from the events: `passed` / `failed` counts, the `failures` list with
name, expected and actual, `steps`, `script_errors` (any GSC error the server printed during the
run) and `duration_s` (between `test_started` and `test_done`).

Rules:

- Never let `main()` block: it runs as a thread, `wait` is fine, but a test must always reach
  `test_done` (use bounded `while (waited < N)` loops).
- GSC has no ternary operator, no `local`, no `{}` blocks, no `;` at the end of statements that
  are not assignments. Strings are double quoted; `getsubstr(s, start, end)` has an exclusive end.
- Test scripts are only loaded when `mwx_test=<script>` is set: in that case
  `gsc::load_gametype_script_stub` also loads `mwx/tests/<script>` with the normal script pass and
  its `main()` runs via `load_main_handles()`. Nothing of this happens in a normal game.
- `run_test`/`run_all_tests` put the map on the server command line (`+map`): a `map` command
  issued after boot is not used by the tests (it crashes a dedicated server in this build).
- A test checks `isdefined(level.something)` only where 0 and undefined differ: `onstartgametype`
  initializes most counters with 0, so `!isdefined(x)` never fires for them. Compare the value.

## The manifest (`data/mwx/tests/tests.json`)

```json
[
  {
    "name": "infect",
    "script": "infect",
    "gametype": "infect",
    "map": "mp_shipment",
    "mod": "mods/sticksandstones",
    "timeout_s": 300,
    "dvars": { "scr_infect_timelimit": "2", "mwx_test_bots": 4 }
  }
]
```

| field | meaning |
|---|---|
| `name` | test id for `run_test {name}` (unique) |
| `script` | script in `mwx/tests/` to run (default: `name`) |
| `map` | map to load (default `mp_shipment`: small and flat, bots meet and kill fast) |
| `gametype` | `g_gametype` for the run |
| `mod` | optional `-mod` (e.g. `mods/sticksandstones`) |
| `dvars` | extra dvars (also `mwx_test_bots`, the number of bots to spawn) |
| `timeout_s` | how long the bridge waits for `test_done` |
| `listen` | `true` = run on a client that hosts (listen server) instead of a dedicated server |

Party modes run as their virtual gametype (`gametype: "slasher"`, `"rpg"`), not as
`war` + `scr_game_hodgepodgeMode`: `gamemodes.cpp` translates the ref to `war` + the hodgepodge dvar
at script load and resets the dvar for every other gametype, so a `+set scr_game_hodgepodgeMode 2`
next to `g_gametype war` is reset to 0 again (the slasher test hung on that).

The extra runs (`infect_rust`, `war_rust`, `war_terrace`) reuse the scripts on other maps: HMW
usermap loading (`mp_rust`) and an AW map port (`mp_terrace`, factions + helicopter).

Objective modes (`sd`, `dom`, `dz`) check that the objective entities spawn; they use `mp_crash`
because their objectives are map-placed.

`listen: true` is used for AW ported maps: `mp_terrace` loads on a client but not on a dedicated
server (the DS hangs during the map load, see the report).

### Round ends

`war.gsc`/`objective.gsc` end the round through the gametype's own path
(`maps\mp\gametypes\_gamelogic::endgame`) instead of waiting for a time limit, so a test takes
~85 s instead of several minutes. The real end path is still what runs. The same is done for
endings that depend on the clock: `infect_time` calls the gametype's `ontimelimit` handler because
`infect.gsc` extends `scr_infect_timelimit` dynamically while the match runs, so a one minute
`+set` would not end it.

### Damage in tests

`dodamage(damage, point, attacker, inflictor, mod, weapon)` is the form HMW's own scripts use
(`maps\mp\gametypes\_weapons.gsc`, `_hodgepodge_ph.gsc`): the **third** argument is the attacker.
`test_kill(victim, attacker, weapon)` wraps it, so a test can produce a real "killed by player X"
death (kill feed, team change, scavenger bag, bankrupt, ...) instead of a world suicide.

An earlier note in this file claimed only the 2 argument form works - that came from passing the
attacker as the second argument (the point), which makes the engine credit the world. Without an
attacker the gametypes treat the death as a suicide.

## Tools

| Tool | Arguments | Result |
|---|---|---|
| `list_tests` | – | the names from `tests.json` |
| `run_test` | `name` | starts a job: `{job, name, state, hint}` |
| `run_all_tests` | `name` (optional) | starts a job for every test (or one) |
| `test_status` | `job` (optional) | `{jobs: [{job, name, state, elapsed_s, result}]}`, newest first |
| `cancel_test` | `job` | stops the running job's server |

A single test result: `{test, script, map, gametype, mod, passed, failed, failures, steps,
script_errors, done, kills, kill_weapons, duration_s, total_s}`. `kills` / `kill_weapons` come from
the event stream (the weapons the match was actually fought with).

Only one test job runs at a time (a second `run_test` answers with an error): two game instances on
one PC block each other's map load.

## Without the MCP

`tools\test\run-tests.ps1` does the same through the debug HTTP interface (start the server with
`Start-Process`, poll `/rpc`, collect the events, stop it) and writes `test-results-<time>.json`.
It is the fallback when the MCP bridge is not connected, and it is what the Windows regression
check uses.

## Menu smoke test

`tools\test\menu-smoke.ps1` drives a **client** through the private match menus over the debug RPC:
main menu -> PLAY ONLINE -> PRIVATE MATCH -> GAME SETUP -> MODE -> every Party mode and
Domination/Team Deathmatch -> START (checks `g_gametype`, `ui_gametype`/loading screen name,
`mwx_gamemode`) -> back to the lobby -> START again -> main menu -> PLAY ONLINE -> MODS menu
open/close. A crash, a new file in `minidumps\`, a Lua error or a wrong mode fails it.

```
powershell -File tools\test\menu-smoke.ps1 -Runs 5        # the release check
powershell -File tools\test\menu-smoke.ps1 -Runs 1 -Quick -Modes ph,dom   # quick pass
```

It starts a fresh client per run (debug ports 27201+), so it does not use `tests.json` servers.

## Class menu (CAC) checks

The class menu is driven over the debug RPC (`ui_click`, `ui_snapshot`, `lua_eval`), never with
`sv_cheats` + `give`: in a listen host `sv_cheats` is registered with `DVAR_FLAG_READ` and cannot
be set, and `give` refuses with "Cheats are not enabled on this server". To give a weapon in a
test, use the test dvar/script path (`aw_crossbow`, `aw_m1garand`) or pick it in the class menu.

A saved class can be read back without the UI: `Engine.GetPlayerData(0,
CoD.GetStatsGroupForGameMode(), "customClasses", <slot>, "weaponSetups", 0, "weapon")` from
`lua_eval`; `Engine.SetPlayerData` with the same path writes it and returns false when the
weapon name is not a member of the playerdata `Weapon` DDL enum (that is the "picking does
nothing" failure). `rpc ddl_dump` dumps that enum; `rpc ddl_extend` adds the ported names
(see docs/aw-weapons-plan.md).

## Shortening timers

The mode scripts register their dvars (`scr_<mode>_scorelimit`, `scr_<mode>_timelimit`, ...) and
the test can set them in `dvars`. Values the script hard-codes as `#define` (e.g. the 15 s
first-infected countdown in `infect.gsc`) can only be shortened by changing that define.

`timescale` is deliberately **not** used: it speeds the whole simulation (physics, bot AI, network
snapshots) and makes raw numbers (move speed, distances) meaningless. Instead a test shortens the
match dvars, calls the gametype's end handler (`_gamelogic::endgame`, `[[level.ontimelimit]]`) where
the clock itself is the thing under test, or sets a state field to its last step (cranked:
`cranked_end_time = gettime() + 300` instead of waiting 30 s).

## Test list

| test | script | map | gametype | what it checks |
|---|---|---|---|---|
| infect | infect | mp_shipment | infect | first infected, both loadouts, infection, team counts, late joiner, scavenger bag, no killstreaks, survivors eliminated -> axis wins |
| infect_time | infect | mp_shipment | infect | time limit with survivors alive -> allies win |
| war | war | mp_shipment | war | spawn state, a kill, normal end |
| dm | war | mp_shipment | dm | free-for-all smoke |
| sd / dom / dz | objective | mp_crash | sd / dom / dz | objectives exist + normal end |
| slasher | slasher | mp_shipment | slasher | one life, one slasher, survivor bots may fire, last survivor gets the powers, all survivors dead |
| rpg | rpg | mp_shipment | rpg | RPG only, ammo refill |
| oic | oic | mp_shipment | oic | revolver with 1 round, +1 round per kill, 3 lives, last alive wins |
| aon | aon | mp_shipment | aon | empty USP + throwing knife + 3 perks, 20 kills, never-died bonus |
| cranked | cranked | mp_shipment | cranked | kill makes cranked, 30 s timer, resets and double team score, explosion = suicide without score loss |
| sas | sas | mp_shipment | sas (+mod) | crossbow/hatchet/throwing knife, throwing knife kill and suicide bankrupt |
| infect_rust / war_rust | infect / war | mp_rust | infect / war | HMW usermap loading |
| war_terrace | war | mp_terrace | war | AW port (factions, helicopter) |

## First full run

See `C:\Games\cod-hwm\mwx-debug\autonomous\report.md` for the results of the first full run and
for the bugs it found.
