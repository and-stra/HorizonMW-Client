# HMW weapons and perks - porting reference

Reference for porting modes and content to HMW (HorizonMW). It answers: which weapon and perk
refs exist, how to give them, how the gamemode loadout and its spawn timing work, and which
pitfalls cost us test runs.

Sources:

- `COD-GSC-Source\HMW-GSC` and `COD-GSC-Source\H1-GSC` - decompiled GSC dumps. HMW is MW2 gameplay
  on the H1/MWR engine: it ships its own `_weapons`/`_perks`/killstreaks/menus on top of H1's
  `_class`, `_playerlogic`, `_gamelogic`, `_hodgepodge`. HMW-GSC contains the files HMW changes;
  H1-GSC the untouched MWR files.
- `refs\h1_dump\h1_dump\mp\*.csv` - the dumped MWR/H1 tables (`statstable.csv`, `perktable.csv`,
  `attachmenttable.csv`, `attachkits.csv`, `gametypestable.csv`) and `localize.json`.
- HMW's own tables are **not dumped**. The HMW weapon/perk tables below marked "runtime" were read
  from a running HMW client with `gsc_eval` (`tablegetrowcount` / `tablelookupbyrow` /
  `tablelookupistring` on `mp/statstable.csv` and `mp/perktable.csv`). Everything else about HMW
  tables is **unverified**.
- `data/mwx` - our own gametype ports and tests. They are running code, so they are the best
  evidence for "does this actually work on HMW".

Legend: `[file:lines]` is a source. **Unverified** means nobody read it from the shipped HMW
table/asset yet.

## 1. Weapons

### 1.1 Ref names and origin prefixes

A weapon has two names:

- the **ref** used by the class/loadout/CAC code, e.g. `h2_m4`, `h1_ak47`, `h2_usp`;
- the **asset name** the engine/`giveweapon` needs, e.g. `h2_m4_mp`, `h1_ak47_mp`,
  `h2_usp_mp_camo00` - `_class::buildweaponname` appends `_mp`, camo, reticle and attachments
  [H1-GSC/maps/mp/gametypes/_class.gsc:1554-1621]
  [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:889-1045].

Prefix = the content's origin namespace:

| prefix | origin | examples |
|---|---|---|
| `h1_` | MWR (H1) native content | `h1_ak47`, `h1_meleeshovel`, `h1_fraggrenade` |
| `h2_` | HMW's added content (MW2/MW3 guns in the `h2_` namespace) | `h2_m4`, `h2_mp7`, `h2_usp` |
| `iw9_` | Modern Warfare III (2023) asset reused by HMW | `iw9_throwknife_mp` |
| `iw5_` | MW3/AW asset namespace; in HMW only our AW port uses it | `iw5_exocrossbow_mp` (Sticks and Stones) |
| no prefix | MW2/MWR launchers and shared engine refs | `at4`, `stinger`, `javelin`, `flare_mp`, `airstrike_mp` |

`h2_` is treated as a HMW/MW2 name throughout the class code (`getsubstr(...,3,...)` strips three
characters, not four) [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:969-977]. `iw5_`/`iw6_` rows
are converted through the weapon name tokens before entering the weapon pool
[HMW-GSC/maps/mp/gametypes/_weapons.gsc:89-95]. The prefix is an asset namespace, not a guarantee
of the original title: the runtime table below contains MW3 guns under `h2_` (`h2_mp7`,
`h2_cm901`, `h2_msr`).

### 1.2 HMW runtime `mp/statstable.csv` (weapon rows)

The pool is built in `_weapons::init`: every `statstable.csv` row whose column 2 starts with
`weapon_`, has no value in column 51 and is not `Never` in the last column, with a non-empty ref in
column 4, is added as `<ref>_mp` [HMW-GSC/maps/mp/gametypes/_weapons.gsc:69-95]. That is the same
column layout as the H1 dump (class, name key, ref).

#### Assault

| ref | full name | class | origin |
|---|---|---|---|
| `h2_m4` | M4A1 | weapon_assault | HMW added (h2_ namespace) |
| `h2_famas` | FAMAS | weapon_assault | HMW added (h2_ namespace) |
| `h2_scar` | SCAR-H | weapon_assault | HMW added (h2_ namespace) |
| `h2_tavor` | TAR-21 | weapon_assault | HMW added (h2_ namespace) |
| `h2_fal` | FAL | weapon_assault | HMW added (h2_ namespace) |
| `h2_m16` | M16A4 | weapon_assault | HMW added (h2_ namespace) |
| `h2_masada` | ACR (Masada) | weapon_assault | HMW added (h2_ namespace) |
| `h2_fn2000` | FN F2000 | weapon_assault | HMW added (h2_ namespace) |
| `h2_ak47` | AK-47 | weapon_assault | HMW added (h2_ namespace) |
| `h2_cm901` | CM901 | weapon_assault | HMW added (h2_ namespace) |
| `h2_g36c` | G36C | weapon_assault | HMW added (h2_ namespace) |
| `h2_iw5acr` | ACR 6.8 | weapon_assault | HMW added (h2_ namespace) |
| `h2_aac` | AAC | weapon_assault | HMW added (h2_ namespace) |
| `h1_ak47` | AK-47 | weapon_assault | MWR (H1) |
| `h1_g3` | G3 | weapon_assault | MWR (H1) |
| `h1_g36c` | G36C | weapon_assault | MWR (H1) |
| `h1_m14` | M14 | weapon_assault | MWR (H1) |
| `h1_m16` | M16A4 | weapon_assault | MWR (H1) |
| `h1_m4` | M4 Carbine | weapon_assault | MWR (H1) |
| `h1_mp44` | MP44 | weapon_assault | MWR (H1) |

#### SMG

| ref | full name | class | origin |
|---|---|---|---|
| `h2_mp5k` | MP5K | weapon_smg | HMW added (h2_ namespace) |
| `h2_ump45` | UMP45 | weapon_smg | HMW added (h2_ namespace) |
| `h2_kriss` | KRISS Vector | weapon_smg | HMW added (h2_ namespace) |
| `h2_p90` | P90 | weapon_smg | HMW added (h2_ namespace) |
| `h2_uzi` | Mini-Uzi | weapon_smg | HMW added (h2_ namespace) |
| `h2_ak74u` | AK-74u | weapon_smg | HMW added (h2_ namespace) |
| `h2_mp7` | MP7 | weapon_smg | HMW added (h2_ namespace) |
| `h2_pm9` | PM-9 | weapon_smg | HMW added (h2_ namespace) |
| `h2_mp5` | MP5 | weapon_smg | HMW added (h2_ namespace) |
| `h1_ak74u` | AK-74u | weapon_smg | MWR (H1) |
| `h1_mp5` | MP5 | weapon_smg | MWR (H1) |
| `h1_p90` | P90 | weapon_smg | MWR (H1) |
| `h1_skorpion` | Skorpion | weapon_smg | MWR (H1) |
| `h1_uzi` | Mini-Uzi | weapon_smg | MWR (H1) |

#### LMG

