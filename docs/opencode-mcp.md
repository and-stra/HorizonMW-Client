# opencode MCP server

Lets Claude hand execution tasks to opencode (DeepSeek) and get the reports back directly.
Claude plans and reviews; opencode executes (see AGENTS.md).

## Requirements

- Node.js 18+ on Windows (`winget install OpenJS.NodeJS.LTS`), `node` on PATH.
- opencode installed and logged in to DeepSeek (`opencode auth login`).
- opencode must not ask for permissions during `opencode run` (allow edit/bash in its config),
  otherwise a task hangs until its timeout.

## Register in Claude desktop

`%APPDATA%\Claude\claude_desktop_config.json`, then restart Claude desktop:

```json
{
  "mcpServers": {
    "opencode": {
      "command": "node",
      "args": ["C:\\Games\\cod-hwm\\cod-mwx\\tools\\opencode-mcp\\opencode-mcp.mjs"],
      "env": {
        "OPENCODE_MODEL": "deepseek/<model id from `opencode models`>",
        "MWX_WORKDIR": "C:\\Games\\cod-hwm"
      }
    }
  }
}
```

For local Claude Code: `claude mcp add opencode -e OPENCODE_MODEL=deepseek/<id> -- node C:\Games\cod-hwm\cod-mwx\tools\opencode-mcp\opencode-mcp.mjs`

## Tools

| Tool | What it does |
|---|---|
| `opencode_task(task, title?, wait_seconds?)` | Starts a task (only one at a time), waits up to `wait_seconds` (default 50, max 110) and returns the report or the id |
| `opencode_wait(id, wait_seconds?)` | Waits again; returns status, log tail while running, the report when finished |
| `opencode_list(count?)` | Recent tasks and their state |
| `opencode_cancel(id)` | Kills opencode and its child processes |

Each task folder `mwx-opencode\<id>\` has `task.md` (rules + task), `report.md` (written by opencode),
`opencode.log` (opencode output) and `result.json` (exit code, timeout, seconds).
