# MCP client config - moved from _migration\archive\mwx-debug\autonomous\mcp-config.ps1 on 27 Nov 2026.
param([switch]$Disable)

$configPath = "C:\Games\cod-hwm\opencode.json"
$exe = "C:\\Games\\cod-hwm\\Call of Duty Horizon Modern Warfare\\Call of Duty Modern Warfare Remastered\\mwx.exe"

$disabled = if ($Disable) { "`n        `"disabled`": true," } else { "" }

$content = @"
{
  "`$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "mwx": {
        "type": "local",
        "command": [
          "$exe",
          "-mcp"
        ],$disabled
        "timeout": {
          "startup": 60000,
          "catalog": 60000
        }
      }
    }
  }
}
"@

Set-Content -Path $configPath -Value $content -Encoding utf8
