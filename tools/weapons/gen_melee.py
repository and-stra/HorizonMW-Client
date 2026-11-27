# generate the melee rows - moved from _migration\archive\mwx-debug\mwr-weapons\gen_melee.py on 27 Nov 2026.
import json, csv, os, re

OUT = r'C:\Games\cod-hwm\_migration\archive\mwx-debug\mwr-weapons'
DUMP = r'C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered\mwx-logs\statstable_dump.csv'

inv = json.load(open(os.path.join(OUT, 'inventory.json'), encoding='utf-8'))
loc = json.load(open(r'C:\Games\cod-hwm\refs\h1_dump\h1_dump\localize.json', encoding='utf-8'))

# pattern: the h2_sickle row (weapon_melee with a real GUID)
pattern = None
with open(DUMP, encoding='utf-8-sig', newline='') as f:
    for row in csv.reader(f):
        if len(row) == 67 and row[4] == 'h2_sickle':
            row = row + ['']
            pattern = row
            break
assert pattern, 'melee pattern not found'
print('pattern icons:', pattern[6], 'cols', len(pattern))

# the melee_* images that exist
imgs = set()
imgdir = r'C:\Games\cod-hwm\refs\dumps\patch_common_mp\images'
for n in os.listdir(imgdir):
    if n.startswith('melee_'):
        imgs.add(n[:-8])  # strip .h1Image

def icon_for(w):
    hud = (w.get('hudIcon') or '').replace('hud_icon_', '')
    for cand in (hud, 'melee_' + hud):
        if cand in imgs:
            return cand
    # fall back by display name words
    for word in re.split(r'[^a-z0-9]+', w['display'].lower()):
        if word:
            for cand in ('melee_' + word, word):
                if cand in imgs:
                    return cand
    return 'melee_shovel'

melee = [w for w in inv if w['inventoryType'] == 6]
rows = []
for i, w in enumerate(melee):
    row = list(pattern)
    row[0] = str(6300 + i)
    row[1] = str(9800 + i)
    row[2] = 'weapon_melee'
    row[3] = 'MWX_MWR_' + w['ref'][:-3].upper()
    row[4] = w['ref'][:-3]  # strip _mp
    row[6] = icon_for(w)
    row[7] = 'PERKS_MELEE_RANGE'
    # no attachments, no unlock GUID (like the crossbow row)
    for c in range(10, 49):
        row[c] = ''
    row[49] = '-1'
    rows.append(row)

def cpp(row):
    return '\t\t{ ' + ', '.join('"' + c + '"' for c in row) + ' },'

with open(os.path.join(OUT, 'melee_rows.txt'), 'w', encoding='utf-8', newline='\n') as f:
    for row in rows:
        f.write(cpp(row) + '\n')

# localized string overrides
with open(os.path.join(OUT, 'melee_strings.txt'), 'w', encoding='utf-8', newline='\n') as f:
    for w in melee:
        name = w['display'].replace('\\', '\\\\').replace('"', '\\"')
        token = 'MWX_MWR_' + w['ref'][:-3].upper()
        f.write(f'\t\t\tlocalized_strings::override("{token}", "{name}");\n')

print('rows', len(rows))
for r in rows[:5]:
    print(r[0], r[3], r[4], r[6])
