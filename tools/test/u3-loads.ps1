# menu/lobby load time measurement - moved from _migration\archive\mwx-debug\autonomous\u3-loads.ps1 on 27 Nov 2026.
param(
    [int]$Port = 27300,
    [int]$StartTimeout = 240
)

$ErrorActionPreference = "Stop"
$GameDir = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$Exe = Join-Path $GameDir "mwx.exe"
$logPath = Join-Path $GameDir "mwx-logs\load_times.log"

function Rpc([string]$method, $params = @{}, [int]$timeout = 40) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout
    } catch {
        return $null
    }
}

function Log-Size {
    if (Test-Path $logPath) { return [long](Get-Item $logPath).Length }
    return [long]0
}

function Log-Delta([long]$from) {
    if (-not (Test-Path $logPath)) { return @() }
    $bytes = [IO.File]::ReadAllBytes($logPath)
    if ($bytes.Length -le $from) { return @() }
    $text = [Text.Encoding]::UTF8.GetString($bytes, $from, $bytes.Length - $from)
    return @($text -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
}

function Step([string]$name, [scriptblock]$action) {
    $before = Log-Size
    $watch = [Diagnostics.Stopwatch]::StartNew()
    & $action
    $watch.Stop()
    $lines = Log-Delta $before
    Write-Host ("== {0}: {1:N0} ms, {2} load_times lines" -f $name, $watch.Elapsed.TotalMilliseconds, $lines.Count)
    foreach ($line in $lines) { Write-Host "   $line" }
}

$log = Join-Path $env:TEMP "u3-$Port.log"
$err = Join-Path $env:TEMP "u3-$Port.err.log"
$process = Start-Process -FilePath $Exe -ArgumentList @("-debugport", "$Port", "+set", "mwx_test_mode", "1") `
    -WorkingDirectory $GameDir -PassThru -RedirectStandardOutput $log -RedirectStandardError $err

$total = [Diagnostics.Stopwatch]::StartNew()
$size = Log-Size
Write-Host "process started (pid $($process.Id)), load_times at $size bytes"

for ($i = 0; $i -lt $StartTimeout; $i++) {
    $s = Rpc "status" @{} 3
    if ($s -and $s.result -and $s.result.main_menu) { break }
    if ($process.HasExited) { throw "client exited before the main menu" }
    Start-Sleep -Seconds 1
}
Write-Host ("== startup -> main menu: {0:N0} ms" -f $total.Elapsed.TotalMilliseconds)
for ($i = 0; $i -lt 60; $i++) {
    $snap = Rpc "ui_snapshot" @{} 20
    if ($snap -and $snap.result -and $snap.result.menu) { break }
    Start-Sleep -Seconds 1
}
foreach ($line in (Log-Delta $size)) { Write-Host "   $line" }

Step "PLAY ONLINE -> menu_xboxlive" {
    Rpc "ui_click" @{ text = "PLAY ONLINE"; expect_menu = "menu_xboxlive"; expect_timeout_ms = 60000 } 120 | Out-Null
}

Step "PRIVATE MATCH -> private lobby" {
    Rpc "ui_click" @{ text = "PRIVATE MATCH"; expect_menu = "menu_xboxlive_privatelobby"; expect_timeout_ms = 60000 } 120 | Out-Null
}

Step "GAME SETUP" {
    Rpc "ui_click" @{ text = "GAME SETUP"; expect_menu = "gamesetup_menu_main"; expect_timeout_ms = 20000 } 40 | Out-Null
}

Step "MODE popup" {
    Rpc "ui_click" @{ id = "gamesetup_menu_main_button_1"; expect_menu = "popup_recipesetup_modes"; expect_timeout_ms = 15000 } 30 | Out-Null
}

Step "back to lobby" {
    Rpc "ui_back" @{ expect_timeout_ms = 15000 } 30 | Out-Null
}

Step "START -> in game" {
    Rpc "ui_click" @{ id = "menu_xboxlive_privatelobby_button_0"; wait = $false } 20 | Out-Null
    for ($i = 0; $i -lt 240; $i++) {
        $s = Rpc "status" @{} 3
        if ($s -and $s.result -and $s.result.in_game) { break }
        Start-Sleep -Seconds 1
    }
}

Write-Host ("total process time: {0:N0} ms" -f $total.Elapsed.TotalMilliseconds)

if ($process.HasExited) {
    Write-Host "client exited during the run"
} else {
    Rpc "command" @{ command = "quit" } 5 | Out-Null
    if (-not $process.WaitForExit(8000)) { try { $process.Kill() } catch {} }
}
