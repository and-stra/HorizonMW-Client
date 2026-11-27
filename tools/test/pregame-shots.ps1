# pre-game screenshots - moved from _migration\archive\mwx-debug\autonomous\pregame-shots.ps1 on 27 Nov 2026.
param(
    [int]$Port = 27580,
    [string]$Map = "mp_crash",
    [string]$Gametype = "infect",
    [string]$Tag = "infect",
    [int]$Shots = 6
)

$ErrorActionPreference = "Stop"
$GameDir = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$Exe = Join-Path $GameDir "mwx.exe"
$OutDir = "C:\Games\cod-hwm\_migration\archive\mwx-debug\autonomous\pregame-shots"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Rpc([string]$method, $params = @{}, [int]$timeout = 30) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout }
    catch { return $null }
}

$log = Join-Path $env:TEMP "pregame-$Tag-$Port.log"
$err = Join-Path $env:TEMP "pregame-$Tag-$Port.err.log"
$args = @("-memoryfix", "-debugport", "$Port")
if ($Gametype -eq "sas") { $args = @("-mod", "mods/sticksandstones") + $args }
$process = Start-Process -FilePath $Exe -ArgumentList $args -WorkingDirectory $GameDir -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
Write-Host "client pid=$($process.Id) gametype=$Gametype"

$up = $false
for ($i = 0; $i -lt 240; $i++) {
    if ($process.HasExited) { break }
    $s = Rpc "status" @{} 2
    if ($s.result -and $s.result.main_menu) { $up = $true; break }
    Start-Sleep -Seconds 1
}
Write-Host "main menu=$up after $($i)s"
if (-not $up) { throw "no main menu" }

Rpc "set_dvar" @{ name = "g_gametype"; value = $Gametype } 5 | Out-Null
Rpc "set_dvar" @{ name = "ui_gametype"; value = $Gametype } 5 | Out-Null
Rpc "set_dvar" @{ name = "ui_mapname"; value = $Map } 5 | Out-Null
Rpc "set_dvar" @{ name = "mwx_show_survival"; value = "1" } 5 | Out-Null
Rpc "command" @{ command = "map $Map" } 10 | Out-Null
$ingame = $false
for ($i = 0; $i -lt 240; $i++) {
    if ($process.HasExited) { break }
    $s = Rpc "status" @{} 2
    if ($s.result -and $s.result.in_game -and $s.result.sv_running) { $ingame = $true; break }
    Start-Sleep -Seconds 1
}
Write-Host "in_game=$ingame after $($i)s"
Start-Sleep -Seconds 1

$loc = Rpc "lua_eval" @{ code = "local o = {} for _, k in ipairs({'OBJECTIVES_$Gametype','OBJECTIVES_${Gametype}_SCORE','OBJECTIVES_${Gametype}_HINT'}) do o[#o+1] = k .. ' => ' .. tostring(Engine.Localize('@' .. k)) end return o" } 20
if ($loc.result.ok) { $loc.result.result | ForEach-Object { Write-Host ("  " + ($_ -replace "[\x01-\x1f]", "")) } }

for ($i = 1; $i -le $Shots; $i++) {
    $shot = "mwx-screenshots\\pregame-$Tag-$('{0:D2}' -f $i).png"
    Rpc "screenshot" @{ path = $shot } 20 | Out-Null
    Write-Host "shot $i"
    Start-Sleep -Milliseconds 900
}

if (-not $process.HasExited) { Rpc "command" @{ command = "quit" } 5 | Out-Null; if (-not $process.WaitForExit(10000)) { try { $process.Kill() } catch {} } }
