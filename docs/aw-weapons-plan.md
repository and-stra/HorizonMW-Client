# Plan: porting Advanced Warfare (S1) weapons into MWX

Goal: add a selected set of AW guns to MWX/HMW. Only the guns that fit a near-present "Modern
Warfare" setting; no energy, railgun, smart, drone or exo weapons. **Nothing is ported yet.**

## Findings (2026-11-22)

### Source install (`C:\Games\Call of Duty - Advanced Warfare`)
- It is **singleplayer only**: `s1_sp64_ship.exe`, campaign zones (`common.ff`, `lagos.ff`,
  `seoul.ff`, ...), `imagefileN.pak` / `soundfileN.pak`. There is **no `s1_mp64_ship.exe`, no
  `common_mp.ff`, no `mp_*.ff`**. `german\` has `deu_common_mp.ff`, `deu_mp_*.ff`, but those
  are localization zones only (strings/VO), not the weapons.
- The MP zones are the better source: they hold the `_mp` weapon defs, MP attachments, MP
  balance, world models and hud icons/killfeed icons. SP zones hold `_sp` defs with campaign
  stats (same models/anims). AW MP is a separate Steam depot ("Call of Duty: Advanced Warfare -
  Multiplayer").
- Open question: whether x64-zt dumps from the SP exe at all, or only from `s1_mp64_ship.exe`.
  Phase 0 answers this.

### Tooling
- Aurora docs: S1 -> H1 conversion is listed as fully supported by x64-zt ("Zonetool Basics").
  H1 runs on the S1 engine, so weapon defs, xmodels, xanims and sounds are nearly the same
  format; this is the easiest kind of port (much easier than the IW5 map workflow on the page
  you linked). Commands: `verifyzones <zone>`, `dumpzone <target game> <zone> <asset filter>`,
  `dumpasset <type> <name>`, then `buildzone` on the H1 side.
- The IW5 map page's techset/sortkey fixes still apply if a material comes out wrong
  ("Could not find mapped X techset", `debug_materials 1` for crashes).
- The H1 game folder already has the build side: `zonetool.exe`, `zonetool\`, `zone_source\`
  (used by `build_gungame_zone.bat` for `hmw_gungame`). Same pattern for a new zone.

### What MWX/HMW already gives us
- `patches.cpp` `ui_init_stub()`: list of HMW content zones (`hmw_ar1`, `hmw_smg`, ...) loaded
  if the file exists -> add our zone(s) there.
- `fastfiles.cpp` already enlarges the weapon, attachment, sound, xanim, loaded_sound and
  localize pools; `weapon.cpp` precaches every weapon found in the pools.
- `stock_weapons.cpp` already patches `mp/statstable.csv` rows at load (68 columns) -> the
  place to append AW rows (CAC menus read the statstable).
- `localized_strings.cpp` can supply `WEAPON_*` names.
- HMW GSC (`scripts/mp_patches/custom_weapons.gsc`):
  - `isvalidprimary` / `isvalidsecondary` are **hardcoded whitelists of `h2_*` weapons** ->
    must be extended (MWX script with `replacefunc`, keeps HMW's zone untouched).
  - `buildweaponname` treats `iw5_*` names with the S1/IW5 grammar
    (`iw5_x_mp_<attachment>`), not H1's `_a#..._f#...`. AW weapons are named `iw5_*`, so they
    already take that path. Whether H1's weapon-name parser accepts S1 attachment suffixes is
    tested in the pilot.
  - camo/reticle code also accepts `iw5` names; AW camos work differently -> force camo 0 for
    AW guns at first.
- Name collisions: HMW already uses `iw5_lsr_mp`. None of the AW gun names below are used by
  HMW scripts; confirm against all HMW zones in phase 0.

## Weapon list and verdict

Internal names from the AW scripts (`COD-GSC-Source/S1X-GSC`); final-vs-early names from TCRF
(titan45 = Atlas 45, vbr = PDW, himar = IMR, m182spr = MK14, rhino = S-12, m990 = NA-45,
thor = Atlas 20mm, asaw = Ameli). `iw5_lsat` (Pytaek) and `iw5_pbw` (probably Bulldog) are
inferred; confirm from `szDisplayName` in phase 0.

