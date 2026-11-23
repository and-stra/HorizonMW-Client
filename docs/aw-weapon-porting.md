# Porting Advanced Warfare (S1) weapons to MWR (H1)

This is the reference process for porting an AW weapon into an H1/MWX mod. The worked
example is the Sticks and Stones crossbow (`iw5_exocrossbow_mp`). All paths are inside
`C:\Games\cod-hwm`; never extract or move anything to another drive, VHDX/Dev Drive or
folder. Keep at least 20 GB free on C:.

- `GAME` = `C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered`
- `AW`   = `C:\Games\cod-hwm\Call of Duty Advanced Warfare`

---

## 1. Tools

| Tool | Path | Use |
|---|---|---|
| S1 x64-zt | `AW\zonetool.exe` | dump AW zones/assets, dump HMW? no — AW only; h1/h2 targets |
| H1 x64-zt | `GAME\x64zt.exe` | build H1 zones, dump H1/HMW zones and weapons |
| Reference copy | `refs\tools\x64-zt\release\zonetool.exe` | same binary as `AW\zonetool.exe` |

Both binaries are **20,908,544 bytes, file version 0.0.0.560, dated 2026-10-05**. They are the
same x64-zt build; only the working directory/zone folder differs.

### Running the tools reliably

Both are interactive console tools. Use `-unbuffered-io` and drive stdin from a script:

```powershell
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = "$AW\zonetool.exe"       # or "$GAME\x64zt.exe"
$psi.Arguments = '-unbuffered-io'
$psi.WorkingDirectory = $AW               # or $GAME
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$p = [Diagnostics.Process]::Start($psi)
Start-Sleep -Seconds 75                   # wait for "ZoneTool initialization complete"
$p.StandardInput.WriteLine('dumpzone h1 patch_common_mp'); $p.StandardInput.Flush()
# ... wait until the output folder is stable, then:
$p.StandardInput.WriteLine('quit'); $p.StandardInput.Flush()
```

- Wait **75–90 s** for `ZoneTool is initializing...` / `initialization complete` before the
  first command. Commands sent earlier are lost.
- Send one command per line; wait for the output folder to stop growing (stable ~30–60 s for
  small dumps, much longer for full zones).
- `quit`, wait ~5 s, then kill the process if it is still alive.
- Reusable drivers: `cod-mwx\docs\aw-port-scripts\aw-dumpzone.ps1` (AW dump + folder stable
  watch) and `h1-command.ps1` (H1 commands; `-Command`, `-WatchFile`, `-MaxMinutes`).
- Typical timing: init 75–90 s; crossbow tr-zone dump 1–2 min; `common_mp` full ~20 min /
  8.9 GB; `buildzone` 2–4 s once dependencies exist.

### Output locations

AW (`AW\zonetool.exe`):

