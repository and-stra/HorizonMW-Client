# verify menu milestones M1/M3 - moved from _migration\archive\mwx-debug\autonomous\verify-m1m3.ps1 on 27 Nov 2026.
# M1/M3 verification on a live client (no MCP): menu labels, map from the frontend, unfocused input.
param(
    [string]$GameDir = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered",
    [int]$Port = 27099,
    [switch]$KeepRunning
)
$ErrorActionPreference = "Continue"
$exe = Join-Path $GameDir "mwx.exe"

function Rpc([string]$method, $params = @{}, [int]$timeout = 5) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec $timeout } catch { return $null }
}

"== start client"
$p = Start-Process -FilePath $exe -ArgumentList "-debugport $Port +set mwx_test_mode 1" -WorkingDirectory $GameDir -PassThru `
    -RedirectStandardOutput (Join-Path $env:TEMP "mwx-verify.out") -RedirectStandardError (Join-Path $env:TEMP "mwx-verify.err")

$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 1
    $s = Rpc 'status' @{} 2
    if ($s -and $s.result -and $s.result.main_menu) { $ready = $true; "main menu after $i s"; break }
    if ($p.HasExited) { "client exited"; break }
}
if (-not $ready) { "NO MAIN MENU"; if (-not $KeepRunning) { Stop-Process -Id $p.Id -Force }; exit 1 }

"== ui_snapshot (main menu)"
$snap = Rpc 'ui_snapshot' @{}
$snap.result | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $PSScriptRoot 'menu-snapshot.json')
$menu = $snap.result.menu
$elements = $snap.result.elements
$byId = @{}
foreach ($e in $elements) { if ($e.id) { $byId[[string]$e.id] = $e } }
"active menu: $menu"
$play = $byId['mp_main_menu_play_online']
if ($play) {
    "play button: id=$($play.id) text=$($play.text) rect=$($play.rect | ConvertTo-Json -Compress)"
} else { "play button element not found by id" }
$order = @($elements | Where-Object { $_.id -match 'play_online|options|quit|mods|MWX' } | ForEach-Object { $_.id })
"menu order (filtered): $($order -join ', ')"
# expected: mp_main_menu_play_online, ... options ..., mods, quit

"== screenshot (main menu)"
$shot = Rpc 'screenshot' @{ scale = 1 } 20
if ($shot -and $shot.result) { "screenshot: $($shot.result.path)" } else { "screenshot failed" }

"== map from the frontend"
$r = Rpc 'command' @{ command = 'set g_gametype war' }
$r = Rpc 'command' @{ command = 'map mp_crash' }
$inGame = $false
for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep -Seconds 1
    $s = Rpc 'status' @{} 2
    if ($s -and $s.result -and $s.result.in_game) { $inGame = $true; "in game after $i s"; break }
    if ($p.HasExited) { "client exited during the map load"; break }
}
if (-not $inGame) {
    "MAP DID NOT LOAD"
    $c = Rpc 'console' @{ lines = 25 }
    if ($c) { $c.result }
    if (-not $KeepRunning) { Stop-Process -Id $p.Id -Force }
    exit 1
}

"== unfocused movement"
Rpc 'command' @{ command = 'spawnBot 1' } | Out-Null
Start-Sleep -Seconds 3
$players = (Rpc 'players' @{}).result.players
$before = $players | Where-Object { -not $_.bot } | Select-Object -First 1
if (-not $before) { $before = $players[0] }
"player: $($before.name) origin=$($before.origin -join ',')"

$r = Rpc 'input' @{ action = 'hold'; command = '+forward'; ms = 1500 }
"sending +forward for 1.5 s: $($r | ConvertTo-Json -Compress)"
Start-Sleep -Seconds 2
$after = ((Rpc 'players' @{}).result.players | Where-Object { $_.name -eq $before.name } | Select-Object -First 1)
$moved = if ($after) { [math]::Round([math]::Sqrt([math]::Pow($after.origin[0]-$before.origin[0],2) + [math]::Pow($after.origin[1]-$before.origin[1],2)), 1) } else { -1 }
"origin after: $($after.origin -join ',')  moved=$moved units"

"== focus check"
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Fg { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid); }
'@
$fg = [Fg]::GetForegroundWindow(); $fgpid = 0
[void][Fg]::GetWindowThreadProcessId($fg, [ref]$fgpid)
"game window focused: $($fgpid -eq $p.Id) (foreground pid $fgpid, game pid $($p.Id))"

if (-not $KeepRunning) {
    Rpc 'command' @{ command = 'quit' } | Out-Null
    if (-not $p.WaitForExit(10000)) { $p.Kill() }
    "stopped"
}
