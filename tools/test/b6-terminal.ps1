# usermap map-command test (moved from _migration\archive\mwx-debug\autonomous on 27 Nov 2026).
param(
    [int]$Port = 27660,
    [int]$NetPort = 27860,
    [int]$WaitS = 240,
    [string]$FirstMap = "mp_rust",
    [string]$NextMap = "mp_terminal",
    [switch]$Control
)

$ErrorActionPreference = "Stop"
$GameDir = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$Exe = Join-Path $GameDir "mwx.exe"

function Rpc([string]$method, $params = @{}, [int]$timeout = 10) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout }
    catch { return $null }
}

$seq = if ($Control) { @("mp_crash", "mp_shipment") } else { @($FirstMap, $NextMap) }
$log = Join-Path $env:TEMP "b6-terminal-$Port.log"
$errLog = "$log.err"

$process = Start-Process -FilePath $Exe -ArgumentList @(
    "-dedicated", "-memoryfix", "-debugport", "$Port",
    "+set", "net_port", "$NetPort",
    "+set", "g_gametype", "war",
    "+map", $seq[0]
) -WorkingDirectory $GameDir -PassThru -RedirectStandardOutput $log -RedirectStandardError $errLog
Write-Host "pid=$($process.Id) log=$log first=$($seq[0]) next=$($seq[1])"

$running = $false
for ($i = 0; $i -lt 300; $i++) {
    $s = Rpc "status" @{}
    if ($s.result -and $s.result.sv_running) { $running = $true; break }
    if ($process.HasExited) { Write-Host "exited before the first map"; break }
    Start-Sleep -Seconds 1
}
Write-Host "first map running=$running at $($i)s"
if (-not $running) {
    Get-Content $log -Tail 20
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    exit 1
}

Start-Sleep -Seconds 3
# the dvar is registered in renderer::post_unpack, after the command line is parsed
Rpc "set_dvar" @{ name = "mwx_debug_fastfiles"; value = "1" } 5 | Out-Null
Rpc "command" @{ command = "map $($seq[1])" } 10 | Out-Null
Write-Host "map $($seq[1]) sent at $(Get-Date -Format HH:mm:ss)"

# completion = the *new map's GSC VM* answers. The mapname dvar and sv_running change before the
# zone has finished, and the console log is buffered, so ask the script VM for the map name.
# One blocking eval (it waits on the server pipeline for up to 60 s), not a 1 s poll.
Start-Sleep -Seconds 25
$answer = Rpc "gsc_eval" @{ code = "return getmapname();" } 70
$done = $false
if ($answer -and $answer.result -and $answer.result.ok -and $answer.result.result -eq $seq[1]) {
    $done = $true
    Write-Host "second map GSC running (getmapname=$($answer.result.result))"
}
if (-not $done) {
    Write-Host ("no GSC eval answer - gsc_eval: " + ($answer | ConvertTo-Json -Compress -Depth 4))
}

# definitive check: the server can spawn a bot and list it (the GSC eval loader can fail after a
# map command even when the map itself is running - the C3 listen-host load_custom_script issue)
Rpc "command" @{ command = "spawnBot 1" } 10 | Out-Null
Start-Sleep -Seconds 4
$p = Rpc "players" @{} 10
$bot_count = 0
if ($p -and $p.result -and $p.result.players) { $bot_count = @($p.result.players).Count }
Write-Host ("bot spawn check: players=$bot_count")
if ($bot_count -gt 0) { $done = $true; Write-Host "second map is running (bot present)" }
$s = Rpc "status" @{}
if ($s.result) { Write-Host ("status now: map={0} sv_running={1} stale_ms={2}" -f $s.result.map, $s.result.sv_running, $s.result.stale_ms) }
$console = Rpc "console" @{ lines = 200 } 15
if ($console -and $console.result) {
    Write-Host "--- console (in-memory, last 80 lines)"
    @($console.result) | Select-Object -Last 80 | ForEach-Object { Write-Host "  $_" }
}

Write-Host "--- db trace (last 60 lines)"
Get-Content $log | Where-Object { $_ -match '^\[db\]' } | Select-Object -Last 60 | ForEach-Object { Write-Host $_ }
Write-Host "--- load_times tail"
Get-ChildItem (Join-Path $GameDir "mwx-logs") -Filter "*.log" | ForEach-Object { if ($_.Name -match 'load') { Get-Content $_.FullName -Tail 12 } }
Write-Host "--- server log tail"
Get-Content $log -Tail 20

Rpc "command" @{ command = "quit" } 5 | Out-Null
Start-Sleep -Seconds 3
if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
