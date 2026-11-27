#!/usr/bin/env python3
"""Replace an AW weapon's anim table with the anim set of a HMW donor weapon.

AW's S1 x64-zt does not write xanim assets for the H1 target (no .xab is produced by
dumpzone), so an AW weapon would reference anim names that do not exist in H1. Using the anim
table of the closest MWR weapon keeps idle/fire/reload/ADS/raise/drop animations working; the H1
build pulls the donor's xanims from the HMW zones as dependencies.

Usage: use_hmw_anims.py <weapon.json> <donor.json> [<out.json>]
"""
import json
import sys


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    weapon_path, donor_path = sys.argv[1], sys.argv[2]
    out_path = sys.argv[3] if len(sys.argv) > 3 else weapon_path

    with open(weapon_path, "r", encoding="utf-8") as f:
        weapon = json.load(f)
    with open(donor_path, "r", encoding="utf-8") as f:
        donor = json.load(f)

    if not isinstance(donor.get("szXAnims"), dict):
        print("donor has no szXAnims object")
        return 1

    weapon["szXAnims"] = donor["szXAnims"]
    for side in ("szXAnimsRightHanded", "szXAnimsLeftHanded"):
        if isinstance(donor.get(side), dict):
            weapon[side] = donor[side]

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(weapon, f, indent=2)
    filled = sum(1 for v in weapon["szXAnims"].values() if v)
    print("anims from %s: %i filled slots -> %s" % (donor_path, filled, out_path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
