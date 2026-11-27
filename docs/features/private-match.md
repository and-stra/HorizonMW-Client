# Private match: game mode selection

The private match game setup stores the chosen mode as the gametype (e.g. `ph`, `slasher`,
`mugger`). Three things decide whether the match actually starts with it:

1. `MatchRules.SetData("gametype", ref)` — the UI calls it from `GameModeChooseAction`.
2. `ui_gametype` — the dvar the lobby panel and the loadscreen read.
3. `xpartygo` — the start command; the engine builds the match from `ui_gametype`.

## Why party modes used to start as Team Deathmatch

`MatchRules.SetData` validates the ref against the **`BaseGameMode` enum** of the DDL asset
`mp/commondata.ddl`:

```
root.gametype   type = DDL_ENUM_TYPE (9), bitSize = 8, one byte enum index
BaseGameMode    16 members (dm war ball sd dom conf ctf hp gun sab koth dd mugger infect gtnw dz)
```

The field is an **8-bit enum index** (240 free values) and the enum's name table is a
**hash-sorted array** (binary search; the hash is `h = h * 31 + tolower(c)`; verified against the
loaded table: `dd` → `0x0C80`, `sd` → `0x0E51`, `war` → `0x1CAE8`). `MatchRules` only accepts values
in that enum, so `ph`, `slasher`, … came back `false` and `ui_gametype` stayed `war`. The loadscreen
and the lobby then showed Team Deathmatch.

The match start (`xpartygo`) reads `ui_gametype`, not the match rules:
with `MatchRules=war` and `ui_gametype=ph` the match started as `level.gametype=ph`.

## Extending the enum in memory (tested, not shipped)

`BaseGameMode` can be extended at load time through the DDL asset (no zone edits): append the refs,
rebuild the hash-sorted name table, keep the enum indices of the existing members. `SetData("ph")`
then returned `true` and wrote the value into the match rules.

It is **not shipped**: selecting such a mode in the game setup crashed the client
(`0xC0000005` at `0x1400F59B2`, one dump) while creating the game setup menu — the extended enum
index is used as an array index by another system that still assumes the original 16 entries.
Extending the enum also changes what saved match rules can contain, which is not worth the risk.
The tests are in the history of `src/client/component/gamemodes.cpp` (`patch_ddl`, `mwx_ddl`).

## What MWX does instead

`data/mwx/ui_scripts/gamemodes/__init__.lua` + `src/client/component/gamemodes.cpp`:

- the Lua `MatchRules.SetData` wrapper records the chosen ref in the dvar `mwx_selected_gametype`
  **only when the top menu is `settings_recipe_choosetype`** (the user's pick). The engine also
  calls `SetData` again when a lobby/setup menu is built (it re-applies the current match-rules
  gametype), and those calls must not replace the pick — otherwise the next start runs the previous
  mode (found by the menu smoke test: `ph` -> second start ran `mugger`);
- C++ `on_ui_gametype` (dvar callback) keeps `ui_gametype` at that ref while `xblive_privatematch`
  is set — the game setup restore writes the engine's match-rules value (`war`) back, this puts the
  pick back;
- C++ `cbuf_add_text_stub` sets `ui_gametype` from `mwx_selected_gametype` right before
  `xpartygo` runs;
- the lobby panel and the loadscreen read `ui_gametype`, so both show the picked mode; the party
  state itself still reports the base gametype (the match rules cannot hold the party ref).

Verified: selecting PROP HUNT in the private match menu shows "PROP HUNT" in the lobby, starts
`g_gametype=ph`, `level.gametype=ph`, `mwx_gamemode=ph`, and the selection survives leaving the
match and re-entering the private lobby.

## Crash tracing

- `GAME\mwx-logs\ui_script_load.log` — one `start <path>` / `done <path>` line per LUI script
  (`src/client/component/ui_scripting.cpp`). A crash during a load-time chunk leaves a `start`
  without `done`.
- `mwx_trace("...")` in Lua appends to `GAME\mwx-logs\ui_trace.log`; `gamemodes/__init__.lua` marks
  every load step, so a crash inside the script names the exact step.
