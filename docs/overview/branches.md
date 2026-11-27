# Branch model

## Protected branch: `mwx`

`mwx` is the integration branch. Only the orchestrator (Claude) merges into it, after review of a
tested stack. Workers never commit to `mwx` directly and never merge into it (the single exception
was C0, approved for the 27 Nov cleanup run: `opencode/fixes` → `mwr-weapons` → `aw-weapons`, all
clean, `mwx` = `5bfa3e7f`).

Remote: `origin` = `git@github.com:and-stra/HorizonMW-Client.git`.

## Working branches

| branch | purpose |
|---|---|
| `cleanup` | the 27 Nov cleanup/migration-preparation work (C1–C8); reviewed and merged by Claude |
| `opencode/fixes` | test-infrastructure and menu fixes (stack 1) |
| `mwr-weapons` | the MWR DLC + melee port (stack 2) |
| `aw-weapons` | the AW pilot weapons, CAC enum, knife, "just play" part 1 (stack 3) |
| `archive/survival` | orphan branch: the survival prototype (scripts, tests, implementation snapshots) |
| `archive/cod-hmw-aw`, `archive/cod-hmw-aw-weapons` | commits from the old separate AW client clone, preserved |
| `main` | upstream/initial state, not used for work |

The three stack branches are linear (`mwx` → `opencode/fixes` → `mwr-weapons` → `aw-weapons`), so the
C0 merge was conflict-free. Keep new work on its own branch, one logical change per commit, and push
after each step.

## Release/prep stack

The "just play" release branch is stacked on `aw-weapons` (never on `mwx`). Part 2 of the "just play"
work goes there; `cleanup` stays architecture/tooling only.

## Archive branches

`archive/*` branches are append-only history: no cleanup, no rewrites. The survival branch is an
orphan (it has no parent) so the active tree can drop the feature without losing the code.

## Rules

- No `--force`, no rebase of shared branches, no merging into `mwx` without the orchestrator.
- One logical change per commit; push after each step; leave working trees clean.
- Merge with `--no-ff` when the orchestrator integrates a stack.
