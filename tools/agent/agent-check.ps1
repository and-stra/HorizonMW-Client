# agent session check - moved from _migration\archive\mwx-debug\autonomous\agent-check.ps1 on 27 Nov 2026.
param(
    [int]$Port = 27650,
    [int]$MaxAgents = 10
)
$ErrorActionPreference = 'Stop'
$g = 'C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered'

function Rpc([string]$method, $params = @{}, [int]$timeout = 15) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec $timeout
    } catch {
        return $null
    }
}

$args = @('-memoryfix', '-debugport', "$Port", '+set', 'mwx_test_mode', '1')
$p = Start-Process -FilePath (Join-Path $g 'mwx.exe') -ArgumentList $args -WorkingDirectory $g -PassThru `
    -RedirectStandardOutput "$env:TEMP\agent-check-$Port.log" -RedirectStandardError "$env:TEMP\agent-check-$Port.err"
Write-Output "pid=$($p.Id)"

$up = $false
for ($i = 0; $i -lt 120; $i++) {
    if (Rpc 'status' @{} 2) { $up = $true; break }
    if ($p.HasExited) { Write-Output 'exited early'; exit 1 }
    Start-Sleep -Seconds 1
}
Write-Output "debug up=$up at $($i)s"
if (-not $up) { exit 1 }

foreach ($d in @(
    @('g_gametype', 'survival'), @('ui_gametype', 'survival'), @('ui_mapname', 'mp_crash'),
    @('mwx_test', 'survival'), @('mwx_show_survival', '1'), @('mwx_survival_maxagents', "$MaxAgents"),
    @('mwx_gsc_print', '1'))) {
    Rpc 'set_dvar' @{ name = $d[0]; value = $d[1] } 5 | Out-Null
}
Rpc 'command' @{ command = 'map mp_crash' } 10 | Out-Null

$inGame = $false
for ($i = 0; $i -lt 240; $i++) {
    $s = Rpc 'status' @{}
    if ($s -and $s.result -and $s.result.in_game) { $inGame = $true; break }
    if ($p.HasExited) { Write-Output 'exited during load'; exit 1 }
    Start-Sleep -Seconds 1
}
Write-Output "in_game=$inGame at $($i)s"

Start-Sleep -Seconds 12
foreach ($q in @('return getdvar("g_gametype");', 'return getdvar("scr_survival_maxagents");',
        'return getdvar("scr_war_maxagents");', 'return getdvar("mwx_gamemode");',
        'return getmaxagents();', 'return level.agentarray.size;', 'return level.survival_wave;',
        'return level.survival_agents.size;')) {
    $r = Rpc 'gsc_eval' @{ code = $q } 20
    if ($r -and $r.result) { Write-Output "$q -> $($r.result | ConvertTo-Json -Compress -Depth 4)" }
    else { Write-Output "$q -> no result ($($r | ConvertTo-Json -Compress -Depth 4))" }
}

Rpc 'command' @{ command = 'quit' } 5 | Out-Null
Start-Sleep -Seconds 4
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
Write-Output "log: $env:TEMP\agent-check-$Port.log"
