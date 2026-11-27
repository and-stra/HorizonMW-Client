# inventory the zone assets - moved from _migration\archive\mwx-debug\mwr-weapons\inventory.py on 27 Nov 2026.
import json, os, glob, re

D = r'C:\Games\cod-hwm\refs\dumps\patch_common_mp'
LOC = r'C:\Games\cod-hwm\refs\h1_dump\h1_dump\localize.json'
OUT = r'C:\Games\cod-hwm\_migration\archive\mwx-debug\mwr-weapons'

loc = json.load(open(LOC, encoding='utf-8'))

CLASS = {0: 'rifle', 1: 'smg', 2: 'lmg', 3: 'sniper', 4: 'shotgun', 5: 'melee',
         6: 'pistol', 7: 'launcher', 8: 'grenade'}

def internal(path):
    return os.path.basename(path)[:-5]

weapons = []
for path in sorted(glob.glob(os.path.join(D, 'weapons', 'h1_*_mp.json'))):
    j = json.load(open(path, encoding='utf-8'))
    name = internal(path)
    display_token = j.get('szDisplayName') or ''
    display = loc.get(display_token, display_token)
    atts = j.get('attachments') or []
    # keep only assets that exist in the dump
    att_rows = []
    for a in atts:
        p = os.path.join(D, 'attachments', a + '.json')
        att_rows.append({'name': a, 'exists': os.path.exists(p)})
    weapons.append({
        'ref': name,
        'display_token': display_token,
        'display': display,
        'class': CLASS.get(j.get('weapClass'), str(j.get('weapClass'))),
        'weapClass': j.get('weapClass'),
        'inventoryType': j.get('inventoryType'),
        'hudIcon': j.get('hudIcon'),
        'killIcon': j.get('killIcon'),
        'ammoCounterIcon': j.get('ammoCounterIcon'),
        'clipSize': j.get('clipSize'),
        'startAmmo': j.get('startAmmo'),
        'gunModel': (j.get('gunModel') or [''])[0],
        'worldModel': (j.get('worldModel') or [''])[0],
        'attachments': att_rows,
    })

os.makedirs(OUT, exist_ok=True)
json.dump(weapons, open(os.path.join(OUT, 'inventory.json'), 'w', encoding='utf-8'), indent=2)

# attachment assets that exist
atts = []
for path in sorted(glob.glob(os.path.join(D, 'attachments', '*.json'))):
    j = json.load(open(path, encoding='utf-8'))
    atts.append({'name': internal(path), 'type': j.get('type')})
json.dump(atts, open(os.path.join(OUT, 'attachments.json'), 'w', encoding='utf-8'), indent=2)

# markdown
lines = ['# MWR patch_common_mp weapon inventory', '',
         f'{len(weapons)} h1_* weapons, {len(atts)} attachment assets.', '',
         '| ref | name | class | clip/start | HUD icon | attachments |',
         '|---|---|---|---|---|---|']
for w in weapons:
    atts_txt = ', '.join(a['name'] + ('' if a['exists'] else ' (MISSING)') for a in w['attachments']) or '-'
    lines.append(f"| `{w['ref']}` | {w['display']} | {w['class']} | {w['clipSize']}/{w['startAmmo']} | "
                 f"`{w['hudIcon']}` | {atts_txt} |")

open(os.path.join(OUT, 'inventory.md'), 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
print('weapons', len(weapons), 'attachments', len(atts))
