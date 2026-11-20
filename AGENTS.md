# AGENTS.md

MWX: a LAN-only fork of the HorizonMW client (H1 / Call of Duty: Modern Warfare Remastered),
based on the last open-source HMW code (Oct 2024). Goals: play the current HMW content with
friends on LAN, short loading times. No master server, accounts or anti-cheat.

## Build

- Windows, Visual Studio 2022 Build Tools ("Desktop development with C++").
- `C:\Games\cod-hwm\build-mwx.bat` does everything: checkout `mwx`, fast-forward to
  `claude/mwx`, submodules, premake, msbuild Release x64, copies `mwx.exe` into the game
  folder. Log: `C:\Games\cod-hwm\build-mwx.log`.
- Output is `mwx.exe`. It must never overwrite `hmw-mod.exe` (the official v1.6.7 client).

## Branches

- `mwx`: the working branch (checked out on Windows).
- `claude/mwx`: Claude pushes here (it works in its own clone); `build-mwx.bat` fast-forwards
  `mwx` to it. If they diverge, merge by hand before building.

## Rules

- Never modify or delete game files or `.ff`/`.pak` files without a backup.
  `mwx.exe -repack` moves originals to `hmw-mod\zone_backup_zlib\`; `-repack-restore` undoes it.
- String dvars can't be registered in `post_unpack` (crash: `MT_AllocIndex ... script string`).
  Register them in `scheduler::once(..., scheduler::pipeline::main)`.
- Game files are CRLF on Windows (`core.autocrlf=true`); keep line endings.

## MWX parts (src/client)

| File | What |
|---|---|
| `component/lan.cpp` | LAN discovery: UDP `getInfo` broadcast on ports 27016–27030 (+ `mwx_servers` dvar) |
| `component/server_list.cpp`, `party.cpp` | server browser and connect use `lan` instead of HTTP/master server |
| `component/load_timing.cpp` | `mwx-logs\load_times.log`: every fastfile + milestones |
| `component/debug_server.cpp` | local debug HTTP interface (127.0.0.1:27099 / 27098) |
| `mcp.cpp` | `mwx.exe -mcp`: MCP server, see [docs/mcp.md](docs/mcp.md) |
| `repack.cpp` | `mwx.exe -repack all` (or zone names): zlib zones → LZ4 blocks |

## Testing

- Use the MCP tools (`start_game`, `wait_for`, `load_times`, `console_log`, `game_status`),
  see [docs/mcp.md](docs/mcp.md).
- Logs in the game folder: `mwx-logs\load_times.log`, `mwx-logs\repack.log`,
  `hmw-mod\logs\games_mp.log`, crash dumps in `minidumps\`.
