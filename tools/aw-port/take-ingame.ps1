# take in-game screenshots via the RPC - moved from _migration\archive\mwx-debug\aw-weapons\W1.2\take-ingame.ps1 on 27 Nov 2026.
param(
    [int]$DebugPort = 27079,
    [string]$OutDir = 'C:\Games\cod-hwm\_migration\archive\mwx-debug\aw-weapons\W1.2'
)
$ErrorActionPreference = 'Stop'
$g = 'C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered'

function Rpc([string]$method, $params = @{}, [int]$timeout = 15) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:$DebugPort/rpc" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec $timeout
    } catch {
        return $null
    }
}

$exe = Join-Path $g 'hmw-aw.exe'
$args = @('-datadir','hmw-aw','-logdir','hmw-aw-logs','-debugport',"$DebugPort",
          '+set','mwx_test_mode','1','+set','g_gametype','war','+set','ui_mapname','mp_shipment',
          '+set','mwx_test_bots','4','+map','mp_shipment')
Write-Output "starting $exe $($args -join ' ')"
$p = Start-Process -FilePath $exe -ArgumentList $args -WorkingDirectory $g -PassThru
Write-Output "pid=$($p.Id)"

$inGame = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 3
    $s = Rpc 'status' @{}
    if ($s -and $s.result -and $s.result.in_game) { $inGame = $true; break }
    if ($p.HasExited) { Write-Output "exited early code=$($p.ExitCode)"; exit 1 }
}
Write-Output "in_game=$inGame after $($i*3)s"
if (-not $inGame) { Write-Output 'not in game'; if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }; exit 1 }

Start-Sleep -Seconds 5
Write-Output 'give crossbow:'
Rpc 'command' @{ command = 'give iw5_exocrossbow_mp' } | ConvertTo-Json -Compress
Start-Sleep -Seconds 2
Rpc 'command' @{ command = 'switchtoweapon iw5_exocrossbow_mp' } | ConvertTo-Json -Compress
Start-Sleep -Seconds 2
Write-Output 'ADS hold:'
Rpc 'input' @{ action = 'hold'; command = '+aim'; ms = 6000 } | ConvertTo-Json -Compress
Start-Sleep -Seconds 2
$shot = Join-Path $OutDir 'ingame_ads_noscope.png'
Write-Output 'screenshot:'
Rpc 'screenshot' @{ scale = 1.0; path = $shot } 30 | ConvertTo-Json -Compress
Start-Sleep -Seconds 1
Rpc 'command' @{ command = '-aim' } | Out-Null
Write-Output "screenshot path: $shot"
Write-Output 'quit:'
Rpc 'command' @{ command = 'quit' } | Out-Null
Start-Sleep -Seconds 5
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
