# MWX — project overview

MWX is the LAN/modded client for **Call of Duty: Modern Warfare Remastered** built on HMW
(HorizonMW / H2M). It loads a client DLL replacement (`mwx.exe`, built from `cod-mwx`) that adds
dedicated/LAN support, a private-match lobby, party game modes, Create-a-Class with ported weapons,
zone loading and the debug/test tooling.

## Repository layout (`cod-mwx`)

| path | content |
|---|---|
| `src/` | the client (C++20, MSVC): components, hooks, RPC, game bindings |
| `data/mwx/` | mirrored to `GAME\mwx`: ui_scripts, GSC (`scripts/`, `maps/`), tests, mods |
| `data/cdata/` | HMW data overrides (ui_scripts, statstable patches) |
| `data/mods/` | optional mods (`mod.json` + GSC + zone csv) |
| `tools/` | build, test, zone, CAC, crash, AW-port, loadscreen, weapon-icons tools |
| `assets/zones/` | zone sources (CSV + converted JSON + build scripts), one folder per zone |
| `docs/` | this documentation (index in [README.md](../README.md)) |

The game install is a sibling of the repo:
`C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered`
(`GAME`). The build copies `mwx.exe` and mirrors `data/mwx` into `GAME\mwx`.

## Rules (summary; the full set is in `AGENTS.md`)

- Work only inside `C:\Games\cod-hwm`; keep ≥20 GB free on C:.
- Back up before changing an existing game/zone file; never edit HMW's zones.
- Never delete — move to `_migration\archive\` (migration archive).
- Stop only processes you started.
- Nothing new named `mwx`; the startup zone budget is ≤9 zones (8 used).
- No secrets, game binaries or large game-derived binaries in git.

## Testing

`tools/test/run-tests.ps1` (suite from `data/mwx/tests/tests.json`), `menu-smoke.ps1` (frontend
flows), `cac-smoke.ps1` (weapon class matrix), `cac-warnings.ps1`. Details in
[guides/testing.md](../guides/testing.md).

## Documentation

- Branch model and merge rules: [branches.md](branches.md)
- Building: [../guides/building.md](../guides/building.md)
- Todo list: [../backlog.md](../backlog.md)
