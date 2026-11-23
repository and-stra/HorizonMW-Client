#!/usr/bin/env python3
"""Convert an Advanced Warfare (S1) weapon JSON to the H1 (MWR) zonetool weapon format.

x64-zt cannot dump S1 weapons for the H1 target (its H1 weapon dumper is commented out). Its H2 target writes
nearly the same layout as H1, but the H1 parser still rejects a series of fields. This script does the
remaining conversion in one step (it merges the overnight repair scripts pad-weapon*.py):

  * szXAnims / szXAnimsRightHanded / szXAnimsLeftHanded: all 190 anim keys, missing ones as ""
  * notetrackSoundMap: 36 {Key, Value}; notetrackRumbleMap / notetrackFXMap / notetrackHideTag: 16 entries built
    from S1's parallel *Keys / *Values / *TagValues arrays
  * bounceSound / rollingSound: arrays of 53 surface sounds (S1 has a single string or nothing)
  * the bool fields: S1 writes 0/1, H1 wants true/false
  * fixed-size string arrays (hideTags 32, reticleViewModels 64, gunModel/worldModel 2, turret spin sounds 4)
  * null fields inside animOverrides / reloadOverrides / notetrackOverrides
  * attachments: only the ones named with --attachment are kept (each kept one must be converted and built too)
  * handModel: "viewmodel_base_viewhands". The game needs a hands model on the weapon: the gun hangs on the hands'
    weapon bone, and the player's faction arms (setviewmodel) are drawn in its place. Empty = no arms and the gun
    floats at the viewmodel origin (too big / too close). The zone CSV must list it as a REFERENCE
    ("xmodel,,viewmodel_base_viewhands" before the weapon), so MWR's model is used: AW's model of the same name
    are the exo arms and would replace MWR's for every weapon. --hands <xmodel> sets a different one.
  * exo-only anim slots (boost jump/slam, dodge, slide and sprint fire, exo punch, boost landing) are cleared: MWR
    has no exo movement, so they would only be built into the zone for nothing (--keep-exo keeps them)

Usage: s1_weapon_to_h1.py <input.json> <output.json> [--attachment <name> ...] [--hands <xmodel>]
Crossbow: --attachment crossbowscopebase (its built-in scope; the optics attachments are not needed)
"""

import argparse
import json
import sys

