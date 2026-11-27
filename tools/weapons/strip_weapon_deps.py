# strip weapon dependencies for a minimal zone - moved from _migration\archive\mwx-debug\mwr-weapons\strip_weapon_deps.py on 27 Nov 2026.
#!/usr/bin/env python3
"""Strip the attachment and icon references from the MWR DLC weapon JSONs.

The full HMW dependency set pulls streamed images from the >2 GB imagefile paks; loading one of
those paks hangs the map load. The weapon definitions and animations are enough for the gun to
work; the models are loaded from the per-weapon _tr zones on demand by the engine.
"""
import json
import pathlib
import sys

GAME = pathlib.Path(r"C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered")
CSV = GAME / "zone_source" / "hmw_mwr_weapons.csv"
SRC = GAME / "zonetool" / "hmw_mwr_weapons" / "weapons"

refs = []
for line in CSV.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line.startswith("weapon,"):
        refs.append(line.split(",", 1)[1].strip())

print(f"weapons: {len(refs)}")
changed = 0
for ref in refs:
    path = SRC / f"{ref}.json"
    if not path.exists():
        print(f"missing {path}")
        continue
    data = json.loads(path.read_text(encoding="utf-8"))
    backup = path.with_suffix(".json.bak-pre-strip")
    if not backup.exists():
        backup.write_bytes(path.read_bytes())

    if data.get("attachments"):
        data["attachments"] = []
    removed = []
    for key in list(data.keys()):
        if key.lower().endswith("icon") or key.lower() in ("hudicon", "ammocountericon", "killicon"):
            if data[key]:
                removed.append(key)
            if isinstance(data[key], str):
                data[key] = ""
    path.write_text(json.dumps(data, indent=4), encoding="utf-8")
    changed += 1
    if removed:
        print(f"{ref}: cleared {', '.join(removed)}")
print(f"stripped {changed} weapon files")
