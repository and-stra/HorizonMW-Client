# verify the objective strings - moved from _migration\archive\mwx-debug\autonomous\objectives-verify.ps1 on 27 Nov 2026.
param(
    [int]$Port = 27600
)

$ErrorActionPreference = "Stop"
$GameDir = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$Exe = Join-Path $GameDir "mwx.exe"

function Rpc([string]$method, $params = @{}, [int]$timeout = 30) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout }
    catch { return $null }
}

function CheckKeys([string]$label) {
    Write-Host "=== $label"
    $refs = @("war","dm","dom","sd","sab","koth","ctf","dd","conf","hp","gun","infect","dz","sas","ph","mprops","slasher","rpg","oic","aon","cranked","sharpshooter","reinforce","srescue","mugger","arena","survival")
    foreach ($r in $refs) {
        $code = "local o = {} for _, s in ipairs({'', '_SCORE', '_HINT'}) do local k = 'OBJECTIVES_$r' .. s; local v = tostring(Engine.Localize('@' .. k)); if v == k then o[#o+1] = 'RAW ' .. k end end return o"
        $answer = Rpc "lua_eval" @{ code = $code } 20
        if ($answer -and $answer.result -and $answer.result.ok) {
            foreach ($line in @($answer.result.result)) { Write-Host ("  " + ($line -replace "[\x01-\x1f]", "")) }
        } else {
            Write-Host "  eval failed for $r"
        }
    }
}

$log = Join-Path $env:TEMP "objectives-verify-$Port.log"
$err = Join-Path $env:TEMP "objectives-verify-$Port.err.log"
$process = Start-Process -FilePath $Exe -ArgumentList @("-memoryfix", "-debugport", "$Port") -WorkingDirectory $GameDir -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
Write-Host "client pid=$($process.Id)"

$up = $false
for ($i = 0; $i -lt 240; $i++) {
    if ($process.HasExited) { throw "client exited" }
    $s = Rpc "status" @{} 2
    if ($s.result -and $s.result.main_menu) { $up = $true; break }
    Start-Sleep -Seconds 1
}
Write-Host "main menu after $($i)s"
Start-Sleep -Seconds 2

CheckKeys "frontend"

Rpc "set_dvar" @{ name = "g_gametype"; value = "war" } 5 | Out-Null
Rpc "set_dvar" @{ name = "ui_gametype"; value = "war" } 5 | Out-Null
Rpc "set_dvar" @{ name = "ui_mapname"; value = "mp_crash" } 5 | Out-Null
Rpc "command" @{ command = "map mp_crash" } 10 | Out-Null
$ingame = $false
for ($i = 0; $i -lt 240; $i++) {
    if ($process.HasExited) { break }
    $s = Rpc "status" @{} 2
    if ($s.result -and $s.result.in_game -and $s.result.sv_running) { $ingame = $true; break }
    Start-Sleep -Seconds 1
}
Write-Host "in_game=$ingame after $($i)s"
Start-Sleep -Seconds 2

CheckKeys "in game (war)"
$answer = Rpc "lua_eval" @{ code = "local o = {} for _, k in ipairs({'OBJECTIVES_war_SCORE','OBJECTIVES_WAR_SCORE','OBJECTIVES_war','OBJECTIVES_WAR','OBJECTIVES_war_HINT','OBJECTIVES_WAR_HINT'}) do o[#o+1] = k .. ' => ' .. tostring(Engine.Localize('@' .. k, 75)) end return o" } 20
if ($answer.result.ok) { $answer.result.result | ForEach-Object { Write-Host ("  " + ($_ -replace "[\x01-\x1f]", "")) } }

Rpc "screenshot" @{ path = "mwx-screenshots\\objectives-pregame-war.png" } 20 | Out-Null

if (-not $process.HasExited) { Rpc "command" @{ command = "quit" } 5 | Out-Null; if (-not $process.WaitForExit(10000)) { try { $process.Kill() } catch {} } }
