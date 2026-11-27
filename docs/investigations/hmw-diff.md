# hmw-mod.exe v1.6.7 vs. our client (last open-source HMW, Oct 2024)

Source: Ghidra export of a copy of hmw-mod.exe (SHA256 940E70C7...FDB8, 12,902 functions, 59,326
strings) in `C:\Games\cod-hwm\refs\hmw_decomp\`, plus HMW's zone rawfiles (`hmw_files.ff`).
Method: every string that the exe references but our source does not contain (5,781, mostly
libraries) -> filtered to game/client logic. We take over behaviour only, never their code.
Game functions are called as `game base + offset` (like our `_b` addresses), so offsets can be
matched against our `symbols.hpp`.

New libraries in the exe: ImGui (overlay UI), SDL (gamepad), protobuf, curl.

## A. Online services (not needed for LAN -> skip)
Matchmaking ("Finding best canidate server", master server), account login (Directus, Discord,
email), anti-cheat flags ("Anticheat Protected", "Your server has been blocked"), auto updater
(manifest, CDN, `cg_auto_update`), UPnP port forwarding (`upnp_enable`), Discord avatars.

## B. Server browser (ImGui)
HMW's current zone script builds `menu_systemlink_join` with `imgui:openServerBrowser()`; the exe
has a new ImGui browser: favourites, history, direct connect ("Enter Server IP:Port"), filters
(game mode, map, max ping, empty/full), player list, "Copy connect command", version check
("The server is running a different version than your client"). Our client restores the old
feeder-based LUI browser (gamemodes phase 2e). Candidates for later: direct connect, version check.

## C. Gameplay / settings (new dvars and options)
- Input: `m_rawinput` (raw mouse input, bypasses Windows acceleration), `m_ads_sensitivity_scale`
  (ADS sensitivity multiplier), gamepad via SDL with `ui_controllerIconDisplayType`.
- Visuals: custom red-dot reticle brightness, HUD color (RGB), `cg_overheadIconSize`,
  `cg_overheadRankSize`, `ui_score_popup_style`, `r_rimLightUseTweaks`.
- Movement/gameplay toggles: MW3-style slide, double bouncing, disable collision clips on
  barriers, max jump height, `player_view_pitch_up/down`, `bg_prone_yawcap`, `bg_ladder_yawcap`,
  bullet end-position range, `bg_compassshowenemies` (set on connect), `sv_max_ping`.
- UI: notifications/toasts, unlock-all toggle state (`ui_unlockall`), playerdata/prestige tools.

## D. Stability fixes (most relevant)
- `cl_disconnect_stub`: on disconnect outside the virtual lobby, clears the current usermap state
  before calling CL_Disconnect.
- `cm_unload_stub`: clears the cached usermap/map names before calling the game's CM_Unload
  (game base + 0x4cd0e0).
- `connect_to_party`: if `Live_SyncOnlineDataFlags` is not 0, the connect is deferred and retried
  instead of connecting immediately (race at join time); also leaves the virtual lobby and sets
  the usermap before CL_ConnectFromParty.
- `G_FindConfigstringIndex` warnings: logs when a configstring range is nearly full / about to
  overflow (custom content can exhaust the ranges -> classic crash cause).
- Missing-zone checks ("Failed to find fastfile for zone"), single-instance mutex, console log to
  file, resumable + verified pakfile downloads.

## E. Content
- **Drop Zone**: `maps/mp/gametypes/dz.gsc` (GSC source rawfile in `hmw_files.ff`) +
  `ui_scripts/mp/hud/dz_hud.lua`. The menu entry comes from HMW's Lua
  `ui_scripts/mp/liam_tests/__init__.lua`, which replaces the Standard list with
  dm war sd dom conf sab koth hp **gtnw** gun **dz** (also active in our client). No `dz`
  registration in the exe and no gametype table / whitelist change in HMW's zones: HMW apparently
  starts it with plain `g_gametype dz`. `gtnw` has no script anywhere (test leftover).
- `dz` has no row in `mp/gametypesTable.csv` -> no proper name/icon in our menus.

## Corrections after a closer look (2026-11-22)

- Already in our client (open-source code): usermap clearing in `cl_disconnect_stub` (party.cpp),
  `cm_unload_stub` (mapents.cpp), deferred connect while `Live_SyncOnlineDataFlags != 0` (party.cpp).
  Not in our client: the configstring overflow warning (exe detours `G_FindConfigstringIndex`,
  base+0x8B530) and the version-mismatch check on join.
- Gametype whitelist and names come from HMW's zone `hmw_patch_code_post_gfx_mp`: rawfile
  `maps/mp/gametypes/_gametypes.txt` = dm dom sd war conf vlobby koth sab ctf dd hp gun gtnw dz, and one
  `maps/mp/gametypes/<ref>.txt` per gametype with its name keys (e.g. dz.txt -> MPUI_DZ,
  gtnw.txt -> MPUI_GTNW; also infect, sr, ball, twar, mugger, zombies, goliath from AW). These .txt
  files are what the engine's display name uses (no slasher.txt -> raw "slasher").
- **GTNW is not implemented**: whitelisted and named, but no `gtnw.gsc` exists in any HMW zone ->
  error when selected. Port candidate: `COD-GSC-Source/IW4-GSC/maps/mp/gametypes/gtnw.gsc` (MW2).
- ADS sensitivity (exe): every frame while `CL_IsCgameInitialized` (0x33C640): remember the normal
  `sensitivity` once, set `sensitivity = base * lerp(1, m_ads_sensitivity_scale, adsFrac)` with
  adsFrac = float at `getCGArray() + 0x39C`, only when it differs by > 0.001; when cgame is not
  initialized, restore the remembered value.
- Raw mouse input (exe): registers a raw mouse device (usage page 1, usage 2) on the game window
  (`hWnd`, 0xC9DD2E0); the WM_INPUT path and how deltas reach the game are not found yet (it keeps
  pointers to base+0xC9DC3FC / 0xC9DC400). Needs more reverse engineering before a spec.
  (The exe's detour of 0x12C8F0 = CL_CharEvent only blocks typing while the ImGui overlay is open.)

## Recommendations (user decides)
1. Drop Zone: add a `dz` table row + names (like the party modes), remove `gtnw` from the
   Standard list, test a DZ match. Small, fits the gamemodes work.
2. Stability batch: usermap clearing on disconnect/unload, deferred connect while online data
   syncs, configstring overflow warning, version check when joining a LAN server.
3. Input batch: `m_rawinput`, `m_ads_sensitivity_scale` (small, noticeable).
4. Later/optional: red-dot brightness, HUD color, movement toggles, direct connect.
5. Skip: everything in A.