ANIM_NAMES = """ROOT IDLE EMPTY_IDLE FIRE HOLD_FIRE LASTSHOT RECHAMBER GRENADE_PRIME GRENADE_PRIME_READY_TO_THROW
MELEE_SWIPE MELEE_HIT MELEE_FATAL MELEE_MISS MELEE_VICTIM_CROUCHING_HIT MELEE_VICTIM_CROUCHING_FATAL
MELEE_VICTIM_CROUCHING_MISS MELEE_ALT_STANDING MELEE_ALT_CROUCHING MELEE_ALT_PRONE MELEE_ALT_JUMPING
MELEE_ALT_STANDING_VICTIM_CROUCHING MELEE_ALT_CROUCHING_VICTIM_CROUCHING MELEE_ALT_PRONE_VICTIM_CROUCHING
MELEE_ALT_JUMPING_VICTIM_CROUCHING RELOAD RELOAD_EMPTY RELOAD_START RELOAD_END FAST_RELOAD FAST_RELOAD_EMPTY
FAST_RELOAD_START FAST_RELOAD_END DUALMAG_RELOAD DUALMAG_RELOAD_EMPTY SPEED_RELOAD RELOAD_FROM_ALT RAISE
FIRST_RAISE BREACH_RAISE DROP ALT_RAISE ALT_DROP ALT_OVERRIDE QUICK_RAISE QUICK_DROP EMPTY_RAISE EMPTY_DROP
HYBRID_SIGHT_ON HYBRID_SIGHT_OFF SPRINT_IN SPRINT_IN_FROM_SLIDE SPRINT_IN_CANCEL SPRINT_LOOP SPRINT_OUT
SPRINTANDFIRE_IN SPRINTANDFIRE_LOOP SPRINTANDFIRE_OUT STUNNED_START STUNNED_LOOP STUNNED_END THROWBACK
DETONATE NIGHTVISION_WEAR NIGHTVISION_REMOVE ADS_FIRE ADS_LASTSHOT ADS_RECHAMBER BLAST_FRONT BLAST_RIGHT
BLAST_BACK BLAST_LEFT SLIDE_IN SLIDE_LOOP SLIDE_OUT_TO_SPRINT SLIDE_OUT SLIDE_AND_FIRE_IN SLIDE_AND_FIRE_LOOP
SLIDE_AND_FIRE_OUT HIGH_JUMP_IN HIGH_JUMP_DROP_IN HIGH_JUMP_DROP_LOOP HIGH_JUMP_DROP_LAND DODGE_GROUND_BACK
DODGE_GROUND_LEFT DODGE_GROUND_RIGHT DODGE_AIR_FORWARD DODGE_AIR_BACK DODGE_AIR_LEFT DODGE_AIR_RIGHT LAND_DIP
RECOIL_SETTLE SWIM_LOOP MANTLE_UP_64 MANTLE_UP_56 MANTLE_UP_48 MANTLE_UP_40 MANTLE_UP_32 MANTLE_UP_24
MANTLE_UP_16 MANTLE_OVER_64 MANTLE_OVER_56 MANTLE_OVER_48 MANTLE_OVER_40 MANTLE_OVER_32 MANTLE_OVER_24
MANTLE_OVER_16 GOLIATH_ENTRY OFFHAND_SWITCH HEAT_COOLDOWN_IN HEAT_COOLDOWN_OUT OVERHEAT_OUT SCRIPTED
INSPECTION RELOAD_MULTIPLE_1 RELOAD_MULTIPLE_2 RELOAD_MULTIPLE_3 RELOAD_MULTIPLE_4 RELOAD_MULTIPLE_5
RELOAD_MULTIPLE_6 RELOAD_MULTIPLE_7 RELOAD_MULTIPLE_8 RELOAD_MULTIPLE_FAST_1 RELOAD_MULTIPLE_FAST_2
RELOAD_MULTIPLE_FAST_3 RELOAD_MULTIPLE_FAST_4 RELOAD_MULTIPLE_FAST_5 RELOAD_MULTIPLE_FAST_6
RELOAD_MULTIPLE_FAST_7 RELOAD_MULTIPLE_FAST_8 ADS_UP ADS_DOWN RECOIL WEAP_ALT_ANIM_ADJUST ADDITIVE_ADS_ROOT
ADDITIVE_ADS_UP ADDITIVE_HYBRID_SIGHT_UP_ROOT ADDITIVE_HYBRID_SIGHT_UP ADDITIVE_DRAG_LEFT_ROOT
ADDITIVE_DRAG_LEFT ADDITIVE_DRAG_RIGHT_ROOT ADDITIVE_DRAG_RIGHT ADDITIVE_DRAG_UP_ROOT ADDITIVE_DRAG_UP
ADDITIVE_DRAG_DOWN_ROOT ADDITIVE_DRAG_DOWN ADDITIVE_SWIM_FORWARD_ROOT ADDITIVE_SWIM_FORWARD
ADDITIVE_SWIM_BACKWARD_ROOT ADDITIVE_SWIM_BACKWARD ADDITIVE_JUMP_ROOT ADDITIVE_JUMP ADDITIVE_JUMP_BOOST
ADDITIVE_JUMP_LAND_ROOT ADDITIVE_JUMP_LAND ADDITIVE_JUMP_LAND_HEAVY ADDITIVE_WALK_ROOT ADDITIVE_WALK
ADDITIVE_HEAT_COOLDOWN_LOOP_ROOT ADDITIVE_HEAT_COOLDOWN_LOOP ADDITIVE_OVERHEAT_IN_ROOT ADDITIVE_OVERHEAT_IN
ADDITIVE_OVERHEAT_LOOP_ROOT ADDITIVE_OVERHEAT_LOOP ADDITIVE_CRAWL_IN_ROOT ADDITIVE_CRAWL_IN
ADDITIVE_CRAWL_LOOP_ROOT ADDITIVE_CRAWL_LOOP ADDITIVE_CRAWL_LOOP_BACK_ROOT ADDITIVE_CRAWL_LOOP_BACK
ADDITIVE_CRAWL_LOOP_LEFT_ROOT ADDITIVE_CRAWL_LOOP_LEFT ADDITIVE_CRAWL_LOOP_RIGHT_ROOT ADDITIVE_CRAWL_LOOP_RIGHT
ADDITIVE_PRONE_DROP_ROOT ADDITIVE_PRONE_DROP ADDITIVE_EMPTY_ROOT ADDITIVE_EMPTY ADDITIVE_MANTLE_ROOT
ADDITIVE_MANTLE ADDITIVE_LOW_MANTLE_ROOT ADDITIVE_MANTLE_UP_24 ADDITIVE_MANTLE_UP_16
ADDITIVE_MANTLE_OVER_24 ADDITIVE_MANTLE_OVER_16 ADDITIVE_SHOT_CHARGE_IN_ROOT ADDITIVE_SHOT_CHARGE_IN
ADDITIVE_SHOT_CHARGE_LOOP_ROOT ADDITIVE_SHOT_CHARGE_LOOP ADDITIVE_SCRIPTED_ROOT ADDITIVE_SCRIPTED""".split()

