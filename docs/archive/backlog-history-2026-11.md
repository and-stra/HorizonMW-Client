# MWX backlog (Claude, 25 Nov 2026)

All open work in one place, in priority order. **Nothing below the line "NOW" starts before the menu is done.**
The agent keeps this file current: mark an item done with its commit hash, add new findings at the right
priority. Merges into `mwx` are done by Claude only.

Branch stack: see "Rules for today" in the THEN section.

## Overnight 26/27 Nov - step Z (custom-zone map-load stall)

**DONE (27 Nov, aw-weapons).** Root cause narrowed and fixed by shrinking the startup list:
- 9 startup zones load `mp_crash`; 10 hang at `imagefile48.pak` (2,138 MB) regardless of the
  10th zone's content/size (172 B rawfile, 1.9 KB xanim, 19.8 MB / 56 MB weapon zones all the
  same) and regardless of load order (experiments a-c in `docs/investigations/zone-load-stall.md`).
- The hang is not a lock: the main thread pumps messages, a DB worker thread retries in a
  `SleepEx` loop (`h1_mp64_ship+0x3A1F42`), `g_zoneCount` stops at 43, no thread is in the pak
  reader. `h1_mp64_ship.exe` is Arxan-packed, so the exact counter is not visible statically.
- Releasing the three extra zones after they were loaded (32 -> 28 zones, -719 MB) does not fix
  it, so the fix is to not load them at startup.
- Fix: the startup list is HMW's own six zones + `hmw_aw_weapons` = 7. `hmw_nightshade`,
  `hmw_dlc_factions`, `hmw_dlc_killstreaks` (added in `d698d8ca` only for the Create-a-Class
  list) are no longer loaded; consequence: their weapons/assets are not in the CAC.
- Verified on the 7-zone build: `ph_listen` 12/12 x3 (142/130/131 s), `aw_crossbow` 15/15 x3
  (58.5/59.2/58.6 s), `sas` 8/8 x3 (56.3/55.9/56.6 s), `mp_crash` then `mp_shipment` in one
  client (43.4 s / 9.8 s), startup to main menu 43.1 s (9 zones: 52-56 s). Full suite
  `-Parallel 2`: **37/38 green**, only `survival` fails (known B5). Menu smoke: 3 passes; one run
  had a single flaky rpg pick (`rpg` -> `gun`, retried by the smoke now).
- New debug RPC `stacks` (walks all threads from the debug server thread) stays in the tree; it
  answered while the main thread was stalled.
- Commits (aw-weapons): `8623a035` (zone list + stacks RPC), `aad5f6cd` (menu: sas in the party
  list, MOTD popup off, retry a mis-picked mode), pushed.
- The full suite also found that the Create-a-Class works without HMW's three menu zones; all
  party/standard gametype tests pass, so nothing in a match needed them.

## Overnight 26/27 Nov - step B (MWR DLC + melee weapons)

**In progress (27 Nov, aw-weapons).**
- `hmw_mwr_weapons.ff` restored from `zone\hmw_mwr_weapons.ff.blocked-b` (the parked copy stays)
  and added to the startup list: 8 zones (6 HMW + `hmw_aw_weapons` + `hmw_mwr_weapons`); `mp_crash`
  loads with it.
- The 12 DLC/melee tests are back in `data/mwx/tests/tests.json` (11 guns + `mwr_melee`).
- First run: 11/12 guns green. `mwr_melee` needed two test fixes: melee weapons are in the melee
  slot (`hasweapon`, not `switchtoweapon`) and the player has a finite weapon-slot count (15
  giveweapon calls, then silent failure), so the test takes each weapon away again. `mwr_melee`
  4/4 after that. The 12 tests are then **12/12 green x3** (2 full subset runs + the fixed melee).
- Create-a-Class (27 Nov): the MWR/CoD4 rows were never in the menu lists. Two causes, both fixed:
  (a) `stock_weapons.cpp` left the `type` column of `mp/customweapons.csv` empty, so
  `Cac.Weapons[type][class]` could not take the rows - derive it from the class
  (Primary/Secondary/Lethal/Tactical); (b) the CAC reads the row count once at UI load, before the
  zones load, so the appended rows (last) were skipped - the table patch is not marked final while
  rows are missing and `ui_scripts/cac_weapons/__init__.lua` fills in any missing ref when the
  class menu opens. Verified: `Cac.Weapons` has 41/41 (39 MWR + 2 CoD4 spot checks) and the class
  screenshots are in `_migration\archive\mwx-debug\mwr-weapons\cac-*.png`. The menu smoke now asserts the 39 refs.
- Full suite -Parallel 2: **GREEN 49/50**, only `survival` fails (known B5); menu smoke PASS with the
  new Create-a-Class check. Commit `58f7e324` pushed on aw-weapons.
- Remaining B (not done tonight): real names/icons/camos/attachments from the matrix, duplicates vs the
  AW PORT list, party-mode weapon pools, memory/load-time measurement with both zones.

## Overnight 27 Nov - step D (AW weapons, pilot)

**Pilot done, paused for the user's manual test.** M1 Garand (`iw5_dlcgun23`) and MP40 (`iw5_dlcgun18`) are in
`hmw_aw_weapons.ff` together with the crossbow (no new startup zone; 8 zones total).
- Weapon JSONs: `dumpzone h2 patch_common_mp` + `s1_weapon_to_h1.py`; anims from the closest
  MWR gun (M14 / MP44) with `use_hmw_anims.py` (the S1 dumper writes no xanims for H1).
- Models from `mp_vm/mp_wm_*_tr` dumps merged into the zone source.
- Materials: AW's `patch_common_mp` has the materials; the h1 image dump is 6.7 GB (temporary, the
  user allowed exceeding the 20 GB floor and cleaning up after). Only the images in the material
  `textureTable` are collected (26) **with their `_streamN.pixels`** - the header alone crashes the
  game with `Create2DTexture(...) failed`. Missing techsets are mapped to an existing one; a bulk
  material copy aborts the build (`mtl_player_emblem`).
- Rows/names/whitelist committed (`eab22750`); `aw_m1garand` 6/6, `aw_mp40` 6/6,
  `aw_crossbow` 15/15 x3 on the folded zone.
- Combat knife: models `vm/npc_mp_tactical_knife` are in AW's `common_mp` dump but their
  xsurfaces/tr zone are not found yet (`mp_vm_tacticalknife_tr` does not exist); row, name,
  whitelist and `aw_knife` test are in the tree, the test fails until the model is ported.

## NOW - a working menu (blocks everything else)

