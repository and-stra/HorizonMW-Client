# Menu and lobby load times (U3)

Measured on the client (`mwx_test_mode 1`, warm OS cache) with
`mwx-debug\autonomous\u3-loads.ps1`; every number comes from `mwx-logs\load_times.log`
(one line per fastfile, plus milestones).

## Startup to the main menu: about 55 s

```
 12.9 s  ---- client hooks installed ----
 12.9 s  hmw_pre_gfx 0.02  hmw_files 0.005  eng_code_pre_gfx_mp 0.002  code_pre_gfx_mp 0.002
 13.9 s  patch_code_pre_gfx_mp      1.0 s
 14.7 s  hmw_post_gfx               0.7 s
 14.9 s  hmw_patch_code_post_gfx_mp 0.2 s   code_post_gfx_mp 0.2 s
 15.2 s  hmw_patch_ui_mp 0.07  ui_mp 0.17
 18.5 s  hmw_patch_common_mp        3.2 s
 18.5 s  techsets_common_mp         2.8 s
 21.3 s  common_mp                  5.7 s
 27.1 s  hmw_killstreak             2.3 s
 29.5 s  hmw_attachments            2.4 s
 31.8 s  hmw_ar1                    2.7 s
 34.2 s  hmw_smg                    2.6 s
 37.0 s  hmw_shotgun                3.0 s
 40.0 s  hmw_rangers                1.7 s
 41.8 s  hmw_nightshade             4.6 s
 46.7 s  hmw_dlc_factions           4.8 s
 51.7 s  hmw_dlc_killstreaks        2.4 s   (first main-thread frame)
 54.2 s  first main-thread frame
```

The frontend loads the whole HMW multiplayer content (`hmw_*` zones ~30 s) before it can draw
the menu. This is the "60-90 s start" the user sees; it is parked by decision (backlog item 19).

## PLAY ONLINE -> the virtual-lobby room: ~4-9 s of zones, once

First visit (cold):

```
 patch_mp_vlobby_room       0.3 s
 techsets_mp_vlobby_room    1.3 s
 eng_patch_mp_vlobby_room   0.02 s
 eng_mp_vlobby_room         0.02 s
 mp_vlobby_room             1.0 s
 imagefile3..20             0.1 s
 mp_vlobby_room_path        1.5 s (cold) .. 5.6 s (first cold run)
 --- main menu (virtual lobby loaded) ---
```

The engine also spends ~10 s between the click and the first zone line (transition/connect), so the
first PLAY ONLINE shows the loading screen for ~15-20 s. On the next visits the room is still loaded:
the same step takes ~1.3 s and no zones are read.

## PRIVATE MATCH, GAME SETUP, MODE: no zone loads

These steps load nothing:

| step | measured |
|---|---|
| back from game setup to the private lobby | 160-200 ms |
| menu-to-menu clicks (game setup, mode popup) | 130-200 ms |
| private lobby (after PLAY ONLINE) | no load lines |

The earlier "3.5-14 s" for the private lobby was the debug click's own wait (the server caps
`expect_timeout_ms` at 20 s, a load that starts inside a click can exceed it), not a zone load.

## START -> map: the normal map load

Starting a match reloads the UI scripts (`hks_start`, < 1 s) and then loads the map zones exactly
like a dedicated server does. There is no extra menu overhead.

## Targets

- after the first start, a menu step without a map load: < 2 s -> **met** (130-200 ms; PLAY ONLINE
  is the only one with a load, and only on its first visit);
- startup ~55 s stays parked (content zones, item 19);
- the private-lobby variance is explained above and is not a bug.

## Reproduce

```
powershell -File mwx-debug\autonomous\u3-loads.ps1 -Port 27300
```

It starts a client with `+set mwx_test_mode 1`, records `load_times.log` bytes before each step and
prints the lines that step added.
