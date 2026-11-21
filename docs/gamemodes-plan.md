# Plan: extra game modes in the private match menu

Goal: pick Prop Hunt, Mad Props, Slasher, Snipers Only, RPGs Only, Infected (and presets like
Ground War / Cage Match / Team Tactical / Old School FFA) in the private match game setup, on LAN.

## Findings (2026-11-22)

- Final retail H1 + HMW know 11 gametypes: war, dm, dom, conf, sd, hp, gun, sab, koth, ctf, dd
  (+ vlobby). Lists are in `mp/gameTypesTable.csv` and in the Lua menus
  (`MPGameSetupOptionsMenu`: `GetOptionClassForGameType` asserts "No Option Class for Game Type").
- The MWR event modes still ship as script code ("hodgepodge" modes), in retail
  `patch_common_mp` and in `hmw_patch_common_mp`:
  `maps/mp/gametypes/_hodgepodge.gsc` + `_hodgepodge_ph.gsc`, started from `_gamelogic.gsc`.
  Selected by dvar `scr_game_hodgepodgeMode`, all on base gametype **war**:
  | mode | value | notes |
  |---|---|---|
  | Slasher | 2 | one slasher (shovel + colt45) vs survivors, `MP_SLASHER*` strings exist |
  | primary only | 3 | strips to primary weapon (no known playlist name) |
  | Snipers Only | 4 | primary only, no melee, kill-range indicator |
  | RPGs Only | 6 (reload) / 7 (no reload) | |
  | Prop Hunt | 9 | 4 rounds, props vs hunters |
  | Mad Props | 9 + `scr_game_madprops 1` | props hunt humans, fixed list of 7 common props |
  Source (decompiled): `COD-GSC-Source/H1-GSC/maps/mp/gametypes/_hodgepodge*.gsc`.
- **Prop Hunt needs `mp/ph_props_<mapname>.csv`** (model, type, offsets...), not present in any
  retail or HMW zone checked. Mad Props does not need it.
- **Infected has no gametype script** in H1, but leftovers exist: splashes
  (`SPLASHES_FIRST_INFECTED`, `SPLASHES_GOT_INFECTED`, `SPLASHES_INFECTED_SURVIVOR`...),
  infected VO sounds, Lua `LUA_MP_COMMON_INFECTED_COUNTDOWN` / omnvar `first_infected_in`.
  Port sources: `COD-GSC-Source/S1X-GSC/maps/mp/gametypes/infect.gsc` (AW, same engine family,
  same `_globallogic` API as H1's war.gsc) and `IW6-GSC/.../infect.gsc` (no exo stuff).
- The client can already: load custom GSC from search paths (`gsc/script_loading.cpp`, also
  serves unknown gametype scripts), load/override Lua (`ui_scripting.cpp`, `ui_scripts/`),
  patch string tables at load (`stock_weapons.cpp` pattern), override localized strings
  (`localized_strings.cpp`).
- HMW is MW2 gameplay on H1 (own _menus/_weapons/_class/killstreaks): hodgepodge loadouts use
  H1 weapon names (`h1_meleeshovel`, `h1_colt45`, RPG, snipers) that must exist in HMW.
- H1 dvar names are hashed in compiled scripts; setting `scr_game_hodgepodgeMode` from the
  client must resolve to the same dvar (verify first).

## Design

**Virtual game modes** in a new client component `gamemodes.cpp`:
`ref -> { base gametype, dvars, name, desc, image }`, e.g.
`ph -> war + scr_game_hodgepodgeMode 9`, `mprops -> war + 9 + scr_game_madprops 1`,
`slasher -> war + 2`, `snipers -> war + 4`, `rpg -> war + 6`, `infect -> infect` (real script).
- UI: add rows for the virtual refs to `mp/gameTypesTable.csv` (string table patch at load) and
  map them to an existing option class in `GetOptionClassForGameType` (TDM class; Lua override),
  names via localized strings.
- Start: when the host starts a map with `ui_gametype`/`g_gametype` = virtual ref, the client
  sets `g_gametype` to the base and the mode dvars (and resets them for normal modes), so all
  hodgepodge code runs exactly as shipped (it assumes level.gametype == "war").
- Data files (GSC, Lua, CSV) live in the repo under `data/mwx/` and are copied to `GAME\mwx\`
  by build-mwx.bat; `mwx` is registered as a search path. Never write into hmw-mod.
- Every LAN player uses mwx.exe with the same data (menus/strings are client side; GSC runs on
  the host).

## Phases (each = one or more opencode prompts, Claude reviews)

0. **Reference data.** Clone tools/dumps into `C:\Games\cod-hwm\refs\`; with the game's
   `zonetool.exe` dump `patch_ui_mp`, `patch_common_mp`, `hmw_patch_ui_mp`,
   `hmw_patch_common_mp`, `english\eng_patch_common_mp` to `refs\dumps\`; decompile the Lua of
   the private match / game setup menus. Output needed: gameTypesTable.csv (retail + HMW),
   matchrules DDL, decompiled `MPGameSetupOptionsMenu` + gametype selection menu, localize list.
1. **Feasibility check (no new code).** In a private match via console: `set
   scr_game_hodgepodgeMode 2; map_restart` on war -> does Slasher start? Same for 4, 6, 9 +
   madprops. Note script errors (console), missing weapons/models. Decides how much HMW fixing
   is needed.
2. **gamemodes component + UI.** Virtual mode table, gameTypesTable rows, Lua option-class
   mapping, localized names/descriptions, translation at match start, `mwx` search path +
   `data/mwx` copy in the build script.
3. **Hodgepodge modes.** Fix HMW incompatibilities found in phase 1 with GSC overrides in
   `data/mwx` (loadouts, weapon names). Prop Hunt: `ph_props_<map>.csv` for the maps we play,
   plus a fallback (if no csv: Mad-Props style generic prop list) so every map works.
4. **Infected.** Port `infect.gsc` (S1 base, IW6 for non-exo parts) to H1/HMW: H1 weapon names
   (survivors: HMW loadout or fixed shotgun+pistol; infected: knife + throwing knife +
   tactical insertion), drop exo code, use the existing splashes/VO/countdown omnvar. Options via
   dvars (initial infected, time limit). UI entry like phase 2.
5. **Presets.** Ground War (war, 18 players), Cage Match (war 1v1), Team Tactical (war 4v4),
   Old School FFA (dm + oldSchoolModeOn), hardcore variants: rows that start a base gametype
   with forced settings. Optional later: Search & Rescue (port `sr.gsc` from IW6/S1).
6. **Test per mode** (debug server + bots): starts from the menu, rounds/end conditions work,
   no script errors, a second PC can join via the LAN browser.
