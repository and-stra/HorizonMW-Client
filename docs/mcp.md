# MWX debug interface and MCP server

MWX has two pieces for looking into a running game: a local debug server inside the
game, and an MCP server (`mwx.exe -mcp`) that AI tools (Claude desktop, opencode, ...)
use to talk to it.

```
AI tool  --stdio (MCP)-->  mwx.exe -mcp  --HTTP 127.0.0.1-->  running mwx.exe (game / dedicated server)
```

## Debug server (in the game)

Source: `src/client/component/debug_server.cpp`

Every `mwx.exe` instance listens on 127.0.0.1 only (not reachable from the network):

| Instance | Port |
|---|---|
| Game (client) | 27099 |
| Dedicated server (`-dedicated`) | 27098 |
| Any, overridden | `-debugport <n>` (`-debugport 0` turns it off) |

Requests: `POST http://127.0.0.1:<port>/rpc` with `{"method": "...", "params": {...}}`.
Answers: `{"result": ...}` or `{"error": "..."}`.

| Method | Params | Result |
|---|---|---|
| `status` | – | mode, uptime_ms, map, gametype, hostname, net_port, sv_running, main_menu, in_game (client), server (client: the server it's connected to), players |
| `get_dvar` | `name` | `{name, value}` |
| `set_dvar` | `name`, `value` | `"ok"` |
| `command` | `command` | queued console command (runs on the next frame) |
| `console` | `lines` (1–1000, default 100), `filter` (substring, case-insensitive) | last console lines |
| `load_times` | – | `mwx-logs\load_times.log`, latest start only |

`players` (name, team, score, ping, bot, origin) are only filled where the server runs:
on a dedicated server or on the host of a match, not on a client that joined.

`status` and `get_dvar` run on the game's main thread. While the game is loading
(zones, maps) the main thread is busy and they answer with an error after 2 s; try again.

Try it with curl (PowerShell: use `curl.exe`):

```
curl.exe -s -X POST http://127.0.0.1:27099/rpc -d "{\"method\":\"status\"}"
curl.exe -s -X POST http://127.0.0.1:27099/rpc -d "{\"method\":\"command\",\"params\":{\"command\":\"map mp_crash\"}}"
```

## MCP server (`mwx.exe -mcp`)

Source: `src/client/mcp.cpp`

Started with `-mcp`, `mwx.exe` doesn't load the game: it runs an MCP server on
stdin/stdout (newline-delimited JSON-RPC 2.0) and forwards to the debug servers above.
It can also start and stop game instances.

### Tools

`target` is `client` (default, port 27099) or `server` (dedicated server, port 27098).

| Tool | Arguments | What it does |
|---|---|---|
| `game_status` | `target` | `status` from the debug server |
| `run_command` | `command`, `target` | runs a console command, e.g. `map mp_crash`, `spawnbot 5`, `fast_restart` |
| `get_dvar` / `set_dvar` | `name` (`value`), `target` | read / set a dvar |
| `console_log` | `lines`, `filter`, `target` | last console lines |
| `load_times` | `target` | load-time log of the latest start |
| `start_game` | `dedicated` (bool), `args` (string) | starts `mwx.exe` from its folder in its own console. Dedicated default args: `+exec server_default.cfg +set net_port 27016 +map_rotate` |
| `stop_game` | `target` | sends `quit`; a process started by `start_game` is terminated after 10 s if it doesn't quit |
| `wait_for` | `state` (`running`, `main_menu`, `in_game`, `server_running`), `timeout_s` (default 120, max 600), `target` | polls `status` every second until the state is reached; returns how long it took |

Typical test run: `start_game` → `wait_for main_menu` → `load_times` →
`run_command "map mp_crash"` → `wait_for in_game` → `game_status` → `stop_game`.

### Setup

Claude desktop app: `%APPDATA%\Claude\claude_desktop_config.json`, then restart the app.

```json
{
  "mcpServers": {
    "mwx": {
      "command": "C:\\Games\\cod-hwm\\Call of Duty Horizon Modern Warfare\\Call of Duty Modern Warfare Remastered\\mwx.exe",
      "args": ["-mcp"]
    }
  }
}
```

opencode: `opencode.json` (project or `~/.config/opencode/opencode.json`):

```json
{
  "mcp": {
    "mwx": {
      "type": "local",
      "command": ["C:\\Games\\cod-hwm\\Call of Duty Horizon Modern Warfare\\Call of Duty Modern Warfare Remastered\\mwx.exe", "-mcp"]
    }
  }
}
```

### Notes

- Nothing but MCP messages may go to stdout in `-mcp` mode; games started by
  `start_game` get their own console (`CREATE_NEW_CONSOLE`).
- `start_game` refuses to start a second instance on the same port.
- Running the game and a dedicated server on one PC works (different debug ports).
- Adding a debug method: handle it in `debug_server.cpp` (`handle()`), then expose it as a
  tool in `mcp.cpp` (`tools()` + `call_tool()`).