| ref | full name | class | origin |
|---|---|---|---|
| `h2_sa80` | L86 LSW (SA80) | weapon_heavy | HMW added (h2_ namespace) |
| `h2_rpd` | RPD | weapon_heavy | HMW added (h2_ namespace) |
| `h2_mg4` | MG4 | weapon_heavy | HMW added (h2_ namespace) |
| `h2_aug` | AUG HBAR | weapon_heavy | HMW added (h2_ namespace) |
| `h2_m240` | M240 | weapon_heavy | HMW added (h2_ namespace) |
| `h2_pkm` | PKM | weapon_heavy | HMW added (h2_ namespace) |
| `h1_m60e4` | M60E4 | weapon_heavy | MWR (H1) |
| `h1_rpd` | RPD | weapon_heavy | MWR (H1) |
| `h1_saw` | M249 SAW | weapon_heavy | MWR (H1) |

#### Sniper

| ref | full name | class | origin |
|---|---|---|---|
| `h2_cheytac` | CheyTac Intervention | weapon_sniper | HMW added (h2_ namespace) |
| `h2_barrett` | Barrett .50cal | weapon_sniper | HMW added (h2_ namespace) |
| `h2_wa2000` | WA2000 | weapon_sniper | HMW added (h2_ namespace) |
| `h2_m21` | M21 EBR | weapon_sniper | HMW added (h2_ namespace) |
| `h2_m40a3` | M40A3 | weapon_sniper | HMW added (h2_ namespace) |
| `h2_msr` | MSR | weapon_sniper | HMW added (h2_ namespace) |
| `h2_as50` | AS50 | weapon_sniper | HMW added (h2_ namespace) |
| `h2_d25s` | D-25S | weapon_sniper | HMW added (h2_ namespace) |
| `h2_l118a` | L118A | weapon_sniper | HMW added (h2_ namespace) |
| `h2_usr` | USR | weapon_sniper | HMW added (h2_ namespace) |
| `h1_barrett` | Barrett .50cal | weapon_sniper | MWR (H1) |
| `h1_dragunov` | Dragunov | weapon_sniper | MWR (H1) |
| `h1_m21` | M21 | weapon_sniper | MWR (H1) |
| `h1_m40a3` | M40A3 | weapon_sniper | MWR (H1) |
| `h1_remington700` | R700 | weapon_sniper | MWR (H1) |

#### Shotgun

| ref | full name | class | origin |
|---|---|---|---|
| `h1_m1014` | M1014 | weapon_shotgun | MWR (H1) |
| `h1_winchester1200` | W1200 | weapon_shotgun | MWR (H1) |

#### Secondary shotgun

| ref | full name | class | origin |
|---|---|---|---|
| `h2_spas12` | SPAS-12 | weapon_secondary_shotgun | HMW added (h2_ namespace) |
| `h2_aa12` | AA-12 | weapon_secondary_shotgun | HMW added (h2_ namespace) |
| `h2_striker` | Striker | weapon_secondary_shotgun | HMW added (h2_ namespace) |
| `h2_m1014` | M1014 | weapon_secondary_shotgun | HMW added (h2_ namespace) |
| `h2_model1887` | Model 1887 | weapon_secondary_shotgun | HMW added (h2_ namespace) |
| `h2_ranger` | Ranger | weapon_secondary_shotgun | HMW added (h2_ namespace) |
| `h2_winchester1200` | W1200 | weapon_secondary_shotgun | HMW added (h2_ namespace) |
| `h2_ksg` | KSG | weapon_secondary_shotgun | HMW added (h2_ namespace) |

#### Pistol

| ref | full name | class | origin |
|---|---|---|---|
| `h2_coltanaconda` | Colt Anaconda | weapon_pistol | HMW added (h2_ namespace) |
| `h2_usp` | USP .45 | weapon_pistol | HMW added (h2_ namespace) |
| `h2_m9` | M9 | weapon_pistol | HMW added (h2_ namespace) |
| `h2_colt45` | M1911 .45 | weapon_pistol | HMW added (h2_ namespace) |
| `h2_deserteagle` | Desert Eagle | weapon_pistol | HMW added (h2_ namespace) |
| `h2_mp412` | MP412 | weapon_pistol | HMW added (h2_ namespace) |
| `h2_p226` | P226 | weapon_pistol | HMW added (h2_ namespace) |
| `h1_beretta` | M9 | weapon_pistol | MWR (H1) |
| `h1_colt45` | M1911 .45 | weapon_pistol | MWR (H1) |
| `h1_deserteagle` | Desert Eagle | weapon_pistol | MWR (H1) |
| `h1_usp` | USP .45 | weapon_pistol | MWR (H1) |

#### Machine pistol

| ref | full name | class | origin |
|---|---|---|---|
| `h2_pp2000` | PP2000 | weapon_secondary_machine_pistol | HMW added (h2_ namespace) |
| `h2_glock` | Glock 18 | weapon_secondary_machine_pistol | HMW added (h2_ namespace) |
| `h2_beretta393` | Beretta 93R | weapon_secondary_machine_pistol | HMW added (h2_ namespace) |
| `h2_tmp` | TMP | weapon_secondary_machine_pistol | HMW added (h2_ namespace) |
| `h2_fmg9` | FMG9 | weapon_secondary_machine_pistol | HMW added (h2_ namespace) |

#### Launcher

| ref | full name | class | origin |
|---|---|---|---|
| `at4` | AT4 | weapon_projectile | shared/engine |
| `h2_m79` | M79 | weapon_projectile | HMW added (h2_ namespace) |
| `stinger` | Stinger | weapon_projectile | shared/engine |
| `javelin` | Javelin | weapon_projectile | shared/engine |
| `h2_rpg` | RPG-7 | weapon_projectile | HMW added (h2_ namespace) |
| `h2_m320` | M320 | weapon_projectile | HMW added (h2_ namespace) |
| `h1_rpg` | RPG-7 | weapon_projectile | MWR (H1) |

#### Melee / deathstreak

| ref | full name | class | origin |
|---|---|---|---|
| `h2_shovel` | Shovel | weapon_melee | HMW added (h2_ namespace) |
| `h2_icepick` | Ice Pick | weapon_melee | HMW added (h2_ namespace) |
| `h2_hatchet` | Hatchet | weapon_melee | HMW added (h2_ namespace) |
| `h2_sickle` | Sickle | weapon_melee | HMW added (h2_ namespace) |
| `h2_karambit` | Karambit | weapon_melee | HMW added (h2_ namespace) |
| `specialty_combathigh` | Combat High (deathstreak) | weapon_melee | perk/deathstreak ref |
| `specialty_copycat` | Copycat (deathstreak) | weapon_melee | perk/deathstreak ref |
| `specialty_finalstand` | Final Stand (deathstreak) | weapon_melee | perk/deathstreak ref |
| `specialty_grenadepulldeath` | Martyrdom (deathstreak) | weapon_melee | perk/deathstreak ref |

#### Lethal / tactical