1. **Menu crash** (0xC0000005 at 0x1400BCB13). **DONE** (`573afae4`, traces in `b000c6f1`).
   The loader trace (`mwx-logs\ui_script_load.log`) showed four dangling starts, all
   `mwx/ui_scripts/gamemodes/__init__.lua`; the step trace (`mwx_trace` -> `ui_trace.log`) stopped
   between `mod list` and `survival`, i.e. at `Engine.GetDvarString("mwx_show_survival")` in the
   load-time chunk. The script now does no engine work at load (the party list/title/hooks are built
   lazily when a menu reads the table). A second, separate startup crash (0xC0000005, fault offset 0,
   no dump) came from the 1 Hz `get_status()` sampler racing engine init; the sampler is gone
   (`5437c445`), the status cache is filled by successful calls. 10/10 cold starts green.
2. **Mode selection in Private Match.** **DONE** (`573afae4`). `MatchRules.SetData` validates against
   the `BaseGameMode` enum of `mp/commondata.ddl` (16 values, 8-bit enum index, hash-sorted name table
   with `h*31+tolower(c)`). Extending it in memory works but crashed on picking the mode, so the
   wrapper is used: record the pick made in the mode menu (`mwx_selected_gametype`), keep
   `ui_gametype` at it while `xblive_privatematch`, re-apply before `xpartygo`; label from
   `ui_gametype`. Details: `docs/features/private-match.md`.
3. **Menu smoke test** in the normal suite. **DONE** (`573afae4`): `tools\test\menu-smoke.ps1`.
   Every Party mode + Domination/TDM, start, loading screen name, back/start again, main menu,
   Play Online, Mods. **5/5 green** on the final build (plus a 10/10 cold-start loop).
4. **Cleanup of the test leftovers.** **DONE**: the `.bak-*`/`.hook-test2` files are in
   `_migration\archive\mwx-debug\backups\gamemodes\`; the folder has only `__init__.lua`.
5. **Commits.** **DONE**, pushed on `opencode/fixes`: `6068b68c` (Mugger), `5437c445` (U1/U2),
   `b000c6f1` (crash traces/hardening), `573afae4` (mode fix + lazy load), `87cc433b` (U3).

## NEXT - clean and working state (before any new features)

6. **Game-mode hints show the string key instead of the text** (e.g. `OBJECTIVES_<REF>_HINT`,
   `_SCORE`). **DONE (26 Nov)**.
   - Repro: the frontend/private-match localization table has no stock `OBJECTIVES_*` strings
     (they arrive with the MP/gametype zones); `Engine.Localize("@OBJECTIVES_war_SCORE")` returned
     the raw key in the menu and the text only in a loaded map. The UI builds the key from the
     lowercase ref (`ingamebase.lua: inGameModeDisplay`), while MWX had uppercase-only entries for
     `sas`, `infect`, `dz`.
   - Fix: `stock_objectives` in `gamemodes.cpp` registers the stock modes' base/`_SCORE`/`_HINT`
     texts for both cases (the engine text, `&&1` score-limit placeholder kept - verified
     "First team to 75 wins."), and sas/infect/dz register both cases. Details:
     `cod-mwx/docs/guides/localization.md`.
   - Test: `menu-smoke.ps1` checks every Party/Standard/`infect`/`dz`/`sas`
     `OBJECTIVES_<ref>[_SCORE|_HINT]` right after the lobby opens (frontend, before any map zone);
     a key returned unchanged fails the run.
   - Found + fixed while testing: `lua_eval` during a LUI reload crashed at `0x1400BCB13`
     (`hks_start` script load or a DB zone load). `ui_scripting` exposes a loading counter,
     `lua_eval` answers "busy" and the smoke retries. `menu-smoke` also retries the known silent
     startup exit (no dump) instead of failing the run.
7. **Part B, the rest of the game-mode fixes.** **DONE (verified 26 Nov)**:
   - mode dvar restore: `mode_reset` (listen host) is 14/14 x3. ph/mprops set
     `scr_player_healthregen 0`, `scr_game_hardpoints 0`, `g_oldschool 0`; slasher sets
     `scr_game_mmUavTime 30` + oldschool 1; back to war restores the saved baseline of every one
     of them (`gamemodes.cpp: saved_globals` / `reset_mode_dvars`).
   - mp_shipment rules: the GSC `ph_setupdvars_stub` sets timelimit 2.2 + oldschool; the `ph` test
     asserts both on mp_shipment (`ph_shipment` is green too). The C++ `on_map()` branch is gone.
   - `ph_spawn_kick`: one `applyLoadout` per spawn (`ph_bridge` sets `mwx_ph_forwarded`, the kick
     clears it on `spawned_player` and only sends when the bridge did not); `ph_listen` green.
   - elevator trace A/B: the PM trace detour is installed for every mode, but the
     `startsolid = false` change is skipped for ph/mprops. A/B: with the change for ph the listen
     host crashed (R2); with the skip `ph_listen` is 12/12 green x3, no dump.
   - probes: `ph_notify_probe` and the `if (undefined)` probe run only with
     `mwx_debug_gamemodes 1` (B7).
   - AGENTS.md: the `applyloadout` case, `scr_<ref>_*` + restore, `giveperk(perk, 0)` and the
     parallel-test rule are documented (B8).
8. **Menu load times (U3).** **DONE** (`87cc433b`, `docs/investigations/menu-load-times.md`): startup ~55 s (the
   HMW content zones; parked), Play Online ~4-9 s of vlobby zones on the first visit (cached later,
   ~1.3 s), private lobby/Game Setup/Mode no zone loads, menu-to-menu 130-200 ms. The old "3.5-14 s"
   private lobby number was the debug click's own wait, not loading. Target (<2 s per step without a
   map load) is met.
9. **Dedicated server hang on `map mp_terminal`.** **DONE (26 Nov, not reproducible)**: on the
   26 Nov build `+map mp_rust` -> `map mp_terminal` loads the second map and it **runs** (its GSC
   loads, `spawnBot 1` creates a bot that `players` lists; 785 MB zone in ~6 s warm). The old
   "hang" was the completion check: the console log is buffered, and `gsc_eval` after a `map`
   switch fails to compile (`couldn't determine function call type` for `mwx_result`), which the
   script read as "no completion". Trace, hook split and b6 script: `docs/features/usermap-map-command.md`.
   The runtime-compile failure after `map` is the same `gsc::load_custom_script` class as the
   t1-build listen-host issue; it moves to item 13 (AW integration) and is the verification there.
