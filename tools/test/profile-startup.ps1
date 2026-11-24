$ErrorActionPreference = "Stop"
$G = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$exe = Join-Path $G "mwx.exe"
$log = Join-Path $G "mwx-logs\load_times.log"
$port = 27301

function Rpc($port, $method, $params = @{}, $timeout = 2) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 8 -Compress
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout } catch { return $null }
}

$p = Start-Process -FilePath $exe -ArgumentList "-debugport $port +set mwx_test_mode 1" -WorkingDirectory $G -PassThru
$samples = New-Object System.Collections.ArrayList
$menu = $false
try {
    for ($i = 0; $i -lt 600; $i++) {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction SilentlyContinue
        if ($proc) {
            [void]$samples.Add([pscustomobject]@{ t = [DateTime]::UtcNow; cpu = [double]$proc.UserModeTime / 10000000; read = [double]$proc.ReadTransferCount })
        }
        if (-not $menu) {
            $s = Rpc $port "status" @{} 2
            if ($s -and $s.result -and $s.result.main_menu) { $menu = $true; break }
        }
        if ($p.HasExited) { break }
        Start-Sleep -Milliseconds 250
    }
    Start-Sleep -Seconds 2
} finally {
    Rpc $port "command" @{ command = "quit" } 2 | Out-Null
    if (-not $p.HasExited) { if (-not $p.WaitForExit(8000)) { try { $p.Kill() } catch {} } }
}

$lines = Get-Content $log
$start = 0
for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -like "*==== MWX start*") { $start = $i; break } }
$block = $lines[$start..($lines.Count - 1)]
$zoneStart = ($block | Select-String -Pattern "start  hmw_killstreak" | Select-Object -First 1).Line
$frame = ($block | Select-String -Pattern "first main-thread frame" | Select-Object -First 1).Line
$zs = if ($zoneStart -match '^\s*(\d+) ms') { [int]$Matches[1] } else { $null }
$fs = if ($frame -match '^\s*(\d+) ms') { [int]$Matches[1] } else { $null }

# CPU/read deltas over the zone window (samples are UTC; map wall window by process uptime)
$procStart = $p.StartTime.ToUniversalTime()
$inWin = $samples | Where-Object { ($_.t - $procStart).TotalMilliseconds -ge $zs -and ($_.t - $procStart).TotalMilliseconds -le $fs }
$cpu = 0; $read = 0
if ($inWin.Count -gt 1) {
    $cpu = $inWin[-1].cpu - $inWin[0].cpu
    $read = $inWin[-1].read - $inWin[0].read
}
$wall = ($fs - $zs) / 1000.0
[pscustomobject]@{
    menu_reached = $menu
    zone_start_ms = $zs
    first_frame_ms = $fs
    zone_wall_s = [math]::Round($wall, 2)
    cpu_s = [math]::Round($cpu, 2)
    cpu_pct_of_one_core = if ($wall -gt 0) { [math]::Round(100.0 * $cpu / $wall, 1) } else { 0 }
    read_mb = [math]::Round($read / 1MB, 1)
    read_mb_s = if ($wall -gt 0) { [math]::Round(($read / 1MB) / $wall, 1) } else { 0 }
    samples = $inWin.Count
} | ConvertTo-Json -Depth 4
