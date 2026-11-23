# Porting Advanced Warfare (S1) weapons to MWR (H1)

Tools: x64-zt (`refs\tools\x64-zt`), the S1 copy in the AW folder (`zonetool.exe`) and the H1 copy in GAME
(`x64zt.exe`).

## Why it is not one command

* x64-zt's **H1 target cannot dump weapons**: `DUMP_ASSET(ASSET_TYPE_WEAPON, ...)` is commented out in its S1 dumper.
  `dumpzone h1 <zone>` writes every other asset type (models, materials, techsets, xanims, sounds, fx).
* Its **H2 target** dumps weapons in almost the H1 layout. `s1_weapon_to_h1.py` converts the rest
  (anim tables, notetrack maps from S1's parallel arrays, surface sound tables, bools, fixed-size arrays,
  attachments).
* The weapon's dependencies must exist in H1 form. They come from `dumpzone h1` of the zone with the weapon and of the
  zones its techsets need. AW's **code shaders** (e.g. `position_only.hlsl_s1`) are in the code zones, not in
  `common_mp`: dump `code_pre_gfx_mp` and `code_post_gfx_mp` too.

## Steps (crossbow example, zone patch_common_mp)

1. In AW (S1 x64-zt), with the h1 target, into `GAME\zonetool_paths\<zone>`:
   `dumpzone h1 code_pre_gfx_mp`, `dumpzone h1 code_post_gfx_mp`, `dumpzone h1 patch_common_mp`
   (common_mp is already there). These are the dependencies.
2. Weapon JSON: `dumpzone h2 patch_common_mp` (weapons only are needed), then
   `python s1_weapon_to_h1.py <dump>\weapons\iw5_exocrossbow_mp.json GAME\zonetool\mod_sticksandstones\weapons\iw5_exocrossbow_mp.json`
   (no attachments; add `--attachment crossbowscopebase` only if ADS has no scope, then the attachment needs the same
   treatment).
   The converter clears the weapon's hands model (the player's MWR arms are used; AW's `viewmodel_base_viewhands`
   are the exo arms and share their name with MWR's model) and the exo-only anim slots.
3. `GAME\zone_source\mod_sticksandstones.csv` = `mod_sticksandstones.csv` from this folder.
4. H1 x64-zt: `buildzone mod_sticksandstones`; copy `zone\mod_sticksandstones.ff` to `GAME\mods\sticksandstones\mod.ff`.

Build errors and what they mean:
* `vertexshader "X.hlsl_s1" not found`: the shader's zone is not in `zonetool_paths`; search the S1 zones for it
  (`dumpcsv <zone>` lists the techsets) and dump that zone with `dumpzone h1`.
* JSON parse errors on the weapon: a field the converter does not know yet; extend `s1_weapon_to_h1.py`.