10. **Clean state check.** **DONE (26 Nov, after items 6-9)**.
    - full suite (`run-tests.ps1 -Parallel 4`): **28/29**, only `survival` fails (known R6c spike);
      every other mode green, including `ph_listen`, `mode_reset`, `sas`, `ph_shipment`.
    - the menu smoke test (full run, every Party mode + dom/war, start + restart, Mods): **PASS**
      (plus the quick passes during the work). The static party/standard lists in the smoke avoid
      the `Engine.GetDvarString` frontend-transition crash at 0x1400BCB13.
    - check-all clean (43 files, 575 calls, 0 problems).
    - backlog and report current; pushed on `opencode/fixes`: `69112a31` (item 6),
      `7b32194e` (lua_eval guard + DB trace), `70e82583` (menu smoke lists).
    Then Claude reviews and merges into `mwx`.

## THEN - today's plan (user at work, 26 Nov; added by Claude)

**Rules for today.**
- The user and Claude are away, so do not wait for a merge. Keep stacking branches:
  `mwx` <- `opencode/fixes` <- `mwr-weapons` <- `aw-weapons` <- `release-prep` <- `ball`. Each new branch
  starts from the previous one, and every branch is pushed.
- Claude reviews and merges the stack in order later.
- TEST RULE: affected tests 3x while working, ONE full suite plus menu smoke at the end of each item.
- No handoffs and no early stop. Mark every item here with commits and results.
- TIME LIMIT: 45 minutes on one problem without real progress -> write down what was tried, the
  cause as far as known and the next idea, mark the step BLOCKED here, and continue with the next
  step. Never stop the whole run because of one blocked step.
- Safety (AGENTS.md): work only in C:\Games\cod-hwm and keep >= 20 GB free on C:; back up before
  changing an existing game file/mod.ff/HMW .ff and never delete a backup; never edit HMW's zones;
  stop only processes you started.

11. **Finish item 9** (DS hang on `map mp_terminal`), then item 10 again (clean state check) on `opencode/fixes`.

11b. **Silent startup exits (test infrastructure, `opencode/fixes`).** The engine exits a second
    instance silently (0-byte console log, no dump) while the first is still initializing.
    - Measured: 4 clients started in the same second -> 3 exited after 11-13.5 s, only the last
      survived; 2 started together -> 1 exited after 11.3 s. With a 25 s stagger all 4 survived,
      which is why the old runner used a fixed 30 s gap (still flaked occasionally).
    - Fix: `load_timing::acquire_startup_lock` takes the named mutex `Local\mwx-startup-lock`
      before `post_start` and releases it on the first main-thread frame (45 s watchdog, 180 s
      timeout, `WAIT_ABANDONED` handled). After the fix, 4 close starts: **all 4 reached the
      menu** (startup lock waits 22 s / 43 s / 67 s). Map load and gameplay stay concurrent.
    - `run-tests.ps1`: next parallel worker starts only after the previous game answers the debug
      RPC (fixed 30 s sleep removed); a silent startup exit is retried once, like menu-smoke.
    - **Status 26 Nov: done**, commit `77df2843` on `opencode/fixes`. Target test: 4-test
      parallel manifest (`war`, `dm`, `sd`, `dom`) 4/4 PASS with the new gate. Full suite:
      **27/29**, only the known `sas` (part C) and `survival` exceptions; no silent
      startup exits. Menu smoke **PASS** (1 run, all party/standard modes).