| ref | full name | class | origin |
|---|---|---|---|
| `h1_fraggrenade` | Frag Grenade | weapon_grenade | MWR (H1) |
| `h1_fraggrenadeshort` | Short-fuse Frag | weapon_grenade | MWR (H1) |
| `h1_flashgrenade` | Flash Grenade | weapon_grenade | MWR (H1) |
| `h1_concussiongrenade` | Concussion Grenade | weapon_grenade | MWR (H1) |
| `h1_smokegrenade` | Smoke Grenade | weapon_grenade | MWR (H1) |
| `h2m_weapon_c4` | C4 | weapon_grenade | HMW added (h2_ namespace) |
| `h2m_weapon_claymore` | Claymore | weapon_grenade | HMW added (h2_ namespace) |
| `weapon_trophy` | Trophy System | weapon_grenade | shared/engine |
| `weapon_emp` | EMP Grenade | weapon_grenade | shared/engine |
| `iw9_throwknife` | Throwing Knife | weapon_grenade | MWIII asset |
| `h2_semtex` | Semtex | weapon_grenade | HMW added (h2_ namespace) |
| `specialty_tacticalinsertion` | Tactical Insertion (gives flare_mp) | weapon_grenade | perk/deathstreak ref |

**How to read the table.** `ref` is what loadouts/`giveweapon("...")` wrappers take; the full asset
name adds `_mp` (and camo/attachment suffixes) via `buildweaponname`. Rows in class `weapon_other`
or with an unlock column are not in `level.weaponlist` [HMW-GSC/maps/mp/gametypes/_weapons.gsc:74-83].
The CAC screens do not list everything from this pool: the primary list is a hard-coded whitelist
(see 2.5).

### 1.3 MWR (H1) weapons in the content

These are the MWR weapons present in the H1 dump. HMW keeps the assets and scripts; the MW2 CAC
whitelist (1.2/2.5) does not offer most of them as primaries, but gamemode scripts can give them by
name - Slasher does exactly that with `h1_colt45` and `h1_meleeshovel`
[data/mwx/tests/slasher.gsc:47-51].

#### Assault

| ref | full name | class | origin |
|---|---|---|---|
| `h1_ak47` | AK-47 | weapon_assault | MWR (H1) |
| `h1_g3` | G3 | weapon_assault | MWR (H1) |
| `h1_g36c` | G36C | weapon_assault | MWR (H1) |
| `h1_m14` | M14 | weapon_assault | MWR (H1) |
| `h1_m16` | M16A4 | weapon_assault | MWR (H1) |
| `h1_m4` | M4 Carbine | weapon_assault | MWR (H1) |
| `h1_mp44` | MP44 | weapon_assault | MWR (H1) |
| `h1_xmlar` | XM-LAR | weapon_assault | MWR (H1) |
| `h1_aprast` | BOS14 | weapon_assault | MWR (H1) |
| `h1_augast` | Lynx CQ300 | weapon_assault | MWR (H1) |

#### Launcher

| ref | full name | class | origin |
|---|---|---|---|
| `h1_rpg` | RPG-7 | weapon_projectile | MWR (H1) |

#### Lethal/tactical

| ref | full name | class | origin |
|---|---|---|---|
| `h1_fraggrenade` | h1_fraggrenade | weapon_grenade | MWR (H1) |
| `h1_fraggrenadeshort` | h1_fraggrenadeshort | weapon_grenade | MWR (H1) |
| `h1_flashgrenade` | h1_flashgrenade | weapon_grenade | MWR (H1) |
| `h1_concussiongrenade` | h1_concussiongrenade | weapon_grenade | MWR (H1) |
| `h1_smokegrenade` | h1_smokegrenade | weapon_grenade | MWR (H1) |
| `h1_c4` | h1_c4 | weapon_grenade | MWR (H1) |
| `h1_claymore` | h1_claymore | weapon_grenade | MWR (H1) |

#### LMG

| ref | full name | class | origin |
|---|---|---|---|
| `h1_m60e4` | M60E4 | weapon_heavy | MWR (H1) |
| `h1_rpd` | RPD | weapon_heavy | MWR (H1) |
| `h1_saw` | M249 SAW | weapon_heavy | MWR (H1) |
| `h1_feblmg` | PKM | weapon_heavy | MWR (H1) |
| `h1_junlmg` | Bered MK8 | weapon_heavy | MWR (H1) |

#### Melee

| ref | full name | class | origin |
|---|---|---|---|
| `h1_meleeshovel` | Gravedigger | weapon_melee | MWR (H1) |
| `h1_meleebottle` | Brawler's Brew | weapon_melee | MWR (H1) |
| `h1_meleeblade` | Scorpion | weapon_melee | MWR (H1) |
| `h1_meleeicepick` | Cliffhanger | weapon_melee | MWR (H1) |
| `h1_meleegladius` | Gladiator | weapon_melee | MWR (H1) |
| `h1_meleesickle` | Sickle | weapon_melee | MWR (H1) |
| `h1_meleehatchet` | Hatchetman | weapon_melee | MWR (H1) |
| `h1_meleefeb1` | Mechanic | weapon_melee | MWR (H1) |
| `h1_meleefeb2` | Shamrock Blade | weapon_melee | MWR (H1) |
| `h1_meleefeb3` | Samurai | weapon_melee | MWR (H1) |
| `h1_meleefeb4` | Thug | weapon_melee | MWR (H1) |
| `h1_meleeapr1` | Caveman | weapon_melee | MWR (H1) |
| `h1_meleeapr2` | Machete | weapon_melee | MWR (H1) |
| `h1_meleeapr3` | Diabolical | weapon_melee | MWR (H1) |
| `h1_meleeapr4` | Sawtooth | weapon_melee | MWR (H1) |
| `h1_meleebayonet` | CQB Bayonet | weapon_melee | MWR (H1) |
| `h1_meleepaddle` | Omsk Hammer | weapon_melee | MWR (H1) |
| `h1_meleefeb5` | Leprechaun | weapon_melee | MWR (H1) |
| `h1_meleejun1` | Bludgeon | weapon_melee | MWR (H1) |
| `h1_meleejun2` | Cleaver | weapon_melee | MWR (H1) |
| `h1_meleejun3` | Nauticus | weapon_melee | MWR (H1) |
| `h1_meleejun4` | Tidal | weapon_melee | MWR (H1) |
| `h1_meleeaug1` | Danger Close | weapon_melee | MWR (H1) |
| `h1_meleeaug2` | Barber | weapon_melee | MWR (H1) |
| `h1_meleeaug3` | Point Knife | weapon_melee | MWR (H1) |
| `h1_meleeaug4` | Enforce | weapon_melee | MWR (H1) |
| `h1_meleejun5` | Tribal | weapon_melee | MWR (H1) |
| `h1_meleejun6` | Sarsaparilla | weapon_melee | MWR (H1) |

#### Pistol

| ref | full name | class | origin |
|---|---|---|---|
| `h1_beretta` | M9 | weapon_pistol | MWR (H1) |
| `h1_colt45` | M1911 .45 | weapon_pistol | MWR (H1) |
| `h1_deserteagle` | Desert Eagle | weapon_pistol | MWR (H1) |
| `h1_usp` | USP .45 | weapon_pistol | MWR (H1) |
| `h1_deserteagle55` | Commander Desert Eagle | weapon_pistol | MWR (H1) |
| `h1_janpst` | .44 Magnum | weapon_pistol | MWR (H1) |
| `h1_aprpst` | Prokolot | weapon_pistol | MWR (H1) |
| `h1_augpst` | BR9 | weapon_pistol | MWR (H1) |

