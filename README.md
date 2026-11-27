# archive/survival — the survival prototype, archived 27 Nov 2026

Decision (user, 27 Nov 2026): survival is **not pursued**. Everything stays recoverable on this
branch; it is removed from the active code and the test manifest on `cleanup`.

## What is here

| path | what it is |
|---|---|
| `cod-mwx/gametypes/survival.gsc` | the prototype gametype script (was `data/mwx/maps/mp/gametypes/survival.gsc`) |
| `cod-mwx/tests/survival.gsc` | the suite test (was `data/mwx/tests/survival.gsc`) |
| `cod-mwx/docs/survival-spike.md` | the spike notes and measurements |
| `cod-mwx/snapshots/gamemodes.cpp` | full snapshot of `src/client/component/gamemodes.cpp` at the time of archiving (mode row, `apply_survival_dvars`, dvars, localized strings) |
| `cod-mwx/snapshots/ui_scripts-gamemodes-init.lua` | the frontend Party-list insertion (`mwx_show_survival`) |

## External mod

`h2-survival-mod` (the original H2M survival asset port, its own git repo, single commit `f078060`,
remote `git@github.com:alicealys/h2-survival-mod.git`) is **not** copied into this branch: it is
~427 MB of zonetool asset-source JSON/CSV plus binaries, and large game-derived content does not
belong in this repository. The complete folder, including its `.git`, is preserved in the migration
archive at `_migration\archive\h2-survival-mod\`, with a mirror bundle next to it
(`h2-survival-mod.bundle`). Restore with:

```
git clone _migration\archive\h2-survival-mod.bundle h2-survival-mod
```

## How to restore the feature

1. `git show archive/survival:cod-mwx/gametypes/survival.gsc > data/mwx/maps/mp/gametypes/survival.gsc`
   (same for the test).
2. Re-add the test entry (`survival`, script `survival`, gametype `survival`, dvar
   `mwx_show_survival 1`) to `data/mwx/tests/tests.json`.
3. Re-apply the survival parts of `cod-mwx/snapshots/gamemodes.cpp` (the `{"survival", ...}` mode row,
   the OBJECTIVES text, `apply_survival_dvars`, the `mwx_show_survival`/`mwx_survival_maxagents`
   dvars and the localized strings) and the Party-list block in `ui_scripts/gamemodes/__init__.lua`.
4. Rebuild; the suite entry needs `scr_survival_maxagents` set before the map load (the reason for
   `apply_survival_dvars`).

The blocker that stopped it is in `cod-mwx/docs/survival-spike.md`: the H1 agent pool / wave spawn
behaviour (tests `survival` red, `expected >=5, got 0`).
