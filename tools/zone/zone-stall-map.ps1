# map the zone load order/timing - moved from _migration\archive\mwx-debug\zone-stall-map.ps1 on 27 Nov 2026.
param(
    [Parameter(Mandatory = $true)][string]$Map,
    [int]$Port = 27980,
    [int]$TimeoutSeconds = 240,
    [switch]$NoZone
)
$ErrorActionPreference = "Stop"
$g = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$exe = Join-Path $g "mwx.exe"
$zoneFf = Join-Path $g "zone\hmw_aw_weapons.ff"
$zonePak = Join-Path $g "zone\hmw_aw_weapons.pak"
$hiddenFf = "$zoneFf.stalltest-hidden"
$hiddenPak = "$zonePak.stalltest-hidden"
$logRoot = "C:\Games\cod-hwm\_migration\archive\mwx-debug\zone-stall"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$log = Join-Path $logRoot "$Map-$(if($NoZone){'nozone'}else{'zone'}).log"
$err = "$log.err"

function Rpc([int]$port, [string]$method, $params = @{}, [int]$timeout = 4) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 10 -Compress
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout }
    catch { return [pscustomobject]@{ error = $_.Exception.Message } }
}

function Set-ZoneHidden([bool]$hidden) {
    if ($hidden) {
        if (Test-Path $zoneFf) { Move-Item $zoneFf $hiddenFf -Force }
        if (Test-Path $zonePak) { Move-Item $zonePak $hiddenPak -Force }
    } else {
        if (Test-Path $hiddenFf) { Move-Item $hiddenFf $zoneFf -Force }
        if (Test-Path $hiddenPak) { Move-Item $hiddenPak $zonePak -Force }
    }
}

if ($NoZone) { Set-ZoneHidden $true }
$p = $null
$inGame = $false
$elapsed = 0
try {
    $p = Start-Process -FilePath $exe -ArgumentList @("-memoryfix", "-debugport", "$Port", "+set", "mwx_test_mode", "1") `
        -WorkingDirectory $g -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
    $up = $false
    for ($i = 0; $i -lt 240; $i++) {
        if ($p.HasExited) { break }
        $s = Rpc $Port "status" @{} 2
        if ($s.result -and $s.result.main_menu) { $up = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $up) { throw "client did not reach the menu (exit=$($p.HasExited))" }

    foreach ($d in @(@{ name = "g_gametype"; value = "war" }, @{ name = "ui_gametype"; value = "war" }, @{ name = "ui_mapname"; value = $Map })) {
        Rpc $Port "set_dvar" $d 5 | Out-Null
    }
    Start-Sleep -Seconds 5
    Rpc $Port "command" @{ command = "map $Map" } 10 | Out-Null

    $start = Get-Date
    for ($i = 0; $i -lt $TimeoutSeconds; $i++) {
        if ($p.HasExited) { break }
        $s = Rpc $Port "status" @{} 3
        if ($s.result -and $s.result.in_game) { $inGame = $true; break }
        Start-Sleep -Seconds 1
    }
    $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 0)
} finally {
    if ($p -and -not $p.HasExited) {
        Rpc $Port "command" @{ command = "quit" } 5 | Out-Null
        if (-not $p.WaitForExit(8000)) { try { $p.Kill() } catch {} }
    }
    if ($NoZone) { Set-ZoneHidden $false }
}

# last zone / pak started
$loadLog = Join-Path $g "mwx-logs\load_times.log"
$tail = @(Get-Content $loadLog -Tail 80 -ErrorAction SilentlyContinue)
$lastStart = @($tail | Where-Object { $_ -match '^\s+\d+ ms\s+start\s+' } | Select-Object -Last 1)
$lastStartName = ""
if ($lastStart) { $lastStartName = ($lastStart -replace '^\s+\d+ ms\s+start\s+', '').Trim() }
$pakInfo = ""
if ($lastStartName -match '^imagefile(\d+)$') {
    $pak = Join-Path $g ("zone\" + $lastStartName + ".pak")
    if (Test-Path $pak) { $pakInfo = "{0:N0} MB" -f ((Get-Item $pak).Length / 1MB) }
}
$result = if ($inGame) { "PASS" } else { "STALL" }
Write-Host ("{0} zone={1} -> {2} in {3}s; lastStart='{4}' {5}" -f $Map, (-not $NoZone), $result, $elapsed, $lastStartName, $pakInfo)