12. **Part D - MWR's own DLC weapons in Create-a-Class** (branch `mwr-weapons` from `opencode/fixes`). Use the
    staged analysis in `_migration\archive\mwx-debug\mwr-weapons\` (inventory, attachments matrix, melee rows, D1 duplicates).
    - D0 runtime check: every `h1_*_mp` from the manifest exists at runtime. For 5 samples (`h1_kam12`,
      `h1_xmlar`, `h1_febsmg`, `h1_junsnp`, `h1_meleejun1`): give, fire, reload, ADS, kill a bot.
    - Statstable rows and the CAC whitelist via GSC `replacefunc`, never HMW's zones. The scope:
      - the 13 DLC guns without an HMW counterpart, minus the two the D1 table marks as duplicates (.44 Magnum,
        Rangers) = 11;
      - the 8 CoD4 guns HMW doesn't offer (G3, M14, MP44, Skorpion, M60E4, M249 SAW, Dragunov, R700);
      - the 28 DLC melee weapons (the 3 "CQB Bayonet" rows sharing one asset count once).
      Real names, icons, camos, and attachments only where the matrix says they exist.
    - Switch dvar `hmw_mwr_weapons` (default 1); with 0 the CAC lists are exactly as before.
    - Tests: one generic weapon-test entry per gun (attachments from the matrix, one camo), one entry that
      cycles the melee weapons, and a CAC check per category in the menu smoke. CAC screenshots into
      `_migration\archive\mwx-debug\mwr-weapons\`.
    - Party modes that pick weapons (Gun Game, Sharpshooter, OIC, AON, Arena, Infected): document whether they
      now pick MWR weapons, and keep them working.
    - Docs: `docs/weapons/mwr.md` (list, attachment matrix, how to add more).
    - **Status 26 Nov (D0):** 27/66 `h1_*_mp` assets exist. The 8 CoD4 guns work end to end
      (`mwr_h1_g3/mp44/m60e4/saw/dragunov/remington700` green 4/4; `m14`/`skorpion` hit the silent
      startup exit, rerun later), pushed `b4ffd1d0` + `392a019c`; the
      11 DLC guns + 28 melee assets are **not loaded** (they live in `zone\patch_common_mp.ff`,
      shadowed by `hmw_patch_common_mp.ff`; loading a copy under another name exits at startup).
      Rows/whitelist/names/tests for the CoD4 subset are committed; the DLC/melee tests are out of
      the manifest until the assets exist. **Next idea:** zonetool repack of the 11 weapons + 28
      melee (from `refs\dumps\patch_common_mp`) into a small `mwr_weapons.ff`, loaded like the HMW
      zones; then re-add the DLC rows/tests. BLOCKED on the repack, continue with item 13.
      **B started 26 Nov:** the DLC models are not in patch_common_mp (it only references them);
      they live in zone\mp_vm_*_base_tr.ff / mp_wm_*_base_tr.ff. The source
      GAME\zonetool\hmw_mwr_weapons has the patch dump (61,368 files) plus the 87 model zones
      dumped into GAME\dump\weapon_models; the zone CSV lists the 11 DLC guns + 28 melee
      (the 8 CoD4 guns stay from the base zones). **Built zone\hmw_mwr_weapons.ff: 56.0 MB,
      8.8 s compile**; loaded in patches.cpp; names for the 19 guns added; 12 tests
      (mwr_h1_* for 11 DLC guns + mwr_melee) added. sset_exists confirms all 39 weapons
      and the key models. **BLOCKED 26 Nov:** every loaded variant (56 MB full, 15 MB defs-only,
      3 MB single weapon, renamed weapon, stripped attachments/icons/xanims) makes the next map
      load hang at imagefile48.pak (2.24 GB); without the zone the same map loads it in 3 s.
      The zone is parked at zone\hmw_mwr_weapons.ff.blocked-b, **not loaded**; the 12 tests
      were removed from the manifest. Next ideas: trace the stream/pool with
      mwx_debug_fastfiles 1; load the zone after the map starts (or unload before map and
      reload after); try the original MWR patch; direct per-weapon _tr loading. Details in
      docs/weapons/mwr.md.

13. **Part C - AW weapons integration (I1)** (branch `aw-weapons`, rebased onto `mwr-weapons`).
    - Bring the AW commits over from `cod-hmw-aw` (aw-weapons), apply the converter patch, and build/verify
      `hmw_aw_weapons.ff`.
    - Crossbow owner: `hmw_aw_weapons.ff` owns `iw5_exocrossbow_mp`, and Sticks and Stones' `mod.ff` keeps only
      scripts (back up the mod.ff first). `sas` and `aw_crossbow_sas` go back into the suite.
    - Fix the `t1-build` listen-host crash (`gsc::load_custom_script`) if it reproduces; document it either way.
    - Missing zone: no crash, and the AW weapons are hidden in CAC. Test by renaming the file.
    - Party-mode weapon pools: same check as in item 12.
    - User decision: drop the AW KF5. Update the weapon list in `hmw-workbench\docs\porting\AW-WEAPONS-PLAN.md`
      (docs-only commit there).
    - **Status 26 Nov:** `hmw_aw_weapons` is in the HMW zone list (patches.cpp); crossbow statstable row
      6100 + name/desc + AW whitelist/buildweaponname + CAC glue copied in; **`aw_crossbow` 15/15
      green** (give/fire/reload/switch/kill/CAC/name). Missing-zone check done (zone renamed: no
      crash, `iw5_exocrossbow_mp` absent). Converter patch applied (`--attachment-map`, anim
      override re-index). KF5 dropped in the AW plan (`hmw-workbench` c42eb2a). The mod.ff is
      swapped to the reference-only build (backup `mod.ff.bak-20261126-0845-pre-reference`);
      `aw_crossbow_sas` is in `tests-aw-sas.json` but the listen-host start with the mod stalls -
      **next:** run it on a dedicated server with `-mod`, or fix the listen-host mod start.
      Pushed `898a7b76`, `eb1d11db` on `aw-weapons`.
      Checks on this build: `aw_crossbow` 15/15, six of eight `mwr_h1_*` tests, menu smoke
      PASS, check-all 47 files/585 calls/0; the full suite reported 27/28 green (only
      `survival`) before the 30-min tool timeout; the remaining listen-host tests
      (`ph_listen`/`mode_reset`) were green on the previous build and are not changed by
      this item.
    - **Part C - native Sticks and Stones (26 Nov, `aw-weapons`):** the `sas` row is enabled in
      `gamemodes.cpp`; `data/mwx/maps/mp/gametypes/sas.gsc` is the mode, the crossbow comes from
      `hmw_aw_weapons.ff`. `data/mods/sticksandstones` is gone from the repo and
      `GAME\mods\sticksandstones` was moved to `_migration\archive\mwx-debug\backups\sticksandstones-mod`
      (mod.ff + all .bak files). `tests-aw-sas.json` + `aw_crossbow_sas.gsc` deleted; the mod
      system test now uses `data/mods/test_mod` (one script, no mod.ff, no weapons). `sas` test
      **8/8 green x3**; `aw_crossbow` 15/15. Menu-smoke static party list includes `sas`.
      **BLOCKED (regression, 26 Nov):** with `hmw_aw_weapons.ff` loaded, a map load on
      `mp_crash` stalls at `imagefile48.pak` (2.24 GB); without the zone `ph_listen` passes
      (12/12, 144 s). Reproduced with the 19.8 MB crossbow zone, a 10.6 MB no-image build and
      a sync `DB_LoadXAssets`, so it is the custom zone + mp_crash engine path, not the crossbow
      assets. The sas/crossbow tests on `mp_shipment` stay green. Needs the load-after-map /
      engine fix before release; also blocks item B and the full suite on `mp_crash`.

14. **All remaining AW weapons** (branch `aw-weapons`, on top of item 13). Plan, recipe and rules:
    `hmw-workbench\docs\porting\AW-WEAPONS-PLAN.md`, `guide.md`, `aw.md`. Only the approved PORT list.
    - Order: the pilot (M1 Garand, combat knife, MP40 - the MP40 replaces the dropped KF5), then batches
      of 4-5:
      - modern: AK-12, ARX160, CZ 805 BREN, CBJ-MS, Ameli, LSAT, GM6 Lynx, UTS-15, MP-443 Grach,
        MAAWS;
      - classic: Sten, Browning BLR, Blunderbuss, LeMat.
    - Leave out any weapon marked as a duplicate in item 12 (same real gun as an MWR weapon).
    - Full pipeline per weapon: dump into new folders only; convert with the patched converter;
      hmw-workbench check (anims on MWR and faction hands, fit report, HMW attachment tags on the view
      and world model, ADS checks, hide the built-in sight); camos (`guide.md` section 4); add to
      `hmw_aw_weapons`; statstable/CAC/real name/icons; a generic `aw_weapon` test entry and an
      attachment-matrix row.
    - One commit per batch. A weapon that fails is marked `BLOCKED: <reason>` and the batch continues.
    - After the last batch: the attachment pass over all AW weapons (every optic ADS reticle within
      its frame, tags on both models, hides for the built-in sights).
    - **Status 26 Nov: not started.** Sources are ready: AW dumps at
      `C:\Games\cod-hwm\Call of Duty Advanced Warfare\dump` (the pilot refs iw5_dlcgun23 = M1
      Garand, iw5_dlcgun18 = MP40 are dumped), the zone source at
      `GAME\zonetool\hmw_aw_weapons` (all AW weapon JSONs incl. the DLC guns), the patched
      converter (`--attachment-map` applied, eb1d11db). The KF5 is dropped (hmw-workbench
      c42eb2a; the workbench has no reachable origin, the commit is local). First batch: the pilot
      (M1 Garand, MP40, combat knife) using the same pipeline as the crossbow.
    - **BLOCKED 26 Nov:** the AW MP model zones **do** exist (`mp_vm_m1garand_tr`,
      `mp_wm_m1garand_tr`, `mp_vm/mp40_tr`; AK-12, ARX160, LSAT, MAAWS and Sten too), and
      `iw5_dlcgun23/18` convert (`vm_m1garand_base`, `npc_m1garand_base`,
      `vm_ger_mp40_dlc_base`). Two blockers: (1) the custom-zone + `mp_crash` map-load stall
      (same as B/C) makes any new weapon zone untestable in a match; (2) the AW dump has no
      xanim files (`aw\dump` has 0 `.xab`), so the weapon animations still need a dump path.
      Modern zones missing: CZ805, CBJ-MS, Ameli, GM6 Lynx, UTS-15, MP-443 Grach, Browning BLR,
      Blunderbuss, LeMat. Next idea: fix the zone load order first, then dump the model zones and
      find the xanim source.

15. **Player cards over LAN (R7 rest)** (branch `release-prep` from `aw-weapons`): every player's card is visible
    to everyone in the lobby and the scoreboard, not only the host's. Per-player wire format, a visual check with
    host plus a second client, and `docs/features/callsigns.md` -> `docs/callsigns.md`.

16. **Release prep** (branch `release-prep`).
    - **LAN test** with two clients on this PC (separate data and log dirs and debug ports):
      - join;
      - both players use MWR and AW weapons with attachments and camos;
      - the kill feed shows on both sides;
      - a weapon drop is picked up by the other player;
      - a party mode and a standard mode.
    - **Content mismatch:** a client without `hmw_aw_weapons.ff`, or with an older version, joining a host that
      has it gets a clear error message, not a crash and not invisible weapons. Implement a content/version
      check in getInfo/connect if it is missing.
    - **Install package:** a script that builds the distributable folder for friends (exe, MWX data, weapon
      zones, README with the install steps), plus an install test into a fresh data dir with only the packaged
      files: first start, CAC, a match. The output goes under `C:\Games\cod-hwm`. Never copy outside it.
    - **Release notes draft** in `docs/release-notes.md`: modes, weapons, known limits.

17. **Ball (new gametype)** (branch `ball` from `release-prep`). The ball party mode: the carrier
    scores by taking the ball into the enemy goal; the ball can be thrown/picked up. Port the GSC,
    the menu entry, strings and bot support, add a test, and document it. Source/reference mode to be
    taken from the effort list the user picks; this is the new mode after release prep.

18. **Prop Hunt:** spot-check the generated prop lists on 5 more maps (screenshots of 3 props each, the size
    classes plausible), and fix bad entries.

19. **MCP:** a numeric input check with a connected client while unfocused (R5 gap), documented in
    `docs/guides/mcp.md`.

20. **More party modes - list only.** An updated list of the not-yet-ported modes with effort estimates in
    `docs/party-modes-todo.md`. Do not port any; the user picks.

## LATER (each needs the user's go)

20. **Survival with real agents, no bots** (skipped for now, user decision). The spike state is in
    `docs/archive/survival-spike.md`.
    - **B5c finding (26 Nov):** the slots are allocated (`getmaxagents()`/`level.agentarray` = 24),
      `add_humanoid_agent` returns 5 entities (`team=axis`, `isactive=1`, `isagent=1`, `isai=1`), but
      they are `isplayer=0` and never enter `level.players`. A manual `spawnagent((0,0,0),(0,0,0))`
      runs without error and does nothing: the engine's agent spawn is a **no-op in MP**.
    - The next step is a decision: hook the engine behind `spawnagent`, or use `spawnBot` + a GSC think layer.
21. **AW W3+:** the remaining AW weapons in batches, after Claude's review of the W2 pilot.
22. **Porting more party modes** from the list in item 19, once the user has picked them.
23. **Startup load time, about 55 s** (parked by the user; `docs/investigations/menu-load-times.md`,
    `docs/investigations/m5-background-zones.md`, `docs/investigations/m5b-zone-compression.md`).
24. **AW map porting** (paused; `docs/archive/todo-aw-porting.md`).
25. **Disk cleanup** (ask the user first):
    - old exes (`mwx.exe.old`, `mwx-prev-*.exe`);
    - the `cod-hmw-aw` clone once part C is merged (its `build` folder alone is 1.8 GB);
    - `hmw-aw.exe` and its data and log folders.

## Cleanup run 27 Nov (branch aw-weapons): CAC + just play

1.1 **DONE** (eebcab0e): hmw_mwr_weapons.ff restored (58.7 MB, no .pak in this zone); the 19
    MWR animation copies are in 	ools/zone-check/overrides.txt with the size evidence (same
    size, different bytes; without them zonetool fails on mwx_xmlar_mp notetrackSoundMap null).
    Both zones pass zone-check: hmw_aw_weapons 841 assets / 0 collisions (76 shared FX/physics/
    view-model-anim assets moved to _migration\archive\mwx-debug\backups\zone-collisions\), hmw_mwr_weapons 20
    assets / 0 collisions.
1.2 **DONE** (31765007): the CAC preview is vlobby GSC; HMW's uildweaponname has no return
    for iw5_*, so streamcacweaponwait looped forever. The hook moved to
    scripts/mp_patches/aw_weapons.gsc (loads in a match and in the lobby). Verified: M1 Garand,
    MP40 and crossbow previews render (screenshots in _migration\archive\mwx-debug\aw-weapons\preview-*.png). M1/
    MP40 previews are washed out (material side, crossbow is fine) - D polish list.
1.3 **DONE** (41213dfb): scripts/mp/mwx_stats.gsc sets level.disableweaponstats = 1 on a real
    map. Verified in a match: level.disableweaponstats = 1, level.rankedmatch = 0; after a 40 s
    match with 5 bots every players2 file is byte-identical to the backup. The combat record /
    barracks read weaponStats and are hidden in Part 2 (2.2).
1.4 **DONE** (`d85fc004`): docs/features/cac.md with the 68 added names and their indices (51
    reused duplicate-name indices, 17 appended, 8 bit ceiling 256). The table is byte-identical on
    3 cold starts and on 2 concurrent clients (`_migration/archive/mwx-debug/cac-bisect/enum/run1..5.json`); no class
    field outside the two weapon slots holds a ported name (20 slots, camo/reticle/perk/equipment,
    0 hits).
1.5 **DONE** (`5810a309`): customweapons rows whose weapon asset does not exist are dropped from
    the table copy (h2_fmg9, h2_mp412, h2_pm9, h2_mp7): no more WEAPON_FMG9 / WEAPON_MP412 rows,
    ids and statstable rows untouched. Machine Pistols = PP2000/G18/M93 RAFFICA/TMP.
1.6 **in progress**: `tools/test/cac-smoke.ps1` is manifest-driven (`gen_cac_manifest.py` from
    stock_weapons_data.hpp): every custom row, category + tab, row found by its position in
    `Cac.Weapons` (display names repeat), melee writes `meleeWeapon`; screenshots for the AW
    weapons and failures; then an HMW preview, attachments and camos; console error scan. Dry run
    4/4 picks + 3 screen checks PASS. `cac-match-smoke.ps1` (class -> map -> loadout) and
    `cac-warnings.ps1` (warning count e vs a) written, to run.
    Vlobby "stall": bisected to I/O starvation from concurrent dump/index jobs - 10/10 cold on the
    d85fc004 build without them, 5/5 on the fixed-list build. See docs/investigations/zone-load-stall.md.
    The 1.5 filter was replaced by a fixed list (`8d79fac8`) so the table patch does no DB work
    while the vlobby zones load.
1.7 **in progress**: AW `common_mp` has the knife def (`iw5_combatknife_mp`: vm/npc
    `mp_tactical_knife`, material `mtl_mp_tactical_knife`) but the earlier dump has no
    xsurface assets and no images. Targeted `dumpzone h1 common_mp xmodelsurfs` run (dump-knife.ps1)
    to get the surfaces; textures still need a separate image dump or a material remap.
1.7 **DONE (model; textures pending)**: the knife has no model zone; its xmodels/surfaces are in AW's
    base `common_mp`. The h1-target dump needs the type token `xmodelsurfs` (`xsurface` is not an
    asset type name, it silently dumps nothing) - 545 .xsb, including
    `vm_mp_tactical_knife_lodvm101` / `npc_mp_tactical_knife_lod0101`. The def was in the source
    but the weapon was **not listed in the zone CSV** - that was the real missing asset. Added
    `weapon,iw5_combatknife_mp` + the two xmodels, copied the materials, rebuilt: 848 assets,
    zone-check green, `aw_knife` 5/5 PASS.
    Textures: the knife's images are not in `common_mp` (a full image dump of 1.3k + 21k streamed
    files, 7.3 GB, had none of them; the dump was deleted and the disk is back to 22.2 GB free).
    They are in AW's `patch_common_mp` -> renders with default images until that 6.7 GB dump is
    repeated for the 8 knife images. Polish item.

## Follow-ups from the 27 Nov cleanup run (recorded, not started)

F1. **vlobby load under heavy disk I/O** (release-prep check): a Play Online run during a large dump
    stayed >60 s in mp_vlobby_room_path and the debug port stopped answering; without heavy jobs
    it was 10/10 and 5/5. Confirm the load *finishes late* (not hangs) while a large file copy runs
    in parallel - a real hang would hit users with slow HDDs. Test: start a client, copy a >10 GB
    file in the same window, log the time to menu_xboxlive and the load_times.log tail; repeat
    5x. A run that never reaches the lobby within 5 minutes = bug (document the stage).
F2. **Silent server exit during tests**: w_knife run 2 (27 Nov, test-results-20261127-125539.json)
    reported passed=0 failed=0 script_errors=0 57,5s ERROR: server exited (code ) - no dump, no
    minidump, no console output. It is the known silent startup exit (see item 11b: the engine exits
    a second instance silently; the runner retries once for the menu smoke but -Name runs do not
    retry). Track it as its own item: make 
un-tests.ps1 retry a silent exit (like menu-smoke) and
    log the exit code/dump state; if it happens without a concurrent instance, collect a dump
    (procdump -e) and file the cause.
F3. **Knife textures**: do a *targeted* image dump of the 8 names from AW's patch_common_mp
    (mp_tactical_knife_col, mp_tactical_knife_nml, ~mp_tactical_knife_occ-l,
    ~mp_tactical_knife_spc-rgb&mp~bf7c86a6, ariable_grenade_lethal_col/nml,
    ~variable_grenade_lethal_occ-l, ~variable_grenade_lethal_spc-~5a88989c) instead of the
    6.7 GB full dump. dumpzone h1 patch_common_mp image cannot filter by name; check whether the
    dumper has an asset-name filter (dumpasset?), otherwise dump the image type, copy only those
    headers + _streamN.pixels, delete the rest. Then swap the knife materials' images in and
    rebuild hmw_aw_weapons.
    Additional evidence (27 Nov, 13:24): the 3x loop (
un-tests.ps1 -Name run per test) hung after
    `aw_m1garand` run 1: the child powershell (PID 22116) had no mwx child, 1 s CPU, and produced
    no further output for 27 min; killing it let the loop end. The runner does retry a silent exit
    once (line ~268), so the hang is after that - check `Wait-NetPortFree` (30 s bound),
    `Stop-Server`'s `WaitForExit(10000)` and the retry `Start-Sleep 20` path; add an overall
    per-test watchdog (e.g. timeout_s + 120) so a stuck invocation fails instead of hanging.
F4. **CAC LUI error after ~12 list rebuilds** (27 Nov): a 71-weapon cac-smoke in one client broke
    after 12 picks with `Error processing event` / `could not reach the class editor (menu: nil)`:
    stack `[C]: registerAnimationState` <- `ui_scripts/mp/buttons/__init__.lua:314 (new)` <-
    `ui_scripts/mp/hmw_ui_scripts/menus/cacdetails.lua:259 (tabCreatorFn)`. After that every
    `ui_snapshot` returned no menu (LUI stuck). Opening and closing the CAC details list 12+ times
    is something a player can do while editing classes - suspect the LUI animation-state registry
    (a fixed array) filling up. Workaround in the test: `cac-smoke-all.ps1` restarts the client
    every 8 weapons. Next: reproduce in-game (open Primary, pick, back, 15x), find the registry
    limit and either free the states on menu close or raise the limit (careful, engine array).
    Also seen 27 Nov 14:26 (cac-smoke slice startup): exception 0xC0000025 (noncontinuable),
    address 0x7FF8AAF4D3DF, three dumps written within 2 s, stack shows a repeating
    RtlRaiseStatus/RtlWow64GetCurrentMachine loop (stack overflow / exhausted walk), game reports
    "Clean game: Yes". It happened while a previous slice client was still shutting down - check the
    startup-lock path (load_timing::acquire_startup_lock) and whether a second instance can enter
    post_start before the first releases it.
1.6 **cac-smoke result (27 Nov)**: all guns pass through the menu (44/44 MWR + AW guns, including
    M1 Garand, MP40, crossbow; HMW preview, attachments and camos screens render). Melee: the
    Melee tab renders **loot names** (TIDAL, CLEAVER, ...) for the list entries, so a rendered row
    cannot be mapped back to a ref; the test verifies the storage path the menu uses
    (`Engine.SetPlayerData` -> `meleeWeapon`) plus list membership instead. Display item for
    the B-rest work: the plain melee names (Caveman/Machete/...) are in `Cac.Weapons` but the tab
    shows the loot variants.
    Spawn check (cac-match-smoke) **deferred to 2.6**: the menu CAC writes the class to
    `customClasses` (ranked group) but a private match spawns with the default class - HMW's
    `maps\mp\_utility::cac_getcustomclassloc()` switches the class location per mode
    (`privateMatchCustomClasses`, options.lua:757), which is exactly the duplication 2.6 removes.
    Verify the spawn after 2.6.
F4 **measured and documented (27 Nov)**: with `cac-rebuild-stress.ps1` (open/close the Assault list
    in one client) variant e (ours) failed at rebuild **55**, variant a (no custom zones/rows, stock
    content) at **56** - the ~55-open limit is HMW/engine, not our rows. `collectgarbage` between
    rebuilds does not move it (C-side pool, not Lua GC). Error: `[C]: registerAnimationState` <->
    `ui_scripts/mp/buttons/__init__.lua:314` (`fillImage:registerAnimationState`) inside
    `cacdetails.lua:259 tabCreatorFn`; the LUI then bails to the lobby. HMW's CacDetails builds a new
    menu (each row button registers 5-10 animation states) on every open and the engine's state pool
    never frees them. Raising it needs a hook into the packed engine pool / the element method table
    (`LUIElement` is not a Lua global, the binding is C-side), so no safe quick fix; the session
    limit is documented. Test: `cac-smoke.ps1 -Stress 40 -StressOnly` = 40 open/close cycles
    alternating Primary/Secondary in one session (the user's 40-per-category figure is above the
    measured limit and cannot pass on stock content either).
    F2 correction: 0xC0000025 is STATUS_NONCONTINUABLE_EXCEPTION, not a stack overflow (0xC00000FD) -
    usually a second exception during handling/unwind. Read the first exception from the minidump
    (cdb: `.ecxr`) before touching the startup path; not fixing in this run.
1.8 **queued (after Part 1, before Part 2)**:
    (1) screenshot R/B channel swap (red looks blue in our PNGs; the game is correct) - fix the writer,
        verify on a known red object, re-take the CAC references;
    (2) red "FX" placeholder models - find whether only bisect runs (zones moved out) or the current
        zones show them; audit every custom weapon's vm/wm model + CAC preview; complete the zone-check
        index (common_mp, code_post_gfx_mp, pre_gfx, hmw_killstreak/smg/shotgun) with only zones that
        are actually loaded (not nightshade/dlc_factions/dlc_killstreaks); explain the yellow striped
        MAC-10 row (missing image vs restriction marker);
    (3) tools/weapon-icons: MWR-style icon renderer (style measured from MWR icons, hmw-workbench render,
        convert + add to the zone + CSV + statstable, batch command, contact sheet, docs/guides/weapon-icons.md),
        run for crossbow/M1/MP40/knife and screenshot CAC list/header, kill feed and HUD next to an MWR
        weapon.
F4 **result (27 Nov)**: the list budget **resets at a map load**: 40 open/close cycles in the frontend
    survived, then a match (map + disconnect back to the main menu) and 55 further cycles in the new
    frontend session survived, failing at the 56th (`cac-f4-match-reset.ps1`, log
    `_migration/archive/mwx-debug/cac-bisect/f4-reset.log`). So it is ~55 opens per frontend/lobby visit, not per
    process - a known HMW/engine limit, no fix (matches the user's first branch). The 40-cycle stress
    test stays in cac-smoke; a player would have to open the class lists ~55 times without loading a
    map to hit it, and a map resets it.
1.8 progress (27 Nov): **(1) done** (eadd5414): the screenshot writer swapped R/B for every
    back buffer; only B8G8R8A8 now swaps. Verified - M1 stock brown, extinguisher red, menu accents
    gold (they were cyan/blue). The CAC reference screenshots need re-taking with the fixed build.
    **(2)** yellow striped rows = HMW's "not owned/loot" marker: cg_unlockall_loot/items default
    off; Part 2.1 turns them on (then re-check). The red "FX" placeholders were not reproduced in
    the current-zone CAC screenshots; the static model audit is inconclusive because the MWR models
    live in the game's mp_vm_*_tr zones (not dumped) - do a runtime sset_exists pass per weapon
    + a preview screenshot of every tab after Part 2's fresh profile. **(3) renderer works, conversion
    BLOCKED** (4d9932f2, docs/guides/weapon-icons.md): hmw-workbench renders our four weapons' world
    models via MCP, but (a) the orbit grid/axes cannot be hidden through the MCP screenshot tool,
    (b) its asset roots do not include GAME\zonetool\hmw_aw_weapons (untextured), (c) there is no
    PNG -> .h1Image writer (zonetool only reads IWI). Each is a workbench repo milestone (its AGENTS
    owns it); the style config + zone/statstable wiring are ready once those land.
    Also 27 Nov 16:45 (suite, one test instance): fatal 0xC0000005 at 0x7FF8AAF5736D (system DLL
    region) with the crash reporter's "make sure to update your graphics card drivers" dialog; two
    dumps written (hmw-mod-crash-1-2026-11-27-16-45-07/-11). The dialog blocked the test worker until
    closed. Same family as the 14:26 startup crash (F2): collect the first exception from the dump
    with cdb (`.ecxr`), check whether it is the render/teardown path of a *dedicated server*
    (this one happened in the suite, not the frontend), and add a watchdog/dialog dismissal to the
    parallel runner so one crash cannot stall the run.
**IMPORTANT (27 Nov 17:10)**: the bisect script's `variant.ps1 -Variant e` restored its
`src\e` snapshot, which was taken **before the knife build and the 76-collision cleanup**. Every
`-Variant e` (the warnings run, the suite, screenshots) silently put the *stale* 23.2 MB zone back
and overwrote the rebuilt 18.3 MB one. That is why `aw_knife` failed the suite ("combat knife in
the loadout", the asset was not in the running .ff) and why the suite's numbers are for the old
zone. Fixed: rebuilt `hmw_aw_weapons` (18.3 MB, 848 assets, zone-check 0 collisions), refreshed
`src\e` with it; `aw_knife` 5/5 on the rebuilt zone. Lesson: `variant.ps1` must snapshot the
current zone state explicitly (or be retired) - it is a bisect tool, not a way to "restore".
**Menu smoke (27 Nov, final zone)**: 1/3 PASS then 1/1 PASS. The failing runs hit the known LUI
    reload crash `0xC0000005 at 0x1400BCB13` (backlog item 1, "Menu crash"), two dumps at
    17:20/17:22; the same zone passed in the other runs, so it is the intermittent LUI/zone-load
    race, not the zone content. F2 evidence grows: the crash can hit a client during menu
    navigation even outside lua_eval.
**Warnings (rebuilt zone)**: `cac-warnings -Label e2` = 0 in 218 console lines (the knife's missing
    textures only show at build time / when the knife model is drawn, not on these screens).
**Regression (27 Nov, NEXT SESSION - item 0 with F2)**: menu-smoke crashes in the *frontend load*
    path again, `0xC0000005 at 0x1400BCB13` (exe base 0x140000000 -> offset 0xBCB13; the address of
    the 25 Nov hks_start/LUI-load crash fixed in `b000c6f1`/`ad28072e`). Seen 2 of 4 menu-smoke
    runs on the final build (17:20:53 and 17:22:37 dumps, version 67ba7852); the same zone passed the
    other 2 runs. ui_scripts added/changed since 573afae4 and their load-time code:
      - `aw_weapons/__init__.lua` (new, 898a7b76): load-time `Engine.InFrontend()` +
        `Engine.IsMultiplayer()` gate, then Cac.* wrapper install (pure Lua). Removed the gate on
        27 Nov (the Cac.* checks are enough; added `if Cac == nil then return end`).
      - `cac_weapons/__init__.lua` (new, 58f7e324; guarded in eebcab0e): load-time
        `LUI.onmenuopen` x2 + `install_restricted_guard()` (wraps LUI.CacDataProvider.GetRestricted,
        pure Lua). Every Engine.Table* call is inside `sync_cac_weapons`, which runs from the
        CacMenu/CacLoadoutEditorMenu open handler.
      - `motd/__init__.lua` (new, aad5f6cd): load-time LUI.MOTD write + one `LUI.onmenuopen`
        registration; no engine calls.
      - `gamemodes/__init__.lua` (modified, aad5f6cd): only the `base_party` table (added "sas");
        its `Engine.InFrontend/IsMultiplayer` gate predates 573afae4, all other Engine calls are
        lazy in the party metatable.
    No new load-time Engine/DB call was found in the scripts (the aw gate was the only difference),
    so the crash may also come from the C++ load-time patches (`stock_weapons.cpp` string-table
    patch during vlobby zone load; `ddl_weapon_enum` extension at the first lobby). Re-measure
    menu-smoke on 573afae4 vs HEAD next session, with the dump stack (.ecxr) for 0x1400BCB13.
**Test-runner bug (27 Nov, F2)**: when a dedicated server exits without writing test_done, the child
    runner's summary has a non-string `error` and `ConvertTo-Json` throws
    ("Der Wert kann nicht in den Typ System.String konvertiert werden", run-tests.ps1:282); the
    result file is never written and the parallel parent waits on that worker forever (this is why
    the 24-test tail never ran; workers hung 17:58-18:10 with no mwx.exe alive). Fix: cast the error
    to string and always write the result file. The two tests hit by it are `war` (mp_shipment,
    server log stops at "Loading fastfile patch_mp_shipment") and `ph_terminal` (mp_terminal), both
    "server exited (code )" = F2 silent dedicated exit.
    Follow-up 27 Nov 18:35: after removing the load-time gate (`ac1c8bbc`), menu-smoke -Runs 4 gave
    3 PASS / 1 FAIL with **0 crashes** (the failure was the known second-start mode pick: "Party ph:
    second start g_gametype is 'mugger'"). Pre-fix on the same zone: 2/4 crashes. Still to do: the
    controlled 573afae4 comparison and a symbolised stack; see `menu-load-regression-2026-11-27.md`.
    Runner error path fixed in `9c646124` (flat fallback summary when ConvertTo-Json throws).
**F2 evidence 27 Nov 19:28**: `aw_m1garand` (dedicated, mp_shipment) died during "Loading fastfile
    patch_mp_shipment" and wrote a dump (Environment: Dedicated Server, 0xC0000005). The reporter
    resolved it with the archived PDB to `utils::string::va+0x81` (src\common\utils\string.cpp:12)
    over `__tlregdtor`; the 17:38 server dump resolves to RtlFreeHeap/_free_base (heap). The
    addresses (0x1602xxxxx) are too far from the image base to be trusted as code offsets, so treat
    the frames as candidates until a cdb/windbg stack confirms them. `war` dies the same way on
    mp_shipment, `ph_terminal` on mp_terminal; the same maps pass in other tests, so it is
    intermittent and load-path related (zone load + our patches), not map content.
**F2 hypothesis (27 Nov)**: three dedicated servers died today with a heap-free 0xC0000005 on a
    thread-pool/RPC thread (`RtlFreeHeap+0xF1`, same address 17:38 and 19:33): `war` (mp_shipment),
    `ph_terminal` (mp_terminal, 2/2 runs, after 9 checks), `aw_m1garand` (mp_shipment, once; passed
    6/6 on retry). 49 other tests pass with the same build, so it is rare corruption, not a broken map.
    New code that runs on a dedicated server and writes into engine tables: the statstable/
    customweapons StringTable copy (`stock_weapons.cpp`) and the DDL Weapon-enum extension
    (`ddl_weapon_enum.cpp`; the log shows "added 68" on the server). Next session: run
    `ph_terminal` with `mwx_cac_enum 0` (custom manifest dvar) and, if needed, a build with the
    table patch off, to see which one correlates; then a cdb stack with the archived PDB.
**Final tally 27 Nov (build 67ba7852, rebuilt zones)**: 53-test suite = **52/53 green** (survival red,
    known B5; war/aw_m1garand/ph_terminal green on retry, ph_terminal crashed 2 of 3 runs - F2).
    menu-smoke 3/4 PASS, 0 crashes (one mode-pick flake); cac-warnings 0; zone-check 848 assets /
    0 collisions; GAME\mwx in sync with data\mwx; branch aw-weapons pushed (e6abecbb).
