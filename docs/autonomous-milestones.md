# Autonomous run: milestones M4-M7

Given by the user for the `opencode/autonomous` run (after M1-M3). General rules: every milestone
ends with `tools\gsc-check\check-all` (0 problems), `run_all_tests` (all green or explained in
`mwx-debug\autonomous\report.md`) and a push of `opencode/autonomous`. `AGENTS.md` applies
(`C:\Games\cod-hwm` only, back up game/`.ff` files, stop only processes you started, keep 20 GB
free).

## M4 - Party modes as real gametypes (remove the fragile translation layer)

Goal: slasher, rpg, ph (and any other hodgepodge party mode) run as their own `g_gametype`
(e.g. `slasher`). The loading screen, scoreboard and menus show the correct name with no
workarounds.

- **Script alias**: in the find_script / script-loading hook, load `maps/mp/gametypes/<partyref>`
  as `maps/mp/gametypes/war.gsc` (the whole script, labels included). An earlier attempt failed
  with "Could not find label in script 'maps/mp/gametypes/slasher'" because `g_gametype` was
  switched without an alias; the alias has to fix exactly that.
- The party ref sets `scr_game_hodgepodgeMode` itself (2 = slasher, 6/7 = rpg, 9 = ph). Keep the
  mapping in one table.
- **GSC compatibility**: `war.gsc` and the hodgepodge scripts compare `getdvar("g_gametype")`.
  Override `getdvar` for `"g_gametype"` so it returns `"war"` while a party ref runs (only for
  this dvar). Alternatively use `replacefunc` where that is cleaner. Document which one you chose
  and why.
- Register party refs like the extra gametypes (whitelist + gametypesTable row, `class_choice`
  where needed).
- Then remove the old pieces: `mwx_party_mode`, the MatchRules wrappers, the `ui_gametype`
  mirror, the `g_gametype` switch/restore in `load_gametype_script_stub` and
  `gamemodes::on_level_load`. Remove the loadscreen `gametypeDisplay` override in
  `ui_scripts/loadscreen` if it is no longer needed.
- Done when: every party mode starts from Private Match and via `map`, the loading screen shows
  the right name from the start, the slasher/rpg tests are green, and an extra test checks
  `getdvar("g_gametype") == "war"` in GSC and `g_gametype == "slasher"` in the console.

## M5 - Faster startup: load HMW content zones in the background

- Today the 9 HMW content zones (~28.5 s) load before the main menu (`patches.cpp ui_init_stub`).
  Load only what the frontend needs before the menu; load the rest in the background after the
  menu.
- Before any map load (party start, `map`, connect, mod switch), wait until the background load
  is done (show the normal loading popup, no freeze without feedback).
- Check that CAC, armory, personalization and the weapon/camo menus work, including when opened
  while zones are still loading. Block or wait if needed.
- The `mod.ff` still loads last, after all HMW zones.
- Fallback dvar (e.g. `mwx_sync_zone_load 1`) brings back the old behaviour.
- Measure: time to main menu and time to the first map, before and after (3 runs each), and put
  the numbers in the report.
- Done when: the menu shows up clearly faster, all tests are green, and there are no
  default-asset errors or crashes in CAC.

## M6 - Fast mod switching without a relaunch

- First fix `lui_restart` (left over from M1); M6 needs it.
- Only allowed in the main menu (not in game, `can_change_mod`).
- `loadmod`/`unloadmod`: unload the old mod zone ("mod"), load the new `mod.ff`, reread
  `mod.json`, `gamemodes::invalidate()` (rebuild the gametype table, whitelist and localized
  strings), mod scripts get picked up on the next map load, restart the LUI so the PARTY list
  and MODS menu update.
- The relaunch stays as a fallback if the zone unload fails or the dvar `mwx_mod_relaunch 1` is
  set.
- Done when: none -> sticksandstones -> none -> sticksandstones works without a restart, the sas
  test is green after every switch, the sas gametype disappears from the list when the mod is
  unloaded, and the switch time is in the report.

## M7 - Final report

- In `report.md`: status of every milestone (done / partial / open), commits per milestone, a
  test table (two `run_all_tests` runs), the startup measurements from M5, mod switch times,
  open bugs with repro steps, things that need Claude's review (risky hooks, anything you weren't
  sure about), and the current branch state (pushed, hash).
- Don't merge into `mwx`; Claude reviews first.
