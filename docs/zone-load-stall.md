# Custom-zone map-load stall (`imagefile48.pak`)

Status: **fixed 27 Nov 2026** (startup list reduced to 7 zones; verified in section 7).
Originally release-critical.

With a custom weapon zone loaded (`hmw_aw_weapons.ff` or `hmw_mwr_weapons.ff`), loading
`mp_crash` stalls at `imagefile48.pak` (2.24 GB); without the zone the same map completes the
imagefile load in ~3 s. `sas` and `aw_crossbow` on `mp_shipment` are green.

This document records the characterisation, the hypotheses and their measured results.

## 1. Characterisation (26 Nov)

| run | custom zone | `mp_crash` | last load line | pak |
|---|---|---|---|---|
| no zone | - | PASS 42 s | `mp_shirt_006_p_tr` | - |
| `hmw_aw_weapons.ff` 19.8 MB | AW crossbow | STALL >240 s | `imagefile48` | 2,138 MB |
| `hmw_aw_weapons.ff` 10.6 MB, no images/streamed pixels | AW crossbow | STALL | `imagefile48` | 2,138 MB |
| `hmw_mwr_weapons.ff` 56 MB (parked) | MWR DLC+melee | STALL | `imagefile48` | 2,138 MB |
| `hmw_stalltest.ff` 172 B, one rawfile (assetbase 0) | minimal | STALL | `imagefile48` | 2,138 MB |
| `hmw_stalltest.ff` 1.9 KB, one xanim (assetbase 1460) | minimal | STALL | `imagefile48` | 2,138 MB |

`mp_shipment` is not a reliable discriminator: earlier `aw_crossbow`/`sas` runs on it passed, but a
later run with the same zone also stalled at imagefile48. The stall is the **next imagefile load
after the custom zone is registered**, not the map name.

The static script-buffer experiment (16 MB `char storage[]` instead of the lazy PMem script block)
made the **no-custom-zone** `mp_crash` run stall too; it was reverted. That is a strong hint that
the stall is a large contiguous allocation that a small custom-zone allocation can push out of
reach, not a weapon-data problem.

## 2. Hypotheses

| # | hypothesis | test | result |
|---|---|---|---|
| a1 | load timing, same call | minimal zone in the `try_load_all_zones` vector, async no-sync | STALL |
| a2 | separate load | minimal zone in a second `DB_LoadXAssets` call, `DB_LOAD_SYNC` | STALL |
| a3 | flags | minimal zone with `DB_ZONE_CUSTOM` only | STALL |
| b | stream/offset >2 GB | the stall is always the 2,138 MB `imagefile48`; a 1.9 KB zone without a `.pak` still triggers it | **not proven**; no pak handle shift is needed |
| c | memory/pool | 8 GB `mem_low`/`mem_high` pools (was 4 GB) | no effect; reverted |
| d | load after map | AW zone loaded after cgame is initialized | map loads and `ph_listen` passes, but the zone is too late for level-init spawn/loadout (tests fail); see section 5 |

## 3. Swapping the zone list (27 Nov)

A temporary experiment reads `mwx-logs/zone-list.txt` instead of the built-in startup list
(`patches.cpp`, removed again after the investigation), so one build can test every zone list.
`mwx-debug/zone-stall/swap-test.ps1` writes the list, loads `mp_crash` and records the last zone
started, the working set at the menu, and (on a stall) the process/thread state and the engine's
`g_zoneCount`/`g_zoneIndex` read from the live process.

| case | zones | result | startup | menu RSS | last zone |
|---|---|---|---|---|---|
| a | 6 HMW + `hmw_stalltest` (7) | PASS 39 s | 56 s | 5,020 MB | `mp_shirt_006_p_tr` |
| b | 8 HMW (without `hmw_dlc_killstreaks`) + `hmw_stalltest` (9) | PASS 41 s | 52 s | 6,483 MB | `mp_shirt_006_p_tr` |
| c | 9 HMW + `hmw_stalltest`, stalltest first (10) | STALL >180 s | 55 s | 6,525 MB | `imagefile48` (2,138 MB) |
| d | 8 HMW + a copy of `hmw_ar1` as `hmw_copyzone` (9) | not usable | - | - | hangs at `techsets_common_mp` during startup (duplicate zone content) |

Cases a-c say: **9 startup zones load `mp_crash`, 10 do not, and the order does not matter**.
Case d could not be used as a "free" 10th zone: a byte copy of a loaded zone makes the *menu*
zone load hang at `techsets_common_mp` (duplicate assets), so there is no zero-cost extra zone.
The count, not the content or size of the 10th zone (172 B / 1.9 KB / 19.8 MB / 56 MB all behave
the same), is the deciding factor.