| Command | Output |
|---|---|
| `dumpzone h1 <zone>` | `AW\dump\<zone>\` (zones whose name contains `weapon`, e.g. `mp_vm_exocrossbow_tr`, go to `AW\dump\weapon_models\`) |
| `dumpzone h1 <zone> <type>` | only that asset type into the same folder |
| `dumpcsv <zone>` | `AW\dump\<zone>\<zone>.csv` (or `AW\dump\weapon_models\<zone>.csv`) |
| `dumpasset <type> <name>` | `AW\dump\assets\<type>s\<name>.json` (weapons) or `.s1Image` (images) |
| `dumpzone h2 patch_common_mp weapon` | H2-shaped weapon JSONs (the H1 target cannot dump AW weapons) |

H1 (`GAME\x64zt.exe`):

| Command | Output |
|---|---|
| `buildzone <zone>` | `GAME\zone\<zone>.ff` |
| `dumpcsv <zone>` | `GAME\dump\<zone>\<zone>.csv` |
| `dumpasset weapon <name>` | `GAME\dump\assets\weapons\<name>.json` |
| `dumpzone <zone>` | `GAME\dump\<zone>\` |

HMW fastfiles live in `GAME\hmw-mod\zone\` (e.g. `hmw_ar1.ff`, 280 MB), not in `GAME\zone`.
To dump an HMW weapon without copying hundreds of MB, create **hardlinks** inside
`C:\Games\cod-hwm` (same volume, no extra disk), run the H1 tool, then remove the links:

```powershell
New-Item -ItemType HardLink -Path "$GAME\zone\hmw_ar1.ff" -Target "$GAME\hmw-mod\zone\hmw_ar1.ff"
# also hmw_files.ff, eng_hmw_common.ff, hmw_attachments.ff, hmw_smg.ff, hmw_shotgun.ff if needed
& "$GAME\x64zt.exe" -unbuffered-io          # working dir GAME
# dumpcsv hmw_ar1
# dumpasset weapon h2_m4_mp
Remove-Item "$GAME\zone\hmw_ar1.ff"         # removes the link, not the original
```

`h2_m4_mp` dumped this way has `handModel=viewmodel_base_viewhands`; see §6.

---

## 2. Find the weapon's zones

1. List AW zones: `AW\zone\*.ff`. The weapon definition is usually in
   `patch_common_mp` (and often `common_mp`); the view/world models are in streamed zones.
2. Run `dumpcsv` on `patch_common_mp` and `common_mp`:

   ```text
   dumpcsv patch_common_mp
   dumpcsv common_mp
   ```

3. Search the CSVs for `weapon,<name>`. For the crossbow:
   `weapon,iw5_exocrossbow_mp` is in `patch_common_mp`/`common_mp`.
4. Find the model zones in the AW zone list. For the crossbow:
   - `mp_vm_exocrossbow_tr.ff` → viewmodel `vm_crossbow_base`, xsurfaces, scope models
   - `mp_wm_exocrossbow_tr.ff` → worldmodel `npc_crossbow_base`
   The zone CSVs list `xmodel`, `material`, `techset`, `xmodelsurfs` references. Materials
   and images are usually **not** in these tr zones; they are in `common_mp` (see §4).

---

## 3. Dependency dumps (h1 target)

Dump only what the weapon needs. Put the result into `GAME\zonetool_paths\<name>` (or into
the `GAME\zonetool\<zone>` source folder for xmodels/xsurfaces; see §5).

Minimum for an AW weapon:

```text
# AW tool
dumpzone h1 code_pre_gfx_mp
dumpzone h1 code_post_gfx_mp
dumpzone h1 mp_vm_<weapon>_tr
dumpzone h1 mp_wm_<weapon>_tr
```

Sizes seen for the crossbow:

| dump | files | size | notes |
|---|---:|---:|---|
| `mp_vm_exocrossbow_tr` (full) | 32 | ~4 MB | only xmodel/xsurface; materials live in `common_mp` |
| `mp_wm_exocrossbow_tr` (full) | 32 | ~4 MB | same |
| `code_post_gfx_mp` (full) | 11,237 | 380 MB | code shaders/techsets; can be huge |
| `code_post_gfx_mp` `pixelshader` | 992 | ~6 MB | enough for ps |
| `common_mp` `material` | 24,690 | 25 MB | all materials, incl. crossbow scope/base/glass/target |
| `common_mp` `techset` | 29,261 | 25.6 MB | techset JSONs |
| `common_mp` `dumped_techsets` | 348 | 193 MB | stateinfo for the techsets (FATAL if missing) |
| `common_mp` `pixelshader` | ~1,000 | ~33 MB | includes `lpo_sm_nofog_lmpb_l0n_r0c0n0s0om0ssr_nc` |
| `common_mp` `vertexshader` / `hullshader` / `domainshader` | small | ~1 MB | subdiv shaders |
| `patch_common_mp` (full) | 34,915 | 7.2 GB | avoid; dump targeted types if needed |

`code_post_gfx_mp` techsets/shlist are also needed for some glass techsets, e.g.
`m_l_sm_lmpb_ndw_b0c0n0sd0sr0_cltrans_s1` is an asset in `code_post_gfx_mp` (not common_mp):

```text
dumpzone h1 code_post_gfx_mp techset
dumpzone h1 code_post_gfx_mp pixelshader
dumpzone h1 code_post_gfx_mp vertexshader
dumpzone h1 code_post_gfx_mp hullshader
dumpzone h1 code_post_gfx_mp domainshader
```

Copy the dumped `techsets`, `materials`, `dumped_techsets`, `images`/`xmodel`/`xsurface`
folders into `GAME\zonetool_paths\common_mp_materials\` (or a new folder there). The H1 build
scans every folder in `zonetool_paths`.

**Delete after the build:** the full `code_post_gfx_mp`/`common_mp`/`patch_common_mp` dumps.
**Keep for the next weapon:** the targeted `common_mp_materials` (materials/techsets/stateinfo),
`code_post_gfx_mp` techsets/shaders, and `weapon_models` xmodels/xsurfaces.

---

## 4. Weapon JSON

H1 x64-zt cannot dump AW weapons (the S1 weapon dump call is commented out; the H1 target
returns 0 files). Use the H2 target:

```text
dumpzone h2 patch_common_mp weapon
```

This writes H2-shaped JSONs to `AW\dump\patch_common_mp\weapons\`. Convert:

```text
py -3 cod-mwx\tools\aw-weapon-port\s1_weapon_to_h1.py \
  "AW\dump\patch_common_mp\weapons\iw5_exocrossbow_mp.json" \
  "GAME\zonetool\mod\weapons\iw5_exocrossbow_mp.json" \
  --hands viewhands_tf141
