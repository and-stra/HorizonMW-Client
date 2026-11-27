# repeat cold starts - moved from _migration\archive\mwx-debug\autonomous\startup-loop.ps1 on 27 Nov 2026.
param(
    [int]$Runs = 10,
    [int]$StartTimeout = 240
)

$ErrorActionPreference = "Stop"
$GameDir = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$Exe = Join-Path $GameDir "mwx.exe"
$dumpDir = Join-Path $GameDir "minidumps"

function Rpc([int]$port, [string]$method, $params = @{}, [int]$timeout = 10) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 10 -Compress
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:$port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout
    } catch {
        return $null
    }
}

$before = @(Get-ChildItem $dumpDir -Filter *.zip -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
$fails = @()

for ($i = 1; $i -le $Runs; $i++) {
    $port = 27400 + $i
    $log = Join-Path $env:TEMP "startup-$port.log"
    $err = Join-Path $env:TEMP "startup-$port.err.log"
    $process = Start-Process -FilePath $Exe -ArgumentList @("-debugport", "$port", "+set", "mwx_test_mode", "1") `
        -WorkingDirectory $GameDir -PassThru -RedirectStandardOutput $log -RedirectStandardError $err

    $reached = $false
    $watch = [Diagnostics.Stopwatch]::StartNew()
    for ($k = 0; $k -lt $StartTimeout; $k++) {
        if ($process.HasExited) { break }
        $s = Rpc $port "status" 3
        if ($s -and $s.result -and $s.result.main_menu) { $reached = $true; break }
        Start-Sleep -Seconds 1
    }
    $ms = $watch.Elapsed.TotalMilliseconds

    $state = if ($reached) { "ok" } elseif ($process.HasExited) { "exited" } else { "timeout" }
    Write-Host ("run {0}/{1}: {2} ({3:N0} ms)" -f $i, $Runs, $state, $ms)
    if ($state -ne "ok") { $fails += "run $i : $state" }

    if (-not $process.HasExited) {
        Rpc $port "command" @{ command = "quit" } 5 | Out-Null
        if (-not $process.WaitForExit(15000)) { try { $process.Kill() } catch {} }
    }
    Start-Sleep -Seconds 5
}

$newDumps = @(Get-ChildItem $dumpDir -Filter *.zip -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Name | Where-Object { $before -notcontains $_ })
if ($newDumps.Count -gt 0) { $fails += "new dumps: $($newDumps -join ', ')" }

if ($fails.Count -eq 0) {
    Write-Host ("{0} startup(s): PASS" -f $Runs) -ForegroundColor Green
    exit 0
}
$fails | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
exit 1
