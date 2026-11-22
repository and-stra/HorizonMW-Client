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

## Phase 2 results (commit 52e10a41)

- Works: whitelist patch (re-compressed with zlib, a plain buffer deadlocks), gametypesTable rows
  (real asset name `mp/gametypesTable.csv`), translation (`[gamemodes] slasher -> war (hodgepodge 2,
  madprops 0)`, normal modes reset to 0), PARTY GAMES group + list with names/descriptions.
- Gaps: `MP_SLASHER` does not exist in HMW (raw key shown); choosing a party mode in the menu does
  not change `ui_gametype`. The engine derives `ui_gametype` from `MatchRules "gametype"`, and
  MatchRules evidently rejects unknown refs (Domination works). Starting with `ui_gametype=ph` works.

## Phase 2b spec (menu selection of party modes)

Idea: MatchRules keeps the base gametype ("war"); the chosen party mode is remembered in a host
dvar `mwx_party_mode`, and the start translation uses it.

C++ (`gamemodes.cpp`):
1. Register string dvar `mwx_party_mode` (default "", not saved) like the other mwx dvars.
2. Start translation (in `load_gametype_script_stub`), in this order:
   a) `g_gametype` is a virtual ref -> as now.
   b) else if not dedicated, `mwx_party_mode` is a known ref and `g_gametype` equals its base ->
      apply that mode (set g_gametype stays base, hodgepodge/madprops dvars, `mwx_gamemode` = ref,
      same log line with "(party mode)").
   c) else -> reset as now.
3. Slasher strings: add `MWX_GAMETYPE_SLASHER` "Slasher" / `MWX_GAMETYPE_SLASHER_DESC`
   "One player is the Slasher with a shovel and a pistol. Survive until time runs out or take the
   Slasher down." and use them for the slasher row instead of MP_SLASHER*.

Lua (`data/mwx/ui_scripts/gamemodes/__init__.lua`, append below the group definition):
```lua
local party_base = { ph = "war", mprops = "war", slasher = "war", snipers = "war", rpg = "war" }

-- selecting a mode in game setup goes through MatchRules.SetData("gametype", ref)
local set_data = MatchRules.SetData
MatchRules.SetData = function(key, value, ...)
    if key == "gametype" then
        local base = party_base[value]
        if base then
            Engine.SetDvarString("mwx_party_mode", value)
            return set_data(key, base, ...)
        end
        Engine.SetDvarString("mwx_party_mode", "")
    end
    return set_data(key, value, ...)
end

-- show the party mode wherever the UI reads ui_gametype (lobby label/icon, list highlight, loadscreen)
local get_dvar_string = Engine.GetDvarString
Engine.GetDvarString = function(name, ...)
    local value = get_dvar_string(name, ...)
    if name == "ui_gametype" then
        local mode = get_dvar_string("mwx_party_mode")
        if mode ~= "" and party_base[mode] == value then
            return mode
        end
    end
    return value
end
```
The base table must match the C++ mode table (all "war" for now).

## Phase 2b results (commit 3bc895d4)

Selection via MatchRules.SetData + `mwx_party_mode` + start translation work (Slasher from the menu:
`[gamemodes] slasher -> war (party mode)`, 4 shovel kills; TDM afterwards normal; Prop Hunt 9).
The `Engine.GetDvarString` wrapper has no visible effect (lobby label still TEAM DEATHMATCH, no
highlight); HMW's lobby scripts most likely keep their own local reference to the function.

## Phase 2c spec (show the party mode in the UI)

1. Remove the `Engine.GetDvarString` wrapper block from `data/mwx/ui_scripts/gamemodes/__init__.lua`
   (keep `party_base` and the MatchRules.SetData wrapper).