BOOL_FIELDS = """bHoldFullPrime adsShouldShowCrosshair adsCrosshairShouldScale turretADSEnabled knifeAttachTagLeft
knifeAlwaysAttached meleeOverrideValues riotShieldEnableDamage allowPrimaryWeaponPickup sharedAmmo lockonSupported
requireLockonToFire isAirburstWeapon bigExplosion noAdsWhenMagEmpty avoidDropCleanup inheritsPerks
crosshairColorChange rifleBullet armorPiercing boltAction aimDownSight canHoldBreath meleeOnly quickMelee bU_086
canVariableZoom rechamberWhileAds bulletExplosiveDamage cookOffHold useBattery reticleSpin45 clipOnly noAmmoPickup
disableSwitchToWhenEmpty suppressAmmoReserveDisplay motionTracker markableViewmodel noDualWield flipKillIcon
actionSlotShowAmmo noPartialReload segmentedReload multipleReload blocksProne silenced isRollingGrenade
projExplosionEffectForceNormalUp projExplosionEffectInheritParentDirection projImpactExplode projTrajectoryEvents
projWhizByEnabled stickToPlayers stickToVehicles stickToTurrets thrownSideways hasDetonatorEmptyThrow
hasDetonatorDoubleTap disableFiring timedDetonation noCrumpleMissile fuseLitAfterImpact rotate holdButtonToThrow
freezeMovementWhenFiring thermalScope thermalToggle outlineEnemies altModeSameWeapon turretBarrelSpinEnabled
missileConeSoundEnabled missileConeSoundPitchshiftEnabled missileConeSoundCrossfadeEnabled offhandHoldIsCancelable
doNotAllowAttachmentsToOverrideSpread useFastReloadAnims dualMagReloadSupported reloadStopsAlt useScopeDrift
alwaysShatterGlassOnImpact oldWeapon raiseToHold notifyOnPlayerImpact decreasingKick counterSilencer
projSuppressedByEMP projDisabledByEMP autosimDisableVariableRate projPlayTrailEffectForOwnerOnly
projPlayBeaconEffectForOwnerOnly projKillTrailEffectOnDeath projKillBeaconEffectOnDeath reticleDetonateHide cloaked
adsHideWeapon adsHideHands bU_108 adsSceneBlur usesSniperScope hasTransientModels signatureAmmoAlternate
useScriptCallbackForHit useBulletTagSystem hideBulletTags""".split()

STRING_ARRAYS = {
    "hideTags": 32,
    "reticleViewModels": 64,
    "gunModel": 2,
    "worldModel": 2,
    "turretBarrelSpinUpSnd": 4,
    "turretBarrelSpinDownSnd": 4,
}

SURFACE_SOUND_COUNT = 53
NOTETRACK_SOUND_COUNT = 36
NOTETRACK_MAP_COUNT = 16


def text(value):
    return value if isinstance(value, str) else ""


def as_list(value):
    return value if isinstance(value, list) else []


def string_array(value, count):
    values = [text(v) for v in as_list(value)]
    values += [""] * max(0, count - len(values))
    return values[:max(count, len(values))]


def anim_table(value):
    table = value if isinstance(value, dict) else {}
    for name in ANIM_NAMES:
        if table.get(name) is None:
            table[name] = ""
    return table


def sound_map(value, keys=None, values=None):
    """{Key, Value} x 36. S1 stores the weapon's map as parallel notetrackSoundMapKeys / ...Values arrays."""
    entries = []
    if keys:
        values = values or []
        for i, key in enumerate(keys):
            entries.append({"Key": text(key), "Value": text(values[i]) if i < len(values) else ""})
    for entry in as_list(value):
        entry = entry if isinstance(entry, dict) else {}
        entries.append({"Key": text(entry.get("Key")), "Value": text(entry.get("Value"))})
    entries += [{"Key": "", "Value": ""}] * max(0, NOTETRACK_SOUND_COUNT - len(entries))
    return entries[:NOTETRACK_SOUND_COUNT]


def parallel_map(weapon, name, with_tag=False, bool_value=False):
    """S1 keeps <name>Keys / <name>Values (/ <name>TagValues) as parallel arrays; H1 wants {Key, Value(, Tag)}."""
    existing = weapon.get(name)
    if isinstance(existing, list) and existing and isinstance(existing[0], dict):
        keys = [e.get("Key") for e in existing]
        values = [e.get("Value") for e in existing]
        tags = [e.get("Tag") for e in existing]
    else:
        keys = as_list(weapon.get(name + "Keys"))
        values = as_list(weapon.get(name + "Values"))
        tags = as_list(weapon.get(name + "TagValues"))

    entries = []
    for i in range(NOTETRACK_MAP_COUNT):
        entry = {"Key": text(keys[i]) if i < len(keys) else ""}
        if bool_value:
            value = values[i] if i < len(values) else False
            entry["Value"] = bool(value) if not isinstance(value, str) else value.lower() in ("1", "true")
        else:
            entry["Value"] = text(values[i]) if i < len(values) else ""
        if with_tag:
            entry["Tag"] = text(tags[i]) if i < len(tags) else ""
        entries.append(entry)
    return entries


