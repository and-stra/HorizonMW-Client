# zone-check: asset name collisions between our zones and the zones loaded before them

## Why

The engine loads our zones (`hmw_aw_weapons`, `hmw_mwr_weapons`) **after** the stock MWR
zones and HMW's own zones. An asset with the same name as one of theirs replaces it for the
whole game, not only for our weapons. The AW pilot did exactly that with generic materials,
techsets and images and broke Create-a-Class previews (docs/weapons/aw-plan.md, the regression
section).

Rule, from now on:

- our zones contain **no asset whose name already exists** in a zone loaded before ours,
  unless the content is identical, or the name is listed in `overrides.txt` (empty on purpose);
- shared assets that already exist in HMW/MWR are **referenced**, not included;
- an AW asset that differs from a same-named HMW/MWR asset gets an AW-specific name
  (`_aw` suffix) and the referencing material/model is repointed to it.

## What "identical" means

Same dumped content, not just the same name:

- material: sha1 of the material JSON **plus** the sha1 of every image/techset it names;
- model/animation: sha1 of the `.xmb` **plus** every material name embedded in it;
- image: sha1 of the `.h1Image` header **plus** all `<name>_streamN.pixels` payloads;
- everything else: sha1 of the dumped file.

A zone build links assets by pointer, so a linked asset is byte-identical by construction -
those show up as `identical` and are allowed. A name that appears with **different** content
is a collision and fails the build.

## Use

```
powershell -File tools\zone-check\build-index.ps1          # (re)build index\prior.json
powershell -File tools\zone-check\build-index.ps1 -List    # what is indexed
py -3 tools\zone-check\zone_check.py check --zone-source "<GAME>\zonetool\hmw_aw_weapons" --index tools\zone-check\index\prior.json
```

`build-zone.ps1` runs the check after every build and throws on a collision. `overrides.txt`
holds the deliberate exceptions, one `type/name` per line.

## Index coverage

Indexed from the dumps on this machine (`refs\dumps` + `<GAME>\dump\workbench_hmw_*`):
`patch_common_mp`, `patch_ui_mp`, `ui_mp`, `hmw_patch_common_mp`, `hmw_patch_ui_mp`,
`hmw_attachments`, `hmw_ar1`, `hmw_rangers`, `post_gfx`, `hmw_dlc_factions`.

**Not yet indexed** (the script prints the current list): `common_mp`, `hmw_smg`,
`hmw_shotgun`, `hmw_killstreak`, `pre_gfx`, `patch_code_post_gfx_mp`. Until they are dumped,
a collision in those zones is not detected. Dump with
`build-index.ps1 -Dump` (x64zt, one zone per run; `common_mp` needs ~20 GB free while dumping,
delete the dump afterwards - the index keeps only names + hashes).

Everything in the index is generated data (names + sha1); it is safe to rebuild at any time.

## Limits

- The check runs on the **zonetool source** of a zone (what we author). It does not yet
  re-read the built `.ff`; the source is the only place a differing asset can come from,
  because everything else is linked by reference. `-Verify` (dump the built zone and compare)
  is the planned extension for release checks.
- Names are compared case-sensitively, like the asset system.
- Only the directories in `TYPE_DIRS` are indexed; add a mapping there when a new asset type
  appears in a zone we ship.

## Zone sources in git

The text parts of the sources live in `assets/zones/<zone>/` (CSV, converted weapon/attachment
JSON, overrides, build scripts); the binary parts (streamed pixels, xsurface .xsb, .xmb, compiled
shaders .cso) are game-derived and stay in the migration archive, re-created with the dump commands
in `assets/zones/README.md`. The current built zones stay in `GAME\zone\`.