2. `gamemodes.cpp`, client only (`!is_dedi()`), event-driven, no polling. Use the existing dvar-write
   hook `dvars::callback::on_new_value(name, fn)` (fires after every write via Dvar_SetVariant;
   one callback per dvar, nothing else uses these two):
   - `on_new_value("ui_gametype")`: if `mwx_party_mode` is a known ref and the new value equals that
     ref's base, set `ui_gametype` to the ref (same dvar setter as the translation code). The nested
     write fires the callback again with the ref, which does nothing, so there is no loop.
   - `on_new_value("mwx_party_mode")`: if the new value is a known ref and `ui_gametype` currently
     equals its base, set `ui_gametype` to the ref (covers the case that the engine does not write
     `ui_gametype` again after MatchRules changed).
   Effect: every UI element reading `ui_gametype` shows the party mode (label, icon, list highlight,
   loadscreen), and because `g_gametype` is taken from `ui_gametype` at start, the start goes through
   translation path (a) (virtual ref), which is already tested.
3. Choosing a standard mode clears `mwx_party_mode` (already), so the loop stops and the engine's
   own value stays.

## Phase 2c results (commit cdff38bb)

ui_gametype mirror works (`ui_gametype=slasher`, start via path a). Still: lobby label TEAM DEATHMATCH,
no highlight in the list, pre-match screen shows raw keys `MWX_GAMETYPE_PH_CAPS` and
`OBJECTIVES_ph_SCORE`. The gametype script loader runs twice per map start. Stability: 5 start/quit
cycles (menu and debug quit), 0 crashes, no new minidumps (anti-cheat scan removed).

## Phase 2d spec

1. Lobby label + list highlight: both read `MatchRules.GetData("gametype")`. Add to
   `data/mwx/ui_scripts/gamemodes/__init__.lua`, below the SetData wrapper:
```lua
local get_data = MatchRules.GetData
MatchRules.GetData = function(key, ...)
    local value = get_data(key, ...)
    if key == "gametype" and select("#", ...) == 0 then
        local mode = Engine.GetDvarString("mwx_party_mode")
        if mode ~= "" and party_base[mode] == value then
            return mode
        end
    end
    return value
end
```
   (Only the plain `GetData("gametype")` call is changed; calls with more arguments are untouched.)
2. Missing strings (localized_strings::override in gamemodes.cpp), for every mode ref:
   - `<name key>_CAPS`: the name in upper case (e.g. `MWX_GAMETYPE_PH_CAPS` "PROP HUNT",
     `MWX_GAMETYPE_SLASHER_CAPS` "SLASHER", ...).
   - `OBJECTIVES_<ref>_SCORE` and `OBJECTIVES_<ref>` and `OBJECTIVES_<ref>_HINT`, registered with
     the ref in lower case (as the UI builds it, e.g. `OBJECTIVES_ph_SCORE`) and in upper case:
     ph "Props hide, hunters seek. Survive the round or find every prop."
     mprops "Props hunt the soldiers. Eliminate every soldier to win."
     slasher "Survive the Slasher, or take the Slasher down."
     snipers "Gain points by eliminating enemy players. Sniper rifles only."
     rpg "Gain points by eliminating enemy players. RPGs only."
   If the localized_strings lookup is case-insensitive, one registration per key is enough; say which.
3. Run the translation once per map load: the gametype script loader runs twice. Keep a flag
   "translated for this load" that is set when a translation or reset happened and cleared on
   script shutdown (`scripting::on_shutdown`, like script_loading does). If the flag is set, the
   second call does nothing (no second log line, no reset).

4. Vanilla look: rename the group to the original MWR playlist "Weekend Warfare":
   `MWX_PARTY_CAPS` -> "WEEKEND WARFARE", group `Image = "h1_ui_icon_playlist_weekend"` (exists in
   retail patch_ui_mp; the vanilla icon of that playlist). The group id stays "Party".
5. Loadscreen name: HMW's loadscreen shows `Engine.Localize("@" .. upper(ui_gametype))` (e.g. `@WAR`).
   Add localized strings with those keys, same text as the mode names, upper case like the other
   loadscreen names: `PH` "PROP HUNT", `MPROPS` "MAD PROPS", `SLASHER` "SLASHER",
   `SNIPERS` "SNIPERS ONLY", `RPG` "RPGS ONLY".
6. Joining players: the server info answer (`party.cpp`, `info.set("gametype", g_gametype)`) must
   report `mwx_gamemode` when it is not empty (the virtual ref), else `g_gametype`. Check the client
   connect path: the joining client must end up with `ui_gametype` = that reported value before its
   loadscreen opens (if it takes `ui_gametype` from somewhere else, report where; do not guess).