### Tier A: port (real or conventional-looking guns)
| AW name | internal | class | basis | fits as |
|---|---|---|---|---|
| AK12 | iw5_ak12 | AR | Kalashnikov AK-12 | AR |
| ARX-160 | iw5_arx160 | AR | Beretta ARX160 | AR |
| HBRa3 | iw5_hbra3 | AR | conventional AR layout | AR |
| MK14 | iw5_m182spr | marksman | Mk 14 / M14 EBR | AR (semi) or sniper slot; overlaps h1_m14 |
| KF5 | iw5_kf5 | SMG | MP5-style | SMG |
| ASM1 | iw5_asm1 | SMG | Thompson-inspired, drum | SMG |
| Ameli | iw5_asaw | LMG | conventional belt-fed | LMG |
| Lynx | iw5_gm6 | sniper | Gepard GM6 Lynx | sniper (semi) |
| Tac-19 | iw5_uts19 | shotgun | UTS-15 | secondary shotgun |
| Atlas 45 | iw5_titan45 | pistol | 1911 pattern | secondary pistol |
| MAAWS | iw5_maaws | launcher | Carl Gustaf M3 | secondary launcher |
| Combat knife | iw5_combatknife | melee | knife | melee slot (optional) |

### Tier B: borderline, your call (fictional, sci-fi styling, normal mechanics)
| AW name | internal | why borderline |
|---|---|---|
| Bal-27 | iw5_bal27 | fictional bullpup, digital ammo readout, very "AW" look |
| IMR | iw5_himar | fictional burst bullpup |
| MP11 | iw5_mp11 | fictional compact SMG |
| SN6 | iw5_sn6 | sci-fi styled SMG |
| Pytaek | iw5_lsat | sci-fi styled LMG |
| S-12 | iw5_rhino | fictional semi-auto shotgun |
| Bulldog (?) | iw5_pbw | identity to confirm |
| MAUL | iw5_maul | based on the real Metal Storm MAUL prototype, looks futuristic |
| PDW | iw5_vbr | fictional compact PDW-pistol |
| Atlas 20mm | iw5_thor | 20mm anti-materiel, bulky future look |
| Crossbow | iw5_exocrossbow | low-tech, but tied to exo/variant scripts |

### Excluded (futuristic mechanics or exo-only)
MORS `iw5_mors` (railgun), NA-45 `iw5_m990` (explosive 2-stage), RW1 `iw5_rw1` (rail pistol),
AMR9 `iw5_hmr9`, SAC3 `iw5_sac3` (akimbo-only), EM1 `iw5_em1` (laser), EPM3 `iw5_epm3`
(pulse), XMG / exo minigun `iw5_exoxmg` `iw5_exominigun`, MAHEM `iw5_mahem`, MDL
`iw5_microdronelauncher`, Stinger M7 `iw5_stingerm7` (HMW has the Stinger already), AW riot
shield `iw5_riotshieldt6*`, Goliath/mech weapons (`*jugg*`, `iw5_mechpunch`), all `*zm`
(Exo Zombies), all `*lootN` (supply-drop variants), all `iw5_dlcgun*` (DLC, MP-only and not
in this install), `iw5_underwater`, `iw5_carrydrone`.
Leftover MW3 guns in AW SP (`iw5_spas12`, `iw5_usp45`, `iw5_mp5`, `iw5_pp90m1`, `iw5_msr`,
`iw5_lsr`): skip, HMW already has MW2/MWR versions.

### Attachments
Keep only present-day ones, mapped to HMW's attachment names: red dot -> reflex, ACOG -> acog,
holographic/hybrid -> holo (if a plain holo exists), thermal, suppressor -> silencer,
foregrip -> grip, extended mags -> xmag, grenade launcher -> gl (ARs), akimbo (pistols).
Drop: Target Enhancer, Parabolic Mic, Ballistic CPU, Heat Sink, Auto Focus, Tracker, Trip
Mine, Hybrid sight if it has no plain equivalent. The exact AW attachment asset names come from
the phase 0 inventory. AW attachment models are per weapon, so attachments come from the same
dump as the guns.

