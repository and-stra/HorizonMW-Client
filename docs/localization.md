# Localized strings in MWX

MWX shows text in three layers. Knowing which layer answers a key explains the "raw key" bugs.

## 1. `localized_strings::override` (MWX, C++)

`src/client/component/gamemodes.cpp` (and `mods.cpp` for `mod.json` gametypes) register
`key -> text` pairs in `localized_strings`, which detours `SEH_StringEd_GetString` (0x585DA0).
The map is checked before the game's string table, so an override wins everywhere the engine
asks for the key, in the frontend and in a match. `utils::string::va` returns the text, so a
`&&1` placeholder is still substituted by the caller (`Engine.Localize(key, arg)`), e.g.
`First team to &&1 wins.` -> `First team to 75 wins.`

## 2. The game's per-zone string table

Stock `OBJECTIVES_*`, `MPUI_*`, `MENU_*` strings live in the localized fastfiles
(`zone\english\eng_*.ff`). They are **not** all present in the frontend: the MP strings arrive
with the MP content/gametype zones. In the main menu `Engine.Localize("@OBJECTIVES_war_SCORE")`
returned the raw key; in a loaded map the same call returned the text. The private-match UI and
the in-game mode display (`ingamebase.lua: inGameModeDisplay`) build
`OBJECTIVES_<gametype>` and `OBJECTIVES_<gametype>_SCORE` from the **lowercase ref**
(`GameX.GetGameMode()`), so a key that only exists in a zone is raw wherever the zone is not
loaded.

Item 6 fix: `gamemodes.cpp` now also registers the stock modes' base/`_SCORE`/`_HINT` texts for
both cases (`stock_objectives`), plus the lowercase variants of the MWX refs (`sas`, `infect`,
`dz`). The text is the English string the engine itself shows in game; `_SCORE` keeps the
`&&1` placeholder.

## 3. `mod.json` gametypes

`mods.cpp` registers, for every declared gametype, `MWXMOD_<REF>`, `_DESC`, `_CAPS`, the
loadscreen key `<REF>` and `OBJECTIVES_<ref>`/`_SCORE`/`_HINT` in **both** cases, from the
mod's `name`/`description`/`objective` fields. A mod gametype therefore never shows a raw key.

## Rules

- Every user-visible key must be registered for the lowercase **and** uppercase ref; the UI
  builds the lowercase one from `GameX.GetGameMode()`, the GSC gametype scripts use the
  uppercase one.
- Do not register stock strings only in the frontend or only in a match; register them in C++
  so the answer is independent of which zones are loaded.
- `tools\test\menu-smoke.ps1` checks every `OBJECTIVES_<ref>`, `_SCORE` and `_HINT` for the
  Party list, the Standard list and `infect`/`dz`/`sas` right after the private lobby opens
  (frontend, before any map zone). A key that comes back unchanged fails the run.
- `lua_eval` must not run while the main thread is reloading the UI: the LUI state exists but
  its script globals are mid-rebuild; an engine call from the chunk crashed at `0x1400BCB13`.
  `debug_server` now answers `main thread is busy (loading?), try again` instead and the menu
  smoke retries.
