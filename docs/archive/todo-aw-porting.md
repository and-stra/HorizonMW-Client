# TODO: Advanced Warfare porting (paused)

Paused on 2026-11-24, to be continued on the new, stronger machine with more disk space. Everything below is the
state at that point. Related docs: `docs/guides/aw-weapon-porting.md` (full weapon process and error list),
`tools/aw-weapon-port/README.md` (converter + zone CSV), `docs/guides/aw-maps.md`, `docs/guides/mods.md`.

## Setup on the new machine

- [ ] Copy or re-create: `C:\Games\cod-hwm` (game, `cod-mwx`, `refs`), the AW install, the map archive
      `compiled advanced warfare maps.zip` (40.7 GB).
- [ ] Restore AW's deleted map zones with Steam "Verify integrity of game files" (deleted 2026-11-22 to free 5.5 GB:
      all `mp_<map>*.ff` contained in the archive + `mp_exo_*_tr.ff`; kept: `mp_seoul2`, `mp_urban`).
      They are needed for our own map re-ports.
- [ ] x64-zt: S1 copy in the AW folder (`zonetool.exe`), H1 copy in GAME (`x64zt.exe`), release in `refs\tools\x64-zt`.
- [ ] Disk: plan for 60+ GB of working space. Full dumps: AW `common_mp` 9.3 GB, `patch_common_mp` 7.2 GB,
      one map dump ~2.7 GB plus ~0.9 GB build output.
- [ ] `AGENTS.md` rule "only inside C:\Games\cod-hwm, keep 20 GB free" stays (2026-11-23 a 38 GB move into the Dev
      Drive VHDX filled C: and detached it). Adjust the free-space number to the new disk.

## Crossbow (Sticks and Stones mod, `data/mods/sticksandstones`)

State: `mod.ff` builds (0 errors) and loads; the crossbow is given, fires, the bolt sticks/explodes and kills
(`iw5_exocrossbow_mp`, `MOD_IMPACT` / `MOD_PROJECTILE_SPLASH`), kill feed icon works. Unloading the mod restores the
normal game.

Open:
- [ ] **No arms on the crossbow and the gun is oversized/too close.** Ruled out: anim table (`szXAnims`, same as
      HMW's M4), position offsets (0, same as the M4), hands model (crash fixed with `viewhands_tf141`; HMW's own
      weapons use `viewmodel_base_viewhands`). Remaining causes:
      (a) AW's viewmodel anims move bones MWR's arms don't have (arms stay in bind pose, gun misplaced), or
      (b) the gun model's root bone / origin differs from MWR's gun models.
      Next steps (prompt was prepared, report target `_migration\archive\mwx-debug\crossbow\report4.md`):
      1. Bone/part name lists side by side: anims `vm_crossbow_idle` vs `vm_h2_m4a1_idle`, models `vm_crossbow_base`
         vs `wpn_h2_m4a1_vm`, arms `viewhands_tf141` / `viewmodel_base_viewhands` (MWR versions). Root bone of each
         gun model, bones moved by each anim.
      2. Experiment A: converter `--anims-from GAME\dump\assets\weapons\h2_m4_mp.json` (M4 anims on the crossbow,
         referenced with `xanim,,<name>` lines; mod.ff loads after hmw_ar1 since 299b061d). Arms appear + normal size
         => (a): rename bones in the converter or retarget the anims (Blender, IK hands to the grip). Otherwise => (b).
      If only the overall position is off: weapon offsets (standMove/standRot/duckedOfs/proneOfs/ADS).
- [ ] **11 missing images** (scope red/default in ADS): `crossbow_scope_base_*`, `crossbow_glass_*`,
      `crossbow_target_ems`, ... All in AW `common_mp`. Single-image dump via `dumpasset image` gives S1 format only.
      Options: an H1-target single-asset dump (check x64-zt source/help), or one full `common_mp` image dump
      (fits on the new machine), keep the 11 images, delete the rest.
- [ ] Re-test after both: arms in idle/ADS/reload/sprint/melee, other weapons (hatchet, M4) keep MWR arms, unload.
- [ ] Final cleanup: list what `GAME\zonetool_paths` needs for the next weapon port, delete the rest.
- [ ] Merge the findings of `docs/guides/aw-weapon-porting.md` into `tools/aw-weapon-port/README.md` (opencode keeps the
      long doc; README = short quick start).

## AW maps

State: 28 of 30 community ports load and play with bots (`_migration\archive\mwx-debug\overnight\report.md`). Installed: `mp_spark`,
`mp_terrace`, `mp_torqued`, `mp_urban` (disk). AW (2014) tab in the map selection lists installed maps.
Fixes merged: `marines` row in the faction table (allies name), helicopter killstreak disabled on maps without
heli paths.

Open:
- [ ] Install the other working maps from the archive (needs disk).
- [ ] **Helicopter paths:** one generic MWX script for all AW maps that creates `heli_start` / `heli_loop_start` /
      `heli_leave` / `heli_crash` path points (loop around the map from the spawn bounds, safe height) before
      `_helicopter::init` reads them. Then remove the "disable heli" fallback where paths exist.
      Needed data (from the prepared analysis prompt): spawn bounds + world height for a few maps.
- [ ] **Classic geometry (ladders, extra stairs/clips) missing in the community ports** (`boost_remove` = 0 on all
      but Retreat). Analysis prompt prepared (`_migration\archive\mwx-debug\aw-classic\report.md` target):
      1. our own Greenband port (`refs\aw-port-greenband-ours`, full dumpmap) as reference: entities with
         `script_gameobjectname`, brush submodel count
      2. community `mp_greenband` / `mp_terrace`: same; are the `*N` submodels still in the clip map?
      3. which AW maps have classic parts at all
      => submodels present: restore with a `<map>.ents` override (mapents.cpp reads it from disk);
         missing: re-port those maps with our pipeline.
- [ ] **Our own map pipeline fixes** before any re-port: `patch_common_mp` in `zonetool_paths` (missing glass/water/
      smoke images), port `mp_<map>_load` too (loading screen image), find the dedicated-server abort
      (0xC0000409 on mp_greenband, not reproduced later; WER LocalDumps + cdb).
- [ ] `mp_seoul2` (Swarm) never loads: own port from the original zone. `mp_solar` failed once: retest.
- [ ] Drift (`mp_torqued`) reportedly breaks the UAV for later maps: same-session test (Drift, then mp_rust) was
      not completed.

## AW weapons (beyond the crossbow)

- [ ] `docs/weapons/aw-plan.md` (untracked in the repo, written earlier): candidate list of AW guns for MWX.
      After the crossbow works end to end, use the same pipeline (`tools/aw-weapon-port`) for those weapons and
      register them natively (statstable rows via stock_weapons.cpp, HMW class whitelists via replacefunc).
- [ ] Sticks and Stones natively (not as a mod) once the crossbow is final.
