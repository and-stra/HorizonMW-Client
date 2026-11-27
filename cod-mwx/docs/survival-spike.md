# Survival feasibility spike (R6)

Status: prototype only. This document answers the four questions in the R6 brief and proposes a
milestone plan. Nothing here is a port; the shipped `survival` gametype is a hidden spike
(`mwx_show_survival 1`).

Sources: `COD-GSC-Source/H1-GSC/maps/mp/agents/_agents.gsc`, `_agent_common.gsc`,
`_agent_utility.gsc`, `_scriptedagents.gsc`; `h2-survival-mod/survival/maps/_so_survival*.gsc`;
live HMW measurements on a dedicated `mp_crash` server (2026-11-25).

## a. Agents on HMW

`maps\mp\agents\_agents.gsc` is H1's humanoid-agent framework. The engine-side entry points are
`addagent()` and `getmaxagents()`:

- `main()` installs `level.agent_funcs["player"]` (spawn/think/on_killed/on_damaged) and starts
  `_agent_common::init()`.
- `_agent_common::add_agents_to_game()` waits for the first `"connected"`, then calls `addagent()`
  until `level.agentarray.size == getmaxagents()`.
- `add_humanoid_agent(kind, team, class)` reuses a free slot (`getfreeagent`), spawns it through
  `spawn_agent_player` (bot spawn path, `bot_war_think`, `_class::giveandapplyloadout`).

**Measured on HMW-MP (dedicated, mp_crash, `g_gametype survival`):**

| query | value |
|---|---|
| `getmaxagents()` | **0** |
| `level.agentarray.size` | 0 |
| `level.numagents` | 0 |
| `sv_maxclients` / `party_maxplayers` | 18 / 18 |
| `scr_horde_maxagents` / `scr_default_maxagents` | 18 / 0 (changing them does not change `getmaxagents()`) |

So **no agent slots are allocated in a multiplayer match**: `add_humanoid_agent` returns
`undefined`, and the wave loop cannot spawn anything through H1's framework. The agent path was
blocked by an engine-side allocation, not by assets or scripts.

**B5 root cause and fix (2026-11-25):** `getmaxagents()` builds the name `scr_<g_gametype>_maxagents`
(format string `scr_%s_maxagents`) and reads the **string** value with `atoi`, capped at **24**. The
spike set `scr_horde_maxagents` and `scr_default_maxagents` (wrong names) and at runtime (too late).
`gamemodes.cpp::apply_survival_dvars()` now registers/sets `scr_survival_maxagents = "24"` **before
the map load** (string dvar; an int dvar is read as a char pointer). The getter is at RVA
**`0x44C980`** in the unpacked engine (`h1_mp64_zt.exe`; the format string is at RVA `0x85F0B0`),
which caps the accepted value at 24. It is correct for survival to use the same
`scr_<g_gametype>_maxagents` convention as the horde mode. No engine hook is needed while the dvar
is present; if a future build returns 0, hook `0x44C980` to return `mwx_survival_maxagents`.

**Prototype fallback (removed in B5):** the spike spawned the wave with
`executecommand("spawnBot <n>")` when `add_humanoid_agent` returned undefined. B5 removes that
fallback: the wave now uses agents only (the test asserts `isagent()` enemies). The old fallback
spawned engine bots that the wave counter could not distinguish from the test's own bot, which was
the wave 1 -> 2 problem.

## b. Bot path nodes on HMW maps