## Phase 2d results (commit a8c392da)

Weekend Warfare group, list highlight, pre-match names/objectives, one translation per load and the
server info gametype work; the joining client gets `ui_gametype=slasher`. Still: the private lobby
label says TEAM DEATHMATCH (it comes from `Lobby.GameTypeNameAbbreviated()`, an engine function that
reads the party gametype, not ui_gametype/MatchRules). User report: the map loading screen first shows
SLASHER, then switches to TEAM DEATHMATCH during the load.
LAN server browser does not open: HMW's current zone script `ui_scripts/mp/server_list/serverlist.lua`
builds `menu_systemlink_join` with `imgui:openServerBrowser()` (ImGui browser of the closed-source
exe); our client has no `imgui` Lua object -> "attempt to index a nil value".

## Phase 2e spec

1. Lobby label: in `data/mwx/ui_scripts/gamemodes/__init__.lua` wrap `Lobby.GameTypeNameAbbreviated`
   (global `Lobby`): if `mwx_party_mode` is a known ref, return
   `Engine.Localize("@" .. <name key> .. "_CAPS")` for it, else the original result. Name keys as in
   the C++ table (MWX_GAMETYPE_PH, MWX_GAMETYPE_MPROPS, MWX_GAMETYPE_SLASHER, MWX_GAMETYPE_SNIPERS,
   MWX_GAMETYPE_RPG); keep them in one Lua table next to `party_base`.
2. LAN server browser: restore our feeder-based browser (server_list.cpp feeds it). Copy
   `data/cdata/ui_scripts/server_list/serverlist.lua` to `data/mwx/ui_scripts/server_list/serverlist.lua`
   and add `data/mwx/ui_scripts/server_list/__init__.lua`:
   `if not LUI.mp_menus then return end` + `require("serverlist")`. Do NOT copy lobby.lua or
   confirm.lua. Our scripts load after HMW's, so our `menu_systemlink_join` wins.
3. Loading screen diagnosis (temporary, behind dvar `mwx_debug_gamemodes`, default 0):
   - C++: in the existing `on_new_value("ui_gametype")` callback, log
     `[gamemodes] ui_gametype <- <value>` (before any correction) when the dvar is 1.
   - Lua: wrap `LUI.MenuBuilder.m_types_build["connect"]` and log (print) `[gamemodes] connect menu
     built, ui_gametype=<value>` each time it is built, when the dvar is 1.
   With `mwx_debug_gamemodes 1`, start Slasher from the menu, watch the loading screen, and report the
   ordered log lines plus screenshots every 1 s during the load. Do not try to fix the switch yet;
   Claude decides the fix from the log.

## Phase 2e results (commit 42bc90b6)

Lobby label shows SLASHER (Lobby.GameTypeNameAbbreviated wrapper). LAN browser works again (needed
`package.loaded["serverlist"] = nil` before `require`, because HMW's zone script had already loaded a
module with that name); server listed with map Rust, join works, joining client gets
`ui_gametype=slasher`. Open: the browser's Type column shows the raw ref `slasher`
(`UI_GetGameTypeDisplayName` returns its input for unknown refs), and the map load screen shows TEAM
DEATHMATCH from its first frame although `ui_gametype=slasher` at that time: it is not LUI
(`connect` builder never called) and does not read `ui_gametype`.

## Phase 2f spec (game type display name)

Detour `game::UI_GetGameTypeDisplayName` (0x4DD8C0, `const char*(const char*)`) in `gamemodes.cpp`:
1. If `mwx_debug_gamemodes` is 1, log `[gamemodes] display name for '<arg>'` (to see which callers
   use it, e.g. the load screen).
2. If the argument is a virtual ref -> return `game::UI_SafeTranslateString(<name key>)`
   (e.g. MWX_GAMETYPE_SLASHER -> "Slasher").
3. Else, if the argument equals a mode's base gametype and an active mode exists -> return that
   mode's translated name. Active mode = the first of these that is a known ref with that base:
   `mwx_gamemode` (running match, host/server), `mwx_party_mode` (host in the lobby),
   `ui_gametype` (joining client, set from the server info).
4. Else -> original function.
