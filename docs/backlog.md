# Backlog — the single todo list

The only todo list in the project. Sections: **NOW**, **NEXT**, **LATER**, **DONE** (recent, one
line, linked to the doc). IDs are stable (`N` = now, `X` = next, `L` = later). Historical detail lives
in `archive/backlog-history-2026-11.md` (the old `_migration/archive/mwx-debug/BACKLOG.md`) and in the linked docs.

Status legend: `open`, `blocked`, `in review`, `done`.

## NOW (in this order)

| ID | item | state | doc |
|---|---|---|---|
| N1 | **F2: dedicated-server crashes + runner watchdog.** `war` (mp_shipment), `ph_terminal` (mp_terminal, 2/3 runs), `aw_m1garand` (mp_shipment once) exit with a heap-free `0xC0000005` on a thread-pool/RPC thread after the map loads. Candidate new engine-table writers: the statstable/customweapons StringTable copy and the DDL Weapon-enum extension (both run on dedicated servers). Next: run `ph_terminal` with `mwx_cac_enum 0`, then a build with the table patch off; symbolise with the archived PDB. Add a worker watchdog (a child that hangs before writing its result still stalls the parallel parent; the ConvertTo-Json crash itself is fixed in `9c646124`). | open | `investigations/menu-load-crash.md`, `guides/testing.md` |
| N2 | **LUI-load crash regression `0xC0000005` at `0x1400BCB13`.** Menu-smoke: 2 crashes in 4 runs before `ac1c8bbc`, 0 in 4 after (same zone). Only new load-time engine call in a ui_script since `573afae4` was the `aw_weapons` gate (removed). Not proven; C++ load-time candidates listed. Next: symbolise a dump, re-measure `573afae4` vs HEAD with 4 runs each, then bisect. First item together with F2. | open | `investigations/menu-load-crash.md` |
| N3 | **Weapon icons into the game (1.8.3 rest).** `tools/weapon-icons/` renders MWR-style list/header/HUD PNGs through hmw-workbench; the CAC row and preview still fall back to the world model and the M1/MP40 still warn about missing HUD icons. Blocked on the workbench (hide the orbit grid/axes, add `zonetool\hmw_aw_weapons` to its asset roots) and on a PNG → `.h1Image` + `_streamN.pixels` writer. Then: add to the zone CSV, statstable `image`, `hudIcon`/`killIcon`, contact sheet, screenshots. | blocked | `guides/weapon-icons.md`, `weapons/aw-plan.md` |
| N4 | **1.8.2 rest.** Runtime `asset_exists` pass for the 7 "NO DEF" MWR refs; locate the red "FX" placeholder models (did not reproduce with the current zones); finish the zone-check index with only actually-loaded zones (`common_mp`, `code_post_gfx_mp`, `pre_gfx`, `hmw_killstreak/smg/shotgun`), re-add missing assets; explain the yellow-striped MAC-10 rows (HMW not-owned/loot marker — turns on with `cg_unlockall_loot` in N8). | open | `guides/zones.md`, `features/cac.md` |
| N5 | **Knife textures.** The material uses AW `mp_tactical_knife_col/nml`, `~mp_tactical_knife_occ-l`, `~mp_tactical_knife_spc-rgb&mp~bf7c86a6` (+ `variable_grenade_lethal_*`); they are not in AW `common_mp` — dump them from AW `patch_common_mp` (8 images), add to the zone, rebuild. Until then the knife renders with default images. | blocked | `weapons/aw-plan.md` |
| N6 | **M1 Garand / MP40 lobby preview polish.** Both render but are washed out (AW spec/gloss vs H1); crossbow is correct. Material conversion, cosmetic. | open | `weapons/aw-plan.md` |
| N7 | **F4 CAC list budget.** ~55 open/close cycles of a category list per frontend visit (stock 56), resets at a map load; measured, documented, stress test at 40 cycles is green. No safe fix (engine LUI pool; exe is packed). Keep as a known limit. | done (limit) | `investigations/menu-load-times.md` |
| N8 | **Part 2 "just play".** One Create-a-Class end to end, the STATS menu unlock buttons (`data/cdata/ui_scripts/stats`), turn on `cg_unlockall_loot`/items so the yellow "not owned" rows and the loot marker disappear, then re-check the CAC rows. | open | `features/cac.md` |

## NEXT

| ID | item | state | doc |
|---|---|---|---|
| X1 | **AW batches (after the zone packs).** More AW weapons with the pilot recipe (M1/MP40/crossbow/knife work); the converters and zone source live under `tools/aw-weapon-port` and `assets/zones/`. | open | `guides/aw-weapon-porting.md`, `weapons/aw-plan.md` |
| X2 | **Zone packs L + R.** Repack and load-time budget; keep the startup list at ≤9 zones (8 used), nothing named "mwx". | open | `guides/zones.md` |
| X3 | **Player cards / callsigns.** The private-lobby card is white: patch/background come from the (stubbed) online party service; no snapshot field exists. Options and findings in the doc. | open | `features/callsigns.md` |
| X4 | **Flaky tests.** `war_rust`/`war_terrace` occasionally, `ph_terminal` (N1), silent dedicated startup exits (retried once by the runner). Keep the list and evidence here, no product fix without a cause. | open | `guides/testing.md` |

## LATER

| ID | item | doc |
|---|---|---|
| L1 | AW map ports (30+ maps, after the zone packs). | `guides/aw-maps.md` |
| L2 | Release prep: the "just play" branch stacked on `aw-weapons`, then a release checklist. | `overview/branches.md` |
| L3 | Ball gametype. | — |
| L4 | Startup time (zone list + load order; the vlobby "stall" was I/O starvation). | `investigations/zone-load-stall.md` |
| L5 | Ghosts weapons — the very last item. | `weapons/aw-plan.md` |

## DONE (recent)

| item | commit / doc |
|---|---|
| C0: `opencode/fixes` → `mwr-weapons` → `aw-weapons` merged into `mwx` (no conflicts), built, menu-smoke PASS, pushed (`mwx` = `5bfa3e7f`). | `overview/branches.md` |
| Survival archived on `archive/survival`, removed from the active code and the manifest (suite 52 tests). | `archive/survival-spike.md` |
| CAC: all 71 custom weapons in the class menu, 270/270 refs storable, enum extension documented. | `features/cac.md` |
| Zones: `hmw_aw_weapons` 848 assets / 0 collisions; `hmw_mwr_weapons` restored with 19 animation copies. | `guides/zones.md` |
| Screenshot R/B fix; CAC reference screenshots re-taken. | `guides/testing.md` |
| Weapon-stat saving off in matches (`level.disableweaponstats`); AW 3D previews in the lobby. | `weapons/aw-plan.md` |
| Combat knife ported and in the zone (`aw_knife` 5/5); textures still N5. | `weapons/aw-plan.md` |
