# Game mode tests

MWX has logic tests for the game modes. They run on a dedicated server (no rendering), report
through the debug interface and are collected by the MCP tools, so a full run needs nothing but
`run_all_tests`.

```
run_all_tests -> for every entry in mwx\tests\tests.json:
                   start_server (+map, +set g_gametype, +set mwx_test=<script>, test dvars)
                   wait for sv_running, spawn the bots
                   wait for the test_done event
                   stop_instance
                 -> {tests: [...], passed, failed}
```

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
| `mwx_test_escape(text)` | escapes text for the JSON the events carry |

The MCP builds the summary from the events: `passed` / `failed` counts, the `failures` list with
name, expected and actual, `script_errors` (any GSC error the server printed during the run) and
`duration_s` (between `test_started` and `test_done`).

Rules:

- Never let `main()` block: it runs as a thread, `wait` is fine, but a test must always reach
  `test_done` (use bounded `while (waited < N)` loops).
- GSC has no ternary operator, no `local`, no `{}` blocks, no `;` at the end of statements that
  are not assignments. Strings are double quoted; `getsubstr(s, start, end)` has an exclusive end.
- Test scripts are only loaded when `mwx_test=<script>` is set: in that case
  `gsc::load_gametype_script_stub` also loads `mwx/tests/<script>` with the normal script pass and
  its `main()` runs via `load_main_handles()`. Nothing of this happens in a normal game.
- `run_test`/`run_all_tests` put the map on the server command line (`+map`): a `map` command
  issued after boot is not used by the tests.

## The manifest (`data/mwx/tests/tests.json`)

```json
[
  {
    "name": "infect",
    "script": "infect",
    "gametype": "infect",
    "map": "mp_shipment",
    "timeout_s": 300,
    "dvars": { "scr_infect_timelimit": "2", "mwx_test_bots": 3 }
  }
]
```

| field | meaning |
|---|---|
| `name` | test id for `run_test {name}` (unique) |
| `script` | script in `mwx/tests/` to run (default: `name`) |
| `map` | map to load (default `mp_shipment`: small and flat, bots meet and kill fast) |
| `gametype` | `g_gametype` for the run |
| `dvars` | extra dvars (also `mwx_test_bots`, the number of bots to spawn) |
| `timeout_s` | how long the bridge waits for `test_done` |

The extra runs (`infect_rust`, `war_rust`, `war_terrace`) reuse the scripts on other maps: HMW
usermap loading (`mp_rust`) and an AW map port (`mp_terrace`, factions + helicopter).

Objective modes (`sd`, `dom`, `dz`) check that the objective entities spawn; they use `mp_crash`
because their objectives are map-placed.

## Tools

| Tool | Arguments | Result |
|---|---|---|
| `list_tests` | – | the names from `tests.json` |
| `run_test` | `name` | one test: `{test, script, map, passed, failed, failures, steps, script_errors, duration_s, total_s}` |
| `run_all_tests` | `name` (optional) | `{tests: [...], passed, failed}` |

## Shortening timers

The mode scripts register their dvars (`scr_<mode>_scorelimit`, `scr_<mode>_timelimit`, ...) and
the test can set them in `dvars`. Values the script hard-codes as `#define` (e.g. the 15 s
first-infected countdown in `infect.gsc`) can only be shortened by changing that define.

## First full run

See `C:\Games\cod-hwm\mwx-debug\autonomous\report.md` for the results of the first full run and
for the bugs it found.
