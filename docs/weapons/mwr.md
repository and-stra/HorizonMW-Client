# MWR weapons in Create-a-Class (item 12, branch `mwr-weapons`)

The MWR (`h1_*`) weapons ship inside `patch_common_mp.ff`; HMW's statstable/customweapons rows for
them exist but only the h2_/iw5_ refs are whitelisted, so they were hidden. This item makes the
approved set selectable.

## Scope (user decision, 26 Nov)

| group | count | refs |
|---|---|---|
| DLC guns without an HMW counterpart | 11 | h1_xmlar, h1_aprast (BOS14), h1_augast (Lynx CQ300), h1_febsmg (MAC-10), h1_aprsmg (Fang 45), h1_augsmg (PK-PSD9), h1_junlmg (Bered MK8), h1_kam12, h1_junsnp (S-Tac Aggressor), h1_aprpst (Prokolot), h1_augpst (BR9) |
| CoD4 guns HMW does not offer | 8 | h1_g3, h1_m14, h1_mp44, h1_skorpion, h1_m60e4, h1_saw, h1_dragunov, h1_remington700 |
| DLC melee | 28 | `stock_weapons_data.hpp` `weapon_melee` rows (the 3 CQB Bayonet rows count once, h1_meleebayonet) |

Out as duplicates (D1): .44 Magnum (`h1_janpst`) and Rangers (`h1_junsho`), plus every h1_ ref
whose real gun HMW already offers (`h1_ak47`, `h1_m4`, ...). Those rows stay in the table but are
not added to the whitelist.

## Status (26 Nov, D0 runtime check)

`asset_exists` over all 66 `h1_*_mp` in the manifest: **27 present, 39 missing**. The missing are
exactly the 11 DLC guns and the 28 melee weapons; the 8 CoD4 guns and the duplicate h1_* rows are
present. Reason: the DLC/melee assets live in `zone\patch_common_mp.ff` (248 MB), which
`hmw-mod\zone\hmw_patch_common_mp.ff` shadows - the engine loads only the latter. Loading a copy of
the MWR patch under another name exits at startup (zone name mismatch / size), so those assets need
a **zonetool repack** into a small `mwr_weapons.ff` (weapons + their xmodels/anims/materials/sounds)
that the client loads like the HMW zones. Until then:
- the 8 CoD4 guns work end to end (rows, whitelist, `mwr_weapon` tests);
- the 11 DLC guns and 28 melee rows are in the header but `stock_weapons` drops them
  (`weapon_loaded` is false), and their tests are not in the manifest.

## Where the assets really are (corrected 26 Nov)

The first D0 check assumed the DLC models were in `patch_common_mp.ff`. They are not: the patch
only **references** them (`xmodel,,name` in the zone CSV = "not built here"). The model data lives
in per-weapon zones:

- `zone\mp_vm_<token>_base_tr.ff` - view model, materials, techsets, image definitions;
- `zone\mp_wm_<token>_base_tr.ff` - world model;
- `zone\mp_vm_<token>_base_p_tr.ff` - the patch/variant model used by e.g. the Kamchatka-12;
- the weapon definitions, xanims, attachments, HUD-icon materials and streamed image data are in
  `patch_common_mp` (`refs\dumps\patch_common_mp`).

The repack therefore copies the patch dump into `GAME\zonetool\hmw_mwr_weapons`, dumps the
per-weapon `_tr` zones (103 zones: 47 weapons incl. the CoD4 set, base and `_p` variants) into
the same folder, and builds one `hmw_mwr_weapons.ff`. The zone lists only `weapon,<ref>` per gun;
zonetool pulls xmodels/xanims/materials/techsets/images/sounds as dependencies, and a missing
asset shows up as a build warning instead of silently disappearing.

Model-zone mapping found by scanning the zone headers for each weapon's `gunModel`/`worldModel`:
`aprast`, `aprpst`, `augast`, `augpst`, `augsmg`, `febsmg`, `junlmg`, `meleejun6->meleebottle`,
`meleefuture*->meleebayonet`, `meleeshovel` (base and `_p`), `kam12` (base and `_p`), `xmlar`;
`aprsmg` uses the Skorpion `vz61` model (`mp_vm_skorpion_base_tr`), `junsnp` the M40A3 model
(`mp_vm_m40a3_base_tr`). No `mp_vm_mac10_base_tr` model is referenced by the MAC-10 weapon def;
the actual model is in `mp_vm_febsmg_base_tr`.

