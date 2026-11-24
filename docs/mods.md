# MWX mod support

A mod is a folder `GAME\mods\<name>\`. Repo copies live in `data/mods/<name>/`.
Weapons, perks and loadouts for new modes: see [hmw-weapons-perks.md](hmw-weapons-perks.md).

| file | purpose |
|---|---|
| `mod.json` | `name`, `description`, `author`, `version`, optional `gametypes` |
| `mod.ff` | optional zone (weapons, models, sounds, ...). Loaded by the engine through `fs_game`. Lua inside `mod.ff` is refused. |
| `maps/mp/gametypes/<ref>.gsc` | gametype scripts of the mod's gametypes |
| `scripts/mp/*.gsc` | script mods (loaded like `GAME\mwx\scripts\mp`) |

`mod.json` gametypes:

```json
"gametypes": [ { "ref": "sas", "template": "dm", "name": "...", "description": "...",
                 "objective": "...", "class_choice": false, "strings": { "KEY": "text" } } ]
```

- `ref`: lower case, `[a-z0-9_]`, max 16 characters; the script is `maps/mp/gametypes/<ref>.gsc`.
- `template`: gametypes table row the icon and flags are copied from (`dm` for FFA, `war` for teams).
- `class_choice: false` = fixed gamemode loadout (`level.bypassclasschoicefunc`), like Infected.
- The gametype is added to the allowed gametype list, the gametypes table and the PARTY group of
  Private Match. Name keys: `MWXMOD_<REF>`, `MWXMOD_<REF>_DESC`, objectives `OBJECTIVES_<REF>*`.

Loading: main menu > MODS (or the console: `loadmod mods/<name>`, `unloadmod`). The game relaunches
with `-mod "mods/<name>"`, so zones, tables and menus are built fresh. A dedicated server uses the
same flag: `mwx.exe -dedicated -mod "mods/<name>" ...`.

Not handled yet: joining a server that runs a mod you don't have (no download on LAN; both PCs need
the same mod folder), and stats are shared with the unmodded game.

## Proof of concept: Sticks and Stones (`data/mods/sticksandstones`)

- `sas.gsc`: BO2 rules (crossbow, knife, throwing knife as tomahawk = bankrupt, suicide = bankrupt).
- `mod.ff`: Advanced Warfare's `iw5_exocrossbow_mp`, ported with x64-zt (see the opencode prompt
  in the session; zone source in `GAME\zone_source\mod_sticksandstones.csv`).
- Without `mod.ff`: `set sas_weapon h2_m21_mp` before the map loads to test the rules.