```

Options:

- `--attachment <name>` (repeatable): keep an attachment (e.g. `crossbowscopebase`); each
  kept attachment must itself be converted/built.
- `--hands <xmodel>`: hands model on the weapon. Default is `viewmodel_base_viewhands`; **use
  `viewhands_tf141` for a mod zone** (see §6). `--hands ""` leaves it empty (the gun floats at
  the viewmodel origin; no arms).
- `--keep-exo`: keep AW's exo-only anim slots (normally cleared).

The converter pads:
- 190 `szXAnims`/RightHanded/LeftHanded keys,
- 36 `notetrackSoundMap`, 16 `notetrackRumbleMap`/`notetrackFXMap`/`notetrackHideTag` from S1
  parallel arrays,
- 53-surface `bounceSound`/`rollingSound`,
- ~100 bool fields (0/1 → true/false),
- fixed-size arrays (hideTags 32, reticleViewModels 64, gunModel/worldModel 2, turret sounds 4),
- null anim/reload/notetrack override defaults.

Result for the crossbow: `cleared 31 exo-only anim slots`, `attachments none`, handModel
set to the requested hands model.

---

## 5. Zone CSV and build

The mod zone must be built with the **internal zone name `mod`** (not
`mod_sticksandstones`). The client loads zone `mod`; an internal-name mismatch gives
`Disc read error 'mod'`.

`GAME\zone_source\mod.csv`:

```text
// MWR's own hands model by reference (",," = not built into the zone)
xmodel,,viewhands_tf141
weapon,iw5_exocrossbow_mp
// explicit gun models: a missing model must fail the build, not be skipped
xmodel,vm_crossbow_base
xmodel,npc_crossbow_base
xmodel,npc_crossbow_bolt
fx,vfx/lights/light_beacon_crossbow
fx,vfx/explosion/frag_grenade_default
sound,exocrossbow_warning
```

- The `,,` reference line means “use the asset from the base game/zone set, do not build it”.
  For `viewhands_tf141` this is the MP faction hands model. Do not put the AW
  `viewmodel_base_viewhands` in the zone (it is the exo arms and would override MWR's model).
- Put the weapon JSON in `GAME\zonetool\mod\weapons\`.
- Put the xmodels/xsurfaces for the gun in `GAME\zonetool\mod\xmodel\`/`xsurface\` **or** in
  `zonetool_paths`; if the H1 build falls back to `fx100` (red/default triangle), the
  surfaces were not found. Copying the dumped xmodel/xsurface files into the zone source is
  the reliable fix.
- Build:

```text
buildzone mod
```

Output `GAME\zone\mod.ff`; copy to `GAME\mods\<mod>\mod.ff`:

```powershell
Copy-Item "$GAME\zone\mod.ff" "$GAME\mods\sticksandstones\mod.ff" -Force
```

- Check the build log: 0 FATAL/0 ERROR (warnings about missing images are possible), and **no**
  real `xmodel "viewmodel_base_viewhands"`/`"viewhands_tf141"` asset. If x64-zt builds the
  model in anyway, temporarily move that model's folder/file out of `GAME\zonetool_paths`
  (into `C:\Games\cod-hwm\refs\moved\`), rebuild, and move it back.

---

## 6. Hands model / arms

`handModel` tells the engine which xmodel the gun hangs on; the player's faction arms are
drawn in its place.

- Empty `handModel`: no arms, the gun floats at the viewmodel origin and looks too big/close.
- `viewmodel_base_viewhands`: the name HMW's own weapon JSONs use (e.g. `h2_m4_mp` dumped from
  `hmw_ar1`). **In a mod match this model is not loaded.** A reference-only
  `xmodel,,viewmodel_base_viewhands` crashes while loading the mod zone with the exact dialog
  (captured in `mwx-debug\crossbow\crash-17.png`):

  > **Fataler Fehler** — “Could not load default asset 'void' for asset type 'xmodel'.
  > Tried to load asset 'viewmodel_base_viewhands'.”

- **Use `viewhands_tf141`** (HMW's MP TF141 faction hands) for a mod zone. It is loaded in MP
  and prevents the crash. `s1_weapon_to_h1.py ... --hands viewhands_tf141` and
  `xmodel,,viewhands_tf141` in the CSV.
- The reference hands model must not be built into the zone. If the weapon's viewmodel
  scale/offset/hand tag are wrong, the gun can still look oversized and the hands can be
  off-screen even though the crash is gone; that is an AW viewmodel conversion issue, not the
  hands model.

---

## 7. GSC side

The mod's gametype (e.g. `data\mods\sticksandstones\maps\mp\gametypes\sas.gsc`) gives the
weapon by name:

```gsc
crossbow = getdvar("sas_weapon");
if (crossbow == "")
    setdvar("sas_weapon", "iw5_exocrossbow_mp");
