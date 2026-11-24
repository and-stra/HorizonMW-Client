# MWX debug interface and MCP server

MWX has two pieces for looking into and driving a running game without touching the window,
keyboard or mouse: a local debug server inside the game, and an MCP server (`mwx.exe -mcp`) that
AI tools (Claude desktop, opencode, ...) use to talk to it.

```
AI tool  --stdio (MCP)-->  mwx.exe -mcp  --HTTP 127.0.0.1-->  running mwx.exe (game / dedicated server)
```

Everything works with the game in the background (not focused): screenshots are taken from the
swap chain at Present, UI actions go through the LUI event handlers and input goes through the
engine's own key/command path.

## Debug server (in the game)

Source: `src/client/component/debug_server.cpp` (dispatch) and `component/debug_api.cpp`,
`component/ui_debug.cpp`, `component/screenshot.cpp` (implementation).

Every `mwx.exe` instance listens on 127.0.0.1 only (not reachable from the network):

| Instance | Port |
|---|---|
| Game (client) | 27099 |
| Dedicated server (`-dedicated`) | 27098 |
| Any, overridden | `-debugport <n>` (`-debugport 0` turns it off) |

Requests: `POST http://127.0.0.1:<port>/rpc` with `{"method": "...", "params": {...}}`.
Answers: `{"result": ...}` or `{"error": "..."}`.

Methods that touch game state run on the matching game thread (main / server / LUI) and answer
with `"the game's main thread is busy (loading?), try again"` while they can't (e.g. during a map
load). The caller retries.

### State and console

| Method | Params | Result |
|---|---|---|
| `status` | – | mode, uptime_ms, map, gametype, hostname, net_port, sv_running, main_menu, in_game, lui, db_ready, server (client: the server it's connected to), players |
| `get_dvar` / `set_dvar` | `name` (`value`) | `{name, value}` / `"ok"` |
| `command` | `command` | queued console command (runs on the next frame) |
| `console` | `lines` (1–1000, default 100), `filter` | last console lines |
| `load_times` | – | `mwx-logs\load_times.log`, latest start only |
| `perf` | – | uptime_ms, fps, frame_ms, map, gametype, players, in_game, server_running, working_set_mb, private_mb, the zone load times |
| `last_crash` | – | newest `minidumps\*.zip` (name, time, size) and the `mwx-logs\last_crash.txt` text, including the call stack |

### Screenshots

| Method | Params | Result |
|---|---|---|
| `screenshot` | `scale` (e.g. 0.5), `region` `{x, y, width, height}`, `path` | `{path, width, height, png_base64}` |

The frame is copied out of the D3D11 back buffer when the game calls `IDXGISwapChain::Present`
(the hook is installed from a small temporary swap chain, see `screenshot.cpp`). It works while
the window is not focused and behind other windows. Files go to `mwx-screenshots\<timestamp>.png`
unless `path` is given. There is also a console command `screenshot` and the key F12 (only bound
when it is free).

### UI (LUI menus)

The logic is in `data/mwx/ui_scripts/mwx_debug/__init__.lua`; it is loaded with the other MWX
ui_scripts and does nothing until one of these methods is called.

| Method | Params | Result |
|---|---|---|
| `ui_snapshot` | – | `{menu, open_menus, count, elements: [{id, full_id, text?, visible, focused?, rect?, depth}]}` |
| `ui_click` | `id` or `text`, `index` | `{ok, id, full_id, matches, queued}` |
| `ui_back` | – | `{ok, left}` |
| `ui_open` | `name` | `{ok, opened}` |
| `lua_eval` | `code` | `{ok, result|error}` |

H1's LUI elements are userdata: only `id` and the class methods are readable. Children come from
`getNumChildren()`/`getFirstChild()`/`getNextSibling()`, text from `getText()` (UIText only),
layout from `getRect()`, visibility from `isClosed()`. The menu stack is
`LUI.FlowManager.GetTopOpenAndVisibleMenuName()` plus `LUI.MenuBuilder.m_types_build` +
`IsMenuOpenAndVisible()`.

`ui_click` schedules the `button_action` event on the game's own LUI event loop (a
`LUI.UITimer`), because the menu handlers call `Engine.ExecNow`, which fails when it is called
directly from an eval chunk. The click therefore completes on the next LUI frame; the effect is
visible in the following `ui_snapshot` (or `wait_for menu_open`).

