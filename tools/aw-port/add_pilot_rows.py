# add the pilot statstable rows - moved from _migration\archive\mwx-debug\aw-weapons\add_pilot_rows.py on 27 Nov 2026.
#!/usr/bin/env python3
"""Add the AW pilot statstable rows (M1 Garand, MP40) to stock_weapons_data.hpp.

The rows are cloned from the closest MWR weapon (M14 for the M1 Garand, MP44 for the MP40) with a
new id/unlock id, the AW weapon ref, and a WEAPON_AW_* name key (localized in aw_weapons.cpp).
"""
import re
import sys

PATH = r"C:\Games\cod-hwm\cod-mwx\src\client\component\stock_weapons_data.hpp"

PILOTS = [
    # ref, donor ref, name key, new id, new unlock id
    ("iw5_dlcgun23", "h1_m14", "WEAPON_AW_M1GARAND", "6200", "10001"),
    ("iw5_dlcgun18", "h1_mp44", "WEAPON_AW_MP40", "6201", "10002"),
    ("iw5_combatknife", "h1_meleebayonet", "WEAPON_AW_COMBATKNIFE", "6202", "10003"),
]

CELL_RE = re.compile(r'"([^"]*)"')
ROW_RE = re.compile(r'^\t\t\{ ".*" \},?\s*$')


def row_line(cells):
    return "\t\t{ " + ", ".join('"%s"' % c for c in cells) + " },"


def main():
    with open(PATH, "r", encoding="utf-8", newline="") as f:
        lines = f.read().split("\n")

    rows = {}
    for index, line in enumerate(lines):
        if ROW_RE.match(line.rstrip("\r")):
            cells = CELL_RE.findall(line)
            if len(cells) == 68:
                rows.setdefault(cells[4], (index, cells))

    new_lines = []
    insert_at = None
    for ref, donor, name_key, new_id, new_unlock in PILOTS:
        if ref in rows:
            print("row for %s already present" % ref)
            continue
        if donor not in rows:
            print("donor row %s not found" % donor)
            return 1
        index, cells = rows[donor]
        cells = list(cells)
        cells[0] = new_id
        cells[1] = new_unlock
        cells[3] = name_key
        cells[4] = ref
        new_lines.append(row_line(cells))
        insert_at = index
        print("row %s from %s (id %s)" % (ref, donor, new_id))

    if not new_lines:
        return 0

    # insert after the last donor row, before the closing "};"
    position = insert_at + 1
    while position < len(lines) and not lines[position].startswith("\t};"):
        position += 1
    lines[position:position] = new_lines

    text = "\n".join(lines)
    count = len(re.findall(r'\{\s*"[^"]*"(?:\s*,\s*"[^"]*"){67}\s*\}', text))
    text = re.sub(r"inline constexpr int row_count = \d+;",
                  "inline constexpr int row_count = %d;" % count, text)
    with open(PATH, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    print("row_count = %d" % count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
