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
- `mwr_melee`: one listen-host test that gives and equips all 28 melee weapons and kills with the
  last.
- `menu-smoke`: a CAC check per category (weapons appear when `hmw_mwr_weapons 1`, not with 0).
- CAC screenshots for the review: `mwx-debug\mwr-weapons\cac-*.png`.

## Adding another stock weapon

1. Append its 68-column statstable row to `stock_weapons_data.hpp`, bump `row_count`.
2. Add a `case` to the right validator in `mwr_weapons.gsc`.
3. If its name is a `MWX_*` key, add the `localized_strings::override` in `mwr_weapons.cpp`.
4. Add a `mwr_weapon` manifest entry with its ref and class.
5. Run that test 3x, then one full suite plus menu smoke.