## Pipeline (per weapon)

1. **Dump + convert** in the AW folder with the x64-zt S1 build:
   `dumpzone h1 common_mp weapon,attachment,xmodel,xmodelsurfs,xanim,material,image,sound,loaded_sound,fx`
   (or the SP zones if MP is not available). Keep the full dump in `refs\dumps\aw_common_mp\`.
2. **Pick** the folders/assets of the chosen guns into
   `GAME\zonetool\mwx_aw_weapons\` (weapon json, attachments, models, anims, images, sounds,
   hud icons).
3. **Edit the weapon json**: retune to HMW values (damage, min damage, ranges, fire time,
   recoil, ADS/sprint-out times, move speed; template = the closest HMW gun), remove exo anim
   references if any remain, set camo-related fields off.
4. **Build**: `zone_source\mwx_aw_weapons.csv` (`weapon,iw5_ak12_mp`, attachment lines;
   zonetool pulls dependencies), `zonetool.exe -buildzone mwx_aw_weapons`, like
   `build_gungame_zone.bat`. Output `.ff` (+ `.pak`) into `hmw-mod\zone\`.
5. **Load**: add `"mwx_aw_weapons"` to the zone array in `patches.cpp ui_init_stub()`.
   Optionally `mwx.exe -repack mwx_aw_weapons` for LZ4 (load times).
6. **Register for CAC**: statstable rows via `stock_weapons.cpp` (new unique ids, class,
   `WEAPON_*` string, image, attachment columns), localized names, GSC whitelist extension,
   camo off.

## Phases

### Phase 0: inventory (no game files changed)
- Decide the source: install AW Multiplayer (recommended), or confirm x64-zt can dump from the
  SP exe.
- Put the x64-zt S1 build next to the AW exe; `verifyzones` on `common_mp` (or `common` + the
  SP levels) and write a CSV: weapon name, zone, display name, class, attachments, sizes.
- Confirm `iw5_lsat` / `iw5_pbw` identities and the AW attachment names.
- `verifyzones` all HMW zones and list every `iw5_*` asset (collision check).
- **Gate**: you confirm the final list (Tier A + chosen Tier B).

### Phase 1: pilot with one gun (AK12)
- Dump/convert/build/load `iw5_ak12_mp` without attachments, then with red dot.
- In a private match: `give iw5_ak12_mp` and `give iw5_ak12_mp_<reddot name>`.
- Check: viewmodel with HMW hands (bones/IK), world model in 3rd person, all anims (raise,
  reload, empty reload, sprint, ADS, inspect, melee), sounds (fire, reload notetracks,
  streamed vs loaded), muzzle flash/shell fx, materials (no black/fullbright/missing), killfeed
  icon, no console errors, load time in `mwx-logs\load_times.log`.
- If S1 attachment suffixes are rejected: fall back to renaming the guns into the H1 grammar
  (`h1_<name>` + `_a#`/`_f#`), decided here.

### Phase 2: integration
- statstable rows, localized names, GSC whitelist, camo off, CAC menu shows the gun with icon
  and attachments; works in a LAN match on two PCs.

### Phase 3: roll out Tier A
- One class at a time (ARs, SMGs, LMG/sniper, secondaries). Zone layout like HMW: one zone per
  class (`mwx_aw_ar`, `mwx_aw_smg`, ...) or one zone; decide by size/load time after the pilot.

### Phase 4: balance pass
- TTK/ranges against HMW's MW2 numbers; AW guns were tuned for exo movement.

### Phase 5: Tier B (only the ones you pick)

## Risks
- AW MP not installed -> SP route needs `_mp` defs built by hand from `_sp` defs.
- H1 weapon-name parsing for S1-style attachment names (pilot tests it).
- Sounds: AW weapon sounds may be streamed from `soundfileN.pak`; zonetool must convert or
  embed them.
