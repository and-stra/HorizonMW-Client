# cold lobby start timing - moved from _migration\archive\mwx-debug\cac-bisect\lobby-cold.ps1 on 27 Nov 2026.
# Cold-start lobby check: Play Online must reach menu_xboxlive every time.
#   powershell -File lobby-cold.ps1 [-Runs 5] [-Port 27190]
param([int]$Runs = 5, [int]$Port = 27190)
$ErrorActionPreference = "Continue"
$GameDir = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$Exe = Join-Path $GameDir "mwx.exe"

function Rpc([string]$method, $params = @{}, [int]$timeout = 20) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 10 -Compress
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout }
    catch { return [pscustomobject]@{ error = $_.Exception.Message } }
}

$ok = 0
for ($run = 1; $run -le $Runs; $run++) {
    $p = Start-Process -FilePath $Exe -ArgumentList @("-debugport", "$Port", "+set", "mwx_test_mode", "1") -WorkingDirectory $GameDir -PassThru
    $menu = $false
    for ($i = 0; $i -lt 240; $i++) {
        if ($p.HasExited) { break }
        $s = Rpc "status" @{}
        if ($s.result -and $s.result.main_menu) { $menu = $true; break }
        Start-Sleep -Seconds 1
    }
    $reached = $false
    if ($menu) {
        Rpc "ui_click" @{ text = "PLAY ONLINE"; wait = $false } 10 | Out-Null
        for ($i = 0; $i -lt 60; $i++) {
            $snap = Rpc "ui_snapshot" @{}
            if ($snap.result -and $snap.result.menu -eq "menu_xboxlive") { $reached = $true; break }
            Start-Sleep -Seconds 1
        }
    }
    $zones = ""
    $lt = Rpc "load_times" @{}
    if ($lt.result) {
        $lines = @($lt.result -split "`r?`n" | Where-Object { $_ -match " start " })
        $zones = "zones=" + $lines.Count + " last=" + (($lines | Select-Object -Last 1) -replace "\s+", " ")
    }
    if ($reached) { $ok++ }
    "run ${run}: main_menu=$menu play_online=$reached $zones"
    Rpc "command" @{ command = "quit" } 10 | Out-Null
    Start-Sleep -Seconds 3
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 4
}
"$ok/$Runs reached Play Online"
if ($ok -ne $Runs) { exit 1 }

