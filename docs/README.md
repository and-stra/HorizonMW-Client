# MWX docs

Index of the project documentation. One line per document; the backlog is the only todo list.

## Overview

| doc | what it is |
|---|---|
| [overview/project.md](overview/project.md) | what MWX is, repository layout, safety rules, machine paths |
| [overview/branches.md](overview/branches.md) | branch model, review/merge rules, release-prep stacking |
| [overview/milestones.md](overview/milestones.md) | the autonomous-run milestones and their state |
| [overview/hw-features.md](overview/hw-features.md) | HMW's features and how MWX builds on them |

## Guides

| doc | what it is |
|---|---|
| [guides/building.md](guides/building.md) | build requirements, `build-mwx.bat`, deploy, PDB archive |
| [guides/testing.md](guides/testing.md) | the test runner, test manifest, menu-smoke, CAC smoke, warnings |
| [guides/mcp.md](guides/mcp.md) | the debug MCP server and the RPC bridge |
| [guides/zones.md](guides/zones.md) | zone build, zone-check, the startup zone list and budget |
| [guides/aw-maps.md](guides/aw-maps.md) | AW map porting (paused, later) |
| [guides/aw-weapon-porting.md](guides/aw-weapon-porting.md) | the full AW weapon conversion process and its error list |
| [guides/weapon-icons.md](guides/weapon-icons.md) | the MWR-style weapon icon renderer and its blockers |
| [guides/localization.md](guides/localization.md) | localized strings, menu text, loading screens |
| [guides/mods.md](guides/mods.md) | mods (`data/mods`, mod.json, GSC loading) |

## Features

| doc | what it is |
|---|---|
| [features/game-modes.md](features/game-modes.md) | the party modes (prop hunt, mad props, slasher, cranked, arena, …) |
| [features/private-match.md](features/private-match.md) | the private-match lobby and gametype selection |
| [features/cac.md](features/cac.md) | Create-a-Class: the ported rows and the weapon enum mapping |
| [features/usermap-map-command.md](features/usermap-map-command.md) | the usermap `map` command fallback |
| [features/callsigns.md](features/callsigns.md) | player card / emblem on LAN (white card problem) |

## Weapons

| doc | what it is |
|---|---|
| [weapons/mwr.md](weapons/mwr.md) | the MWR weapon port (DLC + melee) |
| [weapons/aw-plan.md](weapons/aw-plan.md) | the AW weapon plan, pilot weapons and status |
| [weapons/hmw-reference.md](weapons/hmw-reference.md) | HMW weapon/perk reference tables |

## Investigations

| doc | what it is |
|---|---|
| [investigations/zone-load-stall.md](investigations/zone-load-stall.md) | the vlobby "stall" (I/O starvation) and the zone list |
| [investigations/menu-load-times.md](investigations/menu-load-times.md) | menu/lobby load times and the F4 LUI list limit |
| [investigations/menu-load-crash.md](investigations/menu-load-crash.md) | the `0x1400BCB13` LUI-load crash regression and F2 |
| [investigations/aw-preview-analysis.md](investigations/aw-preview-analysis.md) | AW preview/stat analysis (27 Nov) |
| [investigations/hmw-diff.md](investigations/hmw-diff.md) | HMW binary/menu differences |
| [investigations/m5-background-zones.md](investigations/m5-background-zones.md) | background zone loading (M5) |
| [investigations/m5b-zone-compression.md](investigations/m5b-zone-compression.md) | zone compression (M5b) |

## Archive (kept for history, not maintained)

| doc | why it is archived |
|---|---|
| [archive/survival-spike.md](archive/survival-spike.md) | survival is not pursued; code on branch `archive/survival` |
| [archive/todo-aw-porting.md](archive/todo-aw-porting.md) | superseded by `weapons/aw-plan.md` |
| [archive/hmw-analysis-plan.md](archive/hmw-analysis-plan.md) | the HMW analysis phase is finished |
| [archive/backlog-history-2026-11.md](archive/backlog-history-2026-11.md) | the old `_migration/archive/mwx-debug/BACKLOG.md`, merged into `backlog.md` |
| [archive/repack-all-report.md](archive/repack-all-report.md) | one-off repack report |
| [archive/test-report-2026-11.md](archive/test-report-2026-11.md) | one-off test report |

## The only todo list

[backlog.md](backlog.md) — NOW / NEXT / LATER / DONE, with links.
