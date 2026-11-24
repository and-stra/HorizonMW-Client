<#
  Measures client startup: time to the first main-thread frame (menu) and the first map load.
  Reads GAME\mwx-logs\load_times.log, so no MCP is needed.

  Usage: .\measure-startup.ps1 [-Runs 3] [-Map mp_crash] [-Port 27300] [-Label before]
#>
param(
    [int]$Runs = 3,
    [string]$Map = "mp_crash",
    [int]$Port = 27300,
    [string]$Label = "run",
    [string]$GameDir = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
)

$ErrorActionPreference = "Stop"
$exe = Join-Path $GameDir "mwx.exe"
$log = Join-Path $GameDir "mwx-logs\load_times.log"
if (-not (Test-Path $exe)) { throw "missing $exe" }

function Rpc([int]$port, [string]$method, $params = @{}, [int]$timeout = 5) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 10 -Compress
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:$port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout
    } catch {
        return [pscustomobject]@{ error = "no answer" }
    }
}

function Stop-Game($process, [int]$port) {
    if (-not $process) { return }
    try { Rpc $port "command" @{ command = "quit" } 2 | Out-Null } catch {}
    if (-not $process.HasExited) {
        if (-not $process.WaitForExit(10000)) { try { $process.Kill() } catch {} }
    }
}

function Get-LastBlock {
    $lines = Get-Content $log
    $start = 0
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -like "*==== MWX start*") { $start = $i; break }
    }
    return $lines[$start..($lines.Count - 1)]
}

$results = New-Object System.Collections.ArrayList

for ($run = 1; $run -le $Runs; $run++) {
    Write-Host "=== $Label run $run (port $Port) ==="
    $process = Start-Process -FilePath $exe -ArgumentList "-debugport $Port +set mwx_test_mode 1" `
        -WorkingDirectory $GameDir -PassThru

    try {
        $menu = $false
        for ($i = 0; $i -lt 180; $i++) {
            $s = Rpc $Port "status" @{} 2
            if ($s.result -and $s.result.main_menu) { $menu = $true; break }
            if ($process.HasExited) { break }
            Start-Sleep -Seconds 1
        }

        if (-not $menu) {
            [void]$results.Add([ordered]@{ run = $run; error = "no main menu"; exited = $process.HasExited; code = if ($process.HasExited) { $process.ExitCode } else { $null } })
            continue
        }

        Start-Sleep -Seconds 1
        $block = Get-LastBlock
        $frame = ($block | Select-String -Pattern "first main-thread frame" | Select-Object -First 1).Line
        $frameMs = if ($frame -match '^\s*(\d+) ms') { [int]$Matches[1] } else { $null }

        $t0 = Get-Date
        Rpc $Port "command" @{ command = "set g_gametype war" } 5 | Out-Null
        Rpc $Port "command" @{ command = "map $Map" } 5 | Out-Null

        $ingame = $false
        for ($i = 0; $i -lt 180; $i++) {
            $s = Rpc $Port "status" @{} 2
            if ($s.result -and $s.result.in_game) { $ingame = $true; break }
            if ($process.HasExited) { break }
            Start-Sleep -Seconds 1
        }
        $wall = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)

        $block = Get-LastBlock
        $firstZone = ($block | Select-String -Pattern "start  $Map" | Select-Object -First 1).Line
        $inGame = ($block | Select-String -Pattern "in game on $Map" | Select-Object -First 1).Line
        $zoneMs = if ($firstZone -match '^\s*(\d+) ms') { [int]$Matches[1] } else { $null }
        $gameMs = if ($inGame -match '^\s*(\d+) ms') { [int]$Matches[1] } else { $null }
        $mapMs = if ($zoneMs -and $gameMs) { $gameMs - $zoneMs } else { $null }

        [void]$results.Add([ordered]@{
            run = $run; menu_ms = $frameMs; map_ms = $mapMs; wall_map_s = $wall
            in_game = $ingame; exited = $process.HasExited
        })
        Write-Host ("  menu {0} ms, map {1} ms (wall {2} s)" -f $frameMs, $mapMs, $wall)
    } finally {
        Stop-Game $process $Port
        Start-Sleep -Seconds 2
    }
}

$results | ForEach-Object { [pscustomobject]$_ } | Format-Table -AutoSize
$out = Join-Path (Split-Path $PSCommandPath) ("startup-{0}-{1}.json" -f $Label, (Get-Date -Format "yyyyMMdd-HHmmss"))
$results | ConvertTo-Json -Depth 6 | Set-Content $out -Encoding UTF8
Write-Host "written $out"