self giveweapon(crossbow);
self giveweapon(melee);                 // h2_hatchet
self giveweapon("iw9_throwknife_mp");
self switchtoweapon(crossbow);
self setweaponammoclip(crossbow, weaponclipsize(crossbow));
self setweaponammostock(crossbow, 6);
```

AW projectile/explosion behavior is mostly in the weapon definition (`timedDetonation`,
`explosionRadius`, `projExplosionSound`, `damage`); the AW script effects are ported:

- blink: `vfx/lights/light_beacon_crossbow`
- explosion: `vfx/explosion/frag_grenade_default`
- warning sound: `sound,exocrossbow_warning`

Those three assets must be in the zone CSV (or otherwise loaded). The GSC listens for
`missile_fire`/`missile_stuck` and plays the blink/warning; the weapon's timed detonation
explodes and damages.

---

## 8. Test checklist

Client: `mwx.exe -mod "mods/<mod>" +set mwx_debug_gamemodes 1 +set mwx_gsc_print 1`.
Load via MODS > the mod, then start the gametype on `mp_rust` with 3 bots.

- Console/stdout: `[mods] loading mod.ff of mods/<mod>` and `Loading fastfile mod`; no
  `[sas] weapon ... not available`, no asset errors for the weapon, no script errors.
- **Arms:** MWR (TF141/OpFor) arms in idle, ADS, reload, sprint, melee; hands on the gun,
  normal size/position. Also test the hatchet in the same match and a normal M4A1 after
  `MODS > UNLOAD MOD` (both must have normal MWR arms, not AW exo arms).
- **ADS:** scope/reticle visible; no missing/default/checkerboard texture.
- **Reload:** animation and sound; ammo/stock correct.
- **Projectile:** bolt sticks, blinks, beeps, explodes after ~1.5 s, kills; kill-feed icon/name.
- **Unload:** `MODS > UNLOAD MOD` relaunches without `-mod`; the weapon is gone and base
  weapons have normal MWR arms.
- Capture screenshots of each state; check the build log for FATAL/ERROR/warning counts.

---

## 9. Error catalogue (all crossbow runs)

| Error | Cause | Fix |
|---|---|---|
| H1 `dumpzone h1 patch_common_mp weapon` writes 0 weapon files | x64-zt's S1 dumper has the weapon call commented out | `dumpzone h2 patch_common_mp weapon` + `s1_weapon_to_h1.py` |
| JSON parser errors: missing anim keys, null `notetrack*`, `rollingSound` string, bool/number mismatch, fixed arrays, override nulls | S1 vs H1 layout | converter (190 anims, 36/16 maps, 53 sounds, bools, arrays, override defaults) |
| `vertexshader "position_only.hlsl_s1" not found` | code shader zone not in `zonetool_paths` | `dumpzone h1 code_pre_gfx_mp` / `code_post_gfx_mp` |
| Red/default triangle instead of the gun, `Parsing xmodel surface "fx100"` | xmodel surfaces not found; the build fell back to `fx100` | dump the `mp_vm_<weapon>_tr`/`mp_wm_<weapon>_tr` xmodels/xsurfaces and copy them into the zone source or `zonetool_paths` |
| `Disc read error 'mod'` | `.ff` built with internal name `mod_sticksandstones`, client requests zone `mod` | build with `buildzone mod` (CSV `zone_source\mod.csv`), copy `zone\mod.ff` to `mod.ff` |
| No `[mods] loading mod.ff` / no `Loading fastfile mod`; mod.ff never loaded | old client used fs_game path; release fs_game is read-only | use a client with `fastfiles.cpp` change `6ada442c` (find mod.ff in the loaded mod's folder), build the zone as `mod` |
| Floating gun, no arms, too big/close | `handModel` empty | set a hands model; the gun hangs on it |
| Crash: `Could not load default asset 'void' for asset type 'xmodel'. Tried to load asset 'viewmodel_base_viewhands'.` | reference-only `viewmodel_base_viewhands` is not loaded in the mod match | use `--hands viewhands_tf141` and `xmodel,,viewhands_tf141`; do not use `viewmodel_base_viewhands` here |
| `Missing material ... using default` | materials are in `common_mp`, not the tr zones | `dumpzone h1 common_mp material` into `zonetool_paths` |
| FATAL `stateinfo for techset ... are missing` | stateinfo dump missing | `dumpzone h1 common_mp techset` + copy `dumped_techsets` (stateinfo) |
| FATAL `pixelshader "lpo_sm_nofog_lmpb_l0n_r0c0n0s0om0ssr_nc.hlsl_s1" not found` | common_mp pixelshader set not dumped | `dumpzone h1 common_mp pixelshader`, copy `techsets/ps` |
| FATAL `vertexshader "vertcol_simple_..._subdiv..." not found` | code_post/common vertex/hull/domain shaders missing | dump `vertexshader`/`hullshader`/`domainshader` from `common_mp` and `code_post_gfx_mp`, copy `techsets/vs|hs|ds` |
| FATAL techset `m_l_sm_lmpb_ndw_b0c0n0sd0sr0_cltrans_s1` not found | glass techset is an asset in `code_post_gfx_mp`, not common_mp | `dumpzone h1 code_post_gfx_mp techset` |
| Warnings missing `crossbow_scope_base_*`, `crossbow_glass_*`, `crossbow_target_ems`, `wep_shared_gray_swatch_col`, `weapon_red_cross_background`; red scope | images are `image,` assets in `common_mp`; individual `dumpasset image` writes an S1 `.s1Image`, not an H1 image; full image dump is too large | needs a targeted image extraction/conversion (future work); otherwise red/default scope |
| Disk/VHDX incident | a 38 GB move to `D:` (a Dev Drive VHDX) filled C: and detached the volume | never move/extract outside `C:\Games\cod-hwm`; keep 20 GB free; use hardlinks for HMW zones; delete build/dump artifacts |
| HMW weapon not in `GAME\zone` | HMW fastfiles are in `GAME\hmw-mod\zone` | hardlink the `.ff` into `GAME\zone` (same volume, no copy), dump, remove the link |

---

## 10. Disk budget

| Step | Disk |
|---|---|
| `build-mwx.bat` | ~1.8 GB of `build\obj`/`build\bin`; delete after building |
| `code_post_gfx_mp` full | 380 MB |
| `common_mp` full | 8.9 GB (avoid; dump targeted types) |
| `common_mp` materials/techsets/stateinfo/shaders | ~250 MB total |
| `patch_common_mp` full | 7.2 GB (avoid) |
| crossbow tr-zone dumps | ~8 MB total |
| H1 `mod.ff` | ~20 MB |
| screenshots/logs | ~50–100 MB |
| HMW zone hardlinks | 0 extra bytes |

Keep `GAME\zonetool_paths\common_mp_materials` (materials, techsets, `dumped_techsets`),
`GAME\zonetool_paths\code_post_gfx_mp` (techsets + ps/vs/hs/ds), and
`GAME\zonetool_paths\weapon_models` (xmodels/xsurfaces) for the next weapon. Delete the full
AW dumps and the client `build\obj`/`build\bin` when done.

---

## 11. Next weapon quick start

```text
# 1. locate
dumpcsv patch_common_mp
dumpcsv common_mp
#    search for: weapon,<weapon_name>; note the mp_vm_<weapon>_tr / mp_wm_<weapon>_tr zones