`hmw_nightshade`, `hmw_dlc_factions` and `hmw_dlc_killstreaks` are not in HMW's own `ui_init`
list; MWX added them in `d698d8ca` so more weapons show in Create-a-Class. They are the three
zones that take the startup list from 6 (HMW's own) to 9 - and the custom weapon zone makes 10.

## 4. Minimal repro

`GAME\zone_source\hmw_stalltest.csv` + `GAME\zonetool\hmw_stalltest`:

```text
xanim,h1_wpn_asl_xmlar_idle
```

`hmw_stalltest.ff` = 1876 bytes; adding it to the zone list is enough to stall `mp_crash` at
`imagefile48`. The zone was temporary and is now in `mwx-debug\backups\zone-stall\` (zone file,
172 B variant, CSV and the zonetool source folder); it is not in `patches.cpp`.

## 5. Where it hangs (stack of the stalled client)

`GET/POST rpc {"method":"stacks"}` (new in this step, `exception::get_thread_stacks`) walks every
thread of the game process from the debug server thread, so it also answers while the main thread
is stuck. At the stall (10 startup zones, `imagefile48`):

- `g_zoneCount` = 43 (read from the live process with `mwx-debug\readmem.ps1`), i.e. 43 zone
  entries resident - far below any obvious 64/96 limit. It grows 32 → 40 → 43 during the map load
  and then stops.
- The main thread is in the Windows message loop (`win32u`/`USER32`, then `mwx+0x66E4B`), not in
  the loader.
- One game worker thread sits in `SleepEx+0x91` with the game stack
  `h1_mp64_ship+0x3A1F42 → 0x3A225F → 0x3A259B → 0x399F54` (the DB/zone-loader family; the
  imagefile hooks live at 0x3A0CA5/0x3A0CF5). It is a **retry loop with a timed sleep**, not a
  lock wait: the load never completes and the thread keeps sleeping.
- No thread is in the pak reader (`h1_mp64_ship+0x5B2xxx`).

`h1_mp64_ship.exe` is Arxan-packed (the bytes at those RVAs are not valid code on disk), so the
exact counter that stops being set could not be identified from the exe.

Releasing the three menu zones at map start (a first attempt) did work as intended - the resident
count dropped 32 → 28 and the working set fell from 5,050 to 4,331 MB - but `imagefile48` still
hung. So freeing zone memory/entries *after* the 10 zones were loaded does not repair the state.

## 6. Fix: keep the startup list at HMW's own size

MWX now loads the six zones HMW's own `ui_init` loads plus the AW weapon zone: **7 startup
zones**. `hmw_nightshade`, `hmw_dlc_factions` and `hmw_dlc_killstreaks` (added in `d698d8ca`
only so more weapons show in Create-a-Class) are no longer loaded at startup. 7 zones is the
configuration of experiment a, which loads `mp_crash` in 39 s. Consequence: the HMW content from
those three zones (nightshade/DLC faction/DLC killstreak assets) is not in the Create-a-Class
list anymore; the AW and MWR weapon zones are unaffected.

## 7. Verification (27 Nov)

On the 7-zone build (6 HMW + `hmw_aw_weapons`), all on `mp_crash`:

| test | runs | result |
|---|---|---|
| `ph_listen` | 3 | 12/12 each (142.1 / 130.3 / 131.2 s) |
| `aw_crossbow` | 3 | 15/15 each (58.5 / 59.2 / 58.6 s) |
| `sas` | 3 | 8/8 each (56.3 / 55.9 / 56.6 s) |

`mwx-debug\zone-stall\second-map.ps1`: startup (process -> main menu) **43.1 s**, then
`mp_crash` **43.4 s** and `mp_shipment` **9.8 s** in the same client. With 9/10 startup zones the
same startup took 52-56 s.

Full suite `-Parallel 2`: **37/38 green**, only `survival` fails (known, B5). Menu smoke: 3 passes;
one run had a single flaky mode pick (`rpg` -> `gun` while the chooser list was still building),
which the smoke now retries once.

## 8. Next / open

- The exact engine counter behind the 10-zone threshold is still unknown (Arxan-packed exe); the
  fix avoids it rather than raising it.
- `hmw_nightshade`, `hmw_dlc_factions`, `hmw_dlc_killstreaks` are no longer loaded at all. If
  their Create-a-Class content is needed again, load them lazily when the CAC opens and unload
  them when it closes - do not load them at startup, and re-test a map start after visiting the
  CAC (unloading after a 10-zone startup did *not* repair the stall).

## Frontend -> virtual lobby "stalls" (27 Nov 2026)

A few Play Online runs stayed in the vlobby load for >60 s and the debug port stopped answering
(load_times.log ended with start mp_vlobby_room_path). Bisect:

- the commit before the CAC row filter (d85fc004): 4/5 cold runs, then **10/10** on the same build;
- the fixed-list filter build (8d79fac8): **5/5** cold runs.

The failed runs happened while a heavy x64zt dump/index job was reading the same disk. The
mp_vlobby_room_path line is a streaming start, not a missing done marker. Conclusion: the
frontend->lobby "stall" was **I/O starvation from the test jobs**, not the zone count (8 startup
zones, 56 zone starts in the load log, unchanged) and not the row filter. Rule for tests: no dump,
index or zone build while a client is starting/loading.