## Real-world models (IMFDB, 26 Nov)

| MWR gun | real-world basis | AW PORT duplicate? |
|---|---|---|
| XM-LAR | FAL/ACR hybrid (fictional) | no |
| BOS14 | SCAR 17 Ultralight bullpup conversion (SCAR-H/L) | no |
| Lynx CQ300 | AAC Honey Badger with cosmetic changes | no |
| MAC-10 | MAC-10 | no |
| Fang 45 | fictional AR-15 SMG (LWRC SMG-45 / POF PSG hybrid); user decision treats it as the SIG MPX counterpart | KF5 dropped, no other |
| PK-PSD9 | Prokolot (Strike One/Stryk-B hybrid) in a carbine conversion kit | no |
| Bered MK8 | IMI Negev Commando / Ultimax 100 hybrid | no |
| Kamchatka-12 | Saiga 12K (full-auto, embellished) | no (AW UTS-15 is different) |
| S-Tac Aggressor | Cheyenne Tactical M200 Intervention | no (AW GM6 Lynx is different) |
| Prokolot | Arsenal Firearms Strike One / Stryk-B hybrid ("Russian Glock") | no |
| BR9 | Luger P08 with cosmetic alterations | no |

None of the approved AW PORT weapons is a duplicate of these MWR guns; the only overlap was the
Fang 45 / KF5 (SIG MPX) case, and the KF5 is already dropped in the AW plan.

## B result (26 Nov): zone built, loading BLOCKED

The repack itself works:

- `GAME\zonetool\hmw_mwr_weapons` was built from the `patch_common_mp` dump plus the 87
  per-weapon `_tr` zones (`GAME\dump\weapon_models`, 718 files / 121 MB).
- `hmw_mwr_weapons.ff` compiled in **8.8 s**: full dependencies 56.0 MB, no streamed images
  51.9 MB, weapon definitions + animations 8.8 MB, one weapon 3.0 MB.
- A client with the zone loads it in **5-7 s** and `asset_exists` confirms all 39 weapon assets
  and the key models (`wpn_h1_asl_xmlar_patch_vm_camo`, `wpn_h1_smg_vz61_vm_camo`,
  `wpn_h1_sni_m40a3_vm_camo`, `wpn_h1_melee_sickle_vm`).

But **every version that is loaded at UI init makes the next map load hang** at
`imagefile48.pak` (2.24 GB): `mp_crash` and `mp_shipment` both stop after
`start imagefile48` and never finish; without the zone the same map loads it in ~3 s. Tried and
ruled out:

- full model/attachment/image zone (56 MB) and model-only / no-image variants;
- weapon definitions + xanims only (15 MB), a single weapon (3 MB), a renamed
  `mwx_xmlar_mp` weapon (no name collision);
