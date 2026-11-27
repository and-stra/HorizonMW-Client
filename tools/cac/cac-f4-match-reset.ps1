# CAC list budget vs a match load - moved from _migration\archive\mwx-debug\cac-bisect\cac-f4-match-reset.ps1 on 27 Nov 2026.
# F4 follow-up: does the CAC list budget reset after a map load?
#   powershell -File cac-f4-match-reset.ps1 [-First 40] [-Max 60] [-Port 27297]
# 1. open/close the Primary list `First` times, 2. load a map, 3. back to the frontend,
# 4. open the Primary list until the LUI errors. Prints both counts.
param(
    [int]$First = 40,
    [int]$Max = 60,
    [int]$Port = 27297
)
$ErrorActionPreference = "Continue"
$GameDir = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$Exe = Join-Path $GameDir "mwx.exe"

function Rpc([string]$method, $params = @{}, [int]$timeout = 20) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 10 -Compress
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout }
    catch { return [pscustomobject]@{ error = $_.Exception.Message } }
}
function Menu { return (Rpc "ui_snapshot" @{} 15).result.menu }
function Wait-Menu([string]$want, [int]$seconds = 90) {
    for ($i = 0; $i -lt ($seconds * 2); $i++) {
        if ((Menu) -eq $want) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}
function OpenClose([int]$count, [string]$phase) {
    $catId = "CacLoadoutEditorMenu_optionsList_Primary_button_0"
    $ok = 0
    for ($n = 1; $n -le $count; $n++) {
        Rpc "ui_click" @{ id = $catId; expect_timeout_ms = 20000 } 30 | Out-Null
        Start-Sleep -Milliseconds 400
        if ((Menu) -ne "CacDetails") { "$phase}: failed at open $n"; return $ok }
        Rpc "ui_back" @{} 15 | Out-Null
        Start-Sleep -Milliseconds 400
        if ((Menu) -ne "CacLoadoutEditorMenu") { "$phase}: failed at back $n"; return $ok }
        $ok = $n
    }
    "$phase`: survived $ok opens"
    return $ok
}

$p = Start-Process -FilePath $Exe -ArgumentList @("-debugport", "$Port", "+set", "mwx_test_mode", "1") -WorkingDirectory $GameDir -PassThru
for ($i = 0; $i -lt 240; $i++) { if ($p.HasExited) { throw "client exited" }; $s = Rpc "status" @{}; if ($s.result -and $s.result.main_menu) { break }; Start-Sleep -Seconds 1 }
Rpc "ui_click" @{ text = "PLAY ONLINE"; wait = $false } 10 | Out-Null
if (-not (Wait-Menu "menu_xboxlive" 90)) { throw "no lobby" }
Start-Sleep -Seconds 2
Rpc "ui_click" @{ text = "CREATE A CLASS"; wait = $false } 10 | Out-Null
if (-not (Wait-Menu "CacMenu" 30)) { throw "no CacMenu" }
Rpc "ui_click" @{ id = "cac_class_button_0"; wait = $false } 10 | Out-Null
if (-not (Wait-Menu "CacLoadoutEditorMenu" 30)) { throw "no class editor" }

$before = OpenClose $First "before-match"

# play a short match (the map load rebuilds the LUI)
Rpc "command" @{ command = "map mp_shipment" } 10 | Out-Null
$ingame = $false
for ($i = 0; $i -lt 180; $i++) { $s = Rpc "status" @{}; if ($s.result -and $s.result.in_game) { $ingame = $true; break }; Start-Sleep -Seconds 1 }
"map loaded: $ingame"
Start-Sleep -Seconds 20
Rpc "command" @{ command = "disconnect" } 10 | Out-Null
$menu = $false
for ($i = 0; $i -lt 120; $i++) { $s = Rpc "status" @{}; if ($s.result -and $s.result.main_menu) { $menu = $true; break }; Start-Sleep -Seconds 1 }
"back at the main menu: $menu"

Rpc "ui_click" @{ text = "PLAY ONLINE"; wait = $false } 10 | Out-Null
if (-not (Wait-Menu "menu_xboxlive" 90)) { throw "no lobby after the match" }
Start-Sleep -Seconds 2
Rpc "ui_click" @{ text = "CREATE A CLASS"; wait = $false } 10 | Out-Null
if (-not (Wait-Menu "CacMenu" 30)) { throw "no CacMenu after the match" }
Rpc "ui_click" @{ id = "cac_class_button_0"; wait = $false } 10 | Out-Null
if (-not (Wait-Menu "CacLoadoutEditorMenu" 30)) { throw "no class editor after the match" }

$after = OpenClose $Max "after-match"
"RESET: before=$before after=$after (max $Max)"

Rpc "command" @{ command = "quit" } 10 | Out-Null
Start-Sleep -Seconds 3
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
