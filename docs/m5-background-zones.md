# M5 - background loading of the HMW content zones (investigation, not shipped)

Goal: show the main menu before the nine HMW content zones (`hmw_killstreak`, `hmw_attachments`,
`hmw_ar1`, `hmw_smg`, `hmw_shotgun`, `hmw_rangers`, `hmw_nightshade`, `hmw_dlc_factions`,
`hmw_dlc_killstreaks`, ~28 s total) are loaded, load them after the menu, and gate every map start
until they are in.

## What was implemented and measured

Two variants were built and measured (3 client starts each, `tools/test/measure-startup.ps1`,
`mp_crash`, `mwx_test_mode`):

1. **Old behaviour** (all zones in `ui_init_stub`, `DB_LOAD_ASYNC_NO_SYNC_THREADS`):

   | run | first main-thread frame (menu) | map load |
   |---|---|---|
   | 1 | 61.3 s | 23.9 s |
   | 2 | 63.5 s | 32.9 s |
   | 3 | 55.9 s | 24.1 s |

2. **Background after the menu** (`ui_init_stub` loads only `hmw_dlc_factions`; a scheduler task
   after the first frame calls `DB_LoadXAssets(..., DB_LOAD_ASYNC)` for the other eight, completion
   polled through `g_zoneCount`/`g_zones`, every map load waits):

   | run | first main-thread frame | map load | menu actually usable |
   |---|---|---|---|
   | 1 | 60.2 s | 20.8-25.3 s (waits, then loads) | ~100 s |
   | 2 | ~53 s | ~23 s | ~100 s |
   | 3 | ~50 s | ~21 s | ~100 s |

## Why it does not work

`DB_LoadXAssets` with `DB_LOAD_ASYNC` (and `DB_LOAD_ASYNC_NO_SYNC_THREADS`) **blocks the calling
(main) thread for the whole zone load**. The log shows the first frame at ~60 s, then the eight
zones load from ~61 s to ~100 s, and the MCP `main_menu` state only becomes reachable at ~100 s:
the menu is drawn but frozen for the load. That is worse than the old behaviour and violates the
"no freeze without feedback" requirement (the loading popup is a map-load UI, not available before
a map starts).

Loading the zones *before* the first frame (variant 1 above) does not help either: it just delays
the menu by the same load time.

The engine's DB loader is not usable as a background task from the main thread. A real M5 needs the
load on another thread (the DB API's thread affinity is unknown and a wrong call is fatal) or an
engine-side async completion that this build does not expose. The safe, measured conclusion is:
**background zone loading is not possible with the current `DB_LoadXAssets` usage**, so the change
was reverted (no M5 code in the branch).

## What is left in the tree

- `tools/test/measure-startup.ps1`: reusable 3-run startup/map-load measurement (reads
  `mwx-logs/load_times.log`; no MCP needed). Raw results from these runs are in
  `mwx-debug\autonomous\startup-before-*.json` / `startup-after-*.json`.
- The branch is back to the step-1 code (`b3230e17`), rebuilt: `BUILD OK`; the 16/16 full run in the
  report was made on exactly this code.

## If this is retried

- Find a safe way to run `DB_LoadXAssets` off the main thread (or an engine "load finished" callback)
  before touching `ui_init_stub` again; a wrong thread is a fatal DB error.
- Keep the map gate on the **real map load** (`fastfiles.cpp load_pre_gfx_zones`), not on the virtual
  lobby; the lobby map load must not race the background request.
- The frontend subset (currently just `hmw_dlc_factions`) is the only zone the menu needs; the CAC/
  armory can be blocked behind the load if the zones are not in yet.
