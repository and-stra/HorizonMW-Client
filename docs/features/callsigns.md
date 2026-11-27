# TODO: player cards / callsign graphics (emblem + background) on LAN

Status: **should fix** (user report 2026-11-24). Not a regression: the same white card shows on
the pre-M3 build `708e5a50`.

## Symptom

In the private-match lobby the player card in the top-right shows the name (`JATZEK97`) but the
**patch/emblem area is a plain white rectangle** instead of an emblem and background.

Screenshots: `_migration\archive\mwx-debug\autonomous\lobby-callsign.png` (M3 build, `3b80d004`) and
`_migration\archive\mwx-debug\autonomous\lobby-preM3.png` (`708e5a50`) - identical white card.

## Findings

- The card is built by `mplobbyplayerstats` (HMW, `refs\dumps\hmw_patch_common_mp\ui\lui\mp_menus\
  mplobbyplayerstats.lua`): elements `lobby_basic_playercard_id`, `patchEmblem`, `patchbacking`,
  `playercard`, updated in `update_playercard`.
- Its data comes from the LUI engine bindings `Lobby.GetMemberPatch`,
  `Lobby.GetMemberPatchbacking`, `Lobby.GetMemberBackground` and `Lobby.GetMemberStat`, i.e. from
  the **party member data**, which the retail client fills from the online service (Demonware).
  MWX stubs Demonware, so those fields are empty and the ui image falls back to the default
  (white) material.
- The **name** works because it travels in the snapshot (`clientInfo_t.name`); the **clan tag**
  works because `clantags.cpp` writes it into the snapshot (`clientInfo_t.clanAbbrev` at
  snapshot+0x7C). The patch/background have no snapshot field and are not part of the MWX connect
  info string (`party.cpp` sends hostname/gametype/map/mwx gametype).
- There is a Lua helper `sendPlayerCardUpdate` in HMW's lobby scripts, but it goes through the
  same online path.

## Fix plan

### 1. Stop the white box (local, safe)

- In an MWX ui_script wrapper for the lobby, after the menu is built: read
  `Lobby.GetMemberPatch(0)` / `GetMemberBackground(0)`; when they are empty/0, hide (alpha 0) the
  patch and background images so the card shows only the name/rank instead of a white block.
- Also give the local player a sensible default so the card is not empty: set the patch to a stock
  emblem material (pick one that exists in `hmw_patch_ui_mp`, e.g. from `emblemmenu.lua`'s default
  list) when no patch is stored.

### 2. Make LAN players see each other's cards (real fix)

Two options, both need the same data (patch id, patch backing id, background id per player):

- **Info string**: add `patch` / `patchback` / `background` to the MWX connect info
  (`party.cpp`, `utils::info_string`), keep the server's per-client info, and fill the party member
  data from it on every client (hook the party member update/build that
  `Lobby.GetMemberPatch` reads, or override `Lobby.GetMemberPatch` etc. in Lua to read our own
  table keyed by XUID/name).
- **Snapshot** (like clantags): if `clientInfo_t` has unused/free bytes, put the three ids there
  and read them in the Lua override. Do not overwrite anything the engine uses; verify with the
  struct layout first.

The Lua override is the least invasive: keep a client-side table `mwx_playercards[xuid] =
{patch, backing, background}` filled from the LAN info, and wrap the four `Lobby.GetMember*`
functions to prefer it.

## Acceptance

- Your own card shows a real emblem + background (no white block) in the private lobby.
- A second PC on the LAN sees the host's (and every other client's) card, and vice versa.
- CAC / personalization still open without errors; the emblem/background selected there is what
  the other players see.

## R7 status (2026-11-25)

Implemented (plumbing, not visually verified):

- Local profile dvars mwx_card_patch, mwx_card_backing, mwx_card_background (ints, default 0).
- The host's values are part of the MWX getInfo answer (mwx_card_*).
- data/mwx/ui_scripts/lobby_card/__init__.lua wraps Lobby.GetMemberPatch,
  GetMemberPatchbacking and GetMemberBackground for member 0 (the local player) and returns the
  dvar value when it is non-zero; the existing white-box hiding still applies when everything is 0.

Still open:

1. Per-player wire format: every client must send its three ids to the host, and the host must
   broadcast 
ame -> ids to the other clients (a mwxCard UDP message through 
etwork::send or
   an extra connect userinfo field). The lobby wrapper then keys the card by member name/XUID
   instead of only member 0. Without this the host's card works on a client, but not a client's card
   on the host/other clients.
2. The emblem/patch id semantics: playerCardPatch looks like an int into the emblem icon list
   (see hmw_patch_common_mp/mp/default_emblems.cfg, emblemIcon 198); a valid default id has not
   been confirmed in the lobby yet.
3. Visual check with two clients and a screenshot of menu_xboxlive_privatelobby.