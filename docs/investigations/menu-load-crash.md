# Menu/LUI load crash 0xC0000005 at 0x1400BCB13 — regression analysis (27 Nov 2026)

Status: **open, first item for the next session together with F2**. Not fixed in this run beyond
removing one new load-time engine call (see below); the measurement on that build is at the bottom.

## Symptom

`menu-smoke.ps1` clients crash while the frontend/LUI (re)starts:

- Exception `0xC0000005`, address `0x1400BCB13` (exe base `0x140000000`, so offset `0xBCB13`).
- Dumps: `hmw-mod-crash-1-2026-11-27-17-20-53.zip`, `...-17-22-37.zip`, version
  `67ba78521328dc738dde989058b143fe3e46eca6` (the same address as the 25 Nov crash fixed in
  `b000c6f1`/`ad28072e`).
- Call stack has repeating frames (`0x1408B2B0E`, `0x14025D507`, `0x140253CA2`, `0x140230BCA`), i.e.
  a script/VM state machine, not a plain render or allocator crash.
- A separate crash hit a suite client at 18:14 (`0x7FF8AAF85F3E`, system DLL region) — that one is
  the F2 family (16:45/16:47 dumps), not this address.

## What the crash class was on 25 Nov

`b000c6f1` ("no state-dependent engine calls at LUI restart") moved engine/database calls out of the
chunk body of the `__init__.lua` scripts: `aw_maps` probed `Engine.ControllerHasMap` at load (moved to
the map-setup builder), `gamemodes` called `Engine.GetDvarString("mwx_show_survival")` at load (moved
into the lazy `build_list`). The loader trace added in that commit (`mwx-logs/ui_script_load.log`,
`mwx-logs/ui_trace.log`) is how the script/step was identified.

## ui_scripts added or changed since 573afae4

Range `573afae4..HEAD` (branch `aw-weapons`). Four Lua files changed/added; every item below is the
code that runs **at chunk load** (not inside a menu-open handler).

| file | since | load-time code | engine/db calls at load? |
|---|---|---|---|
| `aw_weapons/__init__.lua` (new) | `898a7b76` | `Engine.InFrontend()` + `Engine.IsMultiplayer()` gate; then `Cac.GetValidAttachKits` / `Cac.GetAllDefinedAndValidWeapons` wrappers installed | **yes, 2** (the gate) — removed in `ac1c8bbc`: `Cac == nil` guard instead, wrappers are pure Lua |
| `cac_weapons/__init__.lua` (new) | `58f7e324`, guard in `eebcab0e` | `LUI.onmenuopen("CacMenu"/"CacLoadoutEditorMenu", ...)` registration; `install_restricted_guard()` (wraps `LUI.CacDataProvider.GetRestricted`) | no — all `Engine.Table*` calls are inside `sync_cac_weapons`, which only runs from the menu-open handler |
| `motd/__init__.lua` (new) | `aad5f6cd` | `LUI.MOTD.TryForceOpenMOTD = ...`; one `LUI.onmenuopen("menu_xboxlive", ...)` registration | no |
| `gamemodes/__init__.lua` (modified) | `aad5f6cd` | only `base_party` (added `"sas"`); the `Engine.InFrontend()/IsMultiplayer()` gate predates 573afae4; `Cac.GameModes.*` setup | the two gate calls only (unchanged since the 25 Nov fix); all other engine calls are lazy in the Party metatable |

So the only **new** load-time engine call in a ui_script was the `aw_weapons` gate. It is removed in
`ac1c8bbc`; because `aw_maps` still uses the same `Engine.InFrontend()` gate at load and was safe
before, that call alone is not proven to be the crash trigger.

Candidate non-Lua load-time code added in the same window (worth checking next session):

- `src/client/component/stock_weapons.cpp`: string-table patch for `mp/statstable.csv` and
  `mp/customweapons.csv`, applied while the vlobby zones load (`5810a309`, `8d79fac8`).
- `src/client/component/ddl_weapon_enum.cpp`: extends the playerdata `Weapon` enum at the first
  lobby (`eebcab0e`).
- `src/client/component/screenshot.cpp` (`eadd5414`) is not on the LUI load path.

The 25 Nov crash was in the **Lua load chunk** itself; to prove or disprove the same for this address
next session: symbolise `crash.dmp` with the archived PDB (`refs\pdb\67ba7852...\mwx.pdb`) and read
`ui_script_load.log`/`ui_trace.log` at the crash time. No debugger (cdb/windbg) is installed on this
machine right now; the PDBs are archived per commit, so a symbolised stack is one download away.

## menu-smoke failure rate

| build | runs | pass | fail (crash 0x1400BCB13) | fail (other) |
|---|---|---|---|---|
| HEAD before the `ac1c8bbc` fix (`fbdbf1f1` + rebuilt zone) | 4 | 2 | **2** (17:20:53, 17:22:37) | 0 |
| HEAD after the `ac1c8bbc` fix (same zone, `ac1c8bbc` not yet deployed to `GAME\mwx`) | 4 | 3 | **0** | 1 (18:35, "Party ph: second start g_gametype is 'mugger'" — the known mode-pick flake, also seen 27 Nov 02:49) |
| 573afae4 | **not re-run this session** | | 0 in the archived runs below | 1 mode-pick |

Baseline caveat: 573afae4 itself was not rebuilt/re-measured. The closest archived menu-smoke runs on
that lineage are `_migration\archive\mwx-debug\zone-stall\menu-smoke-3x.txt` (27 Nov 02:49, builds a few hours after
573afae4: 2 PASS, 1 mode-pick FAIL, **0 crashes**) and `_migration\archive\mwx-debug\mwr-weapons\menu-smoke-b.txt`
(27 Nov 05:50: 1/1 PASS) — i.e. **0 crashes in 4 runs** around the baseline, versus 2/4 now. That is
consistent with a regression but not a controlled measurement (different clients, 4 runs each).

## Next session (item 0, with F2)

1. Symbolise one 0x1400BCB13 dump and name the crashing function; compare with the 25 Nov fix.
2. Re-measure: build 573afae4 (`tools\build\build-mwx.bat -nogit` after a checkout), `menu-smoke -Runs 4`,
   then the same on HEAD. Same zone pair, same machine, no other clients.
3. If the `ac1c8bbc` change clears the crash, keep it; otherwise bisect the load-time C++ patches
   (`stock_weapons` table patch, `ddl_weapon_enum`) with the same 4-run protocol.
4. ~~Fix the parallel runner error path~~ **done in this run**: a summary that `ConvertTo-Json` cannot
   serialize now falls back to a flat JSON instead of leaving the child without a result file
   (`tools\test\run-tests.ps1`). A worker that hangs *before* writing anything still needs a watchdog
   (F2).