#### Shotgun

| ref | full name | class | origin |
|---|---|---|---|
| `h1_m1014` | M1014 | weapon_shotgun | MWR (H1) |
| `h1_winchester1200` | W1200 | weapon_shotgun | MWR (H1) |
| `h1_kam12` | Kamchatka-12 | weapon_shotgun | MWR (H1) |
| `h1_junsho` | Rangers | weapon_shotgun | MWR (H1) |

#### SMG

| ref | full name | class | origin |
|---|---|---|---|
| `h1_ak74u` | AK-74u | weapon_smg | MWR (H1) |
| `h1_mp5` | MP5 | weapon_smg | MWR (H1) |
| `h1_p90` | P90 | weapon_smg | MWR (H1) |
| `h1_skorpion` | Skorpion | weapon_smg | MWR (H1) |
| `h1_uzi` | Mini-Uzi | weapon_smg | MWR (H1) |
| `h1_febsmg` | Mac-10 | weapon_smg | MWR (H1) |
| `h1_aprsmg` | Fang 45 | weapon_smg | MWR (H1) |
| `h1_augsmg` | PK-PSD9 | weapon_smg | MWR (H1) |

#### Sniper

| ref | full name | class | origin |
|---|---|---|---|
| `h1_barrett` | Barrett .50cal | weapon_sniper | MWR (H1) |
| `h1_dragunov` | Dragunov | weapon_sniper | MWR (H1) |
| `h1_m21` | M21 | weapon_sniper | MWR (H1) |
| `h1_m40a3` | M40A3 | weapon_sniper | MWR (H1) |
| `h1_remington700` | R700 | weapon_sniper | MWR (H1) |
| `h1_febsnp` | D-25S | weapon_sniper | MWR (H1) |
| `h1_junsnp` | S-Tac Aggressor | weapon_sniper | MWR (H1) |

### 1.4 Refs that are not weapons on their own

- **Bare refs** (`h2_m4`, `h1_ak47`, `h2_coltanaconda`) are loadout refs, not asset names. Giving
  them directly gives nothing (`giveweapon` needs the `_mp`/attachment-built name). The MWX OIC
  port builds the name before giving it [data/mwx/maps/mp/gametypes/oic.gsc:174-184].
- `h2_inspect` is in `isvalidprimary`, but it is the inspect animation, not a gun
  [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:1128].
- `specialty_*` values in the equipment/melee slots (`specialty_combathigh`, `specialty_copycat`,
  `specialty_finalstand`, `specialty_grenadepulldeath`, `specialty_blastshield`,
  `specialty_tacticalinsertion`) are perks/deathstreaks, not weapon assets
  [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:117-129] [:1226-1241].
- `flare_mp` is the tactical-insertion marker; `specialty_tacticalinsertion` is the loadout value
  that gives it [HMW-GSC/maps/mp/perks/_perkfunctions.gsc:3-10].
- `h2_scavenger_bag` is a script model that shows to players with `specialty_scavenger`, not a gun
  [HMW-GSC/maps/mp/gametypes/_weapons.gsc:1-16].
- `h2_riotshield_mp` is referenced by the weapons code but **excluded from precache**, and it has
  no row in the runtime statstable pool - the content is not in this install. See 2.5.
- `airstrike_mp`, `helicopter_mp`, `radar_mp` are killstreak/script refs, not handheld weapons
  (H1 dump `statstable.csv` class `weapon_other`/empty; they are used by the killstreak scripts,
  e.g. HMW-GSC/maps/mp/h2_killstreaks/_airstrike.gsc).
- `none` / `specialty_null` mean "empty slot" [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:958-960,
  1176-1180].

## 2. Giving weapons

### 2.1 The three layers

1. **Bare ref** - `h2_usp`: the class/loadout syntax. `getloadout` keeps it in
   `loadoutPrimary`/`loadoutSecondary` [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:496-519].