- Hands: AW anims were made for exo arms; same skeleton family, but grips may look off.
- Techsets/sortkeys may need manual mapping (see the Aurora IW5 page).
- Camos/reticles: AW systems differ, disabled at first.
- Memory/load time: each gun adds images/anims/sounds; MWX targets short loads.
- Legal: personal LAN use only; don't redistribute AW assets.

## First prompt for opencode (Phase 0, after AW MP is installed or to test the SP exe)
```
Task: inventory Advanced Warfare weapons. Change no game files.
1. In C:\Games\Call of Duty - Advanced Warfare, report whether s1_mp64_ship.exe and common_mp.ff exist.
2. Report which zonetool/x64-zt builds exist under C:\Games (path, file size, date), and how the one in
   C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered selects the game
   (README, --help output). Do not download anything; if no S1-capable build is present, stop and report.
3. If an S1-capable build is present: copy it into the AW folder and run verifyzones on common_mp
   (or, if absent, on common). Save the full output to C:\Games\cod-hwm\refs\dumps\aw-verify-<zone>.txt.
4. Report: exit code, the number of lines starting with "weapon," and "attachment,", and the last 10 lines
   of the output. Stop there.
```

## Pilot recipe (27 Nov 2026) - M1 Garand, MP40

The pilot lives in **hmw_aw_weapons.ff** with the crossbow; no new startup zone (the startup list
is 8 zones: HMW's 6 + hmw_aw_weapons + hmw_mwr_weapons; a 10th zone hangs the map load, see
zone-load-stall.md).

1. **Weapon JSON**: zonetool.exe -unbuffered-io, dumpzone h2 patch_common_mp (the AW tool in
   the AW folder) writes the S1 weapon JSONs under AW\dump\patch_common_mp\weapons\; convert with
   	ools/aw-weapon-port/s1_weapon_to_h1.py <in> <out>.