def surface_sounds(value):
    sounds = [""] * SURFACE_SOUND_COUNT
    if isinstance(value, str):
        sounds[0] = value
    else:
        for i, sound in enumerate(as_list(value)[:SURFACE_SOUND_COUNT]):
            sounds[i] = text(sound)
    return sounds


def fix_overrides(weapon):
    for override in as_list(weapon.get("animOverrides")):
        if not isinstance(override, dict):
            continue
        for key in ("altmodeAnim", "overrideAnim"):
            if override.get(key) is None:
                override[key] = ""
        for key in ("attachment1", "attachment2", "altTime", "animTime", "animTreeType", "animHand"):
            if override.get(key) is None:
                override[key] = 0

    for override in as_list(weapon.get("reloadOverrides")):
        if not isinstance(override, dict):
            continue
        for key in ("attachment", "reloadAddTime", "reloadEmptyAddTime", "reloadStartAddTime"):
            if override.get(key) is None:
                override[key] = 0

    for override in as_list(weapon.get("notetrackOverrides")):
        if not isinstance(override, dict):
            continue
        if override.get("attachment") is None:
            override["attachment"] = 0
        for key in list(override.keys()):
            if key.lower().startswith("notetrack") and isinstance(override[key], list):
                override[key] = sound_map(override[key])


EXO_ANIM_PREFIXES = ("HIGH_JUMP_", "DODGE_", "SLIDE_", "SPRINTANDFIRE_", "MELEE_ALT_", "LAND_DIP", "SPRINT_IN_FROM_SLIDE")


def convert(weapon, attachments=(), hands=None, keep_exo=False):
    cleared = 0
    for name in ("szXAnimsRightHanded", "szXAnimsLeftHanded", "szXAnims"):
        table = anim_table(weapon.get(name))
        if not keep_exo:
            for key in table:
                if key.startswith(EXO_ANIM_PREFIXES) and table[key]:
                    table[key] = ""
                    cleared += 1
        weapon[name] = table
    if cleared:
        print("cleared %d exo-only anim slots" % cleared)

    # keep the reload/charge sounds: built from the parallel arrays, never by padding those arrays themselves
    weapon["notetrackSoundMap"] = sound_map(weapon.get("notetrackSoundMap"),
        as_list(weapon.pop("notetrackSoundMapKeys", None)), as_list(weapon.pop("notetrackSoundMapValues", None)))
    weapon["notetrackRumbleMap"] = parallel_map(weapon, "notetrackRumbleMap")
    weapon["notetrackFXMap"] = parallel_map(weapon, "notetrackFXMap", with_tag=True)
    weapon["notetrackHideTag"] = parallel_map(weapon, "notetrackHideTag", with_tag=True, bool_value=True)
    for name in ("notetrackRumbleMap", "notetrackFXMap", "notetrackHideTag"):
        for suffix in ("Keys", "Values", "TagValues"):
            weapon.pop(name + suffix, None)

    for name in ("bounceSound", "rollingSound"):
        weapon[name] = surface_sounds(weapon.get(name))

    for name, count in STRING_ARRAYS.items():
        weapon[name] = string_array(weapon.get(name), count)

    converted = 0
    for name in BOOL_FIELDS:
        value = weapon.get(name)
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            weapon[name] = bool(value)
            converted += 1

    fix_overrides(weapon)

    source = [a for a in as_list(weapon.get("attachments")) if isinstance(a, str)]
    weapon["attachments"] = [a for a in source if a in attachments]
    missing = [a for a in attachments if a not in source]
    if missing:
        print("warning: attachments not on the weapon: %s" % ", ".join(missing))

    # MWR's hands model by reference (see the header and the zone CSV)
    weapon["handModel"] = hands if hands else "viewmodel_base_viewhands"
    weapon.pop("handsModel", None)

    return converted


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("input")
    parser.add_argument("output")
    parser.add_argument("--attachment", action="append", default=[], help="attachment to keep (repeatable)")
    parser.add_argument("--keep-exo", action="store_true", help="keep the exo-only anim slots")
    parser.add_argument("--hands", default="", help="hands model on the weapon (default viewmodel_base_viewhands, MWR's)")
    args = parser.parse_args()

    with open(args.input, encoding="utf-8") as f:
        weapon = json.load(f)

    converted = convert(weapon, args.attachment, args.hands, args.keep_exo)

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(weapon, f, indent=4)

    print("converted %s: %d bool fields, attachments %s" % (
        args.input, converted, weapon["attachments"] or "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
