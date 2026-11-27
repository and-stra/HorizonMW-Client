# parse HMW statstable rows - moved from _migration\archive\mwx-debug\mwr-weapons\parse_hmw_rows.py on 27 Nov 2026.
import re, json
p=r'C:\Games\cod-hwm\cod-mwx\src\client\component\stock_weapons_data.hpp'
rows=[]
for line in open(p,encoding='utf-8'):
    m=re.match(r'\s*\{\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)"', line)
    if m:
        rows.append(dict(id=m.group(1),sort=m.group(2),cls=m.group(3),name=m.group(4),ref=m.group(5)))
print(len(rows))
for r in rows[:5]: print(r)
json.dump(rows, open(r'C:\Games\cod-hwm\_migration\archive\mwx-debug\mwr-weapons\hmw_rows.json','w'), indent=1)
