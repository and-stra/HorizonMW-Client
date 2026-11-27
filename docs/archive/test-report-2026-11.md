# MWX test report — 2026-11-20

## Summary

| Step | Result | Notes |
|---|---|---|
| 1. Build | ✅ BUILD OK | 3 fixes committed (see below) |
| 2. MCP smoke test | ✅ 9 tools | initialize + tools/list answered |
| 3. Client start | ✅ main menu ~110 s | virtual lobby loads normally |
| 4. In game `mp_dome` | ✅ in game ~17 s | 1 player, quit cleanly |
| 5. Dedicated server + connect | ✅ in game ~11 s (mp_rust) | needed 1 fix (getInfo handshake) |
| 6. Repack `hmw_smg` | ✅ works | load time **8508 ms → 3113 ms**; repack process crashes on exit (see below) |

Fixes committed on `mwx`:
- `bff08a11` — `debug_server`: include `<future>` (build break).
- `cbdd34a0` — `debug_server`: `main_menu` also true on the offline frontend (not only when the virtual lobby loads).
- `19e58a09` — fix the UDP `getInfo` handshake dropping empty info-string values (broke connecting to a dedicated server).

Two non-fatal issues found (reported, not blocking): the `mwx.exe -repack` process exits with
`0xC0000409` after finishing its work, and `mwx.exe -mcp` exits with code 1 after stdin closes.

## 1. Build

`build-mwx.bat`: fast-forwarded `mwx` to `claude/mwx` (4 commits: Milestone 5 debug server/MCP,
Milestone 6 repacker, docs), then built Release x64.

- First run failed: `src/client/component/debug_server.cpp(40)`: `C2039 "promise" ist kein Member
  von "std"` (missing `<future>`). Fix `bff08a11`.
- Second run: **BUILD OK**, `mwx.exe` copied into the game folder.
- Later fixes `cbdd34a0` (step 3) and `19e58a09` (step 5), each followed by a rebuild.

## 2. MCP smoke test

Both lines got a JSON-RPC answer:

- `initialize` → `serverInfo {name: "mwx", version: "bff08a11..."}`, protocol `2025-06-18`.
- `tools/list` → **9 tools**: `game_status`, `run_command`, `get_dvar`, `set_dvar`,
  `console_log`, `load_times`, `start_game`, `stop_game`, `wait_for`.

Raw output: `_migration\archive\mwx-debug\mcp-smoke.txt`. The MCP process exits with code 1 after stdin is closed
(after answering both requests).

## 3. Client start

Started `mwx.exe` (working directory = GAME) at 16:37:22.

- **Main menu reached after 110 s** (`status.main_menu` becomes true; `load_times` marks
  `main menu (virtual lobby loaded)` at **107.022 s**).
- Virtual lobby loads normally: map `mp_vlobby_room`, `virtual_lobby: true`, `frontend: false`.
- Artifacts: `step34.log`, `step3-mainmenu-status.json`, `step3-load-times.json`.

Finding that led to `cbdd34a0`: one start sat at the **visible** "MULTIPLAYER" menu (screenshot
`gamewindow.png`) with `virtualLobbyActive/Presentable/Ready = 0`, so `VirtualLobby_Loaded()`
stayed false and `status.main_menu` reported false for >7 minutes. `main_menu` now also considers
`Com_InFrontend()`; `virtual_lobby` and `frontend` are exposed separately in `status`.

## 4. In game (`map mp_dome`)

- Command sent from the main menu; **in game after 17.3 s**.
- Status: map `mp_dome`, `in_game: true`, `sv_running: true`, gametype `war`, 1 player
  `JatZek97` (team spectator, score 0, ping 27, not a bot). (`step4-ingame-status.json`)
- Last 50 console lines: `step4-console-50.txt` (mp_dome load = 9480 ms, then "cheat protected"
  dvar warnings).
- `quit` → process exited after 10.1 s.

## 5. Dedicated server + connect

Started `mwx.exe -dedicated -memoryfix +exec server_default.cfg +set net_port 27016 +map_rotate`.

- Server up at **66 s**: `sv_running: true`, `main_menu: false`, map `mp_rust`
  (`step5-server-status.json`).
- Client main menu at **166.7 s**; `connect 127.0.0.1:27016` → **in game after 10.9 s** on
  `mp_rust`.
  - Client (`step5-client-ingame-status.json`): `in_game: true`, map `mp_rust`,
    `server: 127.0.0.1:27016`, net_port `27017`.
  - Server after connect (`step5-server-status-after-connect.json`): 1 player `JatZek97`
    (team allies, ping 15, not a bot).
- Quit: server exited cleanly; the client did not exit within 15 s and was force-killed.

**Bug found & fixed (`19e58a09`):** the first connect attempt stayed in the virtual lobby with
console errors — `[json.exception.type_error.302] type must be string, but is null` (and, in an
earlier run, `string too long`). Root cause: the server answers the UDP `getInfo` handshake with
an info string whose optional fields (`fs_game`, `sv_motd`, `sv_wwwBaseUrl`, `sv_discordImage*`)
are empty. `utils::info_string::parse()` split on `\` with `utils::string::split`, which drops the
empty field after a trailing `\`, so whichever empty-valued key came last vanished; the client then
read that key as JSON `null` and threw. Fix: keep a sentinel delimiter in `parse()` so the trailing
empty value is preserved, and read the optional fields with `json.value(key, "")` in
`connect_to_server_tcp` / `check_download_mod_tcp`. After the fix the connect console is clean
(no `too long` / `type_error` lines).

## 6. Repack test (`hmw_smg`)

- Free disk before repack: **56 GB** (>= 5 GB required).
- `mwx.exe -repack hmw_smg`: `hmw-mod/zone/hmw_smg.ff` **299 MB zlib → 413 MB LZ4** (image
  885 MB) in **4.9 s**, original backed up to `hmw-mod/zone_backup_zlib/`.
  Full log: `step6-repack.log.txt` / `mwx-logs\repack.log`.
- Client started and reached the main menu after **108.1 s** — the repacked `hmw_smg` loads fine
  (no crash/hang while loading it).
- `load_times` `hmw_smg` line: **before 8508 ms → after 3113 ms** (~63% faster).
  (`step6-load-times.txt`; note the recent un-repacked runs in `load_times.log` measured
  ~4.5–4.9 s, still clearly above the repacked 3.1 s.)

**Finding (not blocking):** the `mwx.exe -repack` process finishes its work (writes the file and
logs `done`) but then **exits with `0xC0000409`** (stack-buffer-overrun fast-fail) during
teardown — reproducible even with `-repack` of a non-existent zone, so it is independent of the
actual compression. The repacked fastfile is valid (the game loads it), but the process exit code
is non-zero.

## 7. Notes / follow-ups

- `+exec server_default.cfg` resolves because the file exists under `server_default\`; the dedicated
  server found and ran it (hostname `Birkenau`, map rotation active).
- The repacked `hmw_smg.ff` was left in place (with the zlib original in
  `hmw-mod/zone_backup_zlib/`) for a manual comparison, as requested. `-repack all` was **not** run.
- Minor: `mwx.exe -mcp` returns exit code 1 when stdin closes; the client (game) process sometimes
  needs to be force-killed after `quit` when it was connected to a dedicated server.