- stripping attachments, HUD/kill icons, sounds, and all `szXAnims` values;
- reducing the source `xanim` folder to the 644 referenced anims (the build still pulls the
  dependency set from the game's zones, so the asset base stayed 15,464).

The hang is engine-side, not a build error: the zone load itself completes, then the map's
imagefile48 load stalls. **Solved 27 Nov by the zone-load-stall fix** (`docs/investigations/zone-load-stall.md`):
the engine hangs when the startup zone list has 10 entries, and HMW's three extra menu zones
(`hmw_nightshade`, `hmw_dlc_factions`, `hmw_dlc_killstreaks`) are no longer loaded at startup. The
MWR zone is therefore the 8th startup zone (6 HMW + `hmw_aw_weapons` + `hmw_mwr_weapons`), and
`mp_crash` loads with it.

The zone is restored to `GAME\zone\hmw_mwr_weapons.ff` (the parked copy stays at
`hmw_mwr_weapons.ff.blocked-b`) and is in the startup list. The 12 DLC/melee tests
(`mwr_h1_xmlar`, `aprast`, `augast`, `febsmg`, `aprsmg`, `augsmg`, `junlmg`, `kam12`, `junsnp`,
`aprpst`, `augpst`, `mwr_melee`) are back in `tests.json`.

## How it works

1. **Rows** - `stock_weapons_data.hpp` holds the 68-column statstable rows; `stock_weapons.cpp`
   appends a row to `mp/statstable.csv` and `mp/customweapons.csv` only when the
   `<ref>_mp` weapon asset is loaded. The item-12 melee rows (28) are appended to the header
   (`row_count` 43 -> 71); with `hmw_mwr_weapons 0` they are skipped, so the CAC stays as before.
2. **Names** - `mwr_weapons.cpp` overrides `MWX_MWR_H1_MELEE*` with the real names (Caveman,
   Machete, ...). The gun names use the stock `WEAPON_*` keys, which already resolve.
3. **Whitelist** - `data/mwx/scripts/mp/mwr_weapons.gsc` re-installs
   `_class::isvalidprimary/isvalidsecondary/isvalidmeleeweapon` with the MWR refs added. HMW's
   `custom_weapons.gsc` replaces them from `main()`; this script waits 0.5 s and replaces again,
   so it always wins. It does nothing with `hmw_mwr_weapons 0`.
4. **Attachments/camos** - the rows carry the stock attachment columns; HMW's
   `isvalidattachment` drops the ones whose assets do not exist (`attachments-matrix.md` lists
   them). Camos come from the stock `camoTable.csv`; the `h1_` prefix is already accepted by
   HMW's `applyloadout`.

## Switch

`hmw_mwr_weapons` (bool, default 1). 0 = HMW's whitelist untouched, no melee rows -> the CAC lists
are exactly as before. The dvar is registered in `mwr_weapons.cpp` `post_unpack` (bool is safe
there; only string dvars cannot).

## Tests

- `mwr_weapon`: one listen-host test per gun (`mwx_test_weapon`), give, fire, reload, ADS, kill a
  bot. `mwx_test_weapon_class` is `secondary` for the two pistols.
- `mwr_melee`: one listen-host test that gives all 28 melee weapons and kills with the last.
  Melee weapons go into the melee slot (`switchtoweapon` does not make one current), so the check
  is `hasweapon`. The player has a finite number of weapon slots: after 15 given weapons
  `giveweapon` silently fails (the first run gave 15/28), so the test takes each weapon away
  again (`takeweapon`) before the next one. The model zones (`mp_vm/wm_melee*_base_tr`) load on
  demand while the test runs.
- `menu-smoke`: opens Create-a-Class in the private lobby and reads `Cac.Weapons` via `lua_eval`;
  it fails unless all 39 MWR refs are in the class lists. CAC screenshots per category for the
  review: `_migration\archive\mwx-debug\mwr-weapons\cac-*.png` (script `cac-categories.ps1`; its `cac-check.txt`
  records `41/41` refs found - the 39 MWR plus two CoD4 spot checks).

The Create-a-Class lists needed two fixes (26/27 Nov):
1. `stock_weapons.cpp` appended the rows to `mp/customweapons.csv` with the `type` column empty;
   the CAC reads `Cac.Weapons[type][class]`, so those rows could never show. The type is now
   derived from the class (`weapon_assault`... -> Primary, pistols/launchers/melee -> Secondary,
   equipment -> Lethal/Tactical).
2. The CAC reads the row count once when its UI script loads, before the weapon zones finish
   loading, so the appended rows (which come last) were outside the loop. The table patch is no
   longer marked final while rows are still missing, and
   `data/mwx/ui_scripts/cac_weapons/__init__.lua` re-scans `mp/customweapons.csv` when the class
   menu opens and adds any ref that `Cac.Weapons` is missing (idempotent).

## Adding another stock weapon

1. Append its 68-column statstable row to `stock_weapons_data.hpp`, bump `row_count`.
2. Add a `case` to the right validator in `mwr_weapons.gsc`.
3. If its name is a `MWX_*` key, add the `localized_strings::override` in `mwr_weapons.cpp`.
4. Add a `mwr_weapon` manifest entry with its ref and class.
5. Run that test 3x, then one full suite plus menu smoke.