2. **Animation source**: the S1 dumper does not write xanim assets for the H1 target (checked:
   dumpzone h1 patch_common_mp produced no .xab; only HMW's own anims appear in a build). Use
   the closest MWR weapon's anim table:
   	ools/aw-weapon-port/use_hmw_anims.py <weapon.json> <refs\dumps\patch_common_mp\weapons\h1_*.json>.
   Pilot mapping: M1 Garand -> h1_m14, MP40 -> h1_mp44, combat knife -> h1_meleebayonet. The H1
   build pulls the donor's xanims from the HMW zones as dependencies.
3. **Models**: dumpzone h1 mp_vm_<weapon>_tr and mp_wm_<weapon>_tr (e.g. mp_vm_m1garand_tr)
   write xmodel/xsurface into AW\dump\weapon_models; merge that folder into
   GAME\zonetool\hmw_aw_weapons (robocopy /E). The zone CSV lists the view/world models
   explicitly so a missing model fails the build.
4. **Materials/techsets/images**: the AW materials live in AW's `patch_common_mp` (not in the MWR
   dump and not in AW's `common_mp`): `m/mtl_m1garand_*`, `m/mtl_ger_mp40_base`.
   - `dumpzone h1 patch_common_mp material` writes the materials + techsets (H1 form) into
     `AW\dump\patch_common_mp`. The `h2` target writes `.h2Image` images the H1 build cannot use -
     use the **h1** target only.
   - `dumpzone h1 patch_common_mp image` writes `images/*.h1Image` and
     `streamed_images/*.h1Image` + `*_streamN.pixels` (~6.7 GB for all weapons; it needs the
     temporary disk, clean it up after the collection). Each material JSON lists its images in
     `textureTable`; `mwx-debug\aw-weapons\collect_pilot_images.py` copies only those (26 images for
     the pilot: `tex_m1garand_*`, `ger_mp40_*`, `shared_rail_adapter_01_*`) **plus their
     `_streamN.pixels` payloads** into the source's `images`/`streamed_images`. Copying only the
     `.h1Image` header crashes the game at startup with
     `Create2DTexture(... 128, 128, 0, <fmt>) failed` - the pixels are required.
   - The H1 build is **fatal on a missing techset** (a missing material is only a warning + default).
     The S1-dumped material techset names do not all exist in the dump (e.g.
     `..._dc1dn1ds1dg1_r0c0n0sd0om0_nfwpf_ctq_s1`); map them to an existing techset
     (`m_l_sm_lmpb_r0c0n0sd0om0_nfwpf_ctq_s1` is in the crossbow source) by editing
     `techniqueSet->name` in the copied material JSONs.
   - Do not bulk-copy all AW materials into the source: one unrelated material with a missing
     techset (`mtl_player_emblem`) aborts the whole build.
   - Missing HUD icons (`hud_icon_mp40`, `hud_icon_m1_garand`) and the shared mag material
     (`mtl_mag_dual_clip_base`) are warnings; port the icon images separately if they matter.
5. **Zone**: GAME\zone_source\hmw_aw_weapons.csv lists the weapons + models; build with
   mwx-debug\mwr-weapons\build-zone.ps1 -Zone hmw_aw_weapons (it backs up the old .ff/.pak).
6. **CAC/name/whitelist**: row in stock_weapons_data.hpp (helper mwx-debug\aw-weapons\add_pilot_rows.py),
   real name/description in src/client/component/aw_weapons.cpp, ref added to
   data/mwx/scripts/mp/mwr_weapons.gsc (isvalidprimary / isvalidsecondary / isvalidmeleeweapon).
7. **Test**: data/mwx/tests/aw_pilot.gsc (generic w_weapon body) with mwx_aw_weapon,
   mwx_aw_class; melee has its own w_knife.gsc (hasweapon, not switchtoweapon). 3x green.

## CAC storage: the playerdata Weapon enum (27 Nov 2026)

Symptom: a ported weapon was listed in Create-a-Class, but picking it closed the list and the
class stayed on the old weapon ("selecting does nothing"). It was not the zone and not the
validator: Engine.SetPlayerData(controller, group, "customClasses", <slot>, "weaponSetups",
<0|1>, "weapon", <name>) returns **false** for any name that is not a member of the playerdata
mp/playerdata.ddl enum **Weapon** (228 members). The class slot is an **8 bit** enum index.

What the enum is:

- CustomClass.weaponSetups[].weapon (and meleeWeapon) = 8 bit index into that enum;
  pc ddl_dump prints the members and the hash table.
- 228 of 256 indices are used. **51 of them repeat a name that already has an earlier index**
  (
one x3, camo016..camo062 x2, gold/golddiamond x2, ...). A repeated index is
  unreachable through the name hash (lookups resolve to the first occurrence), so it is a free
  slot that can carry a ported name.
- The remaining names are appended at indices 228..255 (the 8 bit limit is 256 members).
- The enum hash table is a **compact array of count entries sorted by hash**; the hash is a
  lowercase x31 hash (h = h*31 + tolower(c), start 0) and lookup is a binary search. New names
  are inserted in sorted position (src/client/component/ddl_weapon_enum.cpp). An earlier
  attempt guessed open addressing (hash % max) and broke every name lookup in the enum -
  do not touch the table without a binary-search layout.

Implementation: mwx_cac_enum (default 1) polls the DDL on the main pipeline and extends it at
the first lobby (the DDL does not exist at the main menu). pc ddl_extend runs it once and
returns {enum_count, free_slots, appended, capacity, hash, added, present, skipped};
pc ddl_dump shows the result. Verified: after the extension Engine.SetPlayerData accepts
h1_m4, h1_ak47, h1_usp, iw5_dlcgun23/18, iw5_exocrossbow.

Budget and release-prep note: today 68 ported names (MWR DLC guns, MWR melee, AW) compete for
79 slots (51 duplicate indices + 28 appended). skipped in the report lists names that did not
fit (the tail of the melee list today). Keep the skipped count at 0 when adding weapons; a
larger set needs a different storage scheme (a 16 bit class member is a DDL layout change and
needs its own crash test). The extended enum is **identical on every client of the same build**;
a class saved with a ported weapon is not readable by an older client - note it in the
release-prep content check.

## AW preview in the lobby (27 Nov 2026)

The CAC weapon preview is virtual-lobby GSC (maps/mp/_vl_cac.gsc -> setcacweapon ->
uildweaponnamecac -> maps\mp\gametypes\_class::buildweaponname), not LUI. Our
w_buildweaponname only ran in a match: the loader loads scripts/mp/ outside the virtual
lobby and scripts/vlobby_patches/ inside it, while scripts/mp_patches/ loads in both.
HMW's own uildweaponname has no return for iw5_* refs, so the preview name was undefined
and HMW's streamcacweaponwait waited forever (empty preview, no error).

Fix: data/mwx/scripts/mp_patches/aw_weapons.gsc (moved from scripts/mp/) installs the
isvalidsecondary / uildweaponname hooks in both contexts. The lobby calls it as
uildweaponname(ref, attachkit, furniturekit, camo, reticle, emblem); the attachkit name is
not a real attachment, so the attachment lookup rejects it and the name stays <ref>_mp.

Verified: M1 Garand, MP40 and crossbow previews render in the lobby CAC
(mwx-debug\aw-weapons\preview-m1-vlobby-fix2.png, preview-mp40.png, preview-crossbow2.png).
The M1/MP40 previews still look washed out (the crossbow does not): the AW world-model
materials (m/mtl_m1garand_*, m/mtl_ger_mp40_base) do not react to the CAC preview lighting
like HMW's materials do. Pick/name/thumbnail are correct; the material look stays on the D
polish list.

## Combat knife (27 Nov 2026)

The AW knife has no per-weapon model zone (mp_vm_tacticalknife_tr does not exist): its models
and surfaces live in AW's base common_mp. The earlier common_mp dump was defs-only (materials,
878 xmodels, no xsurface, no images). The h1-target dump of that zone can emit the surfaces:

    dumpzone h1 common_mp xmodelsurfs     # 545 .xsb -> dump\common_mp\xsurface
    dumpzone h1 common_mp image           # textures (not run yet)

