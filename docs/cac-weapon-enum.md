# Create-a-Class weapon enum (playerdata DDL `Weapon`)

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

Already members before the extension (no slot needed): `h1_meleeapr3`, `h1_meleehatchet`, `h1_meleeicepick`, `h1_meleeshovel`, `h1_meleesickle`, `h1_rpg`, `iw5_combatknife`.

| index | weapon ref | slot |
|---|---|---|
| 125 | h1_ak47 | reused duplicate index |
| 171 | h1_g3 | reused duplicate index |
| 172 | h1_g36c | reused duplicate index |
| 173 | h1_m14 | reused duplicate index |
| 174 | h1_m16 | reused duplicate index |
| 175 | h1_m4 | reused duplicate index |
| 176 | h1_mp44 | reused duplicate index |
| 177 | h1_ak74u | reused duplicate index |
| 178 | h1_mp5 | reused duplicate index |
| 179 | h1_p90 | reused duplicate index |
| 180 | h1_skorpion | reused duplicate index |
| 181 | h1_uzi | reused duplicate index |
| 182 | h1_m60e4 | reused duplicate index |
| 183 | h1_rpd | reused duplicate index |
| 184 | h1_saw | reused duplicate index |
| 185 | h1_m1014 | reused duplicate index |
| 186 | h1_winchester1200 | reused duplicate index |
| 187 | h1_barrett | reused duplicate index |
| 188 | h1_dragunov | reused duplicate index |
| 189 | h1_m21 | reused duplicate index |
| 190 | h1_m40a3 | reused duplicate index |
| 191 | h1_remington700 | reused duplicate index |
| 192 | h1_beretta | reused duplicate index |
| 193 | h1_colt45 | reused duplicate index |
| 194 | h1_deserteagle | reused duplicate index |
| 195 | h1_usp | reused duplicate index |
| 196 | h1_deserteagle55 | reused duplicate index |
| 197 | h1_kam12 | reused duplicate index |
| 198 | h1_xmlar | reused duplicate index |
| 199 | h1_aprast | reused duplicate index |
| 200 | h1_febsmg | reused duplicate index |
| 201 | h1_aprsmg | reused duplicate index |
| 202 | h1_feblmg | reused duplicate index |
| 203 | h1_janpst | reused duplicate index |
| 204 | h1_aprpst | reused duplicate index |
| 205 | h1_febsnp | reused duplicate index |
| 206 | h1_augast | reused duplicate index |
| 207 | h1_augsmg | reused duplicate index |
| 208 | h1_junlmg | reused duplicate index |
| 209 | h1_junsho | reused duplicate index |
| 210 | h1_junsnp | reused duplicate index |
| 211 | h1_augpst | reused duplicate index |
| 212 | h1_meleeapr1 | reused duplicate index |
| 213 | h1_meleeapr2 | reused duplicate index |
| 214 | h1_meleeapr4 | reused duplicate index |
| 215 | h1_meleeaug1 | reused duplicate index |
| 216 | h1_meleeaug2 | reused duplicate index |
| 218 | h1_meleeaug3 | reused duplicate index |
| 223 | h1_meleeaug4 | reused duplicate index |
| 225 | h1_meleebayonet | reused duplicate index |
| 227 | h1_meleeblade | reused duplicate index |
| 228 | h1_meleebottle | appended |
| 229 | h1_meleefeb1 | appended |
| 230 | h1_meleefeb2 | appended |
| 231 | h1_meleefeb3 | appended |
| 232 | h1_meleefeb4 | appended |
| 233 | h1_meleefeb5 | appended |
| 234 | h1_meleegladius | appended |
| 235 | h1_meleejun1 | appended |
| 236 | h1_meleejun2 | appended |
| 237 | h1_meleejun3 | appended |
| 238 | h1_meleejun4 | appended |
| 239 | h1_meleejun5 | appended |
| 240 | h1_meleejun6 | appended |
| 241 | h1_meleepaddle | appended |
| 242 | iw5_exocrossbow | appended |
| 243 | iw5_dlcgun23 | appended |
| 244 | iw5_dlcgun18 | appended |

The mapping is identical on every client of the same build; a class saved with a ported
weapon is not readable by an older client. Re-check this table in the release-prep content check.
