# static model audit of the CAC rows - moved from _migration\archive\mwx-debug\cac-bisect\audit_models.py on 27 Nov 2026.
import json
import os
import re

MANIFEST = r"C:\Games\cod-hwm\_migration\archive\mwx-debug\cac-bisect\enum\run1.json"  # not the manifest; use the generator
REFS_HPP = r"C:\Games\cod-hwm\cod-mwx\src\client\component\stock_weapons_data.hpp"
AW_DEFS = r"C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered\zonetool\hmw_aw_weapons\weapons"
HMW_DEFS = r"C:\Games\cod-hwm\refs\dumps\patch_common_mp\weapons"
ZONE_SRC = r"C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered\zonetool"
DUMP_ROOTS = [
    r"C:\Games\cod-hwm\refs\dumps\patch_common_mp\xmodel",
    r"C:\Games\cod-hwm\refs\dumps\hmw_patch_common_mp\xmodel",
    r"C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered\dump\workbench_hmw_ar1\xmodel",
    r"C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered\dump\workbench_hmw_attachments\xmodel",
    r"C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered\dump\workbench_hmw_rangers\xmodel",
    r"C:\Games\cod-hwm\Call of Duty Advanced Warfare\dump\common_mp\xmodel",
    r"C:\Games\cod-hwm\Call of Duty Advanced Warfare\dump\weapon_models",
]

src = open(REFS_HPP, encoding="utf-8", errors="ignore").read()
refs = re.findall(r'\{ "[^"]*", "[^"]*", "[^"]*", "[^"]*", "([^"]+)"', src)

known = set()
for root in DUMP_ROOTS:
    if os.path.isdir(root):
        for dirpath, _d, files in os.walk(root):
            for f in files:
                if f.lower().endswith(".xmb"):
                    known.add(os.path.splitext(f)[0].lower())
for zone in ("hmw_aw_weapons", "hmw_mwr_weapons"):
    p = os.path.join(ZONE_SRC, zone, "xmodel")
    if os.path.isdir(p):
        for f in os.listdir(p):
            if f.lower().endswith(".xmb"):
                known.add(os.path.splitext(f)[0].lower())

def def_models(ref):
    for folder in (AW_DEFS, HMW_DEFS):
        p = os.path.join(folder, ref + "_mp.json")
        if not os.path.exists(p):
            continue
        try:
            d = json.load(open(p, encoding="utf-8", errors="replace"))
        except Exception:
            return [], "", ""
        gm = d.get("gunModel") or []
        wm = d.get("worldModel") or []
        gm = gm[0] if gm and gm[0] else ""
        wm = wm[0] if wm and wm[0] else ""
        return [m for m in (gm, wm) if m], gm, wm
    return [], "", ""

rows = []
for ref in refs:
    models, gm, wm = def_models(ref)
    if not models:
        rows.append((ref, "NO DEF", "", ""))
        continue
    missing = [m for m in models if m.lower() not in known]
    rows.append((ref, gm, wm, ",".join(missing)))

bad = [r for r in rows if r[1] == "NO DEF" or r[3]]
print("refs:", len(rows), "| with a def but a model not in the dumps:", len([r for r in rows if r[1] != "NO DEF" and r[3]]), "| no def:", len([r for r in rows if r[1] == "NO DEF"]))
for r in rows:
    if r[1] == "NO DEF" or r[3]:
        print("%-18s gun=%-30s world=%-30s missing=%s" % r)

