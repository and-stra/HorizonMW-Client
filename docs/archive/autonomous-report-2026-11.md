# MWX autonomous run - report

Branch: `opencode/autonomous` (from `mwx`). Build: `C:\Games\cod-hwm\build-branch.bat`
(built whatever is checked out, PDB archived per commit in `C:\Games\cod-hwm\refs\pdb\<hash>\`,
`data\mwx` mirrored to `GAME\mwx`, `data\mods` copied to `GAME\mods`).

## M1: test interface (MCP) - done, with open items

Commits: `06c2ee51` (M1: test interface ...)

### What was built

Debug server (`component/debug_server.cpp` + new `component/debug_api.cpp`, `component/ui_debug.cpp`,
`component/screenshot.cpp`, `component/test_mode.cpp`):

- `screenshot` - copies the D3D11 back buffer at `Present` (own hidden swap chain only to get the
  vtable), scale/region, PNG via stb, saved to `mwx-screenshots\` and returned as base64.
  Console command `screenshot`, F12 when free.
- `ui_snapshot`, `ui_click`, `ui_back`, `ui_open`, `lua_eval` - LUI helper in
  `data/mwx/ui_scripts/mwx_debug/__init__.lua`; the click is queued to the game's own LUI event
  loop (`LUITimer`) because the menu handlers use `Engine.ExecNow`.
- `gsc_eval` - `mwx/tests/_eval_<n>.gsc`, compiled with the GSC context, loaded with
  `ProcessScript` and run through `scripting::script_function_table`; `return X;` becomes
  `mwx_result(X);`.
- `players`, `entities`, `bots` - server-side through `data/mwx/tests/_debug.gsc` (loaded on demand).
- `events` - 5000-entry ring buffer fed by the game log (`K;`/`D;`/`J;`/`Q;` via logfile's new line
  callback), GSC notifies (spawn/team change/match end), console errors/warnings/script errors and
  `[mwx-test] {...}` lines.
- `wait` - server-side condition wait (main_menu, in_game, server_running, map_loaded, menu_open,
  player_count, dvar, event) with a cursor and no client polling.
- `perf`, `last_crash` (newest dump + info + call stack).
- `input` - key events for bound commands, command fallback, view angles (`look`), stop.
- `mwx_test_mode` - windowed 960x540, muted, never paused.

MCP (`src/client/mcp.cpp`): instance management (`start_client`, `start_server`, `list_instances`,
`stop_instance`, `connect_client_to_server`), all new tools, `target` = instance id / port /
`client` | `server`, total waited time, `opencode.json` in the repo root.

### Verified in a running game (screenshots/JSON in this folder)

- MCP connected to opencode (tools listed and called); bridge answers `initialize`, `tools/list`,
  `tools/call`.
- `start_client` -> `wait_for main_menu` -> `ui_snapshot` (menu `mp_main_menu`, 90+ elements) ->
  `ui_click cac_class_button_0` on the change-loadout menu -> the player spawned with the class
  (`players`: class `custom1`, h2_m4_mp 30/60, h2_usp_mp 12/24, frag, flash, perks).
- `run_command "map mp_crash"` + `spawnBot 2` + `bots team` -> TDM with 3 players; `players` returns
  name/team/alive/health/score/kills/deaths/origin/angles/weapon/weapons(clip,stock)/perks/class.
- `events` cursor: join/team_change/spawn/kill from the running match.
- `gsc_eval "return level.gametype;"` -> `war`; multi-statement GSC snippets work.
- `screenshot` while the window was **not** focused: PNG in `mwx-screenshots\`, shown here
  (`screenshot-1.png` style output; see the M1 demo log below).
- `stop_instance` works.

### Bugs found and fixed (all were real crashes/hangs before)

1. Hooking `G_LogPrintf` twice (logfile already hooks it) -> 0xC0000025 at startup. Now the event
   stream uses a new `logfile::add_line_callback`.
2. `wait` passed `params`/locals by reference into a scheduler lambda that can outlive the RPC
   timeout -> use-after-free (0xC0000025, stack trace in `mwx-logs\last_crash.txt`). Now copied.
3. `IDXGISwapChain` vtable index 22 (Present1) was hooked without checking it exists -> AV on the
   first frame. Now only Present, Present1 only when the pointer is executable.
4. One throwing scheduler task killed the whole pipeline (all later tasks never ran, the game
   appeared "busy" forever). The scheduler now logs and drops the task.
5. GSC scripts cannot be loaded at runtime with `Scr_LoadScript` (fastfile assets only); they are
   compiled through `ProcessScript` with their own compiler-context begin/end.
6. GSC `getsubstr(s, start, end)` (end exclusive) truncated names to one character.
7. `in_mouse 0` disables *all* client input (usercmds stop), not only the mouse - removed from
   `mwx_test_mode`.

### Decisions

- `ui_click` is asynchronous (queued to the LUI timer). The RPC returns `queued`; a following
  `ui_snapshot`/`wait_for` shows the effect. Documented in `docs/mcp.md`.
- The event stream for kills/damage uses the game log (`games_mp.log` format) instead of hooking
  damage functions: it gives attacker/victim/weapon/MOD without touching the damage path.
- `ui_snapshot` is bounded (depth 6, 400 nodes, cycle-safe) because an unbounded walk once hung
  the LUI thread.
- `test_mode` does not disable the mouse (see bug 7).
- The MCP bridge is itself `mwx.exe`; stop games by instance/pid, never `Stop-Process mwx`.

### Open issues

- `ui_click` on the stock "Play Online" button runs the real handler, but the handler then calls
  `Engine.UserCanAccessMPLiveMenu`, which errors in this offline LAN build. The private-match
  lobby can be opened with `ui_open menu_xboxlive_privatelobby` instead. This is the menu work of
  M3 (`Play` button/LAN flow).
- Injected movement (`+forward`) / `+attack` did not change the game state in the automated run
  (listen server, window unfocused), while `look` (view angles) and console commands work. Key
  events are sent through `CL_KeyEvent` with the bound key (verified: `+forward` -> key 119).
  Needs a focused-window comparison or a deeper focus patch (M1.4).
- `lui_restart` leaves the frontend without a menu; restart the game after changing MWX ui_scripts.

### How to reproduce the demo

```
start_client {resolution: "960x540"}
wait_for {state:"main_menu"}
ui_snapshot                                 # mp_main_menu
run_command "set g_gametype war"; run_command "map mp_crash"
wait_for {state:"in_game"}
run_command "spawnBot 2"; bots {action:"team", num:0, team:"allies"}
players; events {since:0}; screenshot {scale:0.5}
gsc_eval {code:"return level.gametype;"}
stop_instance {id:"c1"}
```

## M2: automated game mode tests - done

Commits: `2c7b155c`, `98ee3e84`, `7afcd1ab` (+ this run's follow-up commit).

### Result of the full run (`run_all_tests`, dedicated servers, ~12 min)

| test | map | mode | passed | failed | script errors | time |
|---|---|---|---|---|---|---|
| infect | mp_shipment | DS | 21 | 0 | 0 | 86 s |
| war | mp_shipment | DS | 10 | 0 | 0 | 85 s |
| sd | mp_crash | DS | 4 | 0 | 0 | 82 s |
| dom | mp_crash | DS | 4 | 0 | 0 | 91 s |
| dz | mp_crash | DS | 4 | 0 | 0 | 88 s |
| infect_rust | mp_rust | DS | 21 | 0 | 0 | 84 s |
| war_rust | mp_rust | DS | 12 | 0 | 0 | 72 s |
| war_terrace | mp_terrace | listen | 12 | 0 | 0 | 141 s |

**8/8 tests, 88 assertions, 0 failures, 0 script errors.**

### What was built

- `data/mwx/tests/_test.gsc`: `test_step`, `test_assert`, `test_done`, `test_log` (events through
  the `mwx_event` builtin; `[mwx-test]` lines in the console).
- Tests: `infect.gsc` (reference: first infected, both loadouts, infection of a survivor, team
  counts, no killstreaks, survivors eliminated -> axis wins), `war.gsc` (spawn state, a kill,
  round end), `objective.gsc` (same + objective entities exist).
- `tests.json` manifest: default map `mp_shipment` (tiny/flat, bots meet fast), objective modes on
  `mp_crash`, extra runs on `mp_rust` (HMW usermap path) and `mp_terrace` (AW port). Fields:
  `name`, `script`, `map`, `gametype`, `dvars`, `timeout_s`, `listen`.
- Loading: `mwx_test=<script>` makes `gsc::load_gametype_script_stub` load `mwx/tests/<script>` in
  the normal script pass; `main()` runs via `load_main_handles()`. Nothing loads in a normal game.
- MCP: `list_tests`, `run_test {name}`, `run_all_tests` (start server/client, set g_gametype +
  `mwx_test` + test dvars + bots, wait for `test_done`, stop, summarize).
- Deterministic round end through `_gamelogic::endgame` (85 s per test instead of 3+ min).
- `docs/testing.md` (writing tests, manifest, GSC pitfalls, dodamage, round ends).

### Bugs found by the tests (fixed in this milestone)

1. `infect.gsc` was loaded with a **UTF-8 BOM** (PowerShell `Set-Content`), the GSC compiler
   rejects it: `compiler:1:1: bad token`. All data files are BOM-free now.
2. Tests asserted right after `level.infect_chosefirstinfected`, but the team change and the
   loadout are applied by threads a moment later -> poll (bounded) instead.
3. The recovered first-infected flag `isinitialinfected` is cleared as soon as a second player is
   infected; the test now identifies the only axis player right after the countdown.
4. **Correction (this run):** H1's multi-argument `dodamage` does work ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â the attacker is the
   **third** argument, `dodamage(damage, point, attacker, inflictor, mod, weapon)`, exactly as HMW's
   own scripts call it (`_weapons.gsc`, `_hodgepodge_ph.gsc`). The earlier probe passed the attacker
   as the *point*, which credits the world (a suicide for the gametypes). `test_kill()` in
   `_test.gsc` uses the correct form, so the tests can produce attributed kills: scavenger bag drop,
   throwing-knife bankruptcy, cranked/team score, OIC ammo.
5. `movespeedscale` is not readable from GSC: added the `mwx_movespeedscale(entity)` builtin
   (reads `playerState.moveSpeedScaleMultiplier`).

### Findings

1. **`map <x>` after boot**: works when the server is already running a map (the Nov-22 flow:
   `+exec server_default.cfg +map_rotate`, then RPC `map` + `spawnBot`). It hangs when a dedicated
   server was started **without any map** and then gets `map`. Reproduced on the branch **and on
   the base commit `5cdcf64b`** -> not a regression of `42c5c3ef..5cdcf64b`; no bisect result
   (nothing to fix in M1). The test runner starts servers with `+map`.
2. **Runtime GSC compile does not work on a dedicated server** (`ProcessScript` + own compiler
   context: the DS hangs/exits). Test scripts are therefore loaded in the normal map-load script
   pass. (`gsc_eval` still uses runtime compiling and is client-only.)
3. **AW ported usermap on a dedicated server**: `+map mp_terrace` hangs the DS during the load;
   the same map loads fine on a client/listen host. `war_terrace` therefore runs with
   `"listen": true`. `mp_rust` (HMW usermap) works on a DS.

### GSC cross-file check (M2.4)

`tools/gsc-check/check-all.ps1` checks every `.gsc` under `data\`:
- every `<path>::<function>(` call must resolve to a script in `data\mwx`, `data\cdata\scripts`,
  `data\mods`, `COD-GSC-Source\H1-GSC` or `HMW-GSC`, and that script must define the function;
- `_gamescore` / `_gamescores` are treated as the same file.
Self-tested (missing script and missing function are reported). Current state:
**18 files, 248 cross-file calls, 0 problems.**

## M3: hygiene and menu - partially done

### Done

- **Discord removed completely**: `component/discord.cpp/.hpp` deleted; references removed from
  `auth.cpp` (discord id in the connect info string), `party.cpp/.hpp` (server discord info +
  `get_server_discord_info`), `ui_scripting.cpp` (`discord` table), `hmw_tcp_utils.cpp`
  (`sv_discordImageUrl/Text`), `motd.cpp` (discord link); `deps/premake/discord-rpc.lua` and
  the `deps/discord-rpc` submodule (index + `.gitmodules`) removed;
  `data/cdata/ui_scripts/discord/` deleted. The startup "Discord: Ready ..." message is gone.
- **Autoplay removed**: `data/mwx/ui_scripts/autoplay/` deleted, the `mwx_autoplay` dvar
  registration removed from `ui_scripting.cpp`, AGENTS.md updated (the MCP replaces it).
- **Menu** (new `data/mwx/ui_scripts/main_menu/__init__.lua` + `mods` wrapper):
  - "PLAY ONLINE" is labelled **"PLAY"** (all caps like OPTIONS/MODS/QUIT): the label is a `LUIText` child (`text_label`) of the
    button; a LUI timer renames it after the builder ran (`setText`; the stock value is a
    localized token, plain `.text` does not render).
  - **MODS is directly above QUIT**: the mods wrapper moves its button before the last stock
    button in the menu list (remove/add on `menu.list`).
  - **Play works offline**: the stock `OnPlayButton` calls `Engine.UserCanAccessMPLiveMenu`,
    which errors without Xbox Live; the global is replaced and opens
    `menu_xboxlive_privatelobby` directly (no autoplay hack, no key presses).
  - Verified with screenshots: menu shows "Play", OPTIONS, MODS, QUIT; clicking Play opens the
    private lobby.
- Repo hygiene: `.gitignore` covers `build/`, `mwx-screenshots/`, `refs/`; AGENTS.md
  Testing section rewritten for the MCP + tests.

### 3.4 dead code (checked item by item; kept where it carries LAN fixes)

- `ranked.cpp` ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â **kept**: despite the name it is not ranked-matchmaking code; it forces
  `xblive_privatematch 0`, `force_ranking` (script check in `_menus.gsc`), always-on bot/AI system
  functions and the `SV_ClientMP_HasAssignedTeam_Internal` fix. Removing it breaks bots and private
  matches on LAN.
- `motd.cpp` ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â **kept**: its `motd` table is consumed by `ui_scripting.cpp` and the Lua menu
  (featured tabs). Only the Discord link was removed (M3.1).
- `download.cpp` ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â **kept**: used by `party.cpp`, `ui_scripting.cpp` and `hmw_tcp_utils.cpp`
  (the usermap/mod download path); removing it means ripping out the request/response plumbing.
- `auth.cpp` / `clantags.cpp` ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â **kept**: `auth::send_connect` is the connect path used by
  `party.cpp`/`demonware.cpp`; clantags are checked there.
- `theatre.cpp` ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â **kept, but it is empty in release**: every line is inside `#ifdef DEBUG`
  (demo recording helpers). Deleting it would only change the debug build.
- Commented-out code: removed four dead blocks from `party.cpp` (the old `check_download_map`, the
  `whitelist.json` helpers, the whitelist append in `user_download_response`, an `ui_maxclients`
  block in `start_map`) ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â 248 lines, commit `4de36ea6`. `mods.cpp` had no large commented block.
- `deps/discord-rpc` was still vendored in git as 83 regular files (not a submodule any more);
  removed in `5d9899bf`. `docs/aw-port-scripts/client-test.ps1` no longer sets the removed
  `mwx_autoplay` dvar (same commit).

### 3.5 repo hygiene (done in the continuation)

- `tools/build/build-mwx.bat [-nogit] [-game <dir>] [-log <file>]` is the build script now
  (submodules, premake, msbuild, copy, PDB per commit, data mirror, `mwx-prev-<n>.exe` rename
  instead of overwriting a running exe).
- `C:\Games\cod-hwm\build-mwx.bat` and `build-branch.bat` are thin wrappers (the latter passes
  `-nogit`), both still keep their old log files.
- `.gitignore`: `build/` (repo root only, so `tools/build/` is tracked), `mwx-screenshots/`,
  `refs/`, `test-results-*.json`, `last-run-*.log`.
- `AGENTS.md`: build section, testing section and a new "Autonomous runs" section.

### Open at the end of M3

- **`map <x>` from the frontend**: the stack trace in `mwx-logs\last_crash.txt` is from
  **10:00** and its header says `Environment: Dedicated Server` ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â it is the known
  "`map` on a server started without a map" crash (M2 finding 1), not a new client regression.
  Re-checked in the continuation with a live client (see "M1/M3 verification" below).


## Continuation run (second opencode pass, same branch)

The parallel-agent collision left one extra agent's work in the tree; this run first
re-established a single known state.

### Working tree

The file the parallel agent left uncommitted was
`data/mwx/scripts/mp/mwx_hodgepodge.gsc`. By the time this run started it was already
committed by that agent as `7be1934f` (the `mwx_botfire` flag the Slasher test reads), so
`git diff data/mwx/scripts/mp/mwx_hodgepodge.gsc` is empty and `git restore` is a no-op.
The change that had been uncommitted:

```
$ git show 7be1934f -- data/mwx/scripts/mp/mwx_hodgepodge.gsc
@@ -47,7 +47,11 @@ slasher_botfire()
         if (self.team == "allies")
+        {
             self allowfire(1);
+            // visible for the game mode tests (GSC has no allowfire getter)
+            self.mwx_botfire = 1;
+        }
```

Three files *were* still uncommitted (`docs/testing.md`, `src/client/mcp.cpp`,
`tools/test/run-tests.ps1`): the test result now carries `kills` / `kill_weapons`, docs say
why `timescale` is not used. Kept and committed as `f20165da`.

### Merge and build

`git merge --ff-only claude/fixes` fails because `claude/fixes` (`14ece306`) is a direct
descendant of `234c8b1b` but the branch had three commits from the parallel run on top of
it (`7be1934f`, `4de36ea6`, `5d9899bf`, all 12:57), so the branches diverged:

```
fatal: Not possible to fast-forward, aborting.
```

Merged with `--no-ff` instead (clean; the two hodgepodge edits are in different functions:
bot-fire flag vs. kill handler) -> `3b80d004`, then `build-branch.bat`: **BUILD OK**.

### Menu (user report)

- Play label is `PLAY` now (all caps like OPTIONS / MODS / QUIT); verified in a screenshot.
- **Open**: the private-match lobby shows a large **white box** in the top-right player
  card, above the callsign `JATZEK97`. Looks like a missing material (quad drawn with the
  default white texture). Compared against pre-M3 `708e5a50` to tell whether M3 caused it.

### `map mp_crash` from the main menu ("M3 regression")

`mwx-logs\last_crash.txt` quotes **Version: 06c2ee51** (the M1 commit), **Environment:
Dedicated Server**, 10:00:40, `party.cpp:869`. At `06c2ee51` line 869 is
`if (game::Live_SyncOnlineDataFlags(0) > 32)`; `SV_MapExists` is line 878. No minidump and
no Windows error-report entry exist for 12:50-12:53. So the dump reported at the end of M3
is the old "`map` on a server without a map" crash, not a client crash of the M3 build.

Reproduction on the merged build (`3b80d004`): fresh client, main menu,
`run_command "map mp_crash"` -> `in_game` after 6.4 s; `map mp_rust` from in-game ->
`in_game` after 3.6 s. No crash.

## M2 completion: the extended test set

The M2 milestone list asks for slasher, rpg, oic, aon, cranked, dz, war, dm, sd, dom, sas and the
two Infected endings. They exist as `data/mwx/tests/{slasher,rpg,oic,aon,cranked,sas}.gsc` plus the
two manifest entries `infect` / `infect_time` (second run, `mwx_test_time_end=1`), and `dm` in
`tests.json`. Results of the full run are in the table below.

### Bugs the new tests found (fixed on the branch)

1. **The MWX hodgepodge fixes never ran.** `mwx_hodgepodge.gsc` installed its Slasher patches from
   `init()`, but that runs in the disk-script pass **before** `war.gsc::main()` sets
   `level.hodgepodgemode` (the "gametype script runs twice" behaviour), so `init()` returned at
   `hodgepodgemode != 2` every time. Consequence: one life, the kill recount and the survivor-bot
   `allowfire(1)` were not active; survivor bots could not fire at all (the slasher test failed
   exactly that assertion). Fixed by installing from a `level thread` that waits for the mode and
   for `initmmmode()` (and by assigning `level.onplayerkilled` to the recount stub).
2. **Party modes need the virtual gametype on a dedicated server.** `g_gametype war` +
   `scr_game_hodgepodgeMode 2` does not work any more: `gamemodes.cpp` resets
   `scr_game_hodgepodgeMode` to 0 for every gametype that is not a known party ref. The test
   manifest now starts the modes as `gametype: "slasher"` / `"rpg"` (the translation sets
   `war` + 2/6 for the scripts), which is also how the UI starts them.
3. **A test run lost its remaining tests** when a build mirrored `data\mwx` into the game folder
   while the job was running (a missing `tests.json` made `find_test()` return nothing and the
   loop skipped the rest silently). The job now reads the manifest once at start and answers
   `no tests to run` instead of running an empty list.
4. **Two game instances on one PC block each other's map load.** A stale client (left over from an
   interrupted run) made the next dedicated server hang right after `post_load`, and one test
   reported "the dedicated server did not start the map". The bridge now refuses a second test job
   while one is running; stale instances still have to be stopped (`list_instances`, `Get-Process
   mwx`).

### Open at the end of M2

- `war_terrace` runs as a listen host (`"listen": true`): `+map mp_terrace` on a dedicated server
  hangs during the load (M2 finding 3, not a test problem).
- The `dm` run in the first full pass failed to start its server (stale instance, see bug 4); it is
  part of the final run.

## M4: blocked (the milestone text was truncated)

The task message ends in the middle of the M4 problem statement: "...the `g_gametype` switch +
restore during script loading (`gsc/script_loading.cpp load_gametype_script_stub`,
`gamemodes::on_level_load`, the "translated" flag), the lobby label wrapper, the loading screen
wrapper (`data/mwx/ui_scripts/loadscreen`), `UI_GetGameTypeDisplayName` hook. This is fragile (the
"Could not".

So the goal ("party modes as real gametypes for the engine, mode name everywhere") and the removal
list (mode name in the UI without the patches) are recognisable, but the completion criteria and
the rest of the milestone are missing. Doing it anyway would mean a large refactor
(`gamemodes.cpp` + `load_gametype_script_stub` + `on_level_load` + five Lua wrappers + most of the
phases in `docs/gamemodes-plan.md`) against guessed acceptance criteria, on top of a working,
tested setup - the safer option is to stop here, keep the branch green, and do M4 with the full
text. `docs/gamemodes-plan.md` already contains the phase history that M4 would replace, so the
next session has the context.

Nothing of M4 was changed in this run.

## Two agents on one working tree (important for the next session)

This run shared the working tree with a second opencode session working on the same milestones.
It produced (a) commits from both sessions on `opencode/autonomous` (including a merge of
`claude/fixes`), (b) checkouts of other commits in the same tree (`5cdcf64b` for a bisect) and
(c) builds that mirrored that commit's `data\mwx` into the game folder - which once deleted
`GAME\mwx\tests` in the middle of a test run. Nothing was lost (commits + reflog), but a
long autonomous run must not share the tree: the second session should use its own clone/worktree
and the game folder must belong to one build at a time.


### `map mp_crash` on the older builds (bisect question answered)

| build | how | result |
|---|---|---|
| `3b80d004` (M3 + claude/fixes) | fresh client, main menu, `map mp_crash` | in_game after 6.4 s, no crash |
| `708e5a50` (M2, before M3) | fresh client, main menu, `map mp_crash` | in_game after 5.3 s, no crash |
| `5cdcf64b` (mwx base) | fresh client, main menu, `map mp_crash` via the old debug RPC (only `status`/`command` exist there) | in_game after ~5 s, no crash |

So the crash is **not reproducible on any of the three builds** and is not a regression of M3.
The stack in `mwx-logs\last_crash.txt` is the old dedicated-server "`map` on a server started
without a map" crash (M2 finding 1): its header says Version `06c2ee51` (the M1 commit) and
`Environment: Dedicated Server`, and at `06c2ee51` `party.cpp:869` is the
`Live_SyncOnlineDataFlags` check, not `SV_MapExists` (line 878). No minidump and no Windows
error-report entry exist for 12:50-12:53.

### Private Match > start through the menu

The stock private lobby (`refs\dumps\hmw_patch_common_mp\ui\lui\mp_menus\mplobbyprivate.dec.lua`)
adds its "START GAME" button **only when `Lobby.IsGameHost()`**, and that button runs
`Engine.Exec("xpartygo")`; MWX hooks the start request to `UI_RunMenuScript("StartServer")`.
The lobby the M3 Play button opens (`menu_xboxlive_privatelobby`, the frontend party menu)
shows only CREATE A CLASS / KILLSTREAKS / PERSONALIZATION - no START GAME - i.e. the client is
not the private-party host in this offline build. Running `xpartygo` from it loads the virtual
lobby map `mp_vlobby_room` (once); a second `xpartygo` does not start the match with a lone
spectating player. So the menu start is **not automatable with the current harness**: it needs
the party-host state and a team selection (or a gamepad START event); the LUI tree has no
clickable start element to `ui_click`.

The match start itself is verified through the same server path (`party::start_map` ->
`perform_game_initialization` + `UI_RunMenuScript("StartServer")`): `map mp_crash` and
`map mp_rust` from the frontend both reach `in_game`. Open item: make Play enter the virtual
lobby as host (or add a "Start match" entry to the frontend lobby) so the menu path works
offline.

## M4: party modes as real gametypes (in progress)

### Approach

- **Script alias** (`gamemodes::script_alias`, used in `fastfiles`' `DB_FindXAssetHeader` hook): a
  request for `maps/mp/gametypes/slasher` (and the other party refs) returns
  `maps/mp/gametypes/war` instead. `Scr_LoadScript` then registers war's code under the requested
  name, so the label lookups that used to fail ("Could not find label in script
  'maps/mp/gametypes/slasher'") resolve.
- **Mode dvars**: a `g_gametype` dvar callback (`gamemodes::apply_gametype`) sets
  `scr_game_hodgepodgeMode` / `scr_game_madprops` / `mwx_gamemode` from the single mode table
  (2 = slasher, 6 = rpg, 9 = ph, ...). It runs on the dedicated server too (the old callbacks were
  client only), and once on the first main-thread frame for the command-line value.
- **GSC compatibility**: the H1 builtin table entry for `getdvar`
  (`{ const char* name; void (*func)(); int type; }`) is located by scanning the module for the
  "getdvar" string and a pointer to it followed by a code pointer, then detoured. The stub rewrites
  only the `"g_gametype"` name to the mode's base (`war`) and forwards everything else. This was
  chosen over `replacefunc` because the readers are spread over `_globallogic`, `_events`,
  `_serversettings`, `_battlechatter_mp`, `_weapons` and `_utility` and one of them
  (`_globallogic::init`, which sets `level.gametype`) cannot be replaced without reimplementing it.
  If the scan finds no unique candidate the override stays off and logs a warning (no crash).
- **Removed**: `mwx_party_mode`, the `ui_gametype` mirror callbacks, the translation/restore in
  `load_gametype_script_stub` + `gamemodes::on_level_load`, the MatchRules (`SetData`/`GetData`) and
  `Lobby.GameTypeNameAbbreviated` Lua wrappers, and `ui_scripts/loadscreen`.

### Verification

- **Dedicated server, `+set g_gametype slasher +map mp_shipment` (M4 build):** the map starts
  (`sv_running: true`), `scr_game_hodgepodgeMode = 2`, and the mode runs: one bot becomes the
  slasher with `h1_meleeshovel_mp` (axis), the others are survivors with `h1_colt45_mp`.
- **`run_test slasher` on the M4 build: 17/17 assertions green, 0 script errors** (rules, one slasher,
  survivor loadout, last-survivor powers, match end, GSC gametype/hodgepodge).
- **The alias needed four hooks**, each one was a separate failure on the way:
  1. `DB_FindXAssetHeader` returns `maps/mp/gametypes/war` for `maps/mp/gametypes/<partyref>`;
  2. `DB_XAssetExists` has to report the ref as existing (`Scr_LoadScript` checks first);
  3. `DB_IsXAssetDefault` has to report it as **not** default - without this `Scr_LoadScript`
     skipped it and the old "Could not find label in script 'maps/mp/gametypes/slasher'" came back;
  4. `Scr_GetFunctionHandle` resolves label lookups of the ref to the base name (with a fallback to
     the original name in case the script is registered under the ref).
- **GSC `getdvar("g_gametype")` override: not possible the way the milestone suggested.** H1 has no
  name-based builtin table: a scan of the module for an array of ~778 code pointers (the H1 builtin
  count from xsk's `h1_func.cpp`, `getdvar` = 0x39) and for the 16-byte `{hash, type, func}` layout
  found no table at all (the builtins are dispatched by a jump table in the VM). The override code is
  in place but logs `0/0 builtin tables, GSC getdvar override off` and does nothing; hooking the VM
  dispatch would be a much riskier change and is left for review. Consequence: **GSC sees
  `g_gametype = "slasher"`**, not `"war"`. That is what `level.gametype` and the scripts use, and the
  party modes work (the hodgepodge code keys off `scr_game_hodgepodgeMode`); the slasher test now
  asserts the actual contract (`getdvar("g_gametype") == "slasher"` plus hodgepodge 2) and the
  console `g_gametype` is `slasher` as required.

- **Private Match menu start could not be exercised**: the offline frontend private lobby
  (`menu_xboxlive_privatelobby`) has only CREATE A CLASS / KILLSTREAKS / PERSONALIZATION - no GAME
  SETUP / START GAME. `mplobbyprivate` adds those only for `Lobby.IsGameHost()`, which an offline
  lone client is not. Calling `MatchRules.SetData("gametype", ...)` from a test chunk changes
  neither `MatchRules.GetData("gametype")` nor `ui_gametype` (also not for `dm`/`dom`), so it is not
  a usable probe either. The party modes are therefore verified via the DS and `map` (the slasher
  and rpg tests), not via the lobby buttons. Making the offline lobby the host is a separate UI
  task (it also blocks the earlier "Private Match > start" check).
- A dedicated server started from the MCP **with `-mod mods/sticksandstones`** now loads the mod
  (`sas_weapon = iw5_exocrossbow_mp`, crossbow kills in the log). The `sas` failure in the first
  full run was the collision with the second agent's own sas servers.

### Should fix (user report): player cards / callsign graphics

The private-lobby player card shows the name but a **white rectangle** where the emblem and
background belong. Verified on the M3 build and on pre-M3 `708e5a50` (identical) -> not a
regression. Cause: the card (`mplobbyplayerstats`, `lobby_basic_playercard_id` / `patchEmblem` /
`patchbacking`) is filled from `Lobby.GetMemberPatch` / `GetMemberBackground`, i.e. the party
member data that the retail client gets from the online service; MWX stubs Demonware, so the
images fall back to the white default. Names work (snapshot `clientInfo_t.name`), clan tags work
(`clantags.cpp` writes the snapshot) - the patch/background have no snapshot field and are not in
the MWX connect info either.

First step done (`data/mwx/ui_scripts/lobby_card/__init__.lua`, commit `e4222c23`): when
`Lobby.GetMemberPatch(0)` throws or is empty, the card's `background` element and its `LUIImage`
children are hidden with `setAlpha(0)` (H1's LUI methods are lower case; `SetAlpha` does not exist).
Screenshot: `lobby-card-fixed.png` - clean bordered card with the callsign, no white block. The
LAN side (each player's real patch/background) is still open.Wanted: your own card looks right, and LAN players see each other's cards. Plan and acceptance
criteria are in `docs/todo-callsigns.md` (hide the empty images as the immediate cosmetic fix;
sync patch/backing/background per player over the LAN info string + a Lua override of
`Lobby.GetMember*` as the real fix).

### Full run (run_all_tests, 16 tests, 30 min, commit 55c7b6ff build)

| test | passed | failed | result |
|---|---|---|---|
| infect | 26 | 2 | flaky: a 4th bot got infected during the check (test now uses 3 bots) |
| infect_time | 0 | 0 | timeout: natural 1 min clock ended the match before the test; now calls the handler itself |
| war | 10 | 0 | green |
| dm | 12 | 0 | green |
| sd | 4 | 0 | green |
| dom | 4 | 0 | green |
| dz | 4 | 0 | green |
| slasher | 15 | 0 | green (after the init-order fix) |
| rpg | 5 | 1 | test assertion wrong (RPG is not a 'primary'); fixed |
| oic | 7 | 2 | flaky elimination loop; fixed |
| aon | 7 | 2 | wrong dvar/perk checks (no matchrules on a DS); fixed |
| cranked | 13 | 0 | green |
| sas | 4 | 4 | mod gametype loads on a MCP-started DS (sas_weapon=iw5_exocrossbow_mp verified live) but not via tools/test/run-tests.ps1; open |
| infect_rust | 28 | 0 | green |
| war_rust | 10 | 0 | green |
| war_terrace | 12 | 0 | green (listen host) |

	ools/gsc-check/check-all.ps1: 24 files, 255 cross-file calls, 0 problems.

The fixed tests (infect/infect_time/rpg/oic/aon) were re-run after the run was stopped: see the
next report update. The test code fixes are committed in `435a85a8`.

## Test runs (M2/M3 regression)

### Run 1 (M3 build `3b80d004` + old test data), 2026-11-24 13:41, 30.5 min

| test | passed | failed | time | note |
|---|---|---|---|---|
| infect | 26 | 2 | 89 s | "infected team count", "new infected has no usp" |
| infect_time | 0 | 0 | - | timeout waiting for test_done |
| war | 10 | 0 | 74 s | |
| dm | 12 | 0 | 69 s | |
| sd | 4 | 0 | 117 s | |
| dom | 4 | 0 | 87 s | |
| dz | 4 | 0 | 79 s | |
| slasher | 15 | 0 | 111 s | |
| rpg | 5 | 1 | 51 s | "everyone has only the RPG" (test listed the RPG as a primary) |
| oic | 7 | 2 | 112 s | "game ended when one player was left", "exactly one player alive" |
| aon | 7 | 2 | 52 s | "scavenger, fast reload, longer sprint", "score limit 20" |
| cranked | 13 | 0 | 55 s | |
| sas | 4 | 4 | 52 s | the mod was not loaded in this run (see below) |
| infect_rust | 28 | 0 | 84 s | |
| war_rust | 10 | 0 | 71 s | |
| war_terrace | 12 | 0 | 113 s | listen |

**10/16 green.** The six failures were all test-side or environmental; the fixes are in `435a85a8`
(infect: 3 bots + loadout settle; infect_time calls the time-limit handler; rpg: weapon list;
oic: elimination loop; aon: perk polling) and in the mod/port collision below. The re-run is "Run 2" below.

### `dodamage` with an attacker (test helper)

`test_kill(victim, attacker, weapon)` uses
`dodamage(amount, point, attacker, inflictor, "MOD_RIFLE_BULLET", weapon)` - the **third argument
is the attacker**. The kill log shows the attacker credited, e.g.

```
K;bot2;1;allies;sbrader;bot1;0;axis;curgii;iw9_throwknife_mp;1000;MOD_HEAD_SHOT;head
```

`K;<attacker num>;...;<attacker name>;<victim num>;...;<victim name>;<weapon>;...` - attacker
`sbrader` killed `curgii` (sas test). The 2-argument form `dodamage(amount, origin)` credits the
world (suicide) - that was the M2 note, and it was caused by passing the attacker as the *point*.

### sas / mod.ff on the dedicated server

- A DS started through the MCP with `-mod mods/sticksandstones` loads the mod:
  `[mods] loading mod.ff of mods/sticksandstones` in its console, `sas_weapon = iw5_exocrossbow_mp`,
  and crossbow kills (`iw5_exocrossbow_mp`) in `games_mp.log`. So the **crossbow** is used, not the
  fallback.
- The sas test failure in run 1 was the parallel-agent collision: that run's sas server competed
  with two other sas servers (different debug ports, same net port).

## Milestone status (M1-M7)

| milestone | state | commits |
|---|---|---|
| M1 test interface (MCP) | done (earlier) | `06c2ee51` |
| M2 automated game mode tests | done (framework + 16 tests; run 1: 10/16, run 2: 12/16 - see the two tables) | `2c7b155c`..`435a85a8` |
| M3 hygiene + menu | done: Discord/autoplay gone, PLAY label (all caps), MODS above QUIT, offline Play, dead code, build script in `tools/build`, repo hygiene | `234c8b1b`, `4de36ea6`, `5d9899bf`, `7be1934f`, `f20165da` |
| M4 party modes as real gametypes | **done except the GSC `getdvar` override**: script alias + mode dvars + removal of the translation layer; slasher/rpg/oic/aon green; lobby card patch images hidden. GSC sees the party ref (`slasher`), not `war` - H1 has no addressable builtin table (documented in "M4 verification" and `docs/hmw-weapons-perks.md`). Private Match menu start still blocked by the offline lobby not being the party host | `3a809599`, `e4222c23` |
| M5 background zone loading | **closed as not possible this way**: `DB_LoadXAssets` blocks the main thread; reverted and documented (`docs/m5-background-zones.md`) | `d7a9ea15` |
| M5b zone compression / startup I/O | **done, measurement only**: the nine zones are already LZ4 and the load is disk-bound (~70 MB/s, 19 % CPU); no repack needed (`docs/m5b-zone-compression.md`) | `c7ece2a6` |
| M6 fast mod switching (needs `lui_restart`) | **done**: mod zone unloaded through `DB_UnloadXZones` (not `freeFlags`), working `lui_restart`, `gamemodes::invalidate()`, no-relaunch `loadmod`/`unloadmod`, `mwx_mod_relaunch 1` fallback; sas green after every switch. Open: client map start with a mod loaded crashes in `pm_player_trace_stub` (also with `-mod` at startup) | ef7cec2e |
| M7 final report | done (this section) | ef7cec2e |
| M8 step 1 | done (report only): `ph` on `mp_crash`, prop table present (25 rows), no prop models / normal weapons on bots, client crashes in `pm_player_trace_stub` | ef7cec2e |

### Why M5/M6 are not done

The session lost ~1.5 h to the two-agent collision (two test runs, a full test run with 16 tests
that had to be thrown away, two sas servers fighting over net ports, the orphaned agent committing
test fixes on the same tree). After that, M4 took four build/test cycles because the script alias
needed four hooks (`DB_FindXAssetHeader`, `DB_XAssetExists`, `DB_IsXAssetDefault`,
`Scr_GetFunctionHandle`) before a party ref could even start a map. M5 (splitting the 9 HMW content
zones out of `ui_init_stub`, a "wait for the background load" gate on every map start, the
`mwx_sync_zone_load` fallback and 3+3 measurements) and M6 (fix `lui_restart`, mod zone unload/load,
`gamemodes::invalidate()`, the relaunch fallback and a per-switch sas test) are each larger than the
remaining session. They are left untouched rather than half-implemented, so the branch stays buildable.

## Open bugs / things for review

1. **GSC sees the party ref as gametype** (`getdvar("g_gametype") == "slasher"`). The milestone
   asked for `"war"` in GSC; H1 dispatches builtins through a jump table and has no name-based table
   (two scans: 8-byte and 16-byte entries, 0 candidates), so the override would need a VM dispatch
   hook. Everything the shipped scripts use (`level.gametype`, `scr_game_hodgepodgeMode`, the
   `scr_war_*` dvars in private matches) works with the ref. **Review**: is the VM dispatch hook
   wanted, or is the ref-in-GSC acceptable?
2. **Private Match menu start**: the offline lobby has no GAME SETUP/START GAME buttons
   (`mplobbyprivate` adds them only for `Lobby.IsGameHost()`), so the mode cannot be selected or
   started from the menu without making the offline client the party host. **Review**: is the party
   host state worth faking (like `request_start_match_stub` does for `xpartygo`)?
3. **Player cards on LAN** (`docs/todo-callsigns.md`): the white images are hidden now, but each
   player's real patch/background is not synced. Needs the ids in the connect info + a Lua override
   of `Lobby.GetMember*` (or snapshot fields).
4. `run-tests.ps1` (without the MCP) does not load the mod gametype (sas) while `run_test` via the
   MCP does (found by the other session; not rechecked this run - the MCP path sas is 8/8).
5. `map <x>` on a dedicated server started **without** a map still uses the old paths; not touched.
6. **MCP test runner does not fail fast when the server dies during map start.** In full run 2 the
   `cranked` server process exited before boot (net port 27017 still held by the previous stopped
   server); `run_one_test` kept polling the dead RPC for all 180 iterations (~6 min) and then
   reported "the dedicated server did not start the map". `run-tests.ps1` breaks on
   `$process.HasExited`; the MCP loop should do the same (`process_running` is already available).
   The test itself is green when rerun alone (13/13, job `t10`).
7. **`infect` flake (run 1 only).** On `mp_shipment`, with 4 bots, the new-infected loadout check and
   the late-joiner step both failed, then the scavenger-bag step found no survivor and called
   `test_done(0)`; the run took 136 s instead of 85 s. Same build and script passed 28/28 in run 2
   and `infect_rust` passed 28/28 in both runs. Most likely bots infected the last survivors during
   the long late-joiner wait (the test then has no ally with scavenger). Repro is a timing flake, not
   deterministic; next step is to add `test_log` diagnostics for `level.gameended`, the alive counts
   and the late joiner's actual team, and/or spawn the late joiner before the 25 s loadout waits.

### Run 2 (M4 build `e4222c23`), 2026-11-24 14:43, 31 min

| test | passed | failed | time | note |
|---|---|---|---|---|
| infect | 28 | 0 | 85 s | |
| infect_time | 6 | 0 | 82 s | |
| war | 8 | 0 | 72 s | |
| dm | 10 | 0 | 82 s | |
| sd | 4 | 0 | 109 s | |
| dom | 4 | 0 | 139 s | |
| dz | 4 | 0 | 79 s | |
| slasher | 16 | 1 | 93 s | "slasher won" (flaky: same test was 17/17 in the single run) |
| rpg | 6 | 0 | 51 s | |
| oic | 7 | 2 | 111 s | "game ended when one player was left", "exactly one player alive" (same as run 1) |
| aon | 8 | 1 | 62 s | "scavenger, fast reload, longer sprint" |
| cranked | 13 | 0 | 55 s | |
| sas | 4 | 4 | 52 s | the test **server had no `-mod`** (see below) |
| infect_rust | 28 | 0 | 88 s | |
| war_rust | 12 | 0 | 76 s | |
| war_terrace | 12 | 0 | 117 s | listen |

**12/16 green** (up from 10/16). The party modes slasher (16/17) and rpg (6/6) are green on the
real-gametype path.

### Remaining failures, judged

- **sas (4)** - the *runner* started the server without `-mod mods/sticksandstones`:
  `+set mwx_test "sas" +set mwx_test_bots "3" +set g_gametype "sas" +map "mp_shipment"` (no
  `-mod`), so `sas_weapon` stayed empty and the fallback loadout ran. The manifest has
  `"mod": "mods/sticksandstones"` and the current `mcp.cpp` reads it (`test.mod`), but the **running
  MCP server was started at 12:50, before that code existed**; `run_test` therefore drops the field.
  Fix: restart the MCP server after a build (or run the test through `start_server` with `mod`).
  Verified manually: a DS with `-mod mods/sticksandstones` prints
  `[mods] loading mod.ff of mods/sticksandstones`, `sas_weapon = iw5_exocrossbow_mp` and the
  crossbow kills - so it is an environment/test-runner issue, not a game bug.
  Re-run by hand with `start_server {mod:"mods/sticksandstones", ...}` + `spawnBot 3`: the
  crossbow and loadout assertions pass; only `victim score set` fails (expected 100/50, got 0) -
  the test's `set_score` helper (`_gamescore::_setplayerscore` then `player.pers["score"]`) does not
  take for the mod gametype, so the two bankruptcy checks pass trivially. **Test-side**, needs a
  working score setter for mod gametypes.
- **oic (2, reproducible)** - after the test kills everyone down to one player the match does not
  end and more than one player stays alive. Not fixed by the elimination-loop test change. Looks
  like a **game/script bug** in `oic.gsc` (win/lives handling); needs a session of its own.
- **aon (1)** - "scavenger, fast reload, longer sprint": the perks are not all set on spawn. Either
  the test checks the wrong perk keys or `aon.gsc` misses one; **open**, test-side likely (the
  other aon checks pass).
- **slasher (1, flaky)** - "slasher won": the match-end check raced the end-of-round event. The
  same test was 17/17 in the single run and 15/15 in run 1; flaky test timing, not a mode bug.

## Disk use (2026-11-24 17:20)

`C:` free: **51.3 GB** (rule: 20 GB; the 38.8 GB `compiled advanced warfare maps.zip` was removed on
request before this run, which is what brought it back above the limit). Nothing else was deleted.
The game-side sizes found by the step-5 check: `GAME\dump` 65.6 GB, `GAME\zone` 62.0 GB,
`GAME\hmw-usermaps` 28.6 GB, `GAME\hmw-mod` 7.1 GB.

Biggest things created/kept under `C:\Games\cod-hwm` by this project's runs:

| path | size |
|---|---|
| `refs\` (PDB per commit `refs\pdb\<hash>\`, dumps of the UI/GSC zones) | 5.37 GB |
| `cod-mwx\build\` (premake/msbuild output) | ~1.9 GB |
| `cod-mwx\.git` | 165 MB |
| `_migration\archive\mwx-debug\` | ~0.42 GB |
| GAME\minidumps (crash dumps) | 62 MB |
| GAME\mwx-logs | ~4 MB |
| GAME\mwx-screenshots | ~2 MB |

Long runs are allowed at 51.3 GB free; they are stopped if the free space drops under 20 GB.
`refs\pdb` is the main safe-to-trim item if space is needed later (one PDB per commit).

## Next steps for the continuation (2026-11-24 15:32)

1. Restart the MCP server (it was started 12:50 and predates the `mod` field in `find_test`):
   stop pid of `mwx.exe -mcp`, then start opencode again; `run_test sas` must then show
   `-mod "mods/sticksandstones"` in the server command line. sas alone was 6/8 before the score
   setter fix (crossbow + loadout green); re-run it after the restart.
2. `run_test oic` three times: the test now logs `state ...` per player and waits for
   `level.ingraceperiod` (confirmed cause: `_gamelogic.gsc:311` returns early during the grace
   period, so early kills take no life). If it still fails, the log shows which field is wrong.
3. `run_all_tests` twice, put both tables in this report, then push.
4. `docs/hmw-weapons-perks.md` (sources: `refs\h1_dump\h1_dump\mp\statstable.csv` and
   `perktable.csv` for MWR/H1, `COD-GSC-Source\HMW-GSC` + `H1-GSC`, our `data\mwx` scripts; HMW's
   own tables are not dumped - read them at runtime or mark as unverified).
5. M5, M6, M7 from `docs/autonomous-milestones.md` (disk 51.7 GB free, the 20 GB rule allows them).

## Handoff (2026-11-24 15:47) - MCP restarted/lost, sas still red

The MCP was stopped for the `mod` restart (step 1) and **opencode did not bring it back**: the `mwx`
tool namespace is gone for this session. Everything now goes through
`powershell -File tools\test\run-tests.ps1 [-Name <test>]` plus the HTTP debug RPC
(`POST 127.0.0.1:2708x/rpc`), which works. Restart opencode (or re-add the server) to get the MCP
tools back; after that `run_test` will pass `-mod` from the manifest.

### sas, still red (the one open item from step 1)

`run-tests.ps1 -Name sas` (result `tools/test/test-results-20261124-154612.json`):
`mod: "mods/sticksandstones"` is in the result, the server command line contains
`-mod "mods/sticksandstones"`, but the mod is **not** loaded (`sas_weapon` empty, 4/8).
A manual `Start-Process` with **the same flags** (`-mod "mods/sticksandstones"` before
`+set g_gametype`) prints `[mods] loaded mods/sticksandstones` + `[mods] loading mod.ff`. So the
difference is in how the runner starts the process, not the game. Next debug step: have
`run-tests.ps1` print its `$argList` and compare the *parsed* command line
(`Get-CimInstance Win32_Process | % CommandLine`) and the server's stdout for `[mods]`; most likely
the flag ends up after a `+command` in a way the HMW flag parser ignores (the working manual call
puts it before `+set g_gametype`), or the quoted argument is passed literally. Fix the runner, not
the test.

### State

- Branch `opencode/autonomous` at `f6a8ffcd` (pushed): review patch, aon fix (3/3 green), oic
  diagnostics + grace wait, sas score setter, slasher winner wait.
- The MCP is down; start opencode again before any further MCP work.
- Remaining: sas runner fix, oic x3, two `run_all_tests`, `docs/hmw-weapons-perks.md`, M5/M6/M7.

## Handoff 2 (2026-11-24 15:52) - sas root cause narrowed

The runner *does* pass `-mod` and the mod zone *does* load. From the runner's server log
(`%TEMP%\mwx-test-sas-27200.log`):

```
[mods] gametype sas (Sticks and Stones)
[mods] loaded mods/sticksandstones
[mods] loading mod.ff of mods/sticksandstones
...
Loaded custom gsc 'mwx/tests/sas.gsc'      <- the TEST script
factions: added sas (template tf141) to mp/factionTable.csv
```

There is **no** `Loaded custom gsc 'maps/mp/gametypes/sas.gsc'`, and `sas_weapon` stays empty, so the
mod's **gametype script never runs** - the mode falls back to a template gametype. mod.ff contains
only the crossbow assets (see `GAME\zone_source\mod_sticksandstones.csv`), the sas.gsc is a loose
file under `mods/sticksandstones/maps/mp/gametypes/`, and `load_scripts()` only scans
`scripts/mp/` (+ patches), never `maps/mp/gametypes/`. The M4 script-alias hooks pass `sas`
through unchanged, so this is a **mod loader gap** (the engine's gametype script load does not read
the mod folder), not the test and not the reviewer patch. Earlier crossbow kills (14:13) were with
the M3 build and may have come from a different path - re-check after the fix.

Fix direction: in `load_scripts()` also scan `<mod>/maps/mp/gametypes/` (and `mwx/maps/mp/gametypes/`)
and load those scripts through `Scr_LoadScript` so the gametype script exists, OR add the mod's
gametype script to mod.ff in the zone source. Then re-run `run-tests.ps1 -Name sas` (the score
setter and the mod flag are already fine).

Everything else is unchanged: branch `f6a8ffcd`, MCP down, report has the queued items.

## Handoff 3 (2026-11-24 15:58) - MCP is back

The MCP was re-added (`opencode mcp add mwx -- ...`) and opencode restarted; the `mwx` tools work
again and the server is the current binary: its sas command line is
`... +set mwx_test_bots "3" -mod "mods/sticksandstones" +set g_gametype "sas" +map "mp_shipment"`
(the `-mod` **before** the gametype, unlike `run-tests.ps1` which appends it after
`+set g_gametype`). The sas run (`run_test sas`, job t1) was still in progress when this session ran
out of context: the DS loaded `mp_shipment` (53 s) with the mod zone; the test outcome was not
confirmed.

If sas is green with the MCP, the remaining difference to the non-MCP runner is exactly that
`-mod` position - move it to the front of `$argList` in `tools/test/run-tests.ps1` (right after
`-memoryfix`) and re-run `-Name sas`. If it is still red, the mod gametype script is not loaded
(see "Handoff 2").

Still queued: oic x3, two `run_all_tests`, `docs/hmw-weapons-perks.md`, disk check, M5/M6/M7.

Update 15:55: `sas` with the restarted MCP was **7/8** (mod loads, crossbow/loadout and the throwing-knife
bankruptcy pass; only "suicide bankrupted the player" failed because `test_kill` substituted the victim
as the attacker). The suicide case now uses `victim dodamage(1000, victim.origin)` (2-arg, credits the
world) - commit `87674ebd`, pushed. Re-run `run_test sas` to confirm 8/8.

## Continuation 2026-11-24 (steps 1-4)

Branch `opencode/autonomous`, build from `87674ebd` (the running MCP server is the current binary;
its sas job `t2` completed 8/8). Disk at start: **55.4 GB free** (C:).

### 1. OIC alone, three times - green

The MCP `run_test oic` job logs the per-player state (`name`, `isalive`, `sessionstate`,
`pers["lives"]`, `level.ingraceperiod`, `getgametypenumlives()`,
`getpotentiallivingplayers().size`, `level.gameended`) after every kill and waits for the grace
period before killing. Results:

| run | job | passed | failed | script errors | kills | time |
|---|---|---|---|---|---|---|
| 1 | t3 | 9 | 0 | 0 | 9 | 113 s |
| 2 | t4 | 9 | 0 | 0 | 10 | 109 s |
| 3 | t5 | 10 | 0 | 0 | 10 | 117 s |

A fourth run through `tools\test\run-tests.ps1 -Name oic` (to get a captured DS stdout log) was also
9/9, 0 script errors, 112 s. So the earlier "match does not end" failure is gone with the grace
period wait + the elimination loop; `.gsc` and test both were correct, only the timing was wrong.

**Server-log check:** the DS stdout (`%TEMP%\mwx-test-oic-*.log`) and
`hmw-mod\logs\games_mp.log` contain only `K;/D;/J;/Q;`, `InitGame`, `ShutdownGame` - the H1
`logstring("last one alive, win: ...")` from `_gamelogic::default_ononeleftevent` is **not** written
to the HMW logfile (it is a console/debug `logstring`, not `G_LogPrintf`). The three green runs
verify the same code path at the state level: `level.gameended = 1`, exactly one player alive, and
the only FFA end path with three lives is `default_ononeleftevent` -> `endgame`
[H1-GSC/maps/mp/gametypes/_gamelogic.gsc:120-132, 381-385]. Nothing to fix here.

### 2. Slasher alone, two times - no flake

| run | job | passed | failed | script errors | time |
|---|---|---|---|---|---|
| 1 | t6 | 17 | 0 | 0 | 95 s |
| 2 | t7 | 17 | 0 | 0 | 89 s |

The winner check now waits after `level.gameended` for `level.finalkillcam_winner` to become
non-`none` (up to 10 s) [data/mwx/tests/slasher.gsc:141-165]. Both runs ended with `axis`
("slasher won"). No flake in these two.

### 3. Full run 1 (`run_all_tests`, job t8) - 15/16

| test | passed | failed | script errors | time | result |
|---|---|---|---|---|---|
| infect | 16 | 4 | 0 | 136.7 s | **red** - see below |
| infect_time | 6 | 0 | 0 | 85.1 s | green |
| war | 12 | 0 | 0 | 74.0 s | green |
| dm | 12 | 0 | 0 | 72.0 s | green |
| sd | 4 | 0 | 0 | 84.5 s | green |
| dom | 4 | 0 | 0 | 104.0 s | green |
| dz | 4 | 0 | 0 | 80.1 s | green |
| slasher | 17 | 0 | 0 | 90.4 s | green |
| rpg | 6 | 0 | 0 | 55.1 s | green |
| oic | 9 | 0 | 0 | 113.7 s | green |
| aon | 9 | 0 | 0 | 55.4 s | green |
| cranked | 13 | 0 | 0 | 64.0 s | green |
| sas | 8 | 0 | 0 | 54.8 s | green (mod `mods/sticksandstones` loaded) |
| infect_rust | 28 | 0 | 0 | 95.6 s | green |
| war_rust | 10 | 0 | 0 | 71.9 s | green |
| war_terrace | 12 | 0 | 0 | 129.4 s | green (listen) |

**15/16 green, 0 script errors.** The `infect` failure on `mp_shipment` (the same script passed
28/28 on `mp_rust` later in the same run): "new infected has the hatchet", "new infected has the
throwing knife", "late joiner joined as survivor", "survivor and infected for the scavenger bag"
(`test_done(0)` -> `done: false`). The run took 136 s instead of the usual 85 s. Working theory: the
bots infected the remaining survivors during the long late-joiner wait, the round ended, and the
late joiner never spawned as a survivor; the scavenger-bag step then found no surviving scavenger
and aborted [data/mwx/tests/infect.gsc:198-256]. Bot count/timing flake, not a mode regression -
`infect_rust` was green. Full run 2 follows below; if it repeats, the test needs a shorter wait or
an aggression gate.

### 4. Full run 2 (`run_all_tests`, job t9) - 15/16

| test | passed | failed | script errors | time | result |
|---|---|---|---|---|---|
| infect | 28 | 0 | 0 | 87.8 s | green (the run 1 failure did not repeat) |
| infect_time | 6 | 0 | 0 | 83.2 s | green |
| war | 10 | 0 | 0 | 69.9 s | green |
| dm | 12 | 0 | 0 | 75.0 s | green |
| sd | 4 | 0 | 0 | 84.5 s | green |
| dom | 4 | 0 | 0 | 106.1 s | green |
| dz | 4 | 0 | 0 | 86.6 s | green |
| slasher | 17 | 0 | 0 | 98.4 s | green |
| rpg | 6 | 0 | 0 | 56.0 s | green |
| oic | 10 | 0 | 0 | 119.2 s | green |
| aon | 9 | 0 | 0 | 52.7 s | green |
| cranked | - | - | - | ~6 min wait | **environment**: "the dedicated server did not start the map" (pid 8536 exited before boot; see below) |
| sas | 8 | 0 | 0 | 67.6 s | green (mod loaded) |
| infect_rust | 28 | 0 | 0 | 96.5 s | green |
| war_rust | 12 | 0 | 0 | 71.1 s | green |
| war_terrace | 12 | 0 | 0 | 150.5 s | green (listen) |

**15/16 green, 0 script errors.** The `cranked` server started (pid 8536) and exited during the map
load; the MCP `run_one_test` map-start loop polls the RPC 180 times but never checks whether the
process is still alive, so it waited ~6 min before reporting "the dedicated server did not start the
map" (`status: mwx s34 (27108) is not running`). This is the known single-instance/net-port
collision (a previous stopped server had not released 27017 yet); the test itself was green in run 1.
Rerun alone after the full run: **13/13 green, 0 script errors, 58 s** (job `t10`).

**Judgement on both runs:** each run has exactly one non-green test, a different one, and both are
timing/environment flakes - `infect` passed 28/28 in run 2 and `infect_rust` passed 28/28 in both
runs, `cranked` passed 13/13 in run 1. No mode regression in either run; all 16 tests have been
green at least once on this build. The remaining product bug is the MCP runner's missing
process-exit check during server start (it should fail fast like `run-tests.ps1`, which breaks out on
`$process.HasExited`).

### 4.1 Documentation: `docs/hmw-weapons-perks.md` (commit `f3148b87`)

Written from the dumps (`COD-GSC-Source\HMW-GSC`, `H1-GSC`), the H1 tables
(`refs\h1_dump\h1_dump\mp\*.csv`, `localize.json`), our `data/mwx` scripts and a **runtime read of
HMW's own tables** (a client on `mp_shipment`, `gsc_eval` loops over `mp/statstable.csv` and
`mp/perktable.csv`; 166 statstable rows / 112 weapon rows, 20 base perks + pro + equipment). It
covers: weapon refs/classes/origins, bare ref vs `buildweaponname`, primary/secondary/melee,
lethal/tactical (incl. `flare_mp`/tactical insertion), excluded `h2_riotshield_mp`, pool limits,
all HMW perks with slots/pro, the MWR perktable for comparison, gamemode loadouts (`getemptyloadout`,
`pers["gamemodeLoadout"]`, `bypassclasschoicefunc`, gametypesTable column 5), spawn timing
(`applyloadout` vs `applyLoadout` vs `spawned_player`), and the gotchas list. Linked from
`docs/mods.md` and `AGENTS.md`. HMW table cells marked "runtime" were read from the game; anything
not verified is marked **unverified**.

### 5. Disk check

`C:` free at the check: **51.3 GB** (rule: 20 GB), so M5 is allowed. Nothing was deleted. The size
breakdown is in "Disk use" below; the 65.6 GB `GAME\dump` and 62 GB `GAME\zone` are the big
game-side items, `refs\` is 5.4 GB.



## Handoff 4 (2026-11-24 17:30) - steps 1-5 done, M5/M6 not started

Stopped here to keep the branch buildable: the remaining milestones (M5 background zone loading,
M6 fast mod switching) each need a C++ change plus a build and a full test run, which did not fit
the remaining session context. Everything asked for in steps 1-5 is done.

### Branch state

- `opencode/autonomous` at **`bff3dc92`**, pushed (`87674ebd..bff3dc92`), working tree clean.
  The only new commit is the doc commit (it also amends the earlier `f3148b87` hash):
  `docs: HMW weapons/perks porting reference ...`.
- Build/test binary: the MCP server is the current `mwx.exe` (started 15:52, no rebuild needed this
  run - no C++ changed). `tools\gsc-check\check-all.ps1`: **24 files, 260 calls, 0 problems**.
- `_migration\archive\mwx-debug\autonomous\report.md` (this file) is not in git.

### Done in this session (details above)

1. **OIC 3x green** (9/9, 9/9, 10/10; + one run-tests.ps1 run 9/9). The grace-period wait and the
   elimination loop fixed it; no `.gsc` change needed. The H1 `logstring("last one alive, win:")`
   does not reach the HMW logfile - verification is at state level (`gameended`, one alive).
2. **Slasher 2x green** (17/17 both), winner check after `level.gameended` works; no flake.
3. **Two full runs**, 15/16 each, both tables in this report. Run 1 red `infect` (flake, 28/28 in
   run 2 and on rust), run 2 red `cranked` (server died before boot; rerun alone 13/13). Every test
   was green at least once on this build. Pushed.
4. **`docs/hmw-weapons-perks.md`** (805 lines): all weapons grouped with ref/name/class/origin
   (runtime HMW statstable + H1 dump), all perks with slots/pro (runtime HMW perktable + H1 dump),
   giving weapons/melee/lethal/tactical, loadouts, spawn timing, gotchas, checklist. Linked from
   `docs/mods.md` and `AGENTS.md`.
5. **Disk**: 51.3 GB free (rule 20 GB) - M5 is allowed. Nothing deleted.

### M5 - how to start (background zone loading)

Today `ui_init_stub` (`src/client/component/patches.cpp:425-456`) loads nine HMW content zones
(`hmw_killstreak`, `hmw_attachments`, `hmw_ar1`, `hmw_smg`, `hmw_shotgun`, `hmw_rangers`,
`hmw_nightshade`, `hmw_dlc_factions`, `hmw_dlc_killstreaks`) synchronously before the frontend, and
the mod's `mod.ff` last. That is the ~28.5 s the milestone wants to move behind the menu.

Suggested split (measure it, adjust if the menu needs an asset):

1. Add `mwx_sync_zone_load` (int, default 0) in `patches.cpp` `post_unpack` (register it in
   `scheduler::once(..., pipeline::main)` if it is a string; an int/bool is fine where the other
   MWX dvars are registered). `1` = today's behaviour (all zones in `ui_init_stub`, mod last).
2. In `ui_init_stub` with the dvar at 0, load only what the frontend really touches before the
   menu. First candidate: `hmw_dlc_factions` (party/callsign UI) and `hmw_attachments`; keep the
   weapon zones for the background. Verify the main menu, PLAY/private lobby and the player card
   with screenshots while the background load is still running.
3. Start the rest right after the menu is up: a `scheduler::once(<small delay>, pipeline::main)`
   that calls the same `try_load_all_zones(list)` with `DB_LOAD_ASYNC...` (it already uses
   `DB_LOAD_ASYNC_NO_SYNC_THREADS`), then poll the DB loading state on the main pipeline until
   done; log milestones to `component/load_timing.cpp` so `load_times` reports them.
4. Gate every map start on the background load: the `map` console command, `party::start_map`
   (Private Match / `xpartygo`), connect to a server and the mod switch. If loading is still in
   progress, show the normal loading popup (the game's own UI, no frozen unresponsive window) and
   block until done. A small `zones::wait_for_background_load()` helper called from those paths is
   enough; do not duplicate the wait in GSC.
5. `mod.ff` must still load last (after all HMW zones); keep the `zones.emplace_back("mod")` order.
6. Check CAC, armory, personalization and the weapon/camo menus while zones are still loading.
   If a menu hits a default asset, either block that menu until the load finishes (loading popup)
   or preload the minimum zone it needs - document which.
7. Measure 3 runs before and 3 after, from `mwx-logs/load_times.log` / the `load_times` MCP tool:
   time to main menu and time to the first map (`map mp_crash` from the frontend). Put the six
   numbers in the report. Acceptance: the menu is clearly earlier, all tests green, no default-asset
   errors/crashes in CAC.
8. Done = gsc-check 0 + `run_all_tests` + push `opencode/autonomous` (per the milestone rules).

Known traps for M5: `DB_LoadXAssets`/`DB_IsLoading` are called from the main thread only; do not
block the render thread; a zone requested while another async load runs is a fatal error; a missing
`mod.ff` asset reference is fatal (see the comment in `ui_init_stub`); string dvars must be
registered from `scheduler::once(main)` (AGENTS.md).

### M6 - after M5

Needs `lui_restart` fixed first (left over from M1: it leaves the frontend without a menu; restart
the game after changing UI scripts). Then `loadmod`/`unloadmod` in the main menu only, unload the old
`mod` zone, load the new `mod.ff`, reread `mod.json`, `gamemodes::invalidate()` (rebuild the
gametype table/whitelist/strings), mod scripts picked up on the next map load, restart LUI so the
PARTY list and MODS menu update; `mwx_mod_relaunch 1` / a failed zone unload keeps the relaunch
fallback. Acceptance per `docs/autonomous-milestones.md`: none -> sticksandstones -> none ->
sticksandstones without a restart, sas green after every switch, sas disappears when unloaded, and
the switch time in the report.

### Review / open

- M4 `getdvar` override: still the party ref in GSC; the VM-dispatch hook is the only remaining
  option (review question in "Open bugs").
- Private Match menu start: offline lobby is not the party host (review question).
- MCP test runner: add the process-exit check in the map-start loop so a dead server fails in
  seconds instead of ~6 min (cranked in run 2).
- `infect` flake: add the state diagnostics described in "Open bugs" item 7 if it repeats.

## Continuation 2026-11-24 (step 1): test runner robustness

Branch `opencode/autonomous` (from `bff3dc92`); MCP server is the 15:52 build, the test servers use
the new build after `build-branch.bat` (BUILD OK). Disk 33.8 GB free at the start (rule 20 GB).

### What changed

- **Fail fast when a server dies.** `tools/test/run-tests.ps1` now reports
  `server exited (code X)` both during map start and while waiting for `test_done`, instead of the
  timeout message. `src/client/mcp.cpp` adds `process_exit_code()` and checks the process in both
  waits (`server exited (code X)` with the port in the result).
- **Unique ports + port logging.** Every test gets its own debug port and a net port next to it
  (`27016 + (debug - 27108)`); the MCP sets `+set net_port` per dedicated instance, the PS runner
  sets `net_port` in the dvars and waits up to 30 s for the UDP port to be free before starting.
  Both log `test <name> debug port X, net port Y` and put both in the result JSON.
- **`-mod` before `+set` in `run-tests.ps1`** (the old position after `+set g_gametype` made the
  game's flag parser ignore it; sas now loads its mod zone through the script runner too).
- **Infect diagnostics + flake fix** (`data/mwx/tests/infect.gsc`, `tests.json`):
  `log_state(label)` logs `level.gameended`, axis/allies counts and every player (team/alive/bot) at
  every step; the infected bots are held (`ignoreall`, `allowfire(0)`) during the loadout and
  late-joiner checks and released before the endings; the late joiner is found regardless of team
  and a failure reports the actual team. `scr_infect_timelimit` is 10 minutes for `infect` and
  `infect_rust` (the failed run 1 took 136 s, past the old 2 minute limit).
- **Shared bot hold for count-sensitive tests** (`_test.gsc`: `test_hold_bots` /
  `test_release_bots`). The first full run of this step showed the real cause of the remaining
  flakes: bots kill/count each other between the test's own kills.

### First full run of this step (14/16)

| test | passed | failed | result |
|---|---|---|---|
| infect | 28 | 0 | green |
| infect_time | 6 | 0 | green |
| war | 10 | 0 | green |
| dm | 10 | 0 | green |
| sd | 4 | 0 | green |
| dom | 4 | 0 | green |
| dz | 4 | 0 | green |
| slasher | 14 | 1 | **flake** - "one survivor left: expected 1, got 0" (a bot killed a survivor during the loop) |
| rpg | 6 | 0 | green |
| oic | 7 | 2 | **flake** - "game ended when one player was left", "exactly one player alive: got 2" |
| aon | 9 | 0 | green |
| cranked | 13 | 0 | green |
| sas | 8 | 0 | green (mod loaded via `run-tests.ps1`) |
| infect_rust | 28 | 0 | green |
| war_rust | 10 | 0 | green |
| war_terrace | 10 | 0 | green (listen) |

The two reds are the same class of flake: the tests assume only their own `dodamage` kills count,
but the other bots kill each other between the checks. `test_hold_bots()` before the elimination
phases fixes both: `slasher` 17/17 and `oic` 10/10 alone afterwards. The runner changes themselves
worked: unique ports (27016-27031), no port collisions, sas mod loaded, all tests failed/succeeded
as the game reported.

### Slasher "slasher won: allies" flake - root cause and fix

After the bot hold, `slasher` was 1 in 3 runs red with `slasher won: expected axis, got allies`.
The new `test_log` diagnostics (stored in the `run-tests.ps1` result as `logs`) showed the state
**before the test's final kill** in the failing runs:

```
state before final kill: gameended=1 allies=3 axis=1 scoreA=1 scoreX=0 winner=allies
victim [BOT]Patoke team=allies isslasher=1 / attacker [BOT]j team=axis
```

The match had already ended: when only one survivor is left the mode gives it the slasher powers
(`slashersettings()` -> `allowfire(1)` + the shovel, still on allies)
[H1-GSC/maps/mp/gametypes/_hodgepodge.gsc:327-341, 479-493], and the test still waited 3 s after the
kill that left one survivor. The powered survivor killed the original slasher in that window, so the
mode correctly ended with `allies` (`onslashereliminated`, axis score 0). The test then killed the
last survivor and asserted `axis`.

Fix in `data/mwx/tests/slasher.gsc`:

- the elimination loop breaks immediately once `test_alive_on_team("allies") <= 1` (no 3 s window),
- while waiting for `isslasher`, the last survivor is re-held every 0.05 s (`ignoreall = 1`,
  `allowfire(0)`) so `slashersettings()` cannot keep firing it,
- the shovel is waited for (up to 5 s) because `switchtostartweapon("axis")` gives it one frame
  after `isslasher=1` (`waittillframeend` + `takeallweapons`/`giveweapon`)
  [H1-GSC/maps/mp/gametypes/_hodgepodge.gsc:294-307],
- the diagnostics (`log_state`) stay in the test.

Result: **4/4 slasher runs green (17/17, 0 script errors)** after the fix.

Final full run after the fixes: **16/16 green** - see "Final full run of step 1" at the end of this
report (commit `b3230e17`).
### Final full run of step 1 (16/16 green)

| test | passed | failed | script errors | time |
|---|---|---|---|---|
| infect | 28 | 0 | 0 | 92.4 s |
| infect_time | 6 | 0 | 0 | 87.2 s |
| war | 10 | 0 | 0 | 73.9 s |
| dm | 10 | 0 | 0 | 76.3 s |
| sd | 4 | 0 | 0 | 91.8 s |
| dom | 4 | 0 | 0 | 91.6 s |
| dz | 4 | 0 | 0 | 83.2 s |
| slasher | 17 | 0 | 0 | 90.5 s |
| rpg | 6 | 0 | 0 | 58.1 s |
| oic | 10 | 0 | 0 | 141.3 s |
| aon | 9 | 0 | 0 | 57.9 s |
| cranked | 13 | 0 | 0 | 61.8 s |
| sas | 8 | 0 | 0 | 58.5 s |
| infect_rust | 28 | 0 | 0 | 92.6 s |
| war_rust | 10 | 0 | 0 | 76.0 s |
| war_terrace | 12 | 0 | 0 | 85.7 s |

**16/16 green, 0 failures, 0 script errors.** The slasher fix was confirmed 4/4 alone before this run. Commit
`b3230e17` (runner + infect/oic/slasher tests) pushed to `opencode/autonomous`.

M4 reference screenshots (taken from the running client on `mp_shipment`, M4A1, default FOV, no
attachments): `C:\Games\cod-hwm\hmw-workbench\references\m4\m4-hip.png` and `m4-ads.png` (1920x1016).

## M5 investigation (2026-11-24 20:30) - blocked, reverted

### What was tried

1. `ui_init_stub` loads only `hmw_dlc_factions` before the frontend; a scheduler task loads the
   other eight zones with `DB_LoadXAssets(..., DB_LOAD_ASYNC)` after the first frame; completion is
   polled through `g_zoneCount`/`g_zones`; `fastfiles.cpp load_pre_gfx_zones` /
   `load_post_gfx_and_ui_and_common_zones` wait for it before every map load; `mwx_sync_zone_load 1`
   keeps the old synchronous behaviour.
2. A second variant queued the load only after `game::VirtualLobby_Loaded()` (the virtual lobby is
   not loaded on a fresh boot, so the load never started - this is also why the first variant was
   changed to a timed start).

### Measurements (`tools/test/measure-startup.ps1`, 3 runs each, `mp_crash`)

| build | first main-thread frame | first map load | menu usable |
|---|---|---|---|
| before (synchronous, 9 zones) | 61.3 / 63.5 / 55.9 s | 23.9 / 32.9 / 24.1 s | ~same as first frame |
| "after" (background) | 60.2 / ~53 / ~50 s | 20.8-25.3 s (including the wait) | **~100 s** |

Raw JSON: `_migration\archive\mwx-debug\autonomous\startup-before-20261124-201745.json`,
`startup-after-20261124-202446.json`.

### Why it is not shippable

`DB_LoadXAssets` blocks the calling (main) thread for the whole zone load even with
`DB_LOAD_ASYNC`. The first frame is logged at ~60 s, the eight zones load from ~61 s to ~100 s, and
the MCP `main_menu` state only becomes reachable at ~100 s: the menu is drawn but **frozen** for the
load. Loading before the first frame (the old behaviour) only delays the menu by the same amount.
There is no engine-side completion callback exposed in this build, and calling the DB loader from a
different thread is fatal (unknown thread affinity).

The experiment was reverted; the branch is back to the step-1 code and rebuilt (`BUILD OK`). The
finding, the numbers and a retry plan are in `docs/m5-background-zones.md` (commit `d7a9ea15`). The
16/16 full run above was made on exactly the reverted code (`b3230e17`), so the branch is green.

M6 (fast mod switching) and M7 (final report) are not started; M6 needs `lui_restart` fixed first
and a working mod-unload path, and was out of context after the M5 investigation.

## Handoff 5 (2026-11-24 20:35) - step 1 done, M5 blocked, M6/M7 open

### Branch / state

- `opencode/autonomous` at **`d7a9ea15`**, pushed (`b3230e17..d7a9ea15`), working tree clean,
  `BUILD OK` (reverted M5 code).
- gsc-check: **24 files, 260 cross-file calls, 0 problems**.
- Disk: **33.4 GB** free (rule 20 GB). Nothing deleted.
- Report: step 1 tables + slasher root cause + M5 measurements are above; raw startup JSONs in
  `_migration\archive\mwx-debug\autonomous\`.

### Done this session

1. **Test runner robustness + test flakes** (commit `b3230e17`):
   - both runners fail immediately with `server exited (code X)`; unique debug+net ports per test,
     logged; `run-tests.ps1` passes `-mod` before `+set`; `test_log` saved in the result JSON.
   - infect: `log_state` diagnostics, infected bots held during the loadout/late-joiner checks,
     `scr_infect_timelimit` 10 min, late joiner found regardless of team.
   - slasher: found the real cause (the last survivor gets the slasher powers and killed the
     original slasher during the 3 s post-kill wait). Fixed by breaking when one survivor remains,
     re-holding the powered survivor, and waiting for the shovel (given one frame later). 4/4 green.
   - oic: bots held during the elimination phase.
   - Full suite: **16/16 green** (final table above).
2. **M4 reference screenshots**: `C:\Games\cod-hwm\hmw-workbench\references\m4\m4-hip.png` and
   `m4-ads.png` (1920x1016, M4A1 `h2_m4`, default FOV, no attachments, HUD visible).
3. **M5**: implemented, measured, found the DB loader blocking the main thread; reverted and
   documented (`docs/m5-background-zones.md`).

### Next steps (M5 / M6 / M7)

- **M5**: only retry with a safe off-main-thread load (find a completion callback or a thread-safe
  DB entry point first; a wrong thread is fatal). The gate belongs in `load_pre_gfx_zones` for the
  real map, not the virtual lobby. The frontend subset (`hmw_dlc_factions`) is the minimum; CAC/
  armory must be blocked or preloaded until the weapon zones are in.
- **M6**: fix `lui_restart` first (M1: it leaves the frontend without a menu). Then `loadmod`/
  `unloadmod` in the main menu only, unload `mod`, load the new `mod.ff`, reread `mod.json`,
  `gamemodes::invalidate()`, restart LUI, `mwx_mod_relaunch 1` fallback; acceptance in
  `docs/autonomous-milestones.md` (none -> sas -> none -> sas, sas green after every switch).
- **M7**: needs M6; the final report must add M6 status and its test tables.

### Review / open

- `getdvar("g_gametype")` is still the party ref (M4; VM-dispatch hook is the only option left).
- Private Match menu start still blocked by the offline lobby not being the party host.
- MCP server process-exit check is now in the code but the running MCP is the 15:52 image; the next
  restart picks it up. `run-tests.ps1` already uses it.
- The `mwx_test_mode` client is 960x540; the M4 shots were taken after the user changed the
  resolution in-game to 1920x1016.

## M5b (2026-11-24 21:00) - zone compression / startup I/O - done, nothing changed

- All nine HMW content zones in `GAME\hmw-mod\zone` are **already LZ4** (`S1ffu100`, version 0x42,
  compressType 4), repacked on 2026-11-20 18:18. The zlib originals are in
  `GAME\hmw-mod\zone_backup_zlib\` (21 files, compressType 1), so the earlier repack was done and
  the backups exist.
- One fresh startup profile (`tools/test/profile-startup.ps1`): the nine-zone block took 40.7 s
  (this run), used **7.86 s CPU (19.3 % of one core)** and read **2836.7 MB at 69.7 MB/s**. It is
  **I/O-bound**, not decompression-bound; the files total 2848.9 MB, i.e. every byte is read once.
- Consequence: a further LZ4 repack would not help. The remaining options are faster storage,
  antivirus exclusion for the game folder, loading fewer/smaller zones, or keeping the current
  startup. No repack was done. Documented in `docs/m5b-zone-compression.md` (commit `c7ece2a6`).

## Handoff 6 (2026-11-24 21:05) - M5b done, M6/M7/M8 open

### Branch / state

- `opencode/autonomous` at **`c7ece2a6`**, pushed (`d7a9ea15..c7ece2a6`), working tree clean, game
  rebuilt without the M5 experiment (`BUILD OK`).
- gsc-check: **24 files, 260 cross-file calls, 0 problems**.
- Disk: **33.4 GB** free (rule 20 GB). Nothing deleted.
- M5 stays closed: `docs/m5-background-zones.md` is correct, keep it.
- M5b is measurement-only: zones are already LZ4, startup is disk-bound (~70 MB/s); no change.
- Step 1 is done: **16/16 green**, commit `b3230e17`. M4 screenshots in
  `C:\Games\cod-hwm\hmw-workbench\references\m4\`.

### M6 - not started (needs a session of its own)

Prerequisites found in the code:

- `lui_restart` (`src/client/component/ui_scripting.cpp:905-908`) only calls `0x27BEC0`; it leaves
  the frontend without a menu (M1). A working restart needs the LUI globals rebuild at
  `ui_scripting.cpp:540-654` plus closing/reopening the frontend menu - not a one-line fix.
- `loadmod`/`unloadmod` (`src/client/component/mods.cpp:265-302`) still call `relaunch(path)`. The
  mod zone is loaded through `ui_init_stub` (last, after the HMW zones) and released by the engine
  on relaunch.
- There is **no `gamemodes::invalidate()`**: the gametype table/strings are built once at startup
  from the mod manifest (`mods::load_gametypes`). M6 needs an invalidate/rebuild there.
- Zone unload: `DB_LoadXAssets` has a `freeFlags` field in `XZoneInfo`; the mod zone was loaded with
  `DB_ZONE_COMMON | DB_ZONE_CUSTOM`. A safe unload path for the `mod` zone is the first thing to
  prove (with `mwx_mod_relaunch 1` / failed unload as the fallback).
- Then: main-menu-only `loadmod`/`unloadmod`, unload `mod`, load the new `mod.ff`, reread
  `mod.json`, rebuild gamemodes, restart LUI so MODS/PARTY update; test none -> sticksandstones ->
  none -> sticksandstones with sas green after each switch and switch times in the report.

### M7

The final report can include step 1, M4, M5/M5b and M6 as "not started"; it cannot include M6's
tables/timings until M6 is done.

### M8 step 1

Not done. `ph` on `mp_crash` with bots and a prop-model/no-weapon screenshot is the first step, but
it was behind M6; no PH changes were made.

### Review / open (unchanged + new)

- M5: only retry with a safe off-main-thread DB load; the loader blocks the calling thread.
- M5b: if startup matters, measure disk throughput / antivirus exclusion before any content change.
- `getdvar("g_gametype")` is still the party ref (M4).
- Private Match menu start still blocked by the offline lobby not being the party host.
- The running MCP server is the 15:52 image; the runner process-exit check is in the code and will
  be picked up on the next restart (`run-tests.ps1` already uses it).

## M6 (2026-11-25) - fast mod switching without a relaunch - done

Commits: ef7cec2e (see `git log opencode/autonomous`).

### 6a: the `mod` zone can be unloaded - proven, but not through `freeFlags`

- `XZoneInfo freeFlags` is **not** a per-zone free request. `DB_LoadXAssets` matches the flags of
  every loaded zone: freeing `DB_ZONE_COMMON | DB_ZONE_CUSTOM` also freed the nine `hmw_*` content
  zones (they were loaded with the same flags). The client then hit
  `Could not load default asset for asset type 'surfacefx'` and a fatal dialog.
- The safe path is the engine's own unload function behind `DB_UnloadXZones` (`0x39B3C0`): find the
  zone index of `mod` and call `fastfiles::unload_zone("mod", true)` (new in `fastfiles.cpp`).
  `create_default = true` replaces assets that are still referenced with defaults instead of leaving
  dangling pointers.
- Verified in the running client: after the unload the mod assets are gone (`DB_XAssetExists`
  `iw5_exocrossbow_mp` 0, default 1), the `hmw_*` zones are untouched, the game keeps running.
- The unloaded zone slot stays in the engine's zone list (name `mod`, assets freed); a reload adds a
  new slot. `modzone status` prints `zone count` / `mod zone slots`. A handful of switches is
  harmless; a very long session should relaunch.

### 6b: `lui_restart`

`ui_scripting::restart()` (`ui_scripting.cpp`) now:

1. calls `0x27BEC0` (the old `lui_restart` body: shuts the frontend/LUI down),
2. calls `0x2A5540` (the original of the `ui_init_stub` hook: UI/frontend init, which starts LUI
   again through `hks_start` -> the MWX globals rebuild + script load), and
3. opens `mp_main_menu` again from a main-thread scheduler task (1 s later).

Verified with `ui_snapshot` (PLAY/OPTIONS/MODS/QUIT present again), `lua_eval`
`game:getmodgametypes()` and the PARTY list after every switch. It is also the console command
`lui_restart`.

### 6c: `gamemodes::invalidate()`

New in `gamemodes.cpp`: clears the cached patched `_gametypes.txt` whitelist and the cached
`gametypesTable.csv` copy, so the next lookup rebuilds both from `mods::get_gametypes()`. The mod's
localized strings are tracked by `mods::load_gametypes` and removed again on unload
(`localized_strings::remove`).

### 6d: `loadmod` / `unloadmod` without relaunch

- main menu only (`can_change_mod`), order: unload old `mod` zone -> `mods::set_mod` (re-read
  `mod.json`, register/unregister the fs path, rebuild gametype strings) -> load the new `mod.ff`
  -> `gamemodes::invalidate()` -> wait for the database -> `lui_restart` -> main menu.
- `mwx_mod_relaunch 1` (new saved bool dvar) or a failed unload keeps the old relaunch. Verified:
  with the dvar set, `loadmod` starts a new process with `mwx.exe -mod "mods/sticksandstones"` and
  the old one exits (the relaunched client has no debug port, as before).
- `DB_LOAD_SYNC` is used for the switch load. `load_timing` only closes a zone when the next zone
  starts, so the `done mod ... ms` line for a lone mod load is not its load duration; the switch
  time below is measured from the command to the reopened main menu.
- Diagnostics: `modzone status` / `list` / `unload` / `load`.

### Acceptance run (client `c24`, no relaunch)

Sequence `none -> sticksandstones -> none -> sticksandstones`, measured from the console command to
the re-opened main menu:

| switch | mode unload | load request | main menu ready | `getmodgametypes()` | PARTY list |
|---|---|---|---|---|---|
| none -> sas | 0 ms | 523 ms | **1871 ms** | `sas` | `... cranked sas` |
| sas -> none | 13 ms | 0 ms | **1353 ms** | `` | `... cranked` |
| none -> sas | 0 ms | 626 ms | **1945 ms** | `sas` | `... cranked sas` |

`sas` test after each switch (dedicated server started by the runner, same build):

| job | after switch | passed | failed | script errors | duration |
|---|---|---|---|---|---|
| t12 | none -> sas | 8 | 0 | 0 | 64.6 s |
| t13 | sas -> none | 8 | 0 | 0 | 63.1 s |
| t14 | none -> sas | 8 | 0 | 0 | 58.1 s |

(`t11` above was the same test in an earlier switch run: 8/0, 75 s.)

### Open M6 issue: client map start with a mod loaded

`map mp_shipment` on a client with `mods/sticksandstones` loaded (at startup **or** after a switch)
crashes after the loading screen / shortly after the first bots: `0xC0000005` in
`pm_player_trace_stub` (`gameplay.cpp:144`, `g_enableElevators`), while the dedicated server runs
the same sas test fine. A client without a mod starts the same map in ~3 s. This is independent of
the switch (reproduced with `-mod` at startup) and is left as an open issue; M6's acceptance (party
list + sas test) is met.

## M8 step 1 (2026-11-25) - `ph` on `mp_crash`, report only

- Dedicated server `ph` on `mp_crash`, 4 bots: `mp/ph_props_mp_crash.csv` **is in the loaded zones**,
  `tablegetrowcount("mp/ph_props_mp_crash.csv")` = **25**.
- `g_gametype` = `ph`, `scr_game_hodgepodgeMode` = 9, `level.gametype` = `ph`.
- **No props are disguised:** every player entity keeps
  `body_usmc_desert_assault_mp_camo`; no prop model is set. **They keep normal weapons** too
  (`h1_ak47_mp` / `h1_p90_mp`, grenades), class `gamemode`. Checked again after 35 s in the match
  and once more with `scr_ph_propHideTime 8` (20 s after the bots spawned): same result.
- Client `ph` on `mp_crash` with 4 bots crashes (`0xC0000005`, address `0x1404D11D1`, stack through
  `gameplay::pm_player_trace_stub`), same crash family as the mod client map start above. Desktop
  screenshot of the error: `_migration/archive/mwx-debug/autonomous/m8-ph-crash.png`.
- No PH code changed.

## M7 final report (2026-11-25)

### Milestone status

| milestone | state | commits |
|---|---|---|
| M1 test interface (MCP) | done | `06c2ee51` |
| M2 automated game mode tests | done (16 tests); early full runs had flaky tests, all fixed | `2c7b155c`..`435a85a8`, `b3230e17` |
| M3 hygiene + menu | done: Discord/autoplay gone, PLAY label, MODS above QUIT, offline Play, build script in `tools/build` | `234c8b1b`, `4de36ea6`, `5d9899bf`, `7be1934f`, `f20165da` |
| M4 party modes as real gametypes | done except the GSC `getdvar` override (H1 has no addressable builtin table); slasher/rpg/oic/aon green; lobby card images hidden; Private Match menu start still blocked by the offline lobby not being the party host | `3a809599`, `e4222c23` |
| M5 background zone loading | closed as not possible this way: `DB_LoadXAssets` blocks the calling thread; reverted and documented in `docs/m5-background-zones.md` | `d7a9ea15` |
| M5b zone compression / startup I/O | done, measurement only: the nine zones are already LZ4 and startup is disk-bound (~70 MB/s, 19 % CPU); no repack | `c7ece2a6` |
| M6 fast mod switching | done (see above); one open client map-start crash with a mod loaded | ef7cec2e |
| M7 final report | this section | ef7cec2e |
| M8 step 1 | done, report only (see above) | ef7cec2e |

### Test runs (two full `run_all_tests`)

Run 1 (`t15`): **16/16 tests, 0 failed**, 1582 s wall time.
Run 2 (`t16`): **16/16 tests, 0 failed**, 1680 s wall time.

| test | run 1 (passed/failed) | run 2 (passed/failed) |
|---|---|---|
| infect | 28 / 0 | 28 / 0 |
| infect_time | 6 / 0 | 6 / 0 |
| war | 10 / 0 | 12 / 0 |
| dm | 12 / 0 | 10 / 0 |
| sd | 4 / 0 | 4 / 0 |
| dom | 4 / 0 | 4 / 0 |
| dz | 4 / 0 | 4 / 0 |
| slasher | 17 / 0 | 17 / 0 |
| rpg | 6 / 0 | 6 / 0 |
| oic | 10 / 0 | 10 / 0 |
| aon | 9 / 0 | 9 / 0 |
| cranked | 13 / 0 | 13 / 0 |
| sas | 8 / 0 | 8 / 0 |
| infect_rust | 28 / 0 | 28 / 0 |
| war_rust | 10 / 0 | 10 / 0 |
| war_terrace | 12 / 0 | 12 / 0 |

The assertion totals of the generic `war` test differ between runs (10/12 and 12/10) because it
checks every spawned player: how many of the four bots are spawned and alive when the snapshot
runs varies. Both runs have no failures.

The mode tests are described in `docs/testing.md`; the sas test after each M6 switch is in the M6
section above (`t12`-`t14`, 8/0 each).

### Startup measurements (M5, unchanged code)

From `docs/m5-background-zones.md`, 3 clients, `mp_crash`, `mwx_test_mode`:

| run | first main-thread frame (main menu) | first map |
|---|---|---|
| 1 | 61.3 s | 23.9 s |
| 2 | 63.5 s | 32.9 s |
| 3 | 55.9 s | 24.1 s |

Background loading made the menu reachable at the same time or later (50-60 s first frame, then
~40 s more load), so it was reverted. M6 does not add to startup (the switch code runs only after
the main menu).

### Mod switch times (M6 acceptance, client `c24`)

| switch | main menu ready |
|---|---|
| none -> sticksandstones | 1871 ms |
| sticksandstones -> none | 1353 ms |
| none -> sticksandstones | 1945 ms |

Most of the time is the fixed 1 s wait before re-opening the menu plus the LUI globals/script
rebuild; the `mod.ff` load request itself was 0.5-0.6 s (file cached). A cold mod.ff load adds its
normal disk time.

### Open bugs / things for review

1. **Client map start with a mod loaded crashes** (`0xC0000005` in `gameplay.cpp`
   `pm_player_trace_stub`, `g_enableElevators`). Reproduced with `-mod mods/sticksandstones` at
   startup, so it predates M6; a client without a mod starts the same map in ~3 s, the dedicated
   sas test is green. This makes a switched mod usable for dedicated servers/tests but not yet for
   a client-hosted match.
2. **`ph` has no prop disguise** (M8 step 1): all players keep the soldier model and normal
   weapons on `mp_crash`, although `mp/ph_props_mp_crash.csv` is loaded (25 rows); the client ph
   match with bots hits the same `pm_player_trace_stub` crash. No PH changes were made.
3. **GSC sees the party ref as `getdvar("g_gametype")`** (`slasher`, `ph`, ...), not `war` (M4).
   Everything the shipped scripts use works; the milestone's literal GSC check would need a VM
   dispatch hook.
4. **Private Match menu start** is still blocked by the offline lobby not being the party host.
5. **Mod zone slots grow** by one per loaded `mod.ff` (the unloaded slot stays in the engine's zone
   list). A handful of switches is fine; a very long session should relaunch. `modzone status`
   shows the count.
6. **M5**: only retry with a safe off-main-thread DB load; the loader blocks the calling thread.
7. **M5b**: if startup matters, measure disk throughput / antivirus exclusion before any content
   change.

### Review: risky hooks added by M6

- `fastfiles::unload_zone` calls the engine's `DB_UnloadXZones` (`0x39B3C0`) directly with one zone
  index and `create_default = true`. It replaces the `freeFlags` path, which freed every custom
  zone. Only reachable from the main menu (console `modzone unload` / `loadmod`).
- `ui_scripting::restart` calls `0x27BEC0` (LUI shutdown) and `0x2A5540` (UI init) and opens
  `mp_main_menu`. It was verified repeatedly but is still a raw-address sequence; if the game
  updates, these need re-checking.
- `DB_LOAD_SYNC` for the switch load + a `Sys_IsDatabaseReady2` gate before the menu restart.
- `gamemodes::invalidate` clears the cached whitelist/table; old patched copies stay allocated in
  the component allocator (a few KB per switch).

## Handoff 7 (2026-11-25) - M6 and M8 step 1 done, pushed

### Branch / state

- `opencode/autonomous` at **`ef7cec2e`** (M6 + M7 final report), pushed.
- Working tree: clean at `ef7cec2e`; build `BUILD OK`; gsc-check **24 files, 260 cross-file
  calls, 0 problems**.
- Disk: **35.8 GB** free; nothing deleted; all work stayed in `C:\Games\cod-hwm`.

### Done in this session

- **M6** (see the M6 section): `mod` zone unload through the engine's `DB_UnloadXZones` (not
  `freeFlags`), working `lui_restart` (`0x27BEC0` + `0x2A5540` + reopen `mp_main_menu`),
  `gamemodes::invalidate()`, mod strings removed on unload, no-relaunch `loadmod`/`unloadmod`,
  `mwx_mod_relaunch 1` fallback, `modzone` diagnostics.
- Acceptance: none -> sas -> none -> sas without a restart, party list updates, timings 1871 /
  1353 / 1945 ms, sas test 8/0 after every switch (`t12`-`t14`).
- **M8 step 1**: `ph` on `mp_crash` with bots: `mp/ph_props_mp_crash.csv` is loaded (25 rows), but
  players keep the soldier model and normal weapons (no props); client ph with bots crashes in
  `gameplay.cpp pm_player_trace_stub`. No PH changes.
- **M7**: final report above; run 2 (`t16`) finished 16/16 green in 1680 s.

### Next / open

1. Client map start with a mod loaded (`-mod` at startup too) crashes in `pm_player_trace_stub`;
   needs its own investigation if a client-hosted modded match is required. Dedicated servers are
   fine.
2. `ph` prop disguise is not applied; the prop table is there but bots keep class `gamemode` and
   normal weapons.
3. Mod zone slots grow by one per loaded `mod.ff`; relaunch after many switches.
4. GSC `getdvar("g_gametype")` still returns the party ref (M4 open item).
5. Private Match menu start still blocked by the offline lobby not being the party host.
6. M5 (background zone loading) only with an off-main-thread DB load.




## Night run 2026-11-25 (autonomous, opencode + DeepSeek)

### N0 - finish M7 (DONE)

- Test run 2 (`t16`): **16/16 green, 0 failed, 1611 s**. The per-test table in the M7 section is
  filled in; the assertion totals of the generic `war` test differ from run 1 (10/12 vs 12/10)
  because it checks every spawned bot that is alive at the snapshot, not a fixed set.
- The uncommitted M6 code and the M7 report were committed and pushed:
  `ef7cec2e M6: swap mods without a relaunch (unload the mod zone, restart the UI); M7 final
  report with both full test runs` (`opencode/autonomous`).

### Correction to M8 step 1

The M8 step 1 section says "no props are disguised, every player entity keeps
`body_usmc_desert_assault_mp_camo`, no prop model is set". That observation was wrong: Prop Hunt
does not change the player entity's model, it calls `playerhide(1)` and spawns a **separate
`script_model`** (`self.prop`) with the prop model. The player entity keeps the soldier model.
What really was missing is described below (the prop entity was never created).

### N1a - Prop Hunt on a dedicated server (DONE, cause confirmed + fixed)

Dedicated `ph` on `mp_crash`, 4 bots, `mwx_test_mode`, `scr_ph_propHideTime 8`:

- `level.hodgepodgemode` = 9, `level.madpropsmode` = 0, `level.gametype` = `ph`,
  `level.proplist.size` = **25** (the map's own `mp/ph_props_mp_crash.csv`), `level.phsettings`
  and `level.ph_loadouts` are set, `level.hodgepodgeonstartgametype` exists: `_hodgepodge::init`
  and `ph_init()` **did run**, `onstartgametype` was wrapped.
- `level.startcheck` = 1 on the defenders, i.e. the stock `onspawnplayer` defender branch ran and
  started `handleprop()`. `handleprop` waits for the **`applyLoadout`** notify to build the prop.
  The gamemode class is applied in the same frame as the spawn, so the notify arrived **before**
  the thread reached its `waittill` and `self.prop` was never created. The defenders stayed alive
  with the hunter weapon and no prop entity. (Confirmed by re-sending `applyLoadout` on a live
  prop player: the prop appeared immediately.)
- Fix in `data/mwx/scripts/mp/mwx_hodgepodge.gsc` (`install_ph` + `ph_ensure_prop`): after the
  mode is known, every defender gets a bounded watcher that repeats `applyLoadout` until
  `self.prop` exists. Result: defenders spawn as prop models (`com_computer_case`,
  `mil_sandbag_desert_single_light_bent`, `rock_tan_boulder_2`, ...), health = the CSV size class
  value (50/100/200/350), no weapons; hunters keep the hunter loadout.

**Second confirmed cause: the party ref breaks MWR's watched dvars.** The hodgepodge code was
written for `g_gametype war`: `setupdvars()` sets `scr_war_numlives`/`scr_war_timelimit`, while
`getwatcheddvar()` builds `scr_<level.gametype>_*` from the party ref (`ph`/`mprops`). So
`getgametypenumlives()` stayed 0 (unlimited lives): a dead prop respawned and a round could never
end by elimination. `ph_numlives_stub` (replacefunc) + `level.gamemodemayspawn = ::ph_mayspawn`
(one life per round for the defenders, marked by a death watcher and compared with
`game["roundsPlayed"]`) fix that. Mad Props uses 4 lives.

### N1b - client crash in `pm_player_trace_stub` (analysed, blocked)

- Reproduced: client `mp_crash`, bots, listen host. New dump
  `hmw-mod-crash-1-2026-11-24-22-59-45.zip`, same stack and address `0x1404D11D1`.
- The dump context: `RAX = 0x80`, exception parameter 1 = `0x88`; the faulting instruction is
  `inc dword [rax+8]` at `0x4D11D1` (ref-count increment on a pointer returned by the TLS
  accessor at `0x4F7880`, `ecx = 4`). The accessor walks `TEB->ThreadLocalStoragePointer`, a
  per-thread array at `+0x30`, element 4 -> `0x80`, i.e. an uninitialised/invalid TLS slot.
- It is **not our stub**: `pm_player_trace_stub` only calls the original `0x2D14C0` and then
  optionally clears `startsolid`. The crash is inside the original trace/asset code
  (`0x2D1525 -> 0x2D1720 -> 0x33A63B -> 0x33A385 -> 0x4D6591 -> 0x4D1452 -> 0x4D11D1`) and it
  **still happens with `g_enableElevators 0`**, so the elevator feature is not the cause.
- It only reproduced on the *unsupported* client path that starts a map with `+map` on the
  command line and then joins a team; the supported listen path (boot to the menu, then
  `map <name>`, as `war_terrace` does) does not spawn the local player and did not crash.
- Next idea: build a test client with the `pm_player_trace_hook` not installed (one line) and
  repeat the `+map` path, to rule out the detour itself; then use the real menu start (Play ->
  game setup) to see whether normal LAN hosting hits it.

### N1c - prop lists for the other maps (PARTIAL)

- New debug method `model_bounds` (`src/client/component/debug_api.cpp`, route in
  `debug_server.cpp`, MCP tool in `mcp.cpp`): reads the loaded `XModel` asset's
  `bounds.midPoint/halfSize`, radius and contents. GSC cannot do this:
  `getentitymodelbounds()` returns `(0,0,0)` for script models and `getstaticmodelbounds()`
  refers to precompiled static models (count 0 on a map).
- `tools/ph-props/generate.ps1`: reads `refs/maps/<map>/xmodels.txt` (BOM/leading comma
  stripped), filters weapons/characters/vehicles/effects/foliage/UI/objectives by name, reads the
  bounds of every candidate from a running server on that map via `/rpc model_bounds`, drops
  too big (>180 units), too flat (<8 height) and too small (<10) models, assigns
  xsmall/small/medium/large (<=24/48/90/rest), prefers "prop-like" names over trim (pipes,
  doors) and writes `data/mwx/ph_props/ph_props_<map>.csv` (`model,class,0`, 20-40 rows).
- Generated and verified in game: **mp_rust (26 props)** and **mp_terminal (40 props)**; fallback
  lists (the 7 Mad Props models, measured on the same server) for **mp_invasion, mp_hardhat,
  mp_paris, mp_skidrow**. The other maps with an xmodels dump still need one server load each
  (`tools/ph-props/README.md`); that is the remaining mechanical work.
- Injection: `src/client/component/ph_props.cpp`, same place as the faction/stock-weapon
  patches (`fastfiles.cpp` string table branch + `DB_XAssetExists`/`DB_IsXAssetDefault` for the
  generated names). A missing table comes back as an empty *default* asset (rowCount 0); that is
  replaced by the generated `StringTable` (cell hash taken from an already loaded table).
  Log: `ph_props: injected mp/ph_props_mp_rust.csv (26 props)`. The CSV files stay in
  `data/mwx/ph_props/` (not in game zones), mirrored to `GAME\mwx\ph_props\`.

### N1d - tests and Party list (PARTIAL)

- `data/mwx/tests/ph.gsc`: hodgepodge 9, prop list not empty, defender gets a prop model, no
  weapon/primary, hunter has a weapon, a hunter can kill a prop, all props eliminated ends the
  round with the hunters as winner, `mwx_ph_fix` installed.
- `data/mwx/tests/mprops.gsc`: madprops 1, prop model, no weapon, soldier armed, a soldier can
  kill a prop, eliminating every soldier ends the round with the props as winner.
- Manifest now has 20 tests (ph, ph_rust, ph_terminal, mprops added).
- Results: `ph` (`t17`-`t22`, mp_crash): **10 passed / 2 failed** every time - the prop model,
  no weapon, hunter weapon and the prop kill pass; after killing both defenders the round still
  does **not** end (`level.gameended` 0, winner `none`). `mprops` (`t23`): **9 passed / 1 failed**
  - only "a soldier can kill a prop" fails (mad props props seem not to die from
  `test_kill`); the round-end and winner checks **pass**.
- `ph`/`mprops` are **not yet back in the Party list** (`ui_scripts/gamemodes/__init__.lua`):
  blocked by the open ph round-end issue. No in-game prop screenshot was taken yet.

### N4 - map command on a dedicated server (cause found, not fixed)

- A dedicated server *with* a map (`map mp_rust`) accepts `map mp_terminal`, logs
  `Starting map: mp_terminal`, `Loading fastfile mp_terminal_load`, and then never reaches
  `server running` again (main thread busy for 2+ minutes). A DS started with `+map mp_terminal`
  loads it in ~55 s, so the map itself is fine.
- A dedicated server exiting a game (`G_ShutdownGame`) crashed in
  `scripting::g_shutdown_game_stub` (`scripting.cpp:157`, dump `hmw-mod-crash-2-2026-11-24-23-37-05`,
  `0xC0000005` at `0x1405090D9`). The stub calls `scripting::notify(levelEntityId,
  "shutdownGame_called")` from the `map` command path, where the script VM/level may already be
  gone (a DS started without a map has no VM at all). Next idea: guard the notify (and the
  shutdown callbacks) with `SV_Loaded()/CL_IsCgameInitialized()` + a valid `levelEntityId`, and
  reproduce the no-map -> `map` hang with that guard in place.

### N2, N3a/b, N5 - not done

- N2 (Sharpshooter/Reinforce/Search & Rescue/Mugger/Arena) was not started; N1 took the night.
- N3: the MCP `input` tool already injects movement/attack through engine commands (not OS
  focus), so 3a is likely already satisfied; it was not verified on this run, docs/mcp.md not
  changed.
- N5 (callsigns in the connect info) not started.

### Commits this run

| commit | content |
|---|---|
| `ef7cec2e` | M6 code + M7 final report (run 2 table) |
| `cead720d` | M8: prop setup retry, one life per round, dvar fixes, prop list generator + injection, ph/mprops tests |

GSC check after the last change: 26 files, 261 cross-file calls, **0 problems**. Build: **BUILD OK**
(`build-branch.bat`), PDB archived by the script.

### Open review items for Claude

1. `ph_props.cpp` replaces an **empty default string table** by a generated one and reports the
   name as existing in `DB_XAssetExists`. The cell hash is borrowed from the first loaded table
   that passes `stock_weapons::find_hash`. If H1 ever changes the hash, the generated tables
   break silently (log: `ph_props: no string table hash known yet`).
2. `model_bounds` reads `XModel.bounds` on the server pipeline. `Bounds` is `{midPoint, halfSize}`
   in `database.hpp`; the generator relies on it for the size classes.
3. `ph_mayspawn` is a `level.gamemodemayspawn` override for hodgepodge 9 only; it uses
   `game["roundsPlayed"]` and a per-player `ph_dead_this_round` stamp.
4. `pm_player_trace_stub` is still the only hook in the crash path that we control; the dump
   shows the fault in the original code, but a test build without the detour is the clean way to
   prove it is engine-side.
5. `g_shutdown_game_stub` notifying GSC during `map`/shutdown is the leading N4 suspect; it is a
   pre-existing MWX hook, not touched this run.

## Handoff 8 (2026-11-25, night run end)

### Branch / state

- `opencode/autonomous` at `cead720d`, pushed. Working tree clean apart from nothing (all changes
  are in that commit).
- Build `BUILD OK` (last build includes `ph_props.cpp` and `model_bounds`). GSC check 0 problems.
- Game folder `mwx\` mirrors the new scripts/tests/tables (manual copies after the last build;
  `build-mwx.bat` does the same).
- Disk: check `Get-PSDrive C`; nothing deleted, all files stayed in `C:\Games\cod-hwm`.

### Exact next step

1. **PH round end**: `ph` still fails only "the round ended"/"winner". The mprops equivalent
   passes, so the elimination code works; compare the PH path (`ondeadevent` ->
   `propkilledend` -> 3 s -> `ph_endgame`) with what happens to `level.alivecount`/`livescount`
   when the last defender dies with the `ph_mayspawn` override. Debug with `gsc_eval` on a fresh
   server (print `level.alivecount`, `level.livescount`, `game["roundsPlayed"]`,
   `level.gameending`, `level.finalkillcam_winner` right after the kills). Note `gsc_eval` breaks
   the VM after a compile error ("main thread busy") - restart the server then.
2. **mprops prop kill**: mad props props may be invulnerable (`propsinvuln`); either wait for the
   invuln to end or drop that assertion (round/winner checks pass).
3. **Full `run_all_tests`** (20 tests) after the PH end is fixed; the two ph/mprops tests are in
   the manifest and take ~80 s each.
4. **More prop lists**: one server per map + `tools\ph-props\generate.ps1 -Map <map> -Port <port>`
   for the remaining `refs/maps/*/xmodels.txt` maps, then copy `data/mwx/ph_props/*` and rebuild.
5. **Party list**: add `ph`/`mprops` to `ui_scripts/gamemodes/__init__.lua` and take the MCP
   screenshot only after the round end works.
6. **N4**: guard the `shutdownGame_called` notify/VM use in `g_shutdown_game_stub`, then retry a
   DS started without a map + `map mp_rust`.
7. **N1b**: build without the `pm_player_trace_hook` and retry the `+map` client host.

### Open review items

- The 5 review items above (generated string table hash, `model_bounds`, `ph_mayspawn`,
  `pm_player_trace` hook, `g_shutdown_game_stub`).

## Run 2026-11-25 day (autonomous, opencode + DeepSeek)

Branch `opencode/autonomous` from `cead720d`, pulled (already up to date). Build: `build-branch.bat`
(`BUILD OK`). Another opencode instance may work on `hmw-workbench`; this run only touches
`C:\Games\cod-hwm\cod-mwx`, `refs` and this report.

### R1 - Prop Hunt rework (in progress)

**R1a - notify case (verified).** `_hodgepodge_ph.gsc` waits for the camel-case `"applyLoadout"`
(handleprop, givecustomloadout) while HMW's `_class` notifies `"applyloadout"`. A probe in
`mwx_hodgepodge.gsc` waits on both spellings and notifies the camel one once per match; the game
log reports `camelWait=1 lowerWait=0` (mp_crash, 25 props) - notify names are case-sensitive on
this build, so the timing theory is wrong. `ph_ensure_prop`'s 0.25 s re-notify loop is replaced
by one bridge thread per player (`ph_bridge`, started on "connected" and for connected players):
`for (;;) { self waittill("applyloadout"); self notify("applyLoadout"); }`.

**R1b - lives/limits root fix.** `gamemodes.cpp` now sets the `scr_<ref>_*` rule dvars before
the map loads (numeric dvars registered late; the string-dvar crash does not apply):
ph: timelimit 4, scorelimit 0, roundlimit 4, winlimit 3, numlives 1, roundswitch 1, halftime 0,
`scr_player_healthregen 0` and the mp_shipment 2.2 min + g_oldschool exception; mprops: same with
numlives 4; slasher: timelimit 10, numlives 1, hardpoints 0, `scr_game_mmUavTime 30`, oldschool;
rpg: oldschool. A normal gametype resets `g_oldschool` when it follows a party mode.
`setupdvars`/`setupdvarsmm` are replaced by copies that write `scr_<level.gametype>_*` (host
migration path included). Removed: the getgametypenumlives replacefunc, ph_mayspawn,
ph_watch_death, the pers["lives"] reset, the slasher level.numlives + scr_war_numlives workaround.

**R1c - round end.** With numlives 1 the normal `_gamelogic::updategameevents` elimination path
ends the round (diag: alive 0/0, lives 0/0 -> `level.gameending` 1 -> propkilledend -> ph_endgame,
map reload ~28 s later). The test now waits for `level.gameending`/`finalkillcam_winner`
instead of `level.gameended` (the reload killed the script before it saw that) and holds the bots
so a hunter bot cannot end the round during the loadout checks. mprops: the prop is invulnerable for
`scr_ph_madpropsInvulnTime` (default 29 s hide + 6 s invuln); the test sets
`scr_ph_madpropsHideTime 8` and waits the phase out (log line `mwx mprops test: invuln ...`).

Results so far (single runs): `ph` 12/12, `mprops` 10/10, `slasher` 17/17, `rpg` 6/6.

**R1d - prop lists.** `tools/ph-props/generate-all.ps1` starts one dedicated server per map that
has `refs/maps/<map>/xmodels.txt` and no CSV, reads `model_bounds` and runs
`generate.ps1`; it logs to `tools/ph-props/generate-all.log`. (running)

**Party list / screenshot:** pending the 3x runs.
**R1d progress:** 10 of the 29 missing maps are done (afghan, abandon, alpha, boneyard, bootleg,
bravo, brecourt, courtyard_ss, derail, dome, ...), 40 props each except mp_courtyard_ss (34); the
generator is still running. Script: `tools/ph-props/generate-all.ps1`.

### R2/R3 - code ready, verification pending

- `gameplay.cpp`: the PM_JitterPoint trace detour is no longer installed by default; it is behind
  `mwx_elevator_trace` (default 0) because it is the only MWX hook in the listen-host crash path.
  The assembly elevator hook (`pm_trace_stub`) stays for normal modes.
- `scripting.cpp`: `g_shutdown_game_stub` only notifies `shutdownGame_called` while a game is
  loaded (`SV_Loaded() || CL_IsCgameInitialized()`) and the level entity is valid, wrapped in
  try/catch; this is the R3 shutdown crash guard.
- Test to run after the build: `ph_listen` (new manifest entry, listen host + ph + 4 bots).

### R4 - five new party modes (code written, not tested)

Own scripts in `data/mwx/maps/mp/gametypes`: `sharpshooter.gsc` (TDM, same weapon for everyone,
rotates every `scr_sharpshooter_rotatetime` s = 45, perks at 5/10/15 kills), `reinforce.gsc`
(rounds, one life, scripted capture point respawns dead teammates, elimination wins the round),
`srescue.gsc` (S&D-style rounds, one life, tags revive/confirm), `mugger.gsc` (FFA, tags banked,
melee kills steal the bank), `arena.gsc` (rounds, one life, flag late in the round or down-to-one
wins the round). Registered in `gamemodes.cpp` (extra_gametypes + strings + objectives), Party
list in `ui_scripts/gamemodes/__init__.lua`; tests: sharpshooter/reinforce/srescue/mugger/arena
(27 tests total now).

Known deviations: the H1/HMW zones have no dog tag model (only `tag_origin`), so S&R and Mugger
use the universal Mad Props crate model as the tag placeholder; Reinforce/Arena use a scripted
capture zone in the map center with H1's domination flag model instead of dom's map flags. Both are
listed as open review items.

### R5 - focus independence (verified in code, measurement pending)

The input path (`CL_KeyEvent` / view angles) and the swap-chain screenshot never ask for window
focus; the test runner uses dedicated servers and GSC. `docs/mcp.md` documents it. The actual
movement/attack measurement with an unfocused client is pending the build.

### R6 - survival spike (prototype written)

`survival.gsc` (hidden unless `mwx_show_survival 1`): wave 1 = 5 humanoid agents via H1's
`maps\mp\agents\_agents::add_humanoid_agent("player", "axis", "class1")`, next wave 5 s after the
last agent dies, wave HUD, one life per player, match ends when all players are dead. Test
`survival`: wave 1 has 5 agents, killing them starts wave 2. `docs/survival-spike.md` still to
be written with the measurements (max agents, frame time, path nodes, inventory, milestones).
### R1d - prop lists (done, 2 maps blocked)

`tools/ph-props/generate-all.ps1` generated **26 new lists** (40 props each; mp_courtyard_ss 34) in
~50 minutes: abandon, afghan, alpha, boneyard, bootleg, bravo, brecourt, checkpoint, compact,
complex, courtyard_ss, derail, dome, estate, favela, fuel2, highrise, lambeth, mogadishu,
nightshift, plaza2, quarry, seatown, storm, subbase, trailerpark, underpass (plus afghan run
separately). data/mwx/ph_props now has 33 files. **Blocked:** mp_rundown and mp_underground
exit with code 0 before the map loads (same for both runs); their xmodels dumps exist, so retry with
a fresh server and the map log captured (next idea: start them via the MCP start_server to get the
console; likely a zone/pak issue with those two usermaps).

### R2 - listen-host crash (fixed by removing the detour)

`pm_player_trace_hook` (the R2 suspect) is no longer installed by default; it is behind
`mwx_elevator_trace` (default 0). The assembly elevator hook (`pm_trace_stub`) stays for normal
modes. A listen host on mp_crash with `g_gametype ph` + 4 bots ran several rounds (props set up,
rounds ended by elimination) with **no crash** in the no-detour build. `ph_listen` was removed
from the manifest because the MCP bridge in use predates the fix (it did not set `ui_gametype`,
so the test loaded war); `mcp.cpp` now sets `ui_gametype`/`ui_mapname` for listen tests, so
the entry can come back after a bridge restart.

### R3 - DS map command / shutdown

- Shutdown crash: `g_shutdown_game_stub` notifies `shutdownGame_called` only when
  `SV_Loaded() || CL_IsCgameInitialized()` and `*levelEntityId != 0` (try/catch around it). A DS
  started **without** a map now accepts `map mp_rust` and loads it (previous build crashed in the
  stub); a normal DS `quit` exits cleanly with no new minidump.
- Map-command hang: reproduced (mp_rust -> `map mp_terminal`: mp_terminal_load loads, the
  mp_terminal zone starts, d3dbsp + map GSC load, then the DB sync never completes; >4 min). The
  usermap path was wrong for a `map` command (only the party/startup flow called
  `fastfiles::set_usermap`); `find_usermap` now derives the usermap from `<map>.ff` /
  `<map>_load.ff` / `<map>.pak` and registers it. Assets now load, but the big zone still does
  not finish. **Open**; next ideas: compare `DB_LoadXAssets` sync flags on the `+map` vs `map`
  path, test `map_rotate` (the DS rotation path), and run the same command in `hmw-mod.exe` as a
  control.

### R4 - five new party modes (tests green)

| mode | test | result |
|---|---|---|
| sharpshooter | 7 checks | **7/7** (same weapon, 6 s rotation test, weapon changed) |
| reinforce | 8 checks | **8/8** (one life, capture respawns a dead teammate, elimination round end) |
| srescue | 7 checks | **7/7** (tag drop, teammate revive, round end) |
| mugger | 8 checks | **8/8** (tag drop + bank, melee steal) |
| arena | 6 checks | **6/6** (one life, flag spawns, elimination round end) |

Scripts: `data/mwx/maps/mp/gametypes/{sharpshooter,reinforce,srescue,mugger,arena}.gsc`; registered
as real extra gametypes (template rows war/dom/sd/dm), strings and objectives in `gamemodes.cpp`,
Party list in `ui_scripts/gamemodes/__init__.lua`. Deviations: no dog-tag model in H1/HMW zones
(only `tag_origin`), so S&R/Mugger use the universal Mad Props crate as the tag marker;
Reinforce/Arena use a scripted capture zone in the map center with H1's domination flag model.
Round ends use an explicit elimination watch (H1's `updategameevents` is skipped during the grace
period and only re-runs on the next death). **GSC gotcha found:** a bare `if (level.gameending)`
on an undefined variable was truthy in this build - all such guards now use
`maps\mp\_utility::is_true(...)` or an explicit `isdefined`. This was the srescue round-end bug.

### R5 - focus independence

`docs/mcp.md` documents that the input path (`CL_KeyEvent` / view angle writes), the swap-chain
screenshot and the test runner never need window focus; the runner starts dedicated servers with
redirected output and drives the game through GSC. The unfocused movement/attack measurement is
pending (one client run).

### R6 - survival spike

`docs/survival-spike.md` written. Key measurement: **`getmaxagents() == 0`** on HMW-MP
(dedicated mp_crash; sv_maxclients 18, scr_horde_maxagents 18), so H1's humanoid-agent framework
can never spawn: `add_humanoid_agent` returns undefined. This is an engine-side allocation gap,
not assets. The hidden `survival` prototype (mwx_show_survival 1) falls back to engine bots:
wave 1 spawns 5 enemies on axis, kills counted, wave counter on the HUD. **Open:** the wave 1 -> 2
transition did not fire in the test (the wave manager stops after wave 1; the bots die as
`MOD_SUICIDE` within 2 s). Path-node counts and the inventory are in the doc (TODO: fill the
path-node table).

### R7 - callsigns / player cards (partial)

Added `mwx_card_patch` / `mwx_card_backing` / `mwx_card_background` dvars, they are included
in the getInfo answer as the host's card, and `ui_scripts/lobby_card` now wraps
`Lobby.GetMemberPatch/GetMemberPatchbacking/GetMemberBackground` for member 0 to read them (the
white box still hides when all are 0). **Not done:** per-player wire format for every LAN client
(needs a userinfo/packet extension) and the visual verification in the private lobby. Documented as
partial in `docs/todo-callsigns.md`.
### R8 - full runs and test table

**Full run 1** (
un_all_tests, 26 tests): **25 green, 1 known failure** (survival: wave 1 -> 2
transition, see R6). Duration 39:54. Every other test passed with 0 script errors, including the
five new modes and all previous modes.

| test | map | passed | failed |
|---|---|---|---|
| infect | mp_shipment | 28 | 0 |
| infect_time | mp_shipment | 6 | 0 |
| war | mp_shipment | 12 | 0 |
| dm | mp_shipment | 12 | 0 |
| sd | mp_crash | 4 | 0 |
| dom | mp_crash | 4 | 0 |
| dz | mp_crash | 4 | 0 |
| slasher | mp_shipment | 17 | 0 |
| rpg | mp_shipment | 6 | 0 |
| oic | mp_shipment | 10 | 0 |
| aon | mp_shipment | 9 | 0 |
| cranked | mp_shipment | 13 | 0 |
| sas | mp_shipment | 8 | 0 |
| infect_rust | mp_rust | 28 | 0 |
| ph | mp_crash | 12 | 0 |
| ph_rust | mp_rust | 12 | 0 |
| ph_terminal | mp_terminal | 12 | 0 |
| mprops | mp_crash | 10 | 0 |
| sharpshooter | mp_shipment | 7 | 0 |
| reinforce | mp_crash | 8 | 0 |
| srescue | mp_crash | 7 | 0 |
| mugger | mp_shipment | 8 | 0 |
| arena | mp_crash | 6 | 0 |
| survival | mp_crash | 3 | 1 (wave 1 -> 2) |
| war_rust | mp_rust | 10 | 0 |
| war_terrace | mp_terrace (listen) | 12 | 0 |

**3x regression** (ph, mprops, slasher, 
pg each three times, 	ools\test\run-tests.ps1):
(filled after the background run.)
**3x regression results** (	ools\test\run-tests.ps1 -Name <t>, 2026-11-25 10:39-10:56):

| mode | run 1 | run 2 | run 3 |
|---|---|---|---|
| ph | 12/12 PASS (91 s) | 12/12 PASS (106 s) | 12/12 PASS (91 s) |
| mprops | 10/10 PASS (89 s) | 10/10 PASS (90 s) | 10/10 PASS (89 s) |
| slasher | 17/17 PASS (91 s) | 17/17 PASS (91 s) | 17/17 PASS (91 s) |
| rpg | 6/6 PASS (104 s) | 6/6 PASS (79 s) | 6/6 PASS (58 s) |

All 12 runs green, 0 script errors. The JSON summaries are in 	ools/test/test-results-*.json
(git-ignored).

### R1d final

ph/mprops are back in the Party list (ui_scripts/gamemodes/__init__.lua). The bulk generator's
two failures were transient: mp_rundown and mp_underground were started through the MCP
start_server and generated 40 props each, so **all 28 maps that have an xmodels dump now have a
prop list** (33 CSVs in data/mwx/ph_props, including the 6 map-own/fallback ones).

The prop screenshot: not taken yet (pending a client run; the dedicated-server tests cannot
screenshot). Tracked as the last R1 item.

### R5 final

- The **test runner** never needs window focus: 
un_test/
un_all_tests/
un-tests.ps1 start
  dedicated servers with redirected output and drive GSC; no input is injected, no window is
  foregrounded. Verified by all runs.
- The **input path** is focus-independent by construction (CL_KeyEvent, view-angle writes, swap
  chain screenshots; no GetForegroundWindow/raw input). During the measurement attempt the game
  window was confirmed **not** the foreground window (GetForegroundWindow = the opencode window,
  game hwnd "HorizonMW"), and input accepted commands, but the numeric pawn movement/ammo
  measurement could not be completed: a client that connects to a dedicated server hit
  `kicked for inactivity` during the ~2 min map load and then the server state, and the client's
  on-demand debug script failed to load afterwards (`could not load mwx/tests/_debug`). This is a
  tooling issue on *connected clients* (listen hosts and dedicated servers are fine; all 26 tests
  run on those). Documented in docs/mcp.md; next idea: send a 30 s +forward hold immediately at
  spawn (after cl_paused/prematch), or fix the client debug-script load.

### R6 final

docs/survival-spike.md is complete: measured getmaxagents() == 0 (agent framework blocked in
HMW-MP), bot fallback works for wave 1 (5 enemies, kills counted), wave 1 -> 2 transition open, map
inventory (7 h2-survival maps vs HMW), SP-only API list with replacement proposals, missing assets
(juggernaut/riot shield/dogs), and a 2-6 week milestone plan. Path nodes: stock MWR maps ship
<map>_path.ff (mp_crash 213 KB), HMW usermaps (rust/terminal/estate/favela) have no separate path
zone (bots still navigate there in the tests).

### R7 final (partial)

Local card dvars (mwx_card_patch/backing/background), the host's values in the getInfo answer, and
a ui_scripts/lobby_card wrapper for member 0 are in. Per-player LAN propagation (every client's
card on every other client) and the visual lobby check are **not done** (needs a userinfo/packet
extension and two clients); documented in docs/todo-callsigns.md.

### Done / blocked with commits

| commit | content |
|---|---|
| dc191850 | R1a-c: applyLoadout bridge, scr_<ref>_* rule dvars, ph/mprops/slasher/rpg limits, test fixes |
| d28072e | R2-R6: trace-detour gate, shutdown guard + usermap map-command fallback, five party modes, survival prototype, 26 generated prop lists |

**Blocked / open:**
1. R3 map <usermap> hang after a running DS (mp_rust -> mp_terminal): usermap resolution fixed,
   the big zone's DB load still does not complete; next ideas in the R3 section.
2. R6 wave 1 -> 2 (prototype): the wave manager thread stops after wave 1 (the fallback bots die as
   MOD_SUICIDE within 2 s); the agent path itself is engine-blocked (getmaxagents() == 0).
3. R5 numeric input measurement on a connected client (client debug script load / AFK kick).
4. R7 per-player card wire format + visual check.
5. R1 prop screenshot (needs a client with props).

### Open review items for Claude

1. **Rule dvars in C++** (gamemodes.cpp): the party modes now register `scr_<ref>_*` numeric
   dvars before the map load and set them on every `g_gametype` change. This is the root fix for
   the lives problem, but it means MWX mutates dvar values the engine normally owns; check that a
   later normal match gets sane values (`reset_mode_dvars` only resets `g_oldschool`).
2. **`if (undefined)` is truthy** in this build (found via srescue): `if (level.gameending)`
   returned true when the variable was undefined. All new scripts use
   `maps\mp\_utility::is_true(...)` / `isdefined` now. Existing scripts may have the same latent
   bug - worth a grep.
3. **`find_usermap` fallback** (astfiles.cpp): it now derives the usermap from any
   `<map>.ff|<map>_load.ff|<map>.pak` name. Check it cannot mis-resolve a stock map (it skips
   `is_stock_map`) and that a later stock map clears `current_usermap`.
4. **Trace detour off by default** (mwx_elevator_trace): elevators on custom maps need it; the
   listen-host crash was not reproducible *with* it in this run (no crash was seen either way), so
   the A/B proof is missing. If someone reports elevator breakage, the dvar is the switch.
5. **Survival/test hooks**: the new modes expose `mwx*` debug functions (capture/revive/endround)
   used by the tests; they are callable from any loaded script. Fine for LAN, but review whether
   they should be behind `mwx_test_mode`.
6. **R7 getInfo fields**: `mwx_card_*` now travel in the public getInfo answer; no names/XUIDs are
   included (host's card only).
**Full run 2** (
un_all_tests, 26 tests): **25 green, 1 known failure** (survival, same wave
1 -> 2 assertion; 39:24). Identical test set and results as run 1; every test 0 script errors.

| run | green | failed | duration |
|---|---|---|---|
| run 1 | 25/26 | survival (wave 1 -> 2) | 39:54 |
| run 2 | 25/26 | survival (wave 1 -> 2) | 39:24 |

The only failure in both runs is the survival prototype's wave transition (documented in R6); every
shipped mode, including all five new ones, is green in both full runs and in the 3x regression.

**Prop Hunt screenshot (MCP):** `_migration\archive\mwx-debug\autonomous\ph-prop-hunt.png` - a listen host on
mp_crash with g_gametype ph + 4 bots, taken through the debug screenshot method while the window
was not focused. The HUD shows "SPECTATING", the Prop Hunt round timer ("Whistle In: 0:12") and
"2: Props Alive"; the two props are the unarmed allies (the hunters had the p90 loadout).
## Autonomous run 2026-11-25 (single agent): STEP 0, A, B, C, D

Branch stack: `mwx` <- `opencode/fixes` (A+B) <- `aw-weapons` (C) <- `mwr-weapons` (D).

### STEP 0 - merge and cleanup (done)

- `origin/mwx` fast-forwarded `5cdcf64b..1ca2854e` from `opencode/autonomous` (the ancestor
  check passed); local `mwx` moved to `origin/mwx`; leftover `refs/remotes/local/aw-weapons` and
  `.git/stale-maintenance-lock-claude` removed. `opencode/fixes` created from `mwx`.

### A1 - parallel test runner

Measured with `tools\test\run-tests.ps1` on the pre-B build (`opencode/fixes` = `1ca2854e` +
runner changes):

| N | wall time | green | notes |
|---|---|---|---|
| 1 | **38:04** | 24/26 | `srescue`: net port 27036 still in use (environment); `survival`: known wave 1->2 (pre-B5) |
| 4 | **15:10** | 24/26 | same two: `srescue` port 27036 (Steam holds it), `survival` known |

Implementation: `-Parallel N` splits the manifest over N **child runner processes**; each child
runs exactly one test, with its own debug port, net port and log, and writes its own result JSON
which the parent merges in manifest order. The MCP `run_all_tests` got the same option
(`parallel`, default 1, max 8) with a worker pool. Two processes started <~30 s apart make the
second exit with no output, so both runners serialise process starts with a 30 s gap (6 s was not
enough; 30 s works). Default N=4 (2.5x faster, identical result); the net-port picker skips ports owned by other programs (Steam 27036).


### B - game modes (branch `opencode/fixes`)

| item | state | notes |
|---|---|---|
| B1 dvar leak | fixed | `gamemodes.cpp` remembers the pre-party value of `scr_player_healthregen`, `scr_game_hardpoints`, `scr_game_mmUavTime`, `g_oldschool` on first change and restores it in `reset_mode_dvars()`. `scr_player_healthregen` does not exist before Prop Hunt creates it; the fallback is 1 (regen on). New test `mode_reset` (listen host, 1 bot, `setdvar` because a console `set` does not reach the server on a listen host) - **14/14 green x3** |
| B2 mp_shipment | fixed | the C++ `on_map()` branch is gone; the GSC `ph_setupdvars_stub` applies timelimit 2.2 + oldschool. The replacement was installed **after** the first `setupdvars()` call, so `install_ph()` now invokes the stub once after `replacefunc()`. New `ph_shipment` test asserts both values |
| B3 ph_spawn_kick | fixed | `ph_bridge` sets `mwx_ph_forwarded` when it forwards `applyLoadout`; `ph_spawn_kick` clears it on `spawned_player` and sends the extra notify only when the bridge did not. Debug counters under `mwx_debug_gamemodes` |
| B4 elevator trace | done | the `pm_player_trace` detour is installed again for every mode; the stub skips `startsolid=false` when `mwx_gamemode` is `ph`/`mprops`. `mwx_elevator_trace` removed. `ph_listen` x3 green - the old listen-host crash did not return |
| B5 survival | **partially done, low priority per user** | `scr_survival_maxagents` was never set because survival is an *extra* gametype and `apply_gametype()` only looked at the party `modes` table. A direct `survival` branch now sets `scr_survival_maxagents` (string, because the engine `atoi`s `current.string`) and `scr_default_maxagents`; measured `getmaxagents()=10/24` and `level.agentarray` = 10/24. **Open:** the allocated agents never appear in `level.players`/`isalive`, so the wave spawns 0 fighting agents. The wave manager now retries instead of running the wave counter away. `mwx_survival_maxagents` dvar (0-24) added for the 10/20/30 measurements |
| B6 mp_terminal hang | pending experiment | `map mp_terminal` after `mp_rust`; script `_migration\archive\mwx-debug\autonomous\b6-terminal.ps1` |
| B7 probes | done | notify-case probe and the `if (undefined)` truthiness probe now run only with `mwx_debug_gamemodes 1`; result is logged |
| B8 AGENTS rules | done | applyloadout case, `scr_<gametype>_*` + restore rule, `giveperk(perk, 0)`, parallel runner + test rule |

Decision (user, 25 Nov): **Sticks and Stones is integrated natively** instead of keeping the mod. `data/mwx/maps/mp/gametypes/sas.gsc` is copied into the repo (header updated: crossbow from `hmw_aw_weapons.ff`), the mod stays as an archive only, and its `mod.ff` is not rebuilt. The native gametype entry/strings are enabled in part C, when the mod is no longer loaded.

---

## Menu work (U0-U4, 25/26 Nov night)

Pushed on `opencode/fixes`: `6068b68c` (Mugger), `5437c445` (U1/U2), `b000c6f1` (crash
traces/hardening), `573afae4` (mode fix + lazy UI load), `87cc433b` (U3 docs).

### U1/U2 - debug UI and MCP
- `ui_click` built `mwx_debug.click(id, nil, text)`, so a text click landed in the `index` argument;
  arguments are positional again. `ui_snapshot` gives unnamed widgets `<menu>#<n>` ids, nodes inherit
  the first caption below them, and a click on a label/background climbs to the named row.
- `ui_click`/`ui_open`/`ui_back` wait for the main thread, the queued action and an optional
  `expect_menu`/`expect_element`, then return the new top menu; `wait_ready` does the same standalone.
- `status`/`game_status` cache the last successful answer and return it with `stale_ms` while the
  main thread loads. Measured menu clicks: 130-200 ms.
- The first implementation sampled `get_status()` from a 1 Hz main-thread loop; that raced engine
  init and produced rare 0xC0000005 "fault offset 0" exits right after "client hooks installed"
  (no dump). The loop is gone; 10/10 cold starts afterwards (52-56 s each).

### Crash 0x1400BCB13 (M1/M2)
- `ui_scripting.cpp` writes `start/done/error` per LUI script to `mwx-logs\ui_script_load.log` and
  exposes `mwx_trace()` (append to `mwx-logs\ui_trace.log`, callable from Lua).
- The dangling starts were all `mwx/ui_scripts/gamemodes/__init__.lua`; its step trace stopped
  between `mod list` and `survival`, i.e. at `Engine.GetDvarString("mwx_show_survival")` in the load
  chunk (hks_start reloads every ui_script on a match start).
- Fix: the gamemodes chunk now only touches Lua/Cac tables at load; the party `List` (mod gametypes,
  survival dvar), the `Label` (localize) and the MatchRules/Lobby hooks are built lazily on the first
  menu read. `aw_maps` also probes `ControllerHasMap` at menu build, `lobby_card`/`mods` guard
  missing globals.
- Result: 5/5 menu smoke runs (16 modes x start/restart each) with no crash, no dump, no Lua error.

### Mode selection (U4)
- `MatchRules.SetData("gametype", ref)` validates against the `BaseGameMode` enum of
  `mp/commondata.ddl`: 16 values (`dm war ball sd dom conf ctf hp gun sab koth dd mugger infect
  gtnw dz`), stored as a **1-byte enum index** in `root.gametype` (240 free values). The enum's name
  table is a hash-sorted array, binary searched; the hash is `h = h*31 + tolower(c)` (checked against
  `dd` 0xC80, `sd` 0xE51, `war` 0x1CAE8).
- Extending the enum in memory (append + rebuild the sorted table) makes `SetData("ph")` return true
  and writes the value, but selecting such a mode crashed the client (0xC0000005 at
  `0x1400F59B2`): another system indexes by that enum and still assumes the original 16. Rejected and
  documented.
- Shipped: the Lua `MatchRules.SetData` wrapper records a pick **only while the mode menu is on top**
  (the engine re-applies the current match-rules gametype when a lobby/setup is built - recording that
  made the second start of `ph` run the previous `mugger`); a C++ `ui_gametype` dvar callback keeps
  `ui_gametype` at the pick while `xblive_privatematch`; a `Cbuf_AddText` hook applies it right
  before `xpartygo`. The lobby panel and loadscreen read `ui_gametype`, so both show the mode.
- Verified: PROP HUNT -> lobby "PROP HUNT" -> `g_gametype=ph`, `level.gametype=ph`,
  `mwx_gamemode=ph`; the pick survives leaving the match and re-entering the lobby; 5/5 smoke.

### Mugger description
- The stock gametypesTable already has a `mugger` row whose `MENU_MUGGER_DESC` key has no text in
  HMW's localization. `build_stringtable` now overwrites the description for every MWX ref that
  already has a stock row.

### U3 - menu/lobby load times
- `docs/menu-load-times.md` + `_migration\archive\mwx-debug\autonomous\u3-loads.ps1`. Startup ~55 s (hmw_* content
  zones ~30 s, common_mp 5.7 s, techsets 2.8 s, patch_common 3.2 s); first Play Online 4-9 s of
  vlobby zones (patch_mp_vlobby_room 0.3, techsets 1.3, room 1.0, room_path 1.5-5.6; cached later,
  ~1.3 s); private lobby/Game Setup/Mode no zone loads; menu-to-menu 130-200 ms.

### Test tools
- `tools\test\menu-smoke.ps1` (release check, `-Runs 5`; `-Quick -Modes ph,dom` for a fast pass).
- `_migration\archive\mwx-debug\autonomous\startup-loop.ps1` (cold-start loop), `u3-loads.ps1` (per-step load times).

### Open
- Game-mode hints showing the key (backlog 6): static check shows every `&"KEY"` has an override; the
  display path needs an in-game repro.
- Survival agents (backlog 14): slots are allocated and entities returned, but none reach
  `level.players`; next probe is the team/isai state (`survivalautoassign` may assign them as allies).

### Clean state (26 Nov 04:00)
- `tools\gsc-check\check-all.ps1`: 40 files, 573 calls, 0 problems.
- Full suite (`run-tests.ps1 -Parallel 4`): **28/29 GREEN** in ~19 min; only `survival` fails
  (wave 1 spawned 0 agents / wave 2: known R6c spike, user-deprioritised). `sas` and `mode_reset`
  and `ph_listen` all green.
- Menu smoke test 5/5 green (every Party mode + Domination/TDM, start + restart, Mods).
- Backlog and this report current; `opencode/fixes` pushed (`87cc433b`).

### Survival B5c (26 Nov 05:10)
- Dedicated `mp_crash`, `g_gametype survival`, one bot: `getmaxagents()`/`level.agentarray` = 24,
  `add_humanoid_agent` returns 5 entities with `team=axis pers=axis isactive=1 hasdied=0 isagent=1
  isai=1` but `isplayer=0`; `level.players` holds only the bot.
- A manual `spawnagent((0,0,0),(0,0,0))` on a free slot runs without error and does nothing: the
  engine's agent spawn is a **no-op in MP**. Not a team problem. Options: hook the engine behind
  `spawnagent`, or `spawnBot` + a GSC think layer (bots already work). Documented in
  `docs/survival-spike.md` (commit `37e806d3`).

### Items 6-7 (26 Nov, opencode/fixes)

**Item 6 - objective strings.** Root cause: the frontend localization table has no stock
`OBJECTIVES_*` keys (they load with the MP/gametype zones); the UI builds
`@OBJECTIVES_<lowercase ref>[_SCORE|_HINT]` from `GameX.GetGameMode()`, and MWX only had uppercase
entries for sas/infect/dz. In the main menu `Engine.Localize` returned the raw key; in a loaded map
the same call returned the text. Fix: `stock_objectives` in `gamemodes.cpp` (engine texts, both
cases, `&&1` kept) + both cases for sas/infect/dz. Verified in the frontend and in game (TDM
pregame: "First team to 75 wins."). `menu-smoke.ps1` now checks every
Party/Standard/infect/dz/sas `OBJECTIVES_<ref>[_SCORE|_HINT]` in the frontend.

Found while testing: `lua_eval` during a LUI reload crashed at `0x1400BCB13` (`hks_start` script
load or a DB zone load). `ui_scripting` now has a loading counter, `lua_eval` answers busy, the
smoke retries. The known silent startup exit (no dump) is retried too. Also found: a second
`DB_LoadXAssets` detour throws at startup (`renderer.cpp` already hooks it); the trace hook is now
split dedi (`fastfiles.cpp`) / client (`renderer.cpp`).

**Item 7 - Part B verification:** `mode_reset` 14/14 x3, `ph_shipment` green, `ph_listen` x3,
`ph_notify_probe` + `if (undefined)` behind `mwx_debug_gamemodes`, AGENTS.md rules. No code change
needed.

### Item 9 - DS `map mp_terminal` (26 Nov)

**Result: the hang does not reproduce.** `+map mp_rust` -> `map mp_terminal` loads the second map
and it runs: `Loaded custom gsc 'maps/mp/mp_terminal.gsc'`, `spawnBot 1` creates a bot and
`players` lists it on mp_terminal. The 785 MB zone loads in ~6 s warm.

Why the old reports said "hang": the completion check relied on the console log (buffered, the
`done mp_terminal ... (server running)` line is not in the file) and on `gsc_eval`, which fails
after a `map` switch with `compiler:...:3:12: couldn't determine function call type` for
`mwx_result` - a runtime `gsc::load_custom_script` compile failure (same class as the t1-build
listen-host issue, moved to item 13).

Instrumentation kept: `mwx_debug_fastfiles 1` logs every `DB_LoadXAssets` (zones, flags, sync
mode, caller, return) and the `scr_load_level`/`g_load_structs`/init+main handle progress. Clients
use renderer.cpp's existing DB detour, a dedicated server uses fastfiles.cpp's; installing both is
fatal (second detour on 0x397500 throws 0xE06D7363 at startup, seen as a dump loop). The trace is
in `docs/usermap-map-command.md`; the script is `_migration\archive\mwx-debug\autonomous\b6-terminal.ps1`.

### Item 10 - clean state (26 Nov)

- Full suite (`run-tests.ps1 -Parallel 4`): **28/29**, only `survival` fails (known R6c spike);
  every other mode green (infect, infect_time, war, dm, sd, dom, dz, rpg, slasher, aon, cranked,
  oic, sas, infect_rust, ph, ph_rust, ph_terminal, mprops, sharpshooter, reinforce, mugger,
  srescue, arena, ph_shipment, ph_listen, mode_reset/war_rust, war_terrace).
- Menu smoke: full run **PASS** (every Party mode + dom/war, start/restart, Mods). The smoke now
  reads static party/standard lists: reading `Cac.GameModes.Data.Party.List` calls
  `Engine.GetDvarString` from Lua, which can crash at 0x1400BCB13 in a frontend transition.
- check-all: 43 files, 575 calls, 0 problems.
- Pushed on `opencode/fixes`: `69112a31` (item 6), `7b32194e` (lua_eval guard + DB trace),
  `70e82583` (menu smoke static lists). Stack continues with `mwr-weapons` (`b4ffd1d0`).

### Item 12 - MWR weapons in CAC (26 Nov, branch mwr-weapons)

- Rows: the 28 MWR melee rows were appended to `stock_weapons_data.hpp` (71 rows), gated by the new
  `hmw_mwr_weapons` dvar; `mwr_weapons.cpp` adds the switch and the 28 real melee names; the GSC
  whitelist `data/mwx/scripts/mp/mwr_weapons.gsc` re-installs isvalidprimary/secondary/meleeweapon
  with the 11 DLC + 8 CoD4 + 28 melee refs after HMW's own replacefunc. Generic tests
  `mwr_weapon.gsc`/`mwr_melee.gsc`, 8 CoD4 manifest entries, `docs/mwr-weapons.md`, and the
  `asset_exists` debug RPC.
- **D0 runtime check (66 h1_*_mp): 27 present, 39 missing.** Missing = the 11 DLC guns and the 28
  melee weapons. They live in `zone\patch_common_mp.ff` (248 MB), which
  `hmw-mod\zone\hmw_patch_common_mp.ff` shadows; the engine never loads the MWR patch. Loading a
  copy of it as `mwr_dlc.ff` exits at startup (no dump, 0-byte log) - reverted.
- The 8 CoD4 guns (G3, M14, MP44, Skorpion, M60E4, M249, Dragunov, R700) are present and go
  through the rows + whitelist + tests. **BLOCKED (repack):** the 11 DLC guns and 28 melee need a
  zonetool repack of their assets from `refs\dumps\patch_common_mp` into a small `mwr_weapons.ff`,
  loaded like the HMW zones; then their rows/tests come back. Next idea recorded in BACKLOG.

### Item 13 - AW crossbow integration (26 Nov, branch aw-weapons)

- Loaded `hmw_aw_weapons` after the HMW zones (`patches.cpp`), added the crossbow statstable row
  (6100) and the AW name/desc overrides (`aw_weapons.cpp`), the AW whitelist/buildweaponname script,
  the CAC attach-kit/list glue and the AW tests (zone + tests copied from `cod-hmw-aw`).
- `aw_crossbow` **15/15 green** (CAC validity, statstable row/name, give, clip, fire, reload,
  switch, kill, camo/attachments). The crossbow is also a case in the MWR whitelist: both scripts
  replace isvalidsecondary and the delayed MWR replacement is the one that survives.
- Missing zone: renamed `zone\hmw_aw_weapons.ff` - the client starts, no crash, the crossbow asset
  is absent (hidden); restored.
- Converter patch applied (`--attachment-map`, anim override re-index, S1->H1 animTreeType).
- KF5 dropped in the AW plan and porting doc (`hmw-workbench` c42eb2a, pushed).
- Sticks and Stones: `mod.ff` backed up (`mod.ff.bak-20261126-0845-pre-reference`) and swapped to
  the 177-byte reference-only build; `aw_crossbow_sas` is in `tests-aw-sas.json`. The listen-host
  start with the mod stalls (blocked); next: run it on a dedicated server with `-mod` or fix the
  listen-host mod start.
- The t1-build `gsc::load_custom_script` crash/compile failure is the runtime-eval bug documented
  in item 9; the AW tests use map GSC and are not affected.
- Pushed `898a7b76`, `eb1d11db` on `aw-weapons`.

### Overall state (26 Nov, 09:00)

Branches (all pushed except where noted): `mwx` <- `opencode/fixes` (`69112a31`, `7b32194e`,
`70e82583`) <- `mwr-weapons` (`b4ffd1d0`, `392a019c`) <- `aw-weapons` (`898a7b76`, `eb1d11db`).

- **Items 6-10 done**: objective strings + menu check, Part B verification, DS map command
  (not a hang; runtime eval compile issue documented), suite 28/29, menu smoke PASS, check-all
  43 files/0 problems.
- **Item 12 partial**: the 8 CoD4 guns work (6 of 8 tests green; 2 hit the silent startup exit);
  the 11 DLC guns + 28 melee are BLOCKED - their assets are in the shadowed MWR patch, a zonetool
  repack into mwr_weapons.ff is the next idea (docs/mwr-weapons.md).
- **Item 13 crossbow done**: zone loaded, row/name/whitelist/CAC glue, aw_crossbow 15/15,
  missing-zone check, converter patch, KF5 dropped (hmw-workbench c42eb2a, no reachable origin).
  The SAS mod.ff is reference-only (backup kept); aw_crossbow_sas blocked on the listen-host mod
  start.
- **Item 14+ not started**: sources located (AW dump + zone source). Next: the pilot batch.
- Deployed `mwx.exe` = the aw-weapons build; the full suite is running on it.

### Checks on the aw-weapons build (26 Nov, ~09:45)

- `aw_crossbow` 15/15 green; six of eight `mwr_h1_*` tests green (2 hit the silent startup
  exit); menu smoke full run PASS; check-all 47 files / 585 calls / 0 problems.
- Full suite reported **27/28** green (only `survival`) before the 30-minute tool timeout; the
  remaining listen-host tests (ph_listen, mode_reset) were green on the previous build and are not
  touched by the AW item.
- Working tree clean on `aw-weapons` (`898a7b76`, `eb1d11db`).

### Item 14 - PILOT BLOCKED (26 Nov)

The AW install (`C:\Games\cod-hwm\Call of Duty Advanced Warfare`) is the **singleplayer** game; the
DLC gun models/anims live in the separate AW **Multiplayer** depot, which is not installed. The M1
Garand converts cleanly (`vm_m1garand_base`, `npc_m1garand_base`), but neither xmodel nor any
m1garand material/xanim exists in the AW dump or the zone source. Loading the weapon without them
would fail the zone build. Next idea: install the AW MP depot, `dumpzone h1 patch_common_mp` into
`GAME\zonetool\hmw_aw_weapons`, then run the pilot (M1 Garand, MP40, combat knife). The crossbow
assets came from the Sticks and Stones mod, not from the AW dump. Item 14 waits on the depot.

### Item A - silent startup exits fixed (26 Nov, branch opencode/fixes)

Reproduced on the deployed aw-weapons build: four `mwx.exe -dedicated ... +map mp_shipment`
started in the same second, three exited after 11-13.5 s with a 0-byte console log and no dump;
two started together lost one after 11.3 s. The survivors show `client hooks installed` at 12 s
and the first main-thread frame at ~23 s in `mwx-logs/load_times.log`; the failed starts stop
somewhere between `post_start` and the hooks. A 25 s stagger made all four survive, which matches
the old fixed-30 s workaround.

Fix `77df2843` on `opencode/fixes`:
- `load_timing::acquire_startup_lock` takes the named mutex `Local\mwx-startup-lock` in `main()`
  before `post_start` and releases it on the first main-thread frame (45 s watchdog, 180 s wait
  timeout, `WAIT_ABANDONED` handled so a crashed holder never wedges the next client). Map load
  and gameplay remain concurrent.
- `run-tests.ps1` starts the next parallel worker only after the previous game answers the debug
  RPC; the fixed 30 s sleep is gone. A silent startup exit is retried once (raw runner and menu
  smoke).
- `docs/testing.md` documents the cause and the mechanism.

Verification: four clients started in the same second all reached the menu after the fix
(measured startup-lock waits 22 s / 43 s / 67 s); a 4-test parallel manifest (war, dm, sd, dom)
passed 4/4. Full suite is running on this build.

A verification (full run, 26 Nov ~17:42): **27/29 green**. Only `sas` (known, part C:
"crossbow, hatchet and throwing knife" still uses the old mod pool) and `survival` (known
exception) failed; no silent startup exits, parallel workers started one at a time on the RPC
gate. Menu smoke runs separately to close A.

A close-out: menu smoke PASS (1 run, all party/standard modes). Item A done.

### Item B - MWR DLC weapons: zone built, loading BLOCKED (26 Nov, mwr-weapons)

Dumped the per-weapon model zones (87 zones, `GAME\dump\weapon_models`, 718 files/121 MB) and
built `hmw_mwr_weapons.ff` from the patch dump + models. Compile 8.8 s; zone 56.0 MB (full), 51.9 MB
(no images), 8.8 MB (weapon defs + anims), 3.0 MB (one weapon). Zone load 5-7 s; `asset_exists`
confirms all 39 weapon assets and the models.

**Blocker:** with the zone loaded, the next map load hangs at `imagefile48.pak` (2.24 GB) on both
`mp_crash` and `mp_shipment`; without the zone the same map loads imagefile48 in ~3 s. Reproduced
with all zone variants, a renamed weapon, and stripped attachments/icons/anims. The zone load
itself finishes; the map's image stream stalls. The zone is parked at
`GAME\zone\hmw_mwr_weapons.ff.blocked-b`, not in the startup list; the 12 new tests are out of
`tests.json`. Next: trace the stream/pool, load the zone after the map (or unload before `map`),
original patch, or direct `_tr` loading. See `docs/mwr-weapons.md`.

### Item C - Sticks and Stones is a native gametype (26 Nov, aw-weapons)

- `gamemodes.cpp`: the `sas` row is enabled (template dm, fixed loadout). The mode script is
  `data/mwx/maps/mp/gametypes/sas.gsc`; the crossbow comes from `hmw_aw_weapons.ff` (item 13).
- Removed `data/mods/sticksandstones` from the repo. Moved the installed
  `GAME\mods\sticksandstones` (mod.ff + all .bak files + maps + mod.json) to
  `_migration\archive\mwx-debug\backups\sticksandstones-mod`.
- Deleted `data/mwx/tests/aw_crossbow_sas.gsc` + `tests-aw-sas.json`; `aw_crossbow` covers the
  weapon. The `sas` test entry no longer sets `mod`; it asserts crossbow + hatchet + throwing
  knife and both bankruptcy rules. **sas 8/8 green x3; aw_crossbow 15/15 x3.**
- Mod system kept: `data/mods/test_mod` (mod.json + one `scripts/mp/test_mod.gsc`, no mod.ff, no
  weapons). Load, switch without a relaunch and unload verified from the debug console
  (`[mods] loaded mods/test_mod`, `switched ... without a relaunch`, `switched to no mod`).
- menu-smoke static Party/objective lists include `sas`.
- Docs: `docs/mods.md` (native sas + test mod), `hmw-workbench` `b228bd7` (AW plan rule: native
  sas, not the mod).
- Commit `26ffb9f2` on `aw-weapons`, pushed. Full suite + menu smoke running.

C suite (26 Nov, aw-weapons): the full run reached **26 green** (including sas 8/8 and
aw_crossbow 15/15), `survival` failed as known, `ph_listen` hit a child-runner/map-start timeout,
and the final batch of 8 item-12 MWR tests timed out with only 0.3 GB free RAM. `mode_reset` and
`aw_crossbow` were not reached. The suite was stopped and the affected tests are rerun with the
memory free; the definitive full suite is the final one on the last branch.

C blocker (26 Nov): `ph_listen` on `mp_crash` stalls at `imagefile48.pak` (2.24 GB) whenever
`hmw_aw_weapons.ff` is loaded; without the zone ph_listen passes 12/12 in 144 s. Reproduced with
the 19.8 MB crossbow zone, a 10.6 MB no-image rebuild (images + streamed_images removed) and a
sync `DB_LoadXAssets`; the stall is the custom-zone + mp_crash engine path. `sas` (8/8) and
`aw_crossbow` (15/15) on `mp_shipment` are green. This also explains B's imagefile48 hang and is a
release blocker; next ideas: load custom zones after the map / unload before `map`, or fix the
stream/pool path.

## Session status (26 Nov, stop point)

Pushed stack: `opencode/fixes` `77df2843` (A), `mwr-weapons` `582d53e6` (B partial), `aw-weapons` `26ffb9f2` (C, plus `095f12a3` merge). `hmw-workbench` `b228bd7`.

- **A done:** startup lock (4 close clients all up), runner RPC gate + silent-exit retry; suite 27/29 on the A build (sas then was the old mod failure, survival known); menu smoke PASS.
- **B BLOCKED:** `hmw_mwr_weapons.ff` built (56 MB full / 8.8 MB defs) and all 39 assets verified, but loading any variant makes the next map load stall at `imagefile48.pak`. Zone parked outside the startup list; 12 tests out of the manifest.
- **C feature done, release verification BLOCKED:** native `sas` (8/8 x3) and `aw_crossbow` (15/15 x3) green on `mp_shipment`; mod removed, test_mod verified. But `hmw_aw_weapons.ff` + `mp_crash` stalls at imagefile48 (`ph_listen` 12/12 without the zone). This is the same engine/custom-zone issue as B and blocks the full suite/menu smoke on `mp_crash`.
- **D not started:** AW model zones for the pilot exist (`mp_vm_m1garand_tr`, `mp_wm_m1garand_tr`, `mp_vm/mp40_tr`), weapon JSONs convert; no model/animation dump was attempted because the map-load blocker and the missing xanim path make the pilot untestable. Modern zones available: AK-12, ARX160, LSAT, MAAWS, Sten; CZ805/CBJ-MS/Ameli/Lynx/UTS-15/Grach/BLR/Blunderbuss/LeMat have no model zones.
- **E/F/H not started:** release prep and Ball need a working custom-zone/map path.

Next decision: fix the custom-zone + `imagefile48` map-load stall (load zones after the map / unload before `map`, or the engine stream/pool path) before adding more weapon zones or release prep.

## Step Z (26/27 Nov, aw-weapons) - custom-zone map-load stall

**DONE.** Root cause narrowed and fixed by shrinking the startup zone list.

- 9 startup zones load `mp_crash`; a 10th hangs at `imagefile48.pak` (2,138 MB) no matter what
  the 10th zone contains (172 B rawfile, 1.9 KB xanim, 19.8 MB AW zone, 56 MB MWR zone) and no
  matter the order (a/b/c table in `docs/zone-load-stall.md`). A byte copy of a loaded zone is
  not a usable "free" 10th zone: duplicate assets hang the menu load at `techsets_common_mp`.
- Not a lock: `stacks` (new debug RPC, walks every thread from the debug server thread) shows the
  main thread in the Windows message loop and a DB worker thread in a `SleepEx` retry loop
  (`h1_mp64_ship+0x3A1F42`). `g_zoneCount` stops at 43; no thread is in the pak reader.
  `h1_mp64_ship.exe` is Arxan-packed, so the exact engine counter is not identifiable.
- Unloading the three extra zones at map start (a first attempt) drops the resident count 32 -> 28
  and frees 719 MB, but `imagefile48` still hangs; the state is not repaired by unloading.
- Fix: startup = HMW's own 6 zones + `hmw_aw_weapons` = 7 zones. `hmw_nightshade`,
  `hmw_dlc_factions`, `hmw_dlc_killstreaks` (MWX-only, added in `d698d8ca` for the CAC list)
  are no longer loaded; their assets are missing from the Create-a-Class list (trade-off).
- Tests on the 7-zone build: `ph_listen` 12/12 x3 (142.1/130.3/131.2 s), `aw_crossbow` 15/15 x3
  (58.5/59.2/58.6 s), `sas` 8/8 x3 (56.3/55.9/56.6 s), `mp_crash` then `mp_shipment` in one
  client (43.4 s / 9.8 s). Startup process -> main menu 43.1 s (was 52-56 s with 9/10 zones).
- Harnesses: `tools/zone/swap-test.ps1` (zone-list experiments, live zone state,
  stacks), `second-map.ps1` (startup + two maps), `disasm.ps1`/`find-xref.ps1`.

### Step Z verification and follow-up fixes (27 Nov, aw-weapons)

- Full suite `-Parallel 2` on the 7-zone build: **GREEN 37/38**, only `survival` fails (known
  item B5: wave-1 agents 0/5). All gamemodes (party + standard), `ph_listen` 12/12 (135.5 s),
  `sas` 8/8, `aw_crossbow` 15/15, the 8 CoD4 MWR weapon tests pass.
- Menu smoke found two real gaps, both fixed:
  1. `sas` was missing from the Party mode list (`data/mwx/ui_scripts/gamemodes/__init__.lua`)
     -> the lobby chooser had no "Sticks and Stones"; added `"sas"` to `base_party`.
  2. HMW's `motd.lua` force-opens the MOTD popup in the virtual lobby and errors on the disabled
     marketing data (`attempt to index a * value`, MarketingComms.CanReadReserveData).
     `data/mwx/ui_scripts/motd/__init__.lua` now overrides `LUI.MOTD.TryForceOpenMOTD` to return
     false; no Lua errors in the lobby.
- Menu smoke `-Runs 1` PASS after the two fixes; the 3-run confirmation follows.

## Step B (27 Nov, aw-weapons) - MWR DLC + melee weapons

**DONE (core).** hmw_mwr_weapons.ff restored from the parked copy and loaded as the 8th startup
zone (with the step Z fix); mp_crash loads. Commit `58f7e324` pushed.

- 12 DLC/melee tests back in the manifest: **12/12 green x3** (11 guns 4/4 each, melee 4/4).
  mwr_melee fixes: melee weapons live in the melee slot (`hasweapon`, not `switchtoweapon`)
  and the player has a finite weapon-slot count - after 15 `giveweapon` calls it fails silently,
  so each weapon is taken away again.
- Create-a-Class never had the rows: (a) the appended `mp/customweapons.csv` rows had an empty
  `type` column (`Cac.Weapons[type][class]` needs Primary/Secondary/Lethal/Tactical) and (b)
  the CAC reads the row count once at UI load, before the zones load, so the appended rows were
  outside its loop. Fixed in `stock_weapons.cpp` (class -> type, keep rebuilding while rows are
  missing) and `data/mwx/ui_scripts/cac_weapons/__init__.lua` (fill missing refs on menu open).
- `Cac.Weapons` now holds 41/41 checked refs (39 MWR + 2 CoD4); screenshots per category in
  `_migration\\archive\\_migration\archive\mwx-debug\\mwr-weapons\\cac-*.png` (`cac-categories.ps1`).
- The menu smoke opens Create-a-Class and fails unless all 39 MWR refs are in the class lists.
- Full suite `-Parallel 2` (50 tests): **GREEN 49/50**, only `survival` fails (known B5).
  Menu smoke PASS.
- Not tonight (B rest): real names/icons/camos/attachments matrix, duplicates vs the AW PORT list,
  party-mode weapon pools, memory/load-time with both zones.

## Step D (27 Nov, aw-weapons) - AW pilot

- Pilot folded into **hmw_aw_weapons.ff** (crossbow + M1 Garand + MP40), 23.2 MB + 15 MB pak; no
  new startup zone (8 total). `hmw_aw_pilot.ff` moved to `_migration\archive\mwx-debug\backups\zone\`.
- Weapons: `dumpzone h2 patch_common_mp` + `s1_weapon_to_h1.py`; anims via
  `use_hmw_anims.py` (M1 Garand -> M14, MP40 -> MP44; the S1 dumper writes no xanims for H1).
  Models from the `mp_vm/mp_wm_*_tr` dumps.
- Materials: AW `patch_common_mp` materials; only the images in each material's `textureTable`
  are collected from the h1 image dump (the full dump is 6.7 GB; the dump folders were removed
  after collecting). Missing techset names are mapped to an existing techset - a bulk material
  copy makes the build fatal (`mtl_player_emblem` techset missing).
- Rows/names/whitelist: `eab22750`. Verified on the folded zone: aw_m1garand 6/6, aw_mp40 6/6,
  aw_crossbow 15/15 x3.
- Knife: model/tr zone not found yet (`mp_vm_tacticalknife_tr` does not exist); row, name,
  whitelist and test are in the tree, test fails until the model is found.
- Paused after the pilot for the user's manual test.

### Step D pilot - textures and HUD name (27 Nov)

- The first texture attempt copied only the `.h1Image` headers; the game fataled with
  `Create2DTexture(...) failed`. The streamed payloads are `<name>_streamN.pixels` next to the
  header; the collector now copies both (130 files, 26 images), the zone pak grew 15 -> 51.9 MB and
  the M1 Garand renders textured in first person (screenshot
  `_migration\\archive\\_migration\archive\mwx-debug\\aw-weapons\\aw-pilot-m1garand-fp2.png`).
- HUD showed UNKNOWN: the in-game name comes from the AW weapon def's `szDisplayName` key
  (`MDLC6_DLCGUN23`), not the statstable row; aw_weapons.cpp now overrides the AW keys too.
- The 6.7 GB `dumpzone h1 patch_common_mp image` dump was removed after collecting (23 GB free).
- Verified: aw_crossbow 15/15, aw_m1garand 6/6, aw_mp40 6/6 green on the textured zone.

### Step D pilot - final state before the manual test (27 Nov)

- hmw_aw_weapons.ff: crossbow + M1 Garand (iw5_dlcgun23) + MP40 (iw5_dlcgun18), textured
  (22.1 MB ff + 51.9 MB pak), 8 startup zones.
- Real names in the CAC and the HUD (the AW def keys MDLC6_DLCGUN23 / MDLC5_DLCGUN18 are
  overridden), statstable rows 6200/6201, whitelist entries.
- First-person screenshot with the M1 Garand in hand: _migration\archive\mwx-debug\aw-weapons\aw-pilot-m1garand-hud4.png
- Green: aw_crossbow 15/15, aw_m1garand 6/6, aw_mp40 6/6 (on the textured zone).
- Commits on aw-weapons: eab22750 (rows/names/whitelist/tests), 2178f083 (HUD names + recipe doc).
- Combat knife: row/name/whitelist/test are in the tree; the model/xsurfaces are missing
  (mp_vm_tacticalknife_tr does not exist; the xmb is in the AW common_mp dump but not its
  xsurfaces). Paused before fixing it.

PAUSED for the user's manual test per request.

## Cleanup run 27 Nov - CAC + just play

- 1.1 eebcab0e: mwr zone restored, 19 animation copies documented in overrides, AW zone rebuilt
  clean (76 shared assets removed), both zones zone-check green (841 / 20 assets, 0 collisions).
- 1.2 31765007: AW previews work in the lobby (hook moved to scripts/mp_patches). M1/MP40
  previews render but are washed out; crossbow correct.
- 1.3 41213dfb: weapon stats off in matches (disableweaponstats), players2 byte-identical after
  a 40 s match with 5 bots.
- CAC selection works end to end (enum extension): M1 Garand / MP40 picked through the menu and
  read back from the class. Zone index covers 10 zones; 6 still to dump for zone-check.

## Cleanup run 27 Nov - final Part 1 state (before review)

- CAC: all 71 custom weapons verified (cac-smoke: 44 guns through the menu, 20 melee via the
  storage path + list membership, 3 AW; HMW preview/attachments/camos screens). The class is stored
  through the extended playerdata Weapon enum (docs/cac-weapon-enum.md); 270/270 refs storable.
- Zones: hmw_aw_weapons rebuilt with the shared FX/physics/view-model-anim assets removed
  (zone-check 0 collisions); hmw_mwr_weapons restored with the 19 animation copies documented in
  overrides.txt. Zone-check index: 10 prior zones.
- Combat knife ported (surfaces via dumpzone h1 common_mp xmodelsurfs), w_knife 5/5.
- Weapon stats off (players2 byte-identical after a match); AW previews work in the lobby.
- F4 (CAC LUI list limit): ~55 open/close cycles per lobby visit (stock 56), resets at a map load,
  documented; 40-cycle stress test green.
- Screenshot R/B fix: red/brown now correct in the PNGs (verified on the M1 stock + extinguisher).
- Weapon icon renderer built (hmw-workbench MCP); conversion blocked on workbench-side grid/asset-root
  and a PNG->h1Image writer (docs/weapon-icons.md).

## Part 1 close-out (27 Nov evening) - stop before Part 2

### Final test tally (build 67ba7852, zone pair rebuilt today)

- Full suite, 53 tests, two passes on the same build and zone (the parallel parent hung on two
  workers, so the remaining 22 were run from a filtered manifest; same code, same zones):
  - pass 1 (17:36-18:14, 29 tests): 28 green; survival FAIL (known B5 wave spawn); war and
    ph_terminal aborted by the runner bug (F2).
  - pass 2 (19:02-19:29, 22 tests): 21 green; aw_m1garand F2 (dedicated server exited while loading
    patch_mp_shipment).
  - retries alone: aw_m1garand 6/6 PASS, war 12/12 PASS, ph_terminal 9/12 -> crash, then 12/12 PASS.
  - **Result: 52 of 53 green.** Only survival is red (known B5, does not affect CAC/weapons).
    ph_terminal is green but crashed in 2 of 3 runs (heap free on a thread-pool thread, F2).
- menu-smoke on the final build/zone: 4 runs, 3 PASS, 0 crashes; the one failure is the known
  second-start mode pick ("Party ph: second start g_gametype is 'mugger'"). Before the
  aw_weapons load-chunk change the same build/zone crashed 2 of 4 runs at 0x1400BCB13.
- cac-warnings (e2, fixed screenshot writer): **0 warnings** in 218 console lines.
- CAC: 71/71 custom weapons verified earlier today; 40-cycle open/close stress test PASS.
- Zone-check: hmw_aw_weapons **848 assets, 0 collisions** (18.3 MB ff + 51.8 MB pak);
  hmw_mwr_weapons restored (58.7 MB) with 19 animation copies in overrides.txt.

### Items

| item | state |
|---|---|
| 1.1 zone collisions | done (eebcab0e) |
| 1.2 AW 3D previews in the lobby | done (31765007); M1/MP40 washed out (polish) |
| 1.3 no weapon-stat saving | done (41213dfb); players2 byte-identical after a bot match |
| 1.4 CAC weapon enum | done (d85fc004, docs/cac-weapon-enum.md); 270/270 refs storable |
| 1.5 hidden/assetless rows | done (8d79fac8) |
| 1.6 all 71 custom rows | done (67ba7852); cac-smoke matrix + stress |
| 1.7 combat knife | done (4e6794c0, f359a964); aw_knife 5/5; textures still missing |
| F4 CAC list limit | measured and documented: ~55 open/close per lobby visit (stock 56), resets at a map load; no fix |
| 1.8.1 screenshot R/B | done (eadd5414); reference shots cac-warn-e2-*.png at 17:36 show brown M1 stock, red extinguisher, gold accents |
| 1.8.2 visual issues | **partial**: yellow striped MAC-10 rows = HMW not-owned/loot marker (2.1 turns unlocks on); red FX placeholders did not reproduce with the current zones; the static model audit is inconclusive (MWR models live in undumped mp_vm_* zones) - runtime asset_exists pass and the last 6 zone dumps still open |
| 1.8.3 weapon icons | renderer done (4d9932f2, docs/weapon-icons.md, AW plan line); PNG -> .h1Image conversion blocked on the workbench side (orbit grid, AW asset root) |

### Bugs found while closing (logged, not fixed here)

- **menu/LUI load crash regression** (first item next session, with F2): 0xC0000005 at 0x1400BCB13
  in menu-smoke; the only new load-time engine call in a ui_script since 573afae4 was the
  aw_weapons gate, removed in ac1c8bbc; 0 crashes in 4 runs after that, but 573afae4 was not
  re-measured and the dump is not symbolised. Full analysis:
  _migration\archive\mwx-debug\menu-load-regression-2026-11-27.md.
- **parallel runner**: a child whose server exits without test_done threw in ConvertTo-Json and
  never wrote a result file, so the parent waited forever. Fixed in 9c646124 (flat fallback).
- **stale-zone trap**: _migration\archive\mwx-debug\cac-bisect\variant.ps1 -Variant e restored a snapshot taken before
  the knife build/cleanup, silently undoing a rebuilt zone (it made aw_knife fail the suite and
  invalidated one warning run). It now has a -Snapshot switch and a warning in the header.
- **F2 dedicated crashes**: war (mp_shipment), ph_terminal (mp_terminal, 2/3), aw_m1garand
  (mp_shipment once) exit with a heap-free 0xC0000005 on a thread-pool/RPC thread. Candidate new
  writers into engine tables: the statstable/customweapons string-table copy and the DDL weapon
  enum extension (both run on dedicated servers). Next session: mwx_cac_enum 0 run + PDB stack.

### State on disk / git

- Branch aw-weapons, pushed through e6abecbb. GAME\mwx mirrors data\mwx exactly (hash check, 91
  files, 0 differences). Zones current. Free space >= 20 GB.
- players2 backups under players2_backups\ (class writes are tested with backups first).
