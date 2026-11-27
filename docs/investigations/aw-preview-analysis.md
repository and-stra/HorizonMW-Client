# Claude analysis, 27 Nov 2026 (read-only, nothing changed in the repo)

## 1. AW weapons: empty 3D preview in Create-a-Class -- root cause (high confidence)

The CAC weapon preview is not LUI; it is virtual-lobby GSC (H1 `maps/mp/_vl_cac.gsc`):

1. LUI notifies `weapon_highlighted` -> `handleweaponhighlighted` -> `setcacweapon(ref, ...)`
2. `setcacweapon` -> `buildweaponnamecac` -> `maps\mp\gametypes\_class::buildweaponname(ref, attachkit, furniturekit, camo, reticle, emblem)`
3. `streamcacweaponwait(name)` loops **forever** until `self loadweapons([name])` returns true
   (`for(;;) { if(self loadweapons(var_1)) break; waitframe(); }`), so a bad name = preview stays empty, no error.

In the virtual lobby, `buildweaponname` is HMW's replacement
(`HMW-GSC/scripts/mp_patches/custom_weapons.gsc:958`). For `iw5_*` refs its if/else chain takes the
first branch (`!h1_ && !h2_`), optionally appends an attachment, and then **falls off the end without a
return** -> undefined weapon name -> `loadweapons` never succeeds. (`h1_*` refs go through
`h2_buildweaponname` and return a valid name -> the MWR DLC weapons render.)

Our fix for this, `aw_buildweaponname` in `data/mwx/scripts/mp/aw_weapons.gsc`, is NOT active in the
virtual lobby: `script_loading.cpp` `load_gametype_script_stub` loads `scripts/mp_patches/` always, but
`scripts/mp/` only outside the virtual lobby; in the virtual lobby it loads `scripts/vlobby_patches/`
instead. So in the lobby HMW's broken builder runs. This explains why the crossbow, M1 Garand and MP40
all show name/thumbnail but an empty preview, while HMW/MWR weapons render.

Fix:
- Put the `buildweaponname` hook where the virtual lobby loads it too: a new
  `data/mwx/scripts/vlobby_patches/aw_weapons_vl.gsc` with an `init()` that does the same
  `replacefunc(maps\mp\gametypes\_class::buildweaponname, ::aw_buildweaponname)` (shared code, not a
  copy if possible; init() runs after HMW's main(), so ours wins), or move the hook to
  `scripts/mp_patches/` (runs in game AND lobby).
- Note the lobby call signature: (ref, attachkit, furniturekit, camo, reticle, emblem). HMW's version
  treats arg 2/3 as attachment1/attachment2; `aw_buildweaponname` uses attachment1 + camo only, which
  is fine for the lobby, but attachkit names (e.g. "none") must not be appended as an attachment.
Verify in the lobby (gsc_eval or a vlobby test):
  `maps\mp\gametypes\_class::buildweaponname("iw5_dlcgun23", "none", "base", 0, 0, 0)` must return
  `"iw5_dlcgun23_mp"`, and `loadweapons(["iw5_dlcgun23_mp"])` must become true.
  `maps\mp\_vl_base::vlprintln` is an empty stub; replacefunc it with a logger while debugging
  ("weapon_stream: <name>" shows the exact name the preview waits for).

## 2. Enum extension: weaponStats overflow risk (must be guarded)

- HMW forces `xblive_privatematch` false on MP (`ranked.cpp`), so matches count as ranked and
  `rankingenabled()` (`level.rankedmatch && !self.usingonlinedataoffline`) is very likely true in our
  LAN matches. Confirm `level.rankedmatch` in a match.
- Then `_persistence::incrementweaponstat(weapon, stat, n)` (HMW-GSC `_persistence.gsc:220`) writes
  `setplayerdata(ranked, "weaponStats", <weapon>, <stat>, value)` for shots, kills, hits, headShots,
  deaths, hipfirekills, timeInUse on every match end/tracking flush.
- `weaponStats` is indexed by the `Weapon` enum. Its array size was fixed when the DDL was loaded
  (old member count). Our appended indices (>= 228) are past it. Unknown whether the engine's DDL
  setter bounds-checks the index (then the write silently fails) or writes past the array (then it
  corrupts the following playerdata fields in players2).
- Safe fix regardless of the engine: `replacefunc(maps\mp\gametypes\_persistence::incrementweaponstat, ...)`
  that returns early for our custom refs (the AW and MWR refs we added to the enum), else calls HMW's
  version. Install it in scripts/mp/ (game only). Also check the LUI combat record / barracks: does
  any menu read weaponStats for every statstable weapon (would read past the array)?
- Prove it: back up players2, play a match with kills using the M1 Garand, then diff players2:
  only expected fields may change.
- The 51 reused duplicate-name indices are low risk: a write by name always resolves to the first
  index of a duplicated name, so saved data can only contain such an index if something wrote by raw
  index. Still check existing players2 once.

## 3. Zone budget reminder
Startup zone limit is 9 extra zones; 8 are used. Pilot weapons stay inside hmw_aw_weapons.ff.