2. **Full weapon name** - `_class::buildweaponname(ref, attach1, attach2, camo, reticle)` (HMW
   override; H1's original has six args and no perk array)
   [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:958-1045]
   [H1-GSC/maps/mp/gametypes/_class.gsc:1554-1621]. HMW adds a separate
   `h2_buildweaponname(baseName, attachment1, attachment2, camo, perks)` for MW2 names, including
   the bling second attachment and the sniper 2D-scope choice
   [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:889-956].
3. **The asset** - `giveweapon(fullname)`, then `switchtoweapon`, `setspawnweapon`,
   `setweaponammoclip`, `setweaponammostock`, `takeallweapons` (all engine builtins; HMW's
   `applyloadout` uses them in this order)
   [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:31-145].

`#define` a ref and build it in `main()`/spawn, not in the table:

```gsc
weapon = maps\mp\gametypes\_class::buildweaponname("h2_coltanaconda", "none", "none", "none", []);
self takeallweapons();
self giveweapon(weapon);
self switchtoweapon(weapon);
self setspawnweapon(weapon);
self setweaponammoclip(weapon, 1);
self setweaponammostock(weapon, 0);
```

That is the whole OIC loadout [data/mwx/maps/mp/gametypes/oic.gsc:174-184]. For the H1/MWR
(non-`h2_`) path the same call works with five args; the fifth is the perk array used by bling
[HMW-GSC/scripts/mp_patches/custom_weapons.gsc:958-1004].

### 2.2 Primary, secondary, melee

- **Primary**: `loadoutPrimary` (+ `loadoutPrimaryAttachKit`, `...FurnitureKit`, `...Camo`,
  `...Reticle`); MW2 CAC primaries are the `h2_*` whitelist in `isvalidprimary`
  [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:1101-1135]. Invalid primaries silently fall back
  to the table's class-10 primary (usually an AK) [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:572-590].
- **Secondary**: `loadoutSecondary`; pistols, shotguns and launchers are whitelisted in
  `isvalidsecondary` [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:1063-1099].
- **Melee as a real secondary**: `h2_shovel`, `h2_karambit`, `h2_hatchet`, `h2_icepick`,
  `h2_sickle` are valid secondaries [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:1087-1092]. Give
  a melee weapon like any other weapon (`giveweapon(buildweaponname(ref))`); it occupies the
  secondary slot. `loadoutMelee` is a separate deathstreak-style slot, not a melee weapon: its
  whitelist is only `none`/deathstreaks
  [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:1226-1241].
- **Anything**: `giveweapon` bypasses the whitelists. That is how Slasher gives the shovel and the
  Colt (see 1.3) and how the tests arm players.

### 2.3 Lethal and tactical

| slot | refs accepted | source |
|---|---|---|
| lethal (`loadoutEquipment`) | `specialty_null`, `h1_fraggrenade_mp`, `h2_semtex_mp`, `iw9_throwknife_mp`, `specialty_tacticalinsertion`, `specialty_blastshield`, `h1_claymore_mp`, `h1_c4_mp` | [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:1137-1157] |
| tactical (`loadoutOffhand`) | `h1_smokegrenade_mp`, `h1_concussiongrenade_mp`, `h1_flashgrenade_mp`; given by `giveoffhand` | [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:1159-1182] |

- `specialty_tacticalinsertion` is a perk ref, not a weapon. `applyloadout` gives the perk and then
  sets `flare_mp` as the lethal weapon [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:117-129];
  the perk's set function does the same for non-loadout paths
  [HMW-GSC/maps/mp/perks/_perkfunctions.gsc:3-10]. `flare_mp` is the actual throwable.
- `specialty_blastshield` gives the perk and clears the lethal slot
  [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:120-124].
- `settacticalweapon(<ref>)` sets the offhand; `giveoffhand` is what actually gives the grenade
  [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:146-153, 1159-1182]. Giving a tactical without
  `settacticalweapon`/`giveoffhand` leaves the slot empty.
- Our AON port gives the throwing knife as the lethal and empties the pistol
  [data/mwx/maps/mp/gametypes/aon.gsc:10-14, 171-190].

### 2.4 Ammo and taking weapons

- `takeallweapons()` is the reset before a loadout; HMW's `applyloadout` starts with it and
  `_clearperks()` [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:39-40].
- `setweaponammoclip(ref, n)` / `setweaponammostock(ref, n)` take the **full** weapon name, not the
  bare ref. OIC sets clip 1/stock 0 [data/mwx/maps/mp/gametypes/oic.gsc:183-184]; its kill reward
  fills clip first and the rest into the stock [data/mwx/maps/mp/gametypes/oic.gsc:209-228].
- `setspawnweapon(fullname)` makes the weapon the one a player respawns with
  [H1-GSC/maps/mp/gametypes/_class.gsc:1213-1215].
- `switchtoweapon` is skipped for AIs and hodgepodge gametypes in `applyloadout`
  [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:138-140].

### 2.5 Excluded/missing content and pool limits

- **`h2_riotshield_mp` is excluded from precache** (`should_precache` returns false), together with
  the perk pseudo-weapons, `stinger_mp` and `javelin_mp`. The script still contains riot-shield
  code paths, but the asset is not available in this install
  [HMW-GSC/maps/mp/gametypes/_weapons.gsc:18-40].
- **CAC primary pool** is the 26-entry `isvalidprimary` whitelist (25 real guns plus
  `h2_inspect`); the secondary pool is the 27-entry `isvalidsecondary` list including `none`
  (21 guns plus five melee weapons) [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:1063-1135]. Giving a ref outside these
  lists works with `giveweapon` but not through a normal class.
- **Weapon pool** (`level.weaponlist`) is built from the statstable rows as described in 1.2; a row
  with a value in column 51 or `Never` in the last column is not in it
  [HMW-GSC/maps/mp/gametypes/_weapons.gsc:69-95].
- **Explosive pool**: at most `scr_maxPerPlayerExplosives` (default 2, minimum 1) placed explosives
  per player; the check is `>= level.maxperplayerexplosives` before placing another
  [HMW-GSC/maps/mp/gametypes/_weapons.gsc:45, 1660, 1844, 3151].
- **Class slots**: H1 allows 13 class picks by default (`level.classpickcount`,
  `level.customclasspickcount`) [H1-GSC/maps/mp/gametypes/_class.gsc:162-166].

### 2.6 Attachment refs

`buildweaponname` takes attachment refs (not localized names) and appends them in a fixed order;
MW2 names are alphabetized and the second attachment is only used with bling
[HMW-GSC/scripts/mp_patches/custom_weapons.gsc:889-956]. The MWR-style kits (the `*mwr` names) are
in the dumped `attachkits.csv`, the MW2-style mounts in `attachmenttable.csv`:

| id | mount | ref | name key | description key |
|---|---|---|---|---|
| 0 | none | `none` | MPUI_NO_ATTACHMENT | none |
| 1 | unique | `akimbo` | MPUI_AKIMBO | akimbo |
| 2 | undermount | `gl` | MPUI_GRENADELAUNCHER | gl |
| 3 | unique | `firerate` | MPUI_ROF | firerate |
| 4 | undermount | `foregrip` | MPUI_FOREGRIP | foregrip |
| 6 | unique | `heatsink` | MPUI_HEATSINK | heatsink |
| 7 | unique | `lasersight` | MPUI_LASERSIGHT | lasersight |
| 8 | unique | `longrange` | MPUI_LONGRANGE | longrange |
| 11 | rail | `opticsacog2` | MPUI_ACOG_SCOPE | opticsacog2 |
| 12 | rail | `opticseotech` | MPUI_EOTECH | opticseotech |
| 13 | rail | `opticsreddot` | MPUI_RED_DOT_SIGHT | opticsreddot |
| 14 | rail | `opticstargetenhancer` | MPUI_TARGETENHANCER | opticstargetenhancer |
| 15 | rail | `opticsthermal` | MPUI_THERMAL | opticsthermal |
| 16 | unique | `parabolicmicrophone` | MPUI_PARABOLICMICROPHONE | parabolicmicrophone |
| 17 | unique | `quickdraw` | MPUI_QUICKDRAW | quickdraw |
| 18 | barrel | `silencer01` | MPUI_SILENCER | silencer01 |
| 19 | rail | `stabilizer` | MPUI_STABILIZER | stabilizer |
| 20 | unique | `stock` | MPUI_STOCK | stock |
| 21 | undermount | `tactical` | MPUI_TACTICAL | tactical |
| 22 | rail | `thorscopevz` | MPUI_VZSCOPE | scopevz |
| 23 | barrel | `trackrounds` | MPUI_TRACKROUNDS | trackrounds |
| 24 | rail | `variablereddot` | MPUI_VARIABLEREDDOT | variablereddot |
| 25 | unique | `xmags` | MPUI_XMAGS | xmags |
| 26 | unique | `dualmag` | MPUI_DUALMAG | dualmag |
| 27 | unique | `ironsights` | MPUI_IRONSIGHTS | ironsights |
| 36 | rail | `crossbowscopebase` | MPUI_XBOWSCOPE | crossbowscopebase |
| 37 | rail | `scopevz` | MPUI_VZSCOPE | scopevz |
| 38 | barrel | `silencerpistol` | MPUI_SILENCER | silencer01 |
| 39 | barrel | `silencersniper` | MPUI_SILENCER | silencer01 |
| 40 | rail | `opticsacog2ar` | MPUI_ACOG_SCOPE | opticsacog2 |
| 41 | rail | `opticsthermalar` | MPUI_THERMAL | opticsthermal |
| 43 | rail | `reflexmwr` | MPUI_RED_DOT_SIGHT | reflexmwr |
| 25 | unique | `xmagmwr` | MPUI_XMAGS | xmagmwr |
| 42 | none | `done` | MPUI_DONE_SELECTING | done |

`attachkits.csv` also carries the MWR kit ids/names (`gl/glmwr`, `reflex/reflexmwr`,
`silencer/silencermwr`, `grip/gripmwr`, `acog/acogmwr`, `akimbo/akimbomwr`, ...)
[refs/h1_dump/h1_dump/mp/attachkits.csv]. HMW's `isvalidattachment` accepts both spellings and then
checks that the weapon's statstable attachment array contains the ref
[HMW-GSC/scripts/mp_patches/custom_weapons.gsc:1243-1338]. **Unverified**: the per-weapon attachment
array in HMW's own statstable (column 8 onwards in the H1 dump has the same idea).

## 3. Perks

### 3.1 HMW uses MW2 slots - `validateperk` decides

HMW keeps the MWR table/lookup helpers but validates perks against a **hard-coded MW2/MW3-style
slot table** (three slots, index `0`, `1`, `2`; UI slots 1/2/3). A perk in the wrong index becomes
`specialty_null` [HMW-GSC/maps/mp/perks/_perks.gsc:211-269]. The consequence that broke AON:
`specialty_scavenger`,
`specialty_fastreload` (Sleight of Hand) and `specialty_longersprint` (Marathon) are **all slot-1
(UI) perks**, i.e. index 0 [HMW-GSC/maps/mp/perks/_perks.gsc:216-231]. Putting them into
`loadoutPerks[1]`/`[2]` makes `getloadout` drop them with
`Warning: Perk ... in wrong slot.` [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:639-664].
AON now gives them with `giveperk` after spawn instead
[data/mwx/maps/mp/gametypes/aon.gsc:182-189, 296-299].

Table helpers used by HMW: group = column 13, count = column 6, slot = column 12, localized name =
column 2, image = column 3 [HMW-GSC/maps/mp/perks/_perks.gsc:191-209]. The pro upgrade is column 8:
`applyperks` gives base perk column 1 when the player already has the pro perk in column 8
[HMW-GSC/maps/mp/perks/_perks.gsc:412-430].

### 3.2 HMW `mp/perktable.csv` (runtime, actual table)

Read at runtime from a running HMW client. It contains 20 base perks (each with a pro ref), plus the
11 lethal/tactical rows. The shipped set is the MW3-era list (Marathon, Scavenger, ...), while
`validateperk` also still accepts old MW2 refs (Stopping Power, Juggernaut, ...) in the same slots
[compare HMW-GSC/maps/mp/perks/_perks.gsc:216-266 with the table below]. The slot index is 0-based;
UI slot 1 = index 0.

#### Slot 1 (index 0)

| ref | perk | pro ref | pro perk |
|---|---|---|---|
| `specialty_longersprint` | Marathon | `specialty_fastmantle` | Marathon Pro |
| `specialty_fastreload` | Sleight of Hand | `specialty_quickswap` | Sleight of Hand Pro |
| `specialty_scavenger` | Scavenger | `specialty_extraammo` | Scavenger Pro |
| `specialty_bling` | Bling | `specialty_secondarybling` | Bling Pro |
| `specialty_onemanarmy` | One Man Army | `specialty_omaquickchange` | One Man Army Pro |
| `specialty_blindeye` | Blind Eye | `specialty_fasterlockon` | Blind Eye Pro |

#### Slot 2 (index 1)

| ref | perk | pro ref | pro perk |
|---|---|---|---|
| `specialty_quickdraw` | Quickdraw | `specialty_fastoffhand` | Quickdraw Pro |
| `specialty_lightweight` | Lightweight | `specialty_stalker` | Lightweight Pro |
| `specialty_hardline` | Hardline | `specialty_rollover` | Hardline Pro |
| `specialty_radarimmune` | Cold Blooded | `specialty_spygame` | Cold Blooded Pro |
| `specialty_blastshield` | Blast Shield | `specialty_stun_resistance` | Blast Shield Pro |

#### Slot 3 (index 2)

| ref | perk | pro ref | pro perk |
|---|---|---|---|
| `specialty_extendedmelee` | Commando | `specialty_falldamage` | Commando Pro |
| `specialty_bulletaccuracy` | Steady Aim | `specialty_holdbreath` | Steady Aim Pro |
| `specialty_autospot` | Scrambler | `specialty_fastsprintrecovery` | Scrambler Pro |
| `specialty_quieter` | Ninja | `specialty_delaymine` | Ninja Pro |
| `specialty_detectexplosive` | SitRep | `specialty_selectivehearing` | SitRep Pro |

#### Lethal / tactical (no slot)

| ref | item | count |
|---|---|---|
| `h1_concussiongrenade_mp` | Concussion Grenade | 2 |
| `h1_flashgrenade_mp` | Flash Grenade | 2 |
| `h1_smokegrenade_mp` | Smoke Grenade | 1 |
| `h1_fraggrenade_mp` | Frag Grenade | 1 |
| `h2_semtex_mp` | Semtex | 1 |
| `iw9_throwknife_mp` | Throwing Knife | 1 |
| `specialty_tacticalinsertion` | Tactical Insertion | 1 |
| `h1_claymore_mp` | Claymore | 1 |
| `h1_c4_mp` | C4 | 1 |
| `h2_empgrenade_mp` | EMP Grenade | 1 |
| `h2_trophy_mp` | Trophy System | 1 |

### 3.3 MWR `perktable.csv` (H1 dump)

Slots are the MWR ones from column `f5` (`Perk_Slot1/2/3`); `g6` is the inventory count for
grenades/equipment, not a pro flag. The MWR table has no pro column - pro upgrades are HMW's MW2
mechanism (3.1) [refs/h1_dump/h1_dump/mp/perktable.csv].

| slot | ref | localized key | English (UI) | count |
|---|---|---|---|---|
| 1 | `c4_mp` | PERKS_C4_X_2 | C4 x2 | 2 |
| 1 | `claymore_mp` | PERKS_CLAYMORE_X_2 | Claymore x2 | 2 |
| 1 | `rpg_mp` | PERKS_RPG7_X_2 | RPG-7 x2 | 2 |
| 1 | `specialty_fraggrenade` | PERKS_FRAG_X_3 | Frag x3 | 3 |
| 1 | `specialty_specialgrenade` | PERKS_SPECIAL_GRENADES_X_3 | Special Grenades x3 | 3 |
| 1 | `specialty_extraammo` | PERKS_BANDOLIER | Bandolier |  |
| 1 | `specialty_detectexplosive` | PERKS_BOMB_SQUAD | Bomb Squad |  |
| 2 | `specialty_bulletdamage` | PERKS_STOPPING_POWER | Stopping Power |  |
| 2 | `specialty_armorvest` | PERKS_JUGGERNAUT | Juggernaut |  |
| 2 | `specialty_fastreload` | PERKS_SLEIGHT_OF_HAND | Sleight of Hand |  |
| 2 | `specialty_rof` | PERKS_DOUBLE_TAP | Double Tap |  |
| 2 | `specialty_twoprimaries` | PERKS_OVERKILL | Overkill |  |
| 2 | `specialty_radarimmune` | PERKS_UAV_JAMMER | UAV Jammer |  |
| 2 | `specialty_explosivedamage` | PERKS_SONIC_BOOM | Sonic Boom |  |
| 3 | `specialty_longersprint` | PERKS_EXTREME_CONDITIONING | Extreme Conditioning |  |
| 3 | `specialty_bulletaccuracy` | PERKS_STEADY_AIM | Steady Aim |  |
| 3 | `specialty_pistoldeath` | PERKS_LAST_STAND | Last Stand |  |
| 3 | `specialty_grenadepulldeath` | PERKS_MARTYRDOM | Martyrdom |  |
| 3 | `specialty_bulletpenetration` | PERKS_DEEP_IMPACT | Deep Impact |  |
| 3 | `specialty_holdbreath` | PERKS_IRON_LUNGS | Iron Lungs |  |
| 3 | `specialty_quieter` | PERKS_DEAD_SILENCE | Dead Silence |  |
| 3 | `specialty_parabolic` | PERKS_EAVESDROP | Eavesdrop |  |

### 3.4 Safe giving

- **Through a loadout**: `loadoutPerks[0..2]` (index = MW2 slot - 1). This is validated by the
  class code, so a wrong slot is dropped. Use it when the class choice is normal.
- **After spawn**: `maps\mp\_utility::giveperk("specialty_x", 0)` sets `self.perks[ref]` directly and
  bypasses `validateperk` [H1-GSC/maps/mp/_utility.gsc:2078-2085]. This is how AON gives its three
  slot-1 perks and how the HMW deathstreak code grants perks
  [data/mwx/maps/mp/gametypes/aon.gsc:182-189].
- **Reading**: `self maps\mp\_utility::_hasperk("specialty_x")`
  [H1-GSC/maps/mp/_utility.gsc:2070-2076]; `self.perks[ref]` is the raw array
  [H1-GSC/maps/mp/_utility.gsc:2083, 2115-2125].
- **Global switch**: `scr_game_perks 0` makes `validateperk` return `specialty_null` for everything
  [HMW-GSC/maps/mp/perks/_perks.gsc:212-214]. `_utility::init` sets it to 1
  [H1-GSC/maps/mp/_utility.gsc:3743]; a mode that wants no perks must set it explicitly.
- `getemptyperks()` returns three `specialty_null` entries
  [HMW-GSC/maps/mp/perks/_perks.gsc:271-279] - use it for `loadoutPerks` instead of a hand-built
  array.

## 4. Gamemode loadouts

A fixed-loadout mode uses four pieces:

1. **`getemptyloadout()`** - a complete, valid loadout with safe defaults (AK primary, no secondary,
   no equipment, empty perks) [H1-GSC/maps/mp/gametypes/_class.gsc:171-188]. HMW does not replace
   it, so the keys are the H1 ones:
   `loadoutPrimary`, `loadoutPrimaryAttachKit`, `loadoutPrimaryFurnitureKit`, `loadoutPrimaryCamo`,
   `loadoutPrimaryReticle`, `loadoutSecondary*`, `loadoutEquipment`, `loadoutOffhand`,
   `loadoutPerks`, `loadoutMelee`.
2. **`pers["gamemodeLoadout"]`** - the loadout the class code reads when
   `getloadout("gamemode", ...)` runs [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:496-519].
   Set it in the mode's class bypass *and* again on every spawn, so a late joiner or a respawn never
   uses a stale/undefined loadout [data/mwx/maps/mp/gametypes/oic.gsc:149-163].
3. **`level.bypassclasschoicefunc`** - replaces the class menu; the engine calls it when the player
   would choose a class [H1-GSC/maps/mp/gametypes/_menus.gsc:504-505]. It must set
   `self.pers["class"]`, `self.pers["lastClass"]`, `self.pers["gamemodeLoadout"]`, `self.class` and
   `self.lastclass` (OIC does) [data/mwx/maps/mp/gametypes/oic.gsc:149-157]. Hodgepodge sets it to
   `::mmclass` [H1-GSC/maps/mp/gametypes/_hodgepodge.gsc:80]; gun game and RPG-only do the same
   [H1-GSC/maps/mp/gametypes/gun.gsc:43, _hodgepodge.gsc:735].
4. **`gametypesTable` column 5** - "class choice allowed". A fixed-loadout mode sets it to 0 so the
   UI does not offer a class menu. MWX writes that column for mod gametypes from `class_choice`
   [src/client/component/gamemodes.cpp:45-51, 296-306]; the H1 dump shows the values (dm/war/sd/dom
   = 1, gun/infect = 0) [refs/h1_dump/h1_dump/mp/gametypestable.csv].

`loadoutPrimary`/`loadoutSecondary` are **refs**; the class code builds the asset names and gives
them (2.1). `loadoutEquipment` is a lethal, `loadoutOffhand` a tactical (2.3).

## 5. Spawn and loadout timing

Order in an H1/HMW spawn [H1-GSC/maps/mp/gametypes/_playerlogic.gsc:770-831]:

1. gametype `onspawnplayer()` - set `pers["gamemodeLoadout"]` here (OIC
   [data/mwx/maps/mp/gametypes/oic.gsc:159-163]).
2. `_class::applyloadout()` - takes all weapons, applies perks, gives primary/secondary/equipment/
   offhand [HMW-GSC/scripts/mp_patches/custom_weapons.gsc:31-260].
3. `waittillframeend` [H1-GSC/maps/mp/gametypes/_playerlogic.gsc:818].
4. `self notify("spawned_player")` [H1-GSC/maps/mp/gametypes/_playerlogic.gsc:820].

HMW's `applyloadout` notifies **`"applyloadout"` (lower case)** at the end
[HMW-GSC/scripts/mp_patches/custom_weapons.gsc:259]; H1's original notifies **`"applyLoadout"`**
[H1-GSC/maps/mp/gametypes/_class.gsc:1333]. GSC notify/waittill matching is case-insensitive in
practice - HMW's own `h2m_new.gsc` waits for `"applyLoadout"` and works
[HMW-GSC/scripts/mp/h2m_new.gsc:71] - but use the same spelling as the code you
replace to stay readable.

Rules that keep ports correct:

- **Wait for `spawned_player`, not for spawn itself**, before replacing the loadout. OIC and AON
  both do `self waittill("spawned_player")` and only then take/give weapons
  [data/mwx/maps/mp/gametypes/oic.gsc:165-187] [data/mwx/maps/mp/gametypes/aon.gsc:165-190].
  Waiting on `"applyloadout"` is the other valid hook (it fires at the end of applyloadout).
- **Late joiners**: a player who connects after `main()` still goes through the same class code; set
  `pers["gamemodeLoadout"]` in `onspawnplayer` (every spawn), and if you patch the class function
  do it for every `"connected"` player, not only for the players present at match start. OIC's
  class bypass is called per player, and its spawn handler reassigns the loadout every time
  [data/mwx/maps/mp/gametypes/oic.gsc:149-163].
- **`waittillframeend`** is the usual guard after a notify when you must not run inside the notify
  call stack; HMW's `h2m_new` and our Slasher bot-fire loop use it
  [HMW-GSC/scripts/mp/h2m_new.gsc:51-62]
  [data/mwx/scripts/mp/mwx_hodgepodge.gsc:86-92].
- **Bots**: HMW's hodgepodge turns bot firing off in `onmmspawnplayer`; our fix calls
  `allowfire(1)` per spawn and records `mwx_botfire` because GSC has no getter
  [H1-GSC/maps/mp/gametypes/_hodgepodge.gsc:175]
  [data/mwx/scripts/mp/mwx_hodgepodge.gsc:72-94].

## 6. Gotchas

- **Viewhands are per faction and must be set with `setviewmodel`.** HMW's `custom_teams.gsc` sets
  e.g. `viewhands_tf141`, `viewhands_h1_arab_desert_mp_camo`, `globalViewhands_mw2_airborne`,
  `viewhands_rangers`, `viewhands_udt`, `globalViewhands_mw2_militia`, `viewhands_h2_ghillie`
  [HMW-GSC/scripts/mp_patches/custom_teams.gsc:61-263]. A new faction without a viewmodel row gives
  default/first-person-arm errors.
- **`_gamescore` lives in `_gamescores.gsc`.** H1/HMW calls use
  `maps\mp\gametypes\_gamescore::...` but the dump/file is `_gamescores.gsc`; the GSC check accepts
  both spellings [tools/gsc-check/check-all.ps1:8, 42-44]. `updatescorestatsffa` and
  `gethighestscoringplayer` are there
  [H1-GSC/maps/mp/gametypes/_gamescores.gsc:7, 52].
- **`level.mine_explode` is not a GSC variable you can rely on in a port.** HMW's own
  `_weapons::mineexplode` plays `level.mine_explode` [HMW-GSC/maps/mp/gametypes/_weapons.gsc:3336],
  but no GSC file assigns it; it comes from the zone/map asset set. Ported content that has no such
  level field must `loadfx("vfx/...")` into its own variable (the AW port does exactly this for its
  map effects) [_migration/archive/mwx-debug/aw-port/gsc-original/maps/mp/mp_greenband_fx.gsc:3-22]. **Unverified**
  which HMW zones define `level.mine_explode`; the safe pattern for new content is `loadfx`.
- **`dodamage` needs the 6-argument form when the kill must be credited.** The attacker is the
  third argument: `dodamage(damage, point, attacker, inflictor, mod, weapon)`. The 2-argument form
  credits the world (suicide), which is only correct for a suicide test
  [data/mwx/tests/_test.gsc:148-155] [data/mwx/tests/sas.gsc:116-117].
- **Bots need `botsetflag("encourage_grenade_use", 1)`** to throw their offhand (AON's throwing
  knife) [data/mwx/maps/mp/gametypes/aon.gsc:186-189].
- **`allowfire(1)`** is needed in hodgepodge/Slasher modes for survivor bots; stock code calls
  `allowfire(0)` for every bot on spawn [H1-GSC/maps/mp/gametypes/_hodgepodge.gsc:175]
  [data/mwx/scripts/mp/mwx_hodgepodge.gsc:72-94].
- **Hodgepodge is `war.gsc` + `scr_game_hodgepodgeMode`.** `_gamelogic::init` starts
  `_hodgepodge::init` [H1-GSC/maps/mp/gametypes/_gamelogic.gsc:1779], which maps mode 2 = Slasher,
  6/7 = RPG only (reload on/off), 9 = Prop Hunt, 4 = Snipers Only (mode 4 still exists in the table
  but MWX no longer ships the extra party ref) [H1-GSC/maps/mp/gametypes/_hodgepodge.gsc:16-53].
- **Modes run twice during map load.** The gametype script is executed once in the disk-script pass
  (before `war.gsc::main()` sets `level.hodgepodgemode`) and again for real; install patches from a
  thread that waits for `level.hodgepodgemode`, not from `init()`
  [data/mwx/scripts/mp/mwx_hodgepodge.gsc:12-47]. This cost us a full Slasher test run: the stock
  code saw mode 0 and the fixes never installed.
- **numlives and grace period**: `getgametypenumlives()` and `level.ingraceperiod` gate the death
  handler. `_gamelogic` returns early while `level.ingraceperiod` is set, so a kill during the
  spawn grace period does not take a life; `level.ingraceperiod` counts down from
  `level.graceperiod` [H1-GSC/maps/mp/gametypes/_gamelogic.gsc:302-313, 486-494, 1875]. Tests must
  wait for the grace period (OIC's `wait_grace`) before killing
  [data/mwx/tests/oic.gsc:65-76, 113-116].
- **Scavenger bags** are the `h2_scavenger_bag` script model, shown only to living players with
  `specialty_scavenger`, and refilled on pickup
  [HMW-GSC/maps/mp/gametypes/_weapons.gsc:1-16, 871-945].
- **`getdvar("g_gametype")` returns the party ref since M4** (`slasher`, `rpg`, ...), not `war`.
  HMW has no addressable builtin table, so `getdvar` cannot be rewritten; the hodgepodge code keys
  off `scr_game_hodgepodgeMode`, and `level.gametype` is the ref. The Slasher test asserts exactly
  this contract [data/mwx/tests/slasher.gsc:55-60] [src/client/component/gamemodes.cpp:330-370].

## 7. Porting a mode - checklist

1. Read the source script (IW5/IW9/MW2 dump) and list every asset ref it uses: weapons, perks,
   equipment, viewhands, HUD icons, sounds, FX.
2. Resolve refs against HMW: `h2_*` for MW2 weapons, `h1_*` for MWR, `iw9_*` for the MW3 throwing
   knife. Check the weapon is in the pool (1.2) and not excluded (2.5). Remember bare ref != asset.
3. Build the loadout with `getemptyloadout()`, set only the keys you need, and put it into
   `pers["gamemodeLoadout"]` in the class bypass and on every spawn (4).
4. Set `level.bypassclasschoicefunc` and `gametypesTable` column 5 = 0 (fixed loadout) or 1
   (class choice) (4).
5. Give extra weapons after `waittill("spawned_player")`, never before `applyloadout` (5).
6. Perks: put at most one perk per MW2 slot into `loadoutPerks`, or use `giveperk` after spawn for
   wrong-slot/extra perks (3). Check `scr_game_perks` is 1.
7. Lethal/tactical: `loadoutEquipment`/`loadoutOffhand` plus `settacticalweapon`/`giveoffhand`;
   tactical insertion = `specialty_tacticalinsertion` + `flare_mp` (2.3).
8. Deaths/lives: respect `level.ingraceperiod`; use `getgametypenumlives()`; end through
   `_gamelogic::endgame(winner, reason)` and set `level.finalkillcam_winner` the way the gametype
   does (6).
9. Test hooks: `data/mwx/tests/<mode>.gsc` + `tests.json`; use the 6-arg `dodamage` for attributed
   kills and wait for `spawned_player`/grace before asserting.
10. Run `tools\gsc-check\check-all.ps1` (0 problems) and `run_test <mode>` (or
    `tools\test\run-tests.ps1 -Name <mode>`) before committing.

See also: [mods.md](../guides/mods.md) for packaging the mode as a mod, [testing.md](../guides/testing.md) for the test
harness.


