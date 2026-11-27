# check a weapon's assets against the loaded zones - moved from _migration\archive\mwx-debug\mwr-weapons\check-assets.ps1 on 27 Nov 2026.
# B: check that the MWR weapon assets exist in the loaded zone (asset_exists RPC).
param(
    [int]$Port = 27985,
    [string]$Map = "mp_crash"
)
$ErrorActionPreference = "Stop"
$g = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$exe = Join-Path $g "mwx.exe"
$log = Join-Path "C:\Games\cod-hwm\_migration\archive\mwx-debug\mwr-weapons" "check-assets.log"

function Rpc([int]$port, [string]$method, $params = @{}, [int]$timeout = 5) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 10 -Compress
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout }
    catch { return [pscustomobject]@{ error = $_.Exception.Message } }
}

$p = $null
try {
    $p = Start-Process -FilePath $exe -ArgumentList @("-memoryfix", "-debugport", "$Port", "+set", "mwx_test_mode", "1") `
        -WorkingDirectory $g -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    while ($true) {
        if ($p.HasExited) { throw "client exited" }
        $s = Rpc $Port "status" @{} 2
        if ($s.result -and $s.result.main_menu) { break }
        Start-Sleep -Seconds 1
    }
    foreach ($d in @(@{ name = "g_gametype"; value = "war" }, @{ name = "ui_gametype"; value = "war" }, @{ name = "ui_mapname"; value = $Map })) {
        Rpc $Port "set_dvar" $d 5 | Out-Null
    }
    Rpc $Port "command" @{ command = "map $Map" } 10 | Out-Null
    $ok = $false
    for ($i = 0; $i -lt 300; $i++) {
        if ($p.HasExited) { break }
        $s = Rpc $Port "status" @{} 2
        if ($s.result -and $s.result.in_game) { $ok = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ok) { throw "map did not load" }

    $names = @(
        "h1_xmlar_mp", "h1_augast_mp", "h1_meleeapr1_mp", "h1_meleeblade_mp", "h1_meleesickle_mp",
        "h1_g3_mp", "h1_m14_mp", "h2_hatchet_mp", "iw9_throwknife_mp", "h1_knife_mp"
    )
    Write-Host ("zone: " + (Rpc $Port "get_dvar" @{ name = "mapname" } 5).result.value)
    foreach ($n in $names) {
        $a = Rpc $Port "asset_exists" @{ name = $n } 10
        if ($a.result) {
            Write-Host ("{0,-24} exists={1} default={2}" -f $n, $a.result.exists, $a.result.default)
        } else {
            Write-Host ("{0,-24} error: {1}" -f $n, $a.error)
        }
    }
} finally {
    if ($p -and -not $p.HasExited) {
        Rpc $Port "command" @{ command = "quit" } 5 | Out-Null
        if (-not $p.WaitForExit(8000)) { try { $p.Kill() } catch {} }
    }
}
