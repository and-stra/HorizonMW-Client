# screenshot an AW pilot weapon in game - moved from _migration\archive\mwx-debug\aw-weapons\pilot-shot.ps1 on 27 Nov 2026.
# D pilot visual check: load mp_shipment, give the AW pilot weapon, screenshot it.
# Retries a startup hang (the known startup lock; the test runner does the same).
param(
    [int]$Port = 27988,
    [string]$Weapon = "iw5_dlcgun23_mp",
    [string]$Name = "aw-pilot-m1garand"
)
$ErrorActionPreference = "Stop"
$g = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$exe = Join-Path $g "mwx.exe"
$log = Join-Path "C:\Games\cod-hwm\_migration\archive\mwx-debug\aw-weapons" "pilot-shot.log"

function Rpc([int]$port, [string]$method, $params = @{}, [int]$timeout = 8) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 10 -Compress
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout }
    catch { return [pscustomobject]@{ error = $_.Exception.Message } }
}

$p = $null
$up = $false
try {
    for ($attempt = 1; $attempt -le 3 -and -not $up; $attempt++) {
        Write-Host ("startup attempt {0}" -f $attempt)
        $p = Start-Process -FilePath $exe -ArgumentList @("-memoryfix", "-debugport", "$Port", "+set", "mwx_test_mode", "1") `
            -WorkingDirectory $g -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
        for ($i = 0; $i -lt 120; $i++) {
            if ($p.HasExited) { break }
            $s = Rpc $Port "status" @{} 2
            if ($s.result -and $s.result.main_menu) { $up = $true; break }
            Start-Sleep -Seconds 1
        }
        if (-not $up) {
            Write-Host "startup did not reach the menu, retrying"
            if (-not $p.HasExited) { try { $p.Kill() } catch {} }
            Start-Sleep -Seconds 3
        }
    }
    if (-not $up) { throw "client did not reach the main menu" }

    foreach ($d in @(@{ name = "g_gametype"; value = "war" }, @{ name = "ui_gametype"; value = "war" }, @{ name = "ui_mapname"; value = "mp_shipment" })) {
        Rpc $Port "set_dvar" $d 5 | Out-Null
    }
    Rpc $Port "command" @{ command = "map mp_shipment" } 10 | Out-Null
    $inGame = $false
    for ($i = 0; $i -lt 300; $i++) {
        if ($p.HasExited) { break }
        $s = Rpc $Port "status" @{} 2
        if ($s.result -and $s.result.in_game) { $inGame = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $inGame) { throw "map did not load" }
    Start-Sleep -Seconds 5

    $e = Rpc $Port "gsc_eval" @{ code = 'level.players[0] giveweapon("' + $Weapon + '"); level.players[0] switchtoweapon("' + $Weapon + '");' } 30
    Write-Host ("give: " + ($e.result | ConvertTo-Json -Compress))
    Start-Sleep -Seconds 3
    $shot = Rpc $Port "screenshot" @{ name = $Name } 30
    Write-Host ("screenshot: " + ($shot.result | ConvertTo-Json -Compress))
} finally {
    if ($p -and -not $p.HasExited) {
        Rpc $Port "command" @{ command = "quit" } 5 | Out-Null
        if (-not $p.WaitForExit(8000)) { try { $p.Kill() } catch {} }
    }
}