### Server side (GSC)

`data/mwx/tests/_debug.gsc` is compiled and run on demand (never in a normal match): the compiler
context is initialized around the load and the functions are executed through
`scripting::script_function_table`. Parameters come in the string dvars `mwx_debug_arg0..5`,
results go back through the MWX builtin `mwx_result(<string>)` as JSON text.

| Method | Params | Result |
|---|---|---|
| `players` | – | `{players: [{num, name, bot, team, alive, health, score, kills, deaths, origin, angles, current_weapon, weapons: [{name, clip, stock}], perks, class}]}` |
| `entities` | `classname`, `targetname`, `origin` `[x,y,z]`, `radius`, `limit` | `{entities: [{num, classname, targetname, model, origin}]}` |
| `bots` | `action` (`spawn` `count`, `kick` `num`, `team` `num`+`team`, `freeze`/`unfreeze` `num`) | queued / result |
| `events` | `since`, `type`, `limit` | `{cursor, events: [{id, time_ms, type, source, data}]}` |
| `gsc_eval` | `code` | `{ok, result}`; a leading `return X;` becomes `mwx_result(X);`, anything else is used as the function body |

`gsc_eval` writes a small script to `mwx/tests/_eval_<n>.gsc`, loads it with `ProcessScript`,
runs it and deletes the file. Errors come back as text; the game keeps running.

`events` keeps 5000 entries in a ring buffer:

| Type | Source | Data |
|---|---|---|
| `kill`, `damage` | game log (`G_LogPrintf`) | attacker/victim (id, num, team, name), weapon, damage, means_of_death, hit_location |
| `join`, `quit` | game log | id, num, name |
| `spawn`, `team_change`, `connect`, `disconnect` | GSC notifies | entity, arguments |
| `match_end` | GSC notify `game_ended` | winner |
| `script_error` | console | text |
| `console_error`, `console_warning` | console | text |
| `test_assert`, `test_done`, `test_log` | test scripts (`[mwx-test] {...}` console lines or `mwx_event`) | test data |

### Waiting

| Method | Params | Result |
|---|---|---|
| `wait` | `state`, `timeout_s` | `{reached, state, waited_ms, details}` or `{error: "timeout ..."}` |

`state` is one of `main_menu`, `in_game`, `server_running`, `map_loaded` (`value` = map name),
`menu_open` (`name`), `player_count` (`count`, `op` = `>=` or `==`), `dvar` (`name`, `value`),
`event` (`type`, optional `filter`, matched against the event JSON), `running`.
The wait happens inside the game (a condition variable check on a short interval); the caller
does not poll.

### Input without focus

| Method | Params | Result |
|---|---|---|
| `input` | `action` (`press`, `hold`, `move`, `release`, `look`, `stop`), `command`, `ms`, `pitch`, `yaw`, `look_at` `[x,y,z]` | what was queued |

* `press`/`hold`/`release` with a command (`+attack`, `weapnext`, `+forward`, ...): sends the key
  event of the key that is bound to the command (`CL_KeyEvent`), so it takes the same path as a
  real key press; commands without a binding are executed through the command buffer.
* `look` writes the view angles of the local player (or computes them from `look_at`).
* `stop` releases all movement/fire commands.

Note: `in_mouse 0` must not be used for automated runs — it also stops the client from building
usercmds at all. `mwx_test_mode` (see below) does not set it.

## MCP server (`mwx.exe -mcp`)

