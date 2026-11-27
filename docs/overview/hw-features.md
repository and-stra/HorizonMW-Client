# Spec: features taken over from hmw-mod.exe v1.6.7 (see hmw-diff.md)

Behaviour only, our own implementation. **Implemented by Claude (code written, not built/tested):** A (Standard list, dz row/strings, together with Infected), B (`ads_sensitivity.cpp`), C (version check in `party.cpp`, dvar `mwx_ignore_version`), D (`configstrings.cpp`, detour of base+0x8B530; uses the returned index as usage). Do the parts in order; each part is tested and committed
separately. Do not touch anything listed under "Not now".

## Part A: Standard mode list and Drop Zone

1. In `data/mwx/ui_scripts/gamemodes/__init__.lua`, set the Standard list explicitly (HMW's
   `liam_tests` script sets it to a list that contains `gtnw`, which has no script):
   `Cac.GameModes.Data.Standard.List = { "dm", "war", "sd", "dom", "conf", "sab", "koth", "hp", "gun", "dz" }`
   (keep Label/Image as they are).
2. Check in game with `Engine.Localize("@MPUI_DZ")` (Lua print) whether HMW has the DZ strings. If it
   returns the raw key, add `MPUI_DZ` "Drop Zone" and `MPUI_DZ_CAPS` "DROP ZONE" via
   `localized_strings::override` in gamemodes.cpp. Report what you found.
3. If `dz` has no row in `mp/gametypesTable.csv`: add one in the existing gametypesTable patch, copied
   from the `koth` row, with col 0 = `dz`, name `MPUI_DZ`, desc key `MWX_GAMETYPE_DZ_DESC`
   ("Capture the drop zone to earn points and care packages."). Not a party mode (no translation).
4. Test: start Drop Zone from the menu on mp_rust with 5 bots for 2 minutes. Report script errors,
   whether the zone/score HUD works, and screenshots. Also try CTF and Demolition from the console
   (`g_gametype ctf` / `dd`, `map mp_rust`) and report whether they run on an HMW map (they are not in
   the list; we only add them if they work).

## Part B: ADS sensitivity scale

New component `src/client/component/ads_sensitivity.cpp` (client only):
1. Register float dvar `m_ads_sensitivity_scale` (default 1.0, min 0.0, max 5.0, saved), description
   "Mouse sensitivity multiplier when aiming down sights (1.0 = same as hip fire)".
2. `scheduler::loop` on the main pipeline (every frame):
   - if `game::CL_IsCgameInitialized()`:
     - if not active yet: remember the current `sensitivity` value as `base`, set active.
     - `ads_frac` = float at `(char*)game::getCGArray() + 0x39C`, clamped to 0..1.
     - `target = base * (1 + (scale - 1) * ads_frac)`; if `|sensitivity - target| > 0.001`, set
       `sensitivity` to `target` (same dvar setter the code base uses).
   - else if active: set `sensitivity` back to `base`, clear active.
   - If the user changes `sensitivity` while not aiming (ads_frac == 0 and the value differs from
     the last value we wrote), take it as the new `base`.
3. On shutdown (component pre_destroy) restore `base` if active, so the saved config never keeps an
   ADS value.
4. Test: verify `cg + 0x39C` is the ADS fraction: log it while aiming in a private match (it must go
   0 -> 1 when aiming and back). If it does not behave like that, stop and report.

## Part C: version check when joining a LAN server

1. The server's `getInfo` answer already contains `gameversion` (party.cpp). In the join paths
   (`connect_to_server_tcp` in party.cpp and `check_can_join` in server_list.cpp), compare it with our
   own version string (the same value we send as `gameversion`).
2. If they differ and dvar `mwx_ignore_version` (bool, default 0) is 0: do not join, show
   "Version mismatch! Server: <server> | Yours: <ours>. Update MWX on both PCs (or set
   mwx_ignore_version 1)." with the existing error popup.
3. Test with a dedicated server started with `+set mwx_fake_version test` if that is easy; otherwise
   just verify the normal join still works and report.

## Part D: configstring overflow warning

1. Detour `G_FindConfigstringIndex` (base+0x8B530, signature as used in weapon.cpp:
   `int(const char* string, int start, int max, int create, const char* errormsg)`).
2. After calling the original: if `create` was set, count how many entries of the range
   `start..start+max` are in use (use the configstring getter the code base already has; if there is
   none for the server, stop and report). Log once per range and map when usage reaches 90 %:
   `[configstrings] range <start> nearly full (<used>/<max>) adding '<string>'`, and at 100 %
   `[configstrings] range <start> FULL, '<string>' not added`.
3. Test: a normal match must log nothing; report any lines you see with all HMW content loaded.

## Not now
- Raw mouse input (needs more reverse engineering).
- GTNW (port from IW4 later), online services, ImGui browser, UPnP, updater.
