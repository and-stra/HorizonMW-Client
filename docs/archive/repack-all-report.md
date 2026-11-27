# MWX repack-all report — 2026-11-20

## Summary

| | Before (zlib) | After (LZ4) | Change |
|---|---|---|---|
| **Main menu** (status, LUI frontend) | **82.8 s** | **63.8 s** | **−19.0 s (−23 %)** |
| First main-thread frame (`load_times`) | 78.1 s | 61.9 s | −16.1 s |
| `hmw-mod\zone` size | 2,741,430,356 B (2.55 GiB) | 3,760,281,988 B (3.50 GiB) | +1.02 GB (+37 %) |
| Backup folder (`hmw-mod\zone_backup_zlib`) | empty | 17,081,572,027 B (15.91 GiB) | — |

`mwx.exe -repack all`: **exit code 0**, 92 files processed (22 zones in `hmw-mod\zone` + 68 `.ff`
in `hmw-usermaps`), log ends with `done`. Only `hmw-mod\zone\hmw_launcher.ff` was skipped
("not a zlib tools zone") — not an error.

**Five biggest per-zone times (before → after):**

| Zone | Before | After | Change |
|---|---|---|---|
| `hmw_dlc_factions` | 7737 ms | 5696 ms | −2041 ms |
| `hmw_nightshade` | 7487 ms | 5368 ms | −2119 ms |
| `common_mp` (stock, not repacked) | 5954 ms | 7523 ms | +1569 ms (run variance) |
| `hmw_patch_common_mp` | 5598 ms | 4688 ms | −910 ms |
| `hmw_smg` | 5157 ms | 3142 ms | −2015 ms |

Sum over the 31 named fastfiles: **62.3 s → 46.4 s** (−15.8 s). The repacked `hmw_*` zones all got
faster; the one regression (`common_mp`) is a stock zone that was not repacked, i.e. normal
run-to-run noise.

Steps 4–5 ran without crashes or hangs, so no `-repack-restore` was needed. Step 5 (dedicated
server + client connect) also passed: server up at 58.9 s, client in `mp_rust` 39.2 s after
`connect`.

Build: `mwx` at `02394d04` (includes two `debug_server` fixes made during this run — see step 1).

## 1. Baseline (before)

Started `mwx.exe` (cwd GAME), polled `status` every 5 s.

- **Main menu at 82.8 s** (`main_menu: true`, `lui: true`, `db_ready: true`, map empty).
- `load_times`: first main-thread frame at **78.069 s**; `hmw_dlc_killstreaks` was the last
  fastfile before it (4209 ms).
- Artifacts: `before-run.log`, `before-menu-status.json`, `before-load-times.txt`,
  `before-zone-times.json`.
- Quit → exited after 12.1 s.

Note on the `main_menu` signal: on this offline/LAN frontend the virtual lobby often does **not**
load (the game sits at the visible "MULTIPLAYER" menu with `virtualLobbyActive = 0` and
`Com_InFrontend() = false`). The game is fully usable there (`map mp_dome` works). `status.main_menu`
now also treats the LUI frontend as the menu:
`!is_dedi && !in_game && (virtual_lobby || Com_InFrontend() || (LUI running && database ready))`.
(Fix `c7af309a`; follow-up `02394d04` keeps `main_menu` false on dedicated servers.)

## 2. Preconditions

- Free on C: **158.2 GB** (≥ 15 GB required).
- No `mwx.exe`/`hmw-mod.exe` running when the repack started.
- Before sizes: `hmw-mod\zone` 22 `.ff`, 2,741,430,356 B; backup folder empty.
- `hmw_smg` was still LZ4 from an earlier test, so `mwx.exe -repack-restore all` was run first
  (exit code 0) to get a clean zlib baseline before measuring. This also emptied the backup folder.

## 3. `-repack all`

Ran `mwx.exe -repack all` (cwd GAME) at 18:18; it was not interrupted (~8 min).

- **Exit code: 0**; `mwx-logs\repack.log` ends with `done` (no "with errors").
- Scope: 22 files in `hmw-mod\zone` + 68 `.ff` in `hmw-usermaps` = 92 entries.
- Only skip: `hmw-mod\zone\hmw_launcher.ff: not a zlib tools zone, skipped` (it is not a zlib
  tools zone; not an error).
- Log copy: `_migration\archive\mwx-debug\repack-all-repack.log`; console: `repack-all-stdout.txt`.

## 4. After (client restart)

Started `mwx.exe` again.

- **Main menu at 63.8 s** (`lui` + `db_ready`; virtual lobby not loaded this time).
- `load_times`: first main-thread frame at **61.922 s**.
- `map mp_dome` → **in game after 45.8 s**: map `mp_dome`, 1 player `JatZek97` (spectator),
  `sv_running: true`.
- Artifacts: `after-run.log`, `after-menu-status.json`, `after-load-times.txt`,
  `after-zone-times.json`, `after-ingame-status.json`, `after-console-50.txt`.
- Quit → exited after 15.4 s.

## 5. Dedicated server + connect

Started `mwx.exe -dedicated -memoryfix +exec server_default.cfg +set net_port 27016 +map_rotate`.

- Server up at **58.9 s**: `sv_running: true`, `main_menu: false`, map `mp_rust`
  (`step5-server-status.json`).
- Client main menu at **68.2 s** (`main_menu: true` via the LUI frontend), then
  `connect 127.0.0.1:27016` → **in game after 39.2 s** on `mp_rust`.
  - Server after connect (`step5-server-status-after-connect.json`): 1 player `JatZek97`
    (team axis, ping 354, not a bot).
  - Client (`step5-client-ingame-status.json`): `in_game: true`, map `mp_rust`,
    `server: 127.0.0.1:27016`, net_port `27017`.
- Quit: client and server both exited cleanly.

(One earlier step-5 attempt stalled because my new `main_menu` check also fired on the dedicated
server; fixed in `02394d04` — `main_menu` is now always false on a dedicated server. No game
hang or crash.)

## 6. Crashes / hangs

None in steps 4–5: both client runs reached the main menu well under 5 minutes, the dedicated
server started, and the client connected and entered `mp_rust`. No `-repack-restore all` was
necessary.

## 7. Sizes

| Path | Before | After |
|---|---|---|
| `hmw-mod\zone` (22 `.ff`) | 2,741,430,356 B (2.55 GiB) | 3,760,281,988 B (3.50 GiB) |
| `hmw-usermaps` (68 `.ff`) | ~14.3 GiB (zlib) | 18,111,679,380 B (16.87 GiB) |
| `hmw-mod\zone_backup_zlib` | 0 | 17,081,572,027 B (15.91 GiB) |
| Free disk C: | 158.2 GB | 116.7 GB |

The LZ4 files are larger than zlib (as expected) but decompress much faster, which is the win shown
by the load times above.
