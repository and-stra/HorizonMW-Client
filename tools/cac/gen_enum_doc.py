# generate docs/features/cac.md - moved from _migration\archive\mwx-debug\cac-bisect\gen_enum_doc.py on 27 Nov 2026.
import json
import re

rows = open(r"C:\Games\cod-hwm\cod-mwx\src\client\component\stock_weapons_data.hpp",
            encoding="utf-8", errors="ignore").read()
refs = re.findall(r'\{ "[^"]*", "[^"]*", "[^"]*", "[^"]*", "([^"]+)"', rows)
base = json.load(open(r"C:\Games\cod-hwm\_migration\archive\mwx-debug\cac-bisect\enum\base.json", encoding="utf-8-sig"))["members"]
doc = json.load(open(r"C:\Games\cod-hwm\_migration\archive\mwx-debug\cac-bisect\enum\run1.json", encoding="utf-8-sig"))["members"]
added = set(doc) - set(base)
pairs = sorted((i, m) for i, m in enumerate(doc) if m in refs and m in added)
present = sorted(m for m in refs if m in base)

head = """# Create-a-Class weapon enum (playerdata DDL `Weapon`)

The class slot `customClasses/<n>/weaponSetups/<0|1>/weapon` is an **8 bit index** into the
playerdata `Weapon` enum. A name that is not a member makes `Engine.SetPlayerData` return false,
so the pick silently does nothing. `src/client/component/ddl_weapon_enum.cpp` extends the enum
once per client, at the first lobby.

- 228 members ship with HMW. **51 of them repeat a name that already has an earlier index**
  (`none` x3, `camo016`..`camo062` x2, ...). A repeated index is unreachable through the name
  hash (lookup resolves to the first occurrence), so it is a free slot; it carries one of the
  ported names.
- The remaining ported names are **appended** at indices 228..244. The field is 8 bit, so the
  hard ceiling is **256 members** (11 free after this set).
- The enum hash table is a compact array of `count` entries **sorted by hash**; the hash is a
  lowercase x31 hash (`h = h*31 + tolower(c)`, start 0) and lookup is a binary search. New
  entries are inserted in sorted position. (An open-addressing insert with `hash % max` breaks
  every name lookup in the enum - do not touch the table without the binary-search layout.)
- `mwx_cac_enum` (default 1) switches the extension off; `rpc ddl_dump` shows the table,
  `rpc ddl_extend` runs it once and reports.

Verified 27 Nov 2026: 245 members, 51 reused + 17 appended, 0 skipped; 270/270
`mp/customweapons.csv` refs storable (`Engine.SetPlayerData` true); the table is byte-identical
on 3 cold starts and on 2 concurrent clients (`mwx-debug/cac-bisect/enum/run1..5.json`, sha1
`1ecf60a70327...`); no class field outside the two weapon slots holds a ported name
(camo/reticle/perk/equipment, 20 slots, 0 hits).

Already members before the extension (no slot needed): __PRESENT__.

| index | weapon ref | slot |
|---|---|---|
""".replace("__PRESENT__", ", ".join("`%s`" % m for m in present))

lines = [head.rstrip("\n")]
for i, m in pairs:
    lines.append("| %d | %s | %s |" % (i, m, "reused duplicate index" if i < 228 else "appended"))
lines.append("")
lines.append("The mapping is identical on every client of the same build; a class saved with a ported")
lines.append("weapon is not readable by an older client. Re-check this table in the release-prep content check.")
lines.append("")

open(r"C:\Games\cod-hwm\cod-mwx\docs/features/cac.md", "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("added rows:", len(pairs), "| present:", len(present))

