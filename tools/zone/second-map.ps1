# load a second map in one session - moved from _migration\archive\mwx-debug\zone-stall\second-map.ps1 on 27 Nov 2026.
# Step Z done-criteria helper: load mp_crash, then a second map in the same client, and record
# the startup time (process start -> main menu) and each map load time.
param(
    [string]$Map1 = "mp_crash",
    [string]$Map2 = "mp_shipment",
    [int]$Port = 27981,
    [int]$TimeoutSeconds = 300
)
$ErrorActionPreference = "Stop"
$g = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$exe = Join-Path $g "mwx.exe"
$logRoot = "C:\Games\cod-hwm\_migration\archive\mwx-debug\zone-stall"
$log = Join-Path $logRoot "second-map.log"

function Rpc([int]$port, [string]$method, $params = @{}, [int]$timeout = 3) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 10 -Compress
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout }
    catch { return [pscustomobject]@{ error = $_.Exception.Message } }
}

$p = $null
try {
    $t0 = Get-Date
    $p = Start-Process -FilePath $exe -ArgumentList @("-memoryfix", "-debugport", "$Port", "+set", "mwx_test_mode", "1") `
        -WorkingDirectory $g -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"

    $startup = $null
    while (((Get-Date) - $t0).TotalSeconds -lt 300) {
        if ($p.HasExited) { throw "client exited during startup" }
        $s = Rpc $Port "status" @{} 2
        if ($s.result -and $s.result.main_menu) { $startup = ((Get-Date) - $t0).TotalSeconds; break }
        Start-Sleep -Seconds 1
    }
    if ($null -eq $startup) { throw "no main menu after 300 s" }
    Write-Host ("startup (process -> main menu): {0:N1} s" -f $startup)

    foreach ($d in @(@{ name = "g_gametype"; value = "war" }, @{ name = "ui_gametype"; value = "war" })) {
        Rpc $Port "set_dvar" $d 5 | Out-Null
    }

    $results = @()
    foreach ($map in @($Map1, $Map2)) {
        Rpc $Port "set_dvar" @{ name = "ui_mapname"; value = $map } 5 | Out-Null
        Start-Sleep -Seconds 2
        $start = Get-Date
        Rpc $Port "command" @{ command = "map $map" } 10 | Out-Null
        $ok = $false
        while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
            if ($p.HasExited) { break }
            $s = Rpc $Port "status" @{} 2
            if ($s.result -and $s.result.in_game -and $s.result.map -eq $map) { $ok = $true; break }
            Start-Sleep -Seconds 1
        }
        $secs = ((Get-Date) - $start).TotalSeconds
        $results += [pscustomobject]@{ Map = $map; Pass = $ok; Seconds = [math]::Round($secs, 1) }
        Write-Host ("map {0}: {1} in {2:N1} s" -f $map, ($(if ($ok) { "PASS" } else { "FAIL" })), $secs)
        if (-not $ok) { break }
        Start-Sleep -Seconds 5
    }

    $line = "startup {0:N1}s; {1}" -f $startup, (($results | ForEach-Object { "{0}={1} ({2:N1}s)" -f $_.Map, ($(if ($_.Pass) { "PASS" } else { "FAIL" })), $_.Seconds }) -join "; ")
    Add-Content -Path (Join-Path $logRoot "second-map-results.txt") -Value $line
} finally {
    if ($p -and -not $p.HasExited) {
        Rpc $Port "command" @{ command = "quit" } 5 | Out-Null
        if (-not $p.WaitForExit(8000)) { try { $p.Kill() } catch {} }
    }
}