Source: `src/client/mcp.cpp`

Started with `-mcp`, `mwx.exe` doesn't load the game: it runs an MCP server on stdin/stdout
(newline-delimited JSON-RPC 2.0) and forwards to the debug servers above. It can also start and
stop game instances and keeps track of the instances it started.

`target` is an instance id (`c1`, `s2`, ...), a debug port, or `client` / `server` (the default
instance of that kind).

| Tool | Arguments | What it does |
|---|---|---|
| `start_client` / `start_server` | `map`, `gametype`, `mod`, `dvars` `{name: value}`, `resolution`, `args`, `test_mode`, `port` | starts `mwx.exe` in its own console, returns `{id, pid, port, command_line}`. Clients get `mwx_test_mode 1` unless `test_mode: false`; servers default to `+exec server_default.cfg +set net_port 27016 +map_rotate` when no map is given |
| `list_instances` | – | id, port, pid, running, command line, status for every instance the bridge started |
| `stop_instance` | `id` | sends `quit`, terminates after 10 s |
| `connect_client_to_server` | `client`, `server` | `connect 127.0.0.1:<server net_port>` on the client |
| `wait_for` | `state`, `timeout_s`, plus the `wait` params | retries the in-game wait (also while the game is still starting) and returns the total waited time |
| `screenshot` | `scale`, `region`, `path` | returns the PNG as an MCP **image** content block and saves it |
| `ui_snapshot`, `ui_click`, `ui_back`, `ui_open`, `lua_eval`, `gsc_eval` | see above | the debug methods |
| `players`, `entities`, `bots`, `events`, `perf`, `last_crash` | see above | the debug methods |
| `input` | see above | the debug method |
| `game_status`, `run_command`, `get_dvar`, `set_dvar`, `console_log`, `load_times` | as before | the debug methods |
| `start_game` / `stop_game` | `dedicated`, `args` / `target` | older aliases of start_client/start_server and stop_instance |

Typical run:

```
start_client -> wait_for main_menu -> ui_snapshot -> ui_click
-> run_command "map mp_crash" -> wait_for in_game -> spawn bots
-> players / events / screenshot -> stop_instance
```

### Setup

The repo has an `opencode.json` in its root that registers the server:

```json
{
  "mcp": {
    "servers": {
      "mwx": {
        "type": "local",
        "command": ["C:\\Games\\cod-hwm\\Call of Duty Horizon Modern Warfare\\Call of Duty Modern Warfare Remastered\\mwx.exe", "-mcp"]
      }
    }
  }
}
```

opencode discovers project config from its own Location directory upwards, so when it runs one
level above the repo (`C:\Games\cod-hwm`) the same file has to be there as well — that copy is
what makes the tools appear in such a session. `opencode mcp list` (or `/mcps`) shows the state;
editing the file is enough, no restart is needed. To add it by hand:

```
opencode mcp add mwx -- "<GAME>\mwx.exe" -mcp
```

Claude desktop app: `%APPDATA%\Claude\claude_desktop_config.json`, then restart the app:

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

### Notes

- Nothing but MCP messages may go to stdout in `-mcp` mode; games started by the bridge get
  their own console (`CREATE_NEW_CONSOLE`).
- The bridge process itself is also `mwx.exe`: stopping **all** `mwx.exe` processes kills the MCP
  connection (opencode reconnects after the config file is touched). Stop game instances with
  `stop_instance`, or by their PID.
- A rebuild copies `mwx.exe` into the game folder, which fails while the bridge or a game is
  running. Disable the MCP server in the config (or stop the game) before building.
- Running the game and a dedicated server on one PC works (different debug ports); the bridge
  hands out free ports automatically (client 27099+, server 27108+).
- Adding a debug method: handle it in `debug_server.cpp` (`handle()`), then expose it as a tool
  in `mcp.cpp` (`tools()` + `call_tool()`).
