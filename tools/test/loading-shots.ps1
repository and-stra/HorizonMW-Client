# loading-screen screenshots - moved from _migration\archive\mwx-debug\autonomous\loading-shots.ps1 on 27 Nov 2026.
param(
    [int]$Port = 27570,
    [int]$Shots = 25
)

$ErrorActionPreference = "Stop"
$GameDir = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$Exe = Join-Path $GameDir "mwx.exe"
$OutDir = "C:\Games\cod-hwm\_migration\archive\mwx-debug\autonomous\loading-shots"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Rpc([string]$method, $params = @{}, [int]$timeout = 30) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout }
    catch { return $null }
}

function Click($params) {
    for ($try = 0; $try -lt 12; $try++) {
        $answer = Rpc "ui_click" $params 45
        if ($answer -and $answer.result -and $answer.result.ok) { return $answer.result }
        Start-Sleep -Seconds 3
    }
    Write-Host ("click failed: " + ($params | ConvertTo-Json -Compress) + " -> " + ($answer | ConvertTo-Json -Compress))
    return $null
}

function Wait-Menu([string]$name, [int]$seconds = 60) {
    for ($i = 0; $i -lt $seconds; $i++) {
        $snap = (Rpc "ui_snapshot" @{} 20).result
        if ($snap -and $snap.menu -eq $name) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

$log = Join-Path $env:TEMP "loading-shots-$Port.log"
$err = Join-Path $env:TEMP "loading-shots-$Port.err.log"
$process = Start-Process -FilePath $Exe -ArgumentList @("-debugport", "$Port") -WorkingDirectory $GameDir -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
Write-Host "client pid=$($process.Id)"

for ($i = 0; $i -lt 240; $i++) {
    if ($process.HasExited) { throw "client exited" }
    $s = Rpc "status" @{} 3
    if ($s.result -and $s.result.main_menu) { break }
    Start-Sleep -Seconds 1
}
Write-Host "main menu after $($i)s"

Click @{ text = "PLAY ONLINE"; expect_timeout_ms = 30000 } | Out-Null
Write-Host ("play online: " + (Wait-Menu "menu_xboxlive" 60))
Click @{ text = "PRIVATE MATCH"; expect_menu = "menu_xboxlive_privatelobby"; expect_timeout_ms = 30000 } | Out-Null
Write-Host ("lobby: " + (Wait-Menu "menu_xboxlive_privatelobby" 60))
Start-Sleep -Seconds 1

Rpc "ui_click" @{ id = "menu_xboxlive_privatelobby_button_0"; wait = $false } 20 | Out-Null
Write-Host "start clicked"

for ($i = 1; $i -le $Shots; $i++) {
    $shot = "mwx-screenshots\\loading-$('{0:D2}' -f $i).png"
    Rpc "screenshot" @{ path = $shot } 20 | Out-Null
    $s = Rpc "status" @{} 2
    $state = if ($s.result) { "in_game=$($s.result.in_game) map=$($s.result.map)" } else { "?" }
    Write-Host ("shot {0}: {1}" -f $i, $state)
    if ($s.result -and $s.result.in_game) { Start-Sleep -Seconds 1 } else { Start-Sleep -Milliseconds 800 }
}

if (-not $process.HasExited) { Rpc "command" @{ command = "quit" } 5 | Out-Null; if (-not $process.WaitForExit(10000)) { try { $process.Kill() } catch {} } }
