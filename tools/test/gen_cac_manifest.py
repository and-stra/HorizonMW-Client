#!/usr/bin/env python3
"""Write the CAC test manifest (ref, class, category tab) from stock_weapons_data.hpp.

  py -3 tools/test/gen_cac_manifest.py > build/cac_manifest.json
"""
import json
import re
import sys

HEADER = r"C:\Games\cod-hwm\cod-mwx\src\client\component\stock_weapons_data.hpp"
src = open(HEADER, encoding="utf-8", errors="ignore").read()

# rows are { id, id2, class, namekey, ref, ... }
rows = re.findall(r'\{ "([^"]*)", "([^"]*)", "([^"]*)", "([^"]*)", "([^"]+)"', src)

TABS = {
    "weapon_assault": ("Primary", 0),
    "weapon_smg": ("Primary", 1),
    "weapon_sniper": ("Primary", 2),
    "weapon_heavy": ("Primary", 3),
    "weapon_secondary_machine_pistol": ("Secondary", 0),
    "weapon_secondary_shotgun": ("Secondary", 1),
    "weapon_pistol": ("Secondary", 2),
    "weapon_projectile": ("Secondary", 3),
    "weapon_melee": ("Secondary", 4),
}

out = []
for row_id, _id2, cls, namekey, ref in rows:
    if cls not in TABS:
        continue
    cat, tab = TABS[cls]
    out.append({"ref": ref, "class": cls, "name": namekey, "cat": cat, "tab": tab,
                "slot": "melee" if cls == "weapon_melee" else ("0" if cat == "Primary" else "1")})

json.dump(out, sys.stdout, indent=1)