# 2. dependencies (AW tool, h1 target)
dumpzone h1 mp_vm_<weapon>_tr
dumpzone h1 mp_wm_<weapon>_tr
dumpzone h1 code_post_gfx_mp            # or targeted shader/techset types
dumpzone h1 common_mp material
dumpzone h1 common_mp techset
dumpzone h1 common_mp pixelshader
dumpzone h1 common_mp vertexshader
dumpzone h1 common_mp hullshader
dumpzone h1 common_mp domainshader
#    copy the relevant folders to GAME\zonetool_paths\common_mp_materials,
#    code_post_gfx_mp and weapon_models

# 3. weapon JSON
dumpzone h2 patch_common_mp weapon
py -3 cod-mwx\tools\aw-weapon-port\s1_weapon_to_h1.py \
  "AW\dump\patch_common_mp\weapons\<weapon>.json" \
  "GAME\zonetool\mod\weapons\<weapon>.json" --hands viewhands_tf141
#    add --attachment <name> for needed attachments

# 4. zone
#    copy the mod CSV to GAME\zone_source\mod.csv, keep:
#      xmodel,,viewhands_tf141
#      weapon,<weapon>
#      xmodel,<vm_model>
#      xmodel,<wm_model>
#      fx/sound lines as needed
#    put xmodels/xsurfaces into GAME\zonetool\mod\xmodel/xsurface
buildzone mod
copy GAME\zone\mod.ff GAME\mods\<mod>\mod.ff

# 5. test
#    client -mod "mods/<mod>" +set mwx_debug_gamemodes 1 +set mwx_gsc_print 1
#    MODS > <mod>; <gametype> on mp_rust; 3 bots
#    check console lines, arms (idle/ADS/reload/sprint/melee), hatchet/M4A1 arms,
#    ADS textures, bolt behavior, kill feed, unload.
```

If something fails, check the latest `GAME\zone\mod.ff` build log for `FATAL`/`ERROR`, then
the missing asset type: xmodel → tr-zone dump; material/techset/stateinfo/shader → common_mp
and code_post_gfx_mp dumps; image → targeted image extraction (currently the remaining gap).
