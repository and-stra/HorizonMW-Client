# `map <usermap>` on a dedicated server (item 9)

## Result (26 Nov)

The old hang does **not** reproduce on the current build. A DS started with `+map mp_rust`
accepts `map mp_terminal` and the second map **runs**: its GSC loads
(`Loaded custom gsc 'maps/mp/mp_terminal.gsc'`), `spawnBot 1` creates a bot and `players` lists
it on `mp_terminal`. The big zone (785 MB) loads from the DB in ~6 s warm (startup `+map` is
~55 s cold).

The earlier "hang" reports came from the completion check, not from the map:
- the console log is buffered, so `done mp_terminal ... (server running)` is not in the file
  while/after the load; and
- `gsc_eval` after a `map` command fails with a compiler error (see below), which the old script
  treated as "no completion".

## The real remaining bug: runtime script compile after a `map` switch

`gsc_eval` (and any runtime `load_custom_script`) fails after a `map` command:

```
script 'mwx/tests/_eval_0' failed to load!
error: [ERROR]:compiler:mwx/tests/_eval_0:3:12: couldn't determine function call type
```

`mwx_result` is registered through `gsc::on_context_ready` (re-added on every
`Scr_BeginLoadScripts` and on `gsc::begin_runtime_compile`), so the compiler should know it. The
map's own custom scripts load fine, so this is specific to the runtime compile path after a game
shutdown. This is the same `gsc::load_custom_script` class as the t1-build listen-host crash
(item 13); fix it there if the listen host reproduces, and re-enable `gsc_eval` after `map` as
the verification.

## Instrumentation in the tree

- `mwx_debug_fastfiles 1` logs:
  - every `DB_LoadXAssets`: zone count, names, alloc/free flags, sync mode, caller, and whether
    it returned;
  - `scr_load_level` / `g_load_structs` progress and every init/main handle before/after execution.
- Hook placement: clients use `renderer.cpp`'s existing `DB_LoadXAssets` detour (red-dot
  brightness); a dedicated server uses `fastfiles.cpp`'s. **Never both**: a second detour on
  `0x397500` throws at startup (`0xE06D7363` in `detour::create`, seen as a dump loop).

## Reproduction script

`_migration\archive\mwx-debug\autonomous\b6-terminal.ps1 [-FirstMap mp_rust] [-NextMap mp_terminal]`:

1. starts a DS with `+map <FirstMap>`, waits for `server running`;
2. sets `mwx_debug_fastfiles 1`, sends `map <NextMap>`;
3. waits 25 s, asks the new map's GSC (`getmapname()`), then spawns a bot and checks `players`
   (the definitive completion signal, independent of log buffering);
4. prints the in-memory console, the `[db]`/`[load]` trace and the log tail.

## Measured trace for `mp_rust` -> `mp_terminal`

```
[db] DB_LoadXAssets 1 zone(s), mode 5, caller ...1A8AD4     mp_terminal_load alloc=8
[db] DB_LoadXAssets 2 zone(s), mode 0, caller ...3973CF     common_wet_mp, common_core_mp
[db] DB_LoadXAssets 3 zone(s), mode 2, caller ...3974AB     common_bots_mp, mp_terminal_path, mp_terminal (alloc=1024 = DB_ZONE_CUSTOM)
[db] DB_LoadXAssets returned (mode 2)
Waited 4546 msec for asset "maps/mp/mp_terminal.d3dbsp", type "col_map_mp"
[load] scr_load_level: done
```
