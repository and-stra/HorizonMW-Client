# AGENTS.md

MWX: a LAN-only fork of the HorizonMW client (H1 / Call of Duty: Modern Warfare Remastered),
based on the last open-source HMW code (Oct 2024). Goals: play the current HMW content with
friends on LAN, short loading times. No master server, accounts or anti-cheat.

## Build

- Windows, Visual Studio 2022 Build Tools ("Desktop development with C++").
- The build script is in the repository: `tools\build\build-mwx.bat [-nogit] [-game <dir>] [-log <file>]`.
  It updates the submodules, runs premake + msbuild (Release x64), copies `mwx.exe` into the game
  folder, archives `mwx.pdb` per commit (`refs\pdb\<hash>\`) and mirrors `data\mwx` / `data\mods`.
  Without `-nogit` it checks out `mwx` and fast-forwards to `claude/mwx` first.
- The thin wrappers next to the game folder keep the old call sites working:
  `C:\Games\cod-hwm\build-mwx.bat` (normal build, log `build-mwx.log`) and
  `C:\Games\cod-hwm\build-branch.bat` (`-nogit`: builds whatever is checked out, log
  `build-branch.log`; used for `opencode/autonomous` and fix branches).
- Output is `mwx.exe`. It must never overwrite `hmw-mod.exe` (the official v1.6.7 client).
- A running `mwx.exe` (a game or the MCP server) cannot be overwritten, but it can be renamed: the
  script moves it to `mwx-prev-<n>.exe` and copies the new build. The running process keeps the old
  image; the next start uses the new one.

## Branches

- `mwx`: the working branch (checked out on Windows).
- `claude/mwx`: Claude pushes here (it works in its own clone); `build-mwx.bat` fast-forwards
  `mwx` to it. If they diverge, merge by hand before building.

## Rules

- Never modify or delete game files or `.ff`/`.pak` files without a backup.
- Work only inside `C:\Games\cod-hwm`. Never copy, move or extract anything to other drives, other folders or
  virtual disks (VHD/VHDX, Dev Drives): a 38 GB move into the user's Dev Drive VHDX filled C: and detached it.
  Check free space before any large copy/extract and keep at least 20 GB free on C:.
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
| `repack.cpp` | `mwx.exe -repack all` (hmw-mod\zone only; `usermaps` / `everything` / zone names also possible): zlib zones → LZ4 blocks |

- `data/mwx/` is copied to `GAME\mwx\` by `build-mwx.bat`; `GAME\mwx\ui_scripts\` is loaded after HMW's zone ui_scripts (also in release).
- The test interface MCP (`mwx.exe -mcp`) replaces the old autoplay hack: the main menu "Play"
  button works offline, no automatic key presses.

## Testing

- Use the MCP tools (`start_client`, `start_server`, `wait_for`, `players`, `events`, `screenshot`,
  `ui_snapshot`/`ui_click`, `gsc_eval`, `run_test`, `run_all_tests`, `test_status`, `load_times`,
  `console_log`), see [docs/mcp.md](docs/mcp.md) and [docs/testing.md](docs/testing.md).
- Game mode tests: `data/mwx/tests/<name>.gsc` + an entry in `data/mwx/tests/tests.json`. Run them
  with `run_all_tests` (a background job, poll `test_status`) or, without the MCP,
  `powershell -File tools\test\run-tests.ps1 [-Name <test>]`. A full run is ~20-25 minutes.
  Weapons, perks, loadouts and spawn timing for new modes: [docs/hmw-weapons-perks.md](docs/hmw-weapons-perks.md).
- One MCP tool call must stay under ~60 s: opencode kills the MCP server when a call runs longer,
  so `run_test`/`run_all_tests` return a job and `wait_for` returns `still_waiting` after 45 s.
- GSC check before every commit: `powershell -File tools\gsc-check\check-all.ps1`
  (cross-file `path::function` calls for every `.gsc` in `data\`).
- Logs in the game folder: `mwx-logs\load_times.log`, `mwx-logs\repack.log`,
  `hmw-mod\logs\games_mp.log`, crash dumps in `minidumps\`.
- opencode integration: `opencode.json` in the repo root registers the MWX MCP server
  (`GAME\mwx.exe -mcp`). opencode only discovers project config from its own Location
  directory upwards, so when opencode runs one level above the repo (`C:\Games\cod-hwm`)
  the same file has to exist there too — that copy is what makes the tools show up in a
  session started in `C:\Games\cod-hwm`. Check with `opencode mcp list` (or `/mcps`);
  editing the file is enough, no restart needed. If the tools are missing, run
  `opencode mcp add mwx -- <GAME>\mwx.exe -mcp` from the directory opencode uses.

## Workflow: Claude drives, opencode executes

- **Claude** (claude.ai, runs in a Linux VM) does planning, architecture, troubleshooting,
  orchestration and review. It cannot build with MSVC or run the game.
- **opencode + DeepSeek** on Windows does everything Claude can't: builds, running the game and
  tests, measurements, anything that needs Windows.
- For each such step Claude writes a **short, self-contained prompt for opencode** in a code block.
  The user copies it into opencode and pastes the result back. Claude reviews it and approves it
  or writes a follow-up prompt.
- A prompt for opencode states: the goal, exact steps/commands, what to check, what to report
  (exit codes, key log lines, numbers), and when to stop. Keep it small: one task per prompt.
- When you are opencode running such a prompt: do only that task, make no design decisions,
  stop and report if something fails or is unclear, never touch game files by hand.
- Git: Claude pushes to `claude/mwx` (always rebased onto the current `mwx`); `build-mwx.bat`
  fast-forwards `mwx` to it. opencode commits only on `mwx` and never merges or rebases itself:
  if the script says the branches diverged, stop and report it to Claude.

- GSC check without the game (Linux): `tools/gsc-check/build.sh`, then `tools/gsc-check/gsct <file.gsc> <COD-GSC-Source/H1-GSC>`; compiles with the repo's gsc-tool for H1 and resolves unqualified calls.

## Autonomous runs

- Long autonomous runs (e.g. the branch `opencode/autonomous`) build with
  `C:\Games\cod-hwm\build-branch.bat` (`-nogit`), keep the PDB per commit and write their progress
  to `C:\Games\cod-hwm\mwx-debug\autonomous\report.md` (done work, commits, test results,
  decisions, open issues).
- They push only their own branch (never `mwx` / `main` / `claude/mwx`), never merge, rebase or
  force-push, and revert a failed milestone on that branch so it keeps building.
- The regression check before a milestone is finished: build, `run_all_tests` (or
  `tools\test\run-tests.ps1`), then the report and the push.