H1's bot think (`bot_think_tactical_goals`, `getclosestnodeinsight`) uses the map's path data. In
MWR/HMW the bot navigation data is a **separate fastfile**, `<map>_path.ff` in `zone\`, not
`pathnode` entities (the debug `entities classname:pathnode` RPC returns 0 on every map). Measured
2026-11-25:

| map | path zone | size | bots moved in tests |
|---|---|---|---|
| mp_crash | `zone\mp_crash_path.ff` | 213,036 B | yes (all mode tests) |
| mp_rust | none (usermap) | - | yes (infect_rust/ph_rust: bots kill each other) |
| mp_terminal | none (usermap) | - | yes (ph_terminal) |
| mp_estate | none (usermap) | - | not run yet |
| mp_favela | none (usermap) | - | not run yet |

Stock MWR maps ship `<map>_path.ff` (backlot/broadcast/carentan/crash/shipment/vacant/... are all in
`zone\`). The HMW usermaps (`hmw-usermaps\mp_rust`, `mp_terminal`, `mp_estate`, `mp_favela`) have
only `<map>.ff`, `<map>_load.ff` and a `.pak` - no `_path` zone. Their bots still navigate in the
tests, so the usermap zone must carry enough navigation data (or HMW's bot code falls back to direct
movement). For a survival port this is acceptable on the stock maps and a risk on the usermaps; the
mp_crash spike is on the safe side.

## c. Prototype

`data/mwx/maps/mp/gametypes/survival.gsc` (hidden unless `mwx_show_survival 1`):

- 1-2 human players on allies (autoassigned), wave enemies on axis.
- wave 1 = 5 enemies, wave n = 5 + 2(n-1); next wave 5 s after the last enemy dies.
- wave counter on the server HUD (`MWX_SURVIVAL_WAVE`), one life per player, match ends when every
  human player is dead.
- enemy spawn: `add_humanoid_agent("player", "axis", "class1")` first (returns undefined on HMW),
  then the `spawnBot` fallback.
- test `survival` in `data/mwx/tests/tests.json`: wave 1 spawns 5 enemies and killing them is
  counted. **Open:** the wave-1→wave-2 transition did not fire in the test (the wavemanager stops
  after wave 1; the enemy bots die as `MOD_SUICIDE` within 2 s of spawning, and the clear loop is
  never reached). The prototype proves spawning + kills; the transition is the remaining spike work.

## d. Inventory for the real port

### Maps

`h2-survival-mod` ships 7 maps (`survival/maps/so_survival_*.gsc`):

| h2-survival-mod | HMW map | notes |
|---|---|---|
| so_survival_estate.gsc | mp_estate | MW2CR Estate |
| so_survival_favela_escape.gsc | mp_favela | MW2CR "Upper Favela"; HMW has the MP favela, not the escape layout |
| so_survival_mp_backlot.gsc | mp_backlot (MWR) | HMW ships the MWR map |
| so_survival_mp_broadcast.gsc | mp_broadcast (MWR) | |
| so_survival_mp_carentan.gsc | mp_carentan (MWR "Chinatown") | |
| so_survival_mp_crash.gsc | mp_crash | already the spike map |
| so_survival_mp_vacant.gsc | mp_vacant | |

The per-map scripts are small (0.6-4.4 KB): entity setup, spawners, doors, clips, portals,
`survival_init/preload/postload` hooks. The gameplay lives in the shared `_so_survival*.gsc` files
(~500 KB): `_so_survival.gsc` (waves, economy, objectives), `_so_survival_ai.gsc` (enemy
composition/spawners), `_so_survival_armory.gsc` (weapons/upgrades), `_specialops*.gsc` and
`_squad_enemies.gsc`.

### Script APIs used by the source that have no MP equivalent (top offenders)

| API / concept | where | proposed MP replacement |
|---|---|---|
| `add_humanoid_agent`, `getmaxagents`, `addagent` | _agents.gsc / horde | **blocked**: getmaxagents()==0; either a C++ agent-pool allocation or `SV_AddBot` + a GSC think loop (bots already work) |
| `spawnTurret`, `CreateTurret`, `sentry` | armory/_sentry | HMW killstreak sentry (`h2_killstreaks/_autosentry.gsc`) can be reused |
| `setPlayerData`/`getPlayerData` (SP stats) | _playerdata.gsc | GSC `level`/player structs + the existing MWX stats path |
| `missionFailed`, `objective_*`, `SetObjective` (SP objectives) | _so_survival | `maps\mp\_utility::setobjectivetext` + `_objpoints` (as the new modes do) |
| `playViewmodelAnim`, `useanimtree`, `animscripted` (SP cutscenes) | _laststand, _chopperboss | drop; no third-person/SP animations in MP |
| `_specialops` code (spec-ops scoring, checkpoints) | _specialops_code.gsc | not ported; the mode only needs waves + money |
| `airstrike`/`chopper` boss logic | _air_support_strobe, _chopperboss | HMW killstreaks (`_helicopter`, `_airstrike`) cover the visuals, not the boss AI |
| `dog` / `enemy_dog` AIType | aitype/enemy_dog.gsc | needs a dog model/anim set; HMW has no MP dog |
| juggernaut AITypes | aitype/enemy_juggernaut_*.gsc | needs the juggernaut model + riot shield; check HMW's h2_killstreaks/juggernaut assets |
| riot shield (`_riotshield.gsc`, animscripts/riotshield) | h2 mod | not in HMW's MP content (no shield weapon in the stock table); port would need the H2 asset |
| `so_survival_*` spawners (script_brushmodel clones) | map scripts | portable: HMW supports `clonebrushmodeltoscriptmodel` |

Missing assets (juggernaut, riot shield, dogs) are the main reason this is not a quick port: they
need either HMW's existing killstreak models (sentry/helicopter) or new assets from H2/MW3, which
is a content-pipeline task (zonetool + a new zone), not a GSC task.

## e. Milestone plan (effort estimates)

1. **Enemy backend (2-4 days)**: decide agents vs bots. Agents need an engine change
   (`getmaxagents` > 0 + agent pool allocation); bots need a GSC wave/think layer and a
   `spawnBot`/team-assignment wrapper. Deliverable: 20 enemies on mp_crash at a stable server frame.
2. **Wave/economy loop (2-3 days)**: port `_so_survival.gsc` wave logic (composition per wave,
   intermission, money per kill, armory hooks) onto H1's gametype skeleton (`survival.gsc`).
3. **Maps (3-5 days)**: port the 7 `so_survival_*` entity scripts; verify spawn points, barriers and
   the map-specific doors/clips. Estate and favela_escape are the layout mismatches.
4. **Armory/upgrades (2-3 days)**: reuse `_so_survival_armory` data with HMW weapons
   (`docs/hmw-weapons-perks.md`); a wall-buy interaction is the main new UI.
5. **Bosses/special enemies (3-5 days, optional)**: chopper/juggernaut/dogs; asset work.
6. **HUD/UX (1-2 days)**: wave counter, money, armory prompt in the H1 HUD style.
7. **Tests + polish (2-3 days)**: a dedicated test per milestone (wave spawn, money, armory,
   downed/revive), full regression.

Total: ~2-3 weeks for a playable single-map port (mp_crash), 4-6 weeks for all seven maps with the
boss content. The blocking decision is item 1 (agent allocation vs bots).

## B5c: why the wave agents never appear (26 Nov)

Measured on a dedicated `mp_crash` server (`g_gametype survival`, `mwx_show_survival 1`, one bot):

| query | value |
|---|---|
| `getmaxagents()` / `level.agentarray.size` | 24 / 24 |
| `level.survival_agents.size` (created by `add_humanoid_agent`) | 5 |
| first agent | `team=axis pers=axis isactive=1 hasdied=0 isagent=1 isai=1 **isplayer=0**` |
| `level.players` | only the bot (`ai=1 agent=0 alive=1`) |
| `spawnagent((0,0,0),(0,0,0))` on a free slot | runs, returns, no error — still not a player |

So the framework gets as far as `connectnewagent`/`activateagent`; the engine's **`spawnagent()` is a
no-op in MP** (no script error, no player entity, nothing added to `level.players`). This is not a team
assignment problem (the slots are already `axis`). The three paths forward:

1. find/hook the engine function behind `spawnagent` (the slot must transition to a connected player;
   `addagent()` allocates the slot but MP never spawns it), or
2. use `spawnBot` + a GSC think layer (the bots already move and shoot in every mode test), or
3. leave the spike as is (hidden, hidden tests).

The wave manager intentionally retries wave 1 instead of advancing (a wave of 0 agents must not count
as cleared).
