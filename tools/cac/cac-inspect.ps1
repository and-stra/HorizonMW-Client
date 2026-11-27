# open the CAC from the private lobby and screenshot it - moved from _migration\archive\mwx-debug\mwr-weapons\cac-inspect.ps1 on 27 Nov 2026.
param(
    [int]$Port = 27961,
    [string]$OutDir = "C:\Games\cod-hwm\_migration\archive\mwx-debug\mwr-weapons"
)
$ErrorActionPreference = "Stop"
$game = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$exe = Join-Path $game "mwx.exe"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Rpc([int]$port, [string]$method, $params = @{}, [int]$timeout = 30) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:$port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout
    } catch {
        return [pscustomobject]@{ error = "no answer: $($_.Exception.Message)"; not_running = $true }
    }
}

function Click([int]$port, $params) {
    $answer = Rpc $port "ui_click" $params 40
    if ($answer.result -eq $null) { throw "ui_click failed: $($answer.error)" }
    if (-not $answer.result.ok) { throw "ui_click failed: $($answer.result.error)" }
    if ($params.ContainsKey("expect_menu") -and -not $answer.result.expect_met) {
        throw "ui_click did not reach '$($params.expect_menu)' (menu=$($answer.result.menu))"
    }
    return $answer.result
}

function Wait-Menu([int]$port, [string]$name, [int]$seconds = 40) {
    for ($i = 0; $i -lt ($seconds * 2); $i++) {
        $snap = (Rpc $port "ui_snapshot" @{} 20).result
        if ($snap.menu -eq $name) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Open-PrivateLobby([int]$port) {
    $snap = (Rpc $port "ui_snapshot" @{} 25).result
    if ($snap.menu -eq "menu_xboxlive_privatelobby") { return }
    if ($snap.menu -eq "mp_main_menu") {
        Click $port @{ text = "PLAY ONLINE" } | Out-Null
        if (-not (Wait-Menu $port "menu_xboxlive" 40)) { throw "PLAY ONLINE did not open menu_xboxlive" }
    }
    Click $port @{ text = "PRIVATE MATCH"; expect_menu = "menu_xboxlive_privatelobby"; expect_timeout_ms = 30000 } | Out-Null
}

$log = Join-Path $env:TEMP "mwx-cac-inspect-$Port.log"
$err = "$log.err"
$p = Start-Process -FilePath $exe -ArgumentList @("-debugport", "$Port", "+set", "mwx_test_mode", "1") `
    -WorkingDirectory $game -PassThru -RedirectStandardOutput $log -RedirectStandardError $err

try {
    $up = $false
    for ($i = 0; $i -lt 240; $i++) {
        if ($p.HasExited) { throw "client exited ($($p.ExitCode))" }
        $s = Rpc $Port "status" @{} 3
        if ($s.result -and $s.result.main_menu) { $up = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $up) { throw "client did not reach the main menu" }
    Start-Sleep -Seconds 3

    Open-PrivateLobby $Port
    $snap = (Rpc $Port "ui_snapshot" @{} 25).result
    $snap | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $OutDir "cac-snapshot-lobby.json") -Encoding UTF8
    Rpc $Port "screenshot" @{ name = "cac-lobby" } 20 | Out-Null

    $create = @($snap.elements | Where-Object { $_.text -and (($_.text -replace "[\x01-\x1f]", "").Trim() -match "CREATE A CLASS|Create a Class") }) | Select-Object -First 1
    if ($create) {
        Write-Host ("clicking create-a-class: id={0} text={1}" -f $create.id, $create.text)
        Click $Port @{ id = $create.id } | Out-Null
        Start-Sleep -Seconds 2
        $snap2 = (Rpc $Port "ui_snapshot" @{} 25).result
        $snap2 | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $OutDir "cac-snapshot-create.json") -Encoding UTF8
        Rpc $Port "screenshot" @{ name = "cac-create" } 20 | Out-Null
        Write-Host ("menu after click: {0}" -f $snap2.menu)
        $snap2.elements | Select-Object id, text | Format-Table -AutoSize | Out-String -Width 160 | Write-Host
    } else {
        Write-Host "no CREATE A CLASS element; lobby elements:"
        $snap.elements | Select-Object id, text | Format-Table -AutoSize | Out-String -Width 160 | Write-Host
    }
} finally {
    if (-not $p.HasExited) {
        Rpc $Port "command" @{ command = "quit" } 5 | Out-Null
        if (-not $p.WaitForExit(10000)) { try { $p.Kill() } catch {} }
    }
}
