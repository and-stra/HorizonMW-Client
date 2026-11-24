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
