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

## Phase 0 results (refs in C:\Games\cod-hwm\refs)

- `refs\key\lua_decompiled\`: decompiled final retail menus (HMW's mp_menus are byte-identical
  to retail). `refs\h1_dump\` has the full older H1 dump (Lua + csv).
- Mode list = Lua table `Cac.GameModes.Data[group].List` (defined in `s1cacutils`). The final
  `mpgamesetupmodemenu` already loops over the groups `Standard` and `Party`; `Party` is just not
  defined. -> A ui_script that adds `Cac.GameModes.Group.Party` + `Data.Party` gives a second
  "PARTY" mode list without touching any menu code.
- Selecting a mode does `MatchRules.SetData("gametype", ref)` and labels come from
  `mp/gameTypesTable.csv` (ref, name, desc, image, flags..., presence). The retail table already
  has rows for `infect` (MPUI_INFECT / MENU_INFECT_DESC / icon_pl_exo_infected), `sr`, `ball`,
  `twar`, `mugger` (AW leftovers); localized strings for infect exist
  (`MENU_INFECT_DESC`, `LUA_MENU_RULES_NUM_INIT_INFECTED`, scoreboard strings).
- `GetOptionClassForGameType` is only used for gametype-specific options (dom/sd/...), so
  war-based modes do not hit its assert.
- No matchrules DDL found; HMW's gameTypesTable and HMW English strings were not in the dumped
  zones (zonetool does not write string tables with -dumpzone).
- Dvar names are hashed with the same function in GSC and in the client (`dvars.cpp`), so
  `set scr_game_hodgepodgeMode N` from the console should reach the scripts (verify in phase 1).

## Design

**Virtual game modes** in a new client component `gamemodes.cpp`:
`ref -> { base gametype, dvars, name, desc, image }`, e.g.
`ph -> war + scr_game_hodgepodgeMode 9`, `mprops -> war + 9 + scr_game_madprops 1`,
`slasher -> war + 2`, `snipers -> war + 4`, `rpg -> war + 6`, `infect -> infect` (real script).
- UI: a ui_script defines the `Party` group (ph, mprops, slasher, snipers, rpg, infect); rows for
  the virtual refs are appended to `mp/gameTypesTable.csv` (string table patch at load, like
  stock_weapons), names/descriptions via localized strings (reuse MP_SLASHER*, MPUI_INFECT...).
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

## Phase 1 results (2026-11-22)

- `set scr_game_hodgepodgeMode N` + `map` works: **Slasher ran** (axis bot became slasher, kills
  with `h1_meleeshovel_mp`), **Prop Hunt ran** (4 rounds, round logic, "ALLIES ELIMINATED"), but
  without props because `mp/ph_props_<map>.csv` is missing. The earlier "nothing happens" was the
  human stuck in the pregame/team menu (console `map` does not auto-assign).
- Release clients do not scan `scripts/mp/` on disk (only dedicated servers; `load_scripts` in
  `gsc/script_loading.cpp` has `#ifndef DEBUG if (is_dedi())`).
- The engine whitelists gametypes in the rawfile `maps/mp/gametypes/_gametypes.txt`
  (dm dom sd war conf vlobby koth sab ctf dd hp gun). New refs must be added there.

## Phase 2 spec (menu + start of the hodgepodge modes)

Virtual modes (ref -> base gametype + dvars):
| ref | base | scr_game_hodgepodgeMode | scr_game_madprops | name key | desc key |
|---|---|---|---|---|---|
| ph | war | 9 | 0 | MWX_GAMETYPE_PH | MWX_GAMETYPE_PH_DESC |
| mprops | war | 9 | 1 | MWX_GAMETYPE_MPROPS | MWX_GAMETYPE_MPROPS_DESC |
| slasher | war | 2 | 0 | MP_SLASHER (exists) | MP_SLASHER_DESC (exists) |
| snipers | war | 4 | 0 | MWX_GAMETYPE_SNIPERS | MWX_GAMETYPE_SNIPERS_DESC |
| rpg | war | 6 | 0 | MWX_GAMETYPE_RPG | MWX_GAMETYPE_RPG_DESC |

New component `src/client/component/gamemodes.cpp/.hpp` (registered like the others):
1. Mode table above in one place (`gamemodes::find(ref)`).
2. Strings via `localized_strings::override` in post_unpack:
   MWX_GAMETYPE_PH "Prop Hunt" / "One team hides as props, the other hunts them. Survive the round as a prop or find them all.";
   MWX_GAMETYPE_MPROPS "Mad Props" / "Props hunt the soldiers. Props win by eliminating every soldier.";
   MWX_GAMETYPE_SNIPERS "Snipers Only" / "Team Deathmatch with sniper rifles only.";
   MWX_GAMETYPE_RPG "RPGs Only" / "Team Deathmatch with RPGs only.";
   MWX_PARTY_CAPS "PARTY GAMES".
3. Rawfile patch (hook in `fastfiles.cpp` db_find_xasset_header, RAWFILE branch, next to the
   override logic): for `maps/mp/gametypes/_gametypes.txt` return a copy with the virtual refs
   appended, one per line (allocate once, keep alive; keep `len`, set `compressedLen = 0` so
   `db_get_raw_buffer_stub` copies the plain buffer).
4. String table patch (STRINGTABLE branch, like `stock_weapons::patch`): for
   `mp/gameTypesTable.csv` append one row per virtual ref, copying the `war` row and replacing
   col 0 (ref), 1 (name key), 2 (desc key); keep the war image/flags/presence. Cell hashes like
   stock_weapons does (reuse its hash detection). Do it once and cache.
5. Start translation in `load_gametype_script_stub` (gsc/script_loading.cpp), BEFORE the original
   call: read `g_gametype`; if it is a virtual ref -> set `g_gametype` to the base, set
   `scr_game_hodgepodgeMode` / `scr_game_madprops`, set string dvar `mwx_gamemode` to the ref,
   log "[gamemodes] <ref> -> <base> (hodgepodge N, madprops M)". Otherwise, if it is any other
   gametype -> set both hodgepodge dvars to 0 and `mwx_gamemode` "" (so a later normal match is
   normal again). Use the same dvar setter the code base already uses for string/int dvars.
   Register `mwx_gamemode` like lan.cpp registers its dvars.
6. Release disk scripts from GAME\mwx: in `load_scripts`, also scan the disk folder in release when
   `root_dir` is the `mwx` search path (`is_dedi() || root_dir.filename() == "mwx"`).
   (Needed for phases 3/4; harmless now.)

UI (`data/mwx/ui_scripts/gamemodes/__init__.lua`, frontend + multiplayer only, use
`Engine.IsMultiplayer()`, never `game:issingleplayer()`):
```lua
if not Engine.InFrontend() or not Engine.IsMultiplayer() then return end
Cac.GameModes.Group.Party = "Party"
Cac.GameModes.Data.Party = {
    Label = Engine.Localize("@MWX_PARTY_CAPS"),
    Image = "h1_ui_icon_playlist_standard",
    List = { "ph", "mprops", "slasher", "snipers", "rpg" }
}
```
(Standard list stays as HMW sets it. Infected is added in phase 4 when its script exists.)