Knife assets (single LOD each): m_mp_tactical_knife.xmb +
m_mp_tactical_knife_lodvm101.xsb, 
pc_mp_tactical_knife.xmb +

pc_mp_tactical_knife_lod0101.xsb; materials m/mtl_mp_tactical_knife (and the
m/mtl_variable_grenade_lethal the view model names), all copied into
GAME\zonetool\hmw_aw_weapons and listed in the zone CSV after the MP40 block.
The def weapons/iw5_combatknife_mp.json (converted, anims from h1_meleebayonet) is in the
source; it was never listed in the CSV before, which is why the weapon asset did not exist.
Textures: the material uses mp_tactical_knife_col/nml/spc/occ (AW images, not dumped yet) and
the shared cloak_detail3 / ~envbrdflut_ggx_16-rg (HMW has those - reference, do not copy).

Update, same day: the knife is **in the zone and works**. The asset-type token is xmodelsurfs
(not xsurface; the latter is not an asset type name and silently dumps nothing), and the weapon
was never listed in the zone CSV - both fixed. Build: 848 assets, zone-check green, w_knife
5/5. Textures: a full dumpzone h1 common_mp image run produced 1.3k images + 21k streamed files
(7.3 GB) but **none of the knife's** (mp_tactical_knife_col/nml, ~mp_tactical_knife_occ/spc);
only ttachment_tactical_knife - they live in AW's patch_common_mp (the 6.7 GB dump that was
deleted after the pilot). Until that dump is repeated for those 8 images the knife renders with
default images. Texture polish item, like the washed-out M1/MP40 previews.

Icons (1.8.3): the ported weapons have no CAC list icon, kill-feed icon or HUD icon of their own
(the M1 Garand and MP40 still warn about `hud_icon_mp40`/`hud_icon_m1_garand`); the CAC row and
the big preview fall back to the world model, which is why the list rows show the actual gun. The
renderer in `tools/weapon-icons/` turns the world model into MWR-style list/header/HUD PNGs through
hmw-workbench (see `docs/weapon-icons.md`); wiring them into the zone waits on the workbench side
(hide the orbit grid/axes, add `zonetool\hmw_aw_weapons` to its asset roots) and a PNG ->
`.h1Image` + `_streamN.pixels` writer. The style config, batch command and contact sheet are
ready for when those two land.
