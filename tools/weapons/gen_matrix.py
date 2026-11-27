# generate the CAC weapon test matrix - moved from _migration\archive\mwx-debug\mwr-weapons\gen_matrix.py on 27 Nov 2026.
import json, re, os

ROOT = r'C:\Games\cod-hwm\_migration\archive\mwx-debug\mwr-weapons'
HDR = r'C:\Games\cod-hwm\cod-mwx\src\client\component\stock_weapons_data.hpp'
inv = {w['ref'][:-3]: w for w in json.load(open(os.path.join(ROOT, 'inventory.json'), encoding='utf-8'))}

# statstable rows: ref -> attachment names (columns 11..25)
rows = {}
for line in open(HDR, encoding='utf-8'):
    m = re.match(r'\s*\{\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)"(.*)', line)
    if not m:
        continue
    cells = re.findall(r'"([^"]*)"', line)
    if len(cells) < 40:
        continue
    rows[cells[4]] = {
        'class': cells[2], 'name': cells[3], 'att': [c for c in cells[11:26] if c],
    }

lines = ['# MWR weapons - attachment matrix', '',
         'The attachment names HMW offers for the h1_ weapons are the MWR attachment **assets**',
         '(`acogmwr`, `reflexmwr`, `silencermwr`, `gripmwr`, `longbarrelmwr`, `xmagmwr`, ...), taken from',
         "each weapon's own `attachments` list in `patch_common_mp`. `h2_buildweaponname()` appends",
         '`_<name>`; the engine resolves the variant from the base weapon def and that attachment asset.',
         'A CAC row only lists attachments the weapon actually has.', '',
         '| ref | name | class | CAC attachments (statstable row) | dump attachments (existing) |',
         '|---|---|---|---|---|']
for ref in sorted(rows):
    w = inv.get(ref)
    cls = rows[ref]['class'].replace('weapon_', '')
    cac = ', '.join(rows[ref]['att']) or '-'
    dump = '-'
    if w:
        dump = ', '.join(a['name'] for a in w['attachments'] if a['exists']) or '-'
    lines.append(f"| `{ref}` | {rows[ref]['name']} | {cls} | {cac} | {dump} |")

lines += ['', '## Missing attachment assets in the dump', '',
          'The dump only contains the weapon-specific variants that the patch zone actually shipped.',
          'Generic assets (`acogmwr`, `reflexmwr`, `thermalmwr`, `holosightmwr`) are shared and were',
          'dumped once; per-weapon variants (`acogmwrxmlar`) exist only where the zone names them.',
          'The runtime check (D0) decides whether a name resolves; the CAC row lists only names from',
          'the weapon def, so a missing dump file does not mean a missing runtime asset.']

open(os.path.join(ROOT, 'attachments-matrix.md'), 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
print('rows', len(rows))
