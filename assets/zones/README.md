# Zone sources (`assets/zones`)

Text parts of the zone sources that are in git. The binary, game-derived parts are **not** in git:
they live in the migration archive (`_migration\archive\game\zonetool\`) and are re-created with the
zonetool dump commands below. The current built zones stay in the game's `zone\` folder.

## `hmw_aw_weapons`

- `hmw_aw_weapons.csv` — the zone manifest (weapons, models, surfaces, materials, images, anims).
- `weapons/`, `materials/`, `xmodel/`, `xanim/`, `effects/`, `techsets/`, `localizedstrings/` — the
  converted JSON/technique sources (`zonetool\hmw_aw_weapons\` in the game folder).
- `build-zone.ps1` — copy of `tools/zone/build-zone.ps1` for reference.

Excluded (binary, re-creatable): `streamed_images/*.pixels`, `xsurface/*.xsb`, `images/*.h1Image`,
`*.cso` (compiled shaders), `*.xmb`, `*.xab`.

## `hmw_mwr_weapons`

- `hmw_mwr_weapons.csv`, the converted weapon JSON, `overrides.txt` (the 19 animation copies that
  resolve asset collisions with HMW's zones).

## Rebuild

```
# 1. restore/re-dump the binary parts (needs the AW install; dumps ~9 GB)
tools\aw-port\dumpzone-aw.ps1        # AW common_mp / patch_common_mp per docs/guides/aw-weapon-porting.md
tools\aw-port\dump-models.ps1        # xmodels
tools\aw-port\dump-material.ps1      # materials
tools\aw-port\dump-h1-images.ps1     # images (+ streamed pixels)

# 2. build + gate
tools\zone\build-zone.ps1 -Zone hmw_aw_weapons
py -3 tools\zone-check\zone_check.py --zone hmw_aw_weapons
```

`docs/guides/zones.md` documents the asset-type tokens (`xmodelsurfs`, not `xsurface`) and the
zone-check overrides. `docs/guides/aw-weapon-porting.md` has the full conversion recipe.
