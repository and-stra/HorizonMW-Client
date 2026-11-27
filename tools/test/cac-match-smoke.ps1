# cac-match-smoke: a saved class with an AW weapon must spawn with it.
#
#   powershell -File tools\test\cac-match-smoke.ps1 [-Port 27270]
#
# Phase 1: client without a map -> PLAY ONLINE -> write the class through the same DDL path the
#          CAC uses (Engine.SetPlayerData) -> quit (the profile is saved).
# Phase 2: client with +map mp_shipment -> wait in game -> the player must hold the weapon from
#          the saved class (iw5_dlcgun23_mp).
# No sv_cheats / give: the weapon comes from the class, which is the thing under test.
param(
    [int]$Port = 27270
)
$ErrorActionPreference = "Stop"
$GameDir = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$Exe = Join-Path $GameDir "mwx.exe"

function Rpc([int]$p, [string]$method, $params = @{}, [int]$timeout = 30) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:$p/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout
    } catch {
        return [pscustomobject]@{ error = "no answer: $($_.Exception.Message)" }
    }
}

function Wait-MainMenu([int]$p, $process, [int]$seconds = 240) {
    for ($i = 0; $i -lt $seconds; $i++) {
        if ($process.HasExited) { return $false }
        $s = Rpc $p "status" @{} 3
        if ($s.result -and $s.result.main_menu) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Wait-InGame([int]$p, $process, [int]$seconds = 180) {
    for ($i = 0; $i -lt $seconds; $i++) {
        if ($process.HasExited) { return $false }
        $s = Rpc $p "status" @{} 3
        if ($s.result -and $s.result.in_game) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

# --- phase 1: save the class -------------------------------------------------------------
$p1 = Start-Process -FilePath $Exe -ArgumentList @("-debugport", "$Port", "+set", "mwx_test_mode", "1") -WorkingDirectory $GameDir -PassThru
if (-not (Wait-MainMenu $Port $p1)) { throw "phase 1: no main menu" }
Rpc $Port "ui_click" @{ text = "PLAY ONLINE"; expect_menu = "menu_xboxlive"; expect_timeout_ms = 40000 } 45 | Out-Null
Start-Sleep -Seconds 5
$write = $null
for ($try = 0; $try -lt 12; $try++) {
    $write = Rpc $Port "lua_eval" @{ code = "Engine.SetPlayerData(0, CoD.GetStatsGroupForGameMode(), 'customClasses', 0, 'weaponSetups', 0, 'weapon', 'iw5_dlcgun23'); return tostring(Engine.GetPlayerData(0, CoD.GetStatsGroupForGameMode(), 'customClasses', 0, 'weaponSetups', 0, 'weapon'))" } 20
    if ($write.result -and $write.result.ok -and $write.result.result -eq "iw5_dlcgun23") { break }
    Start-Sleep -Seconds 2
}
if (-not $write.result -or -not $write.result.ok -or $write.result.result -ne "iw5_dlcgun23") { throw "phase 1: class write failed: $($write.error) $($write.result.error)" }
"phase 1: class saved (iw5_dlcgun23)"
# also *select* Custom Slot 1: the spawn uses the selected class, not slot 0 automatically
Rpc $Port "ui_click" @{ text = "CREATE A CLASS"; expect_menu = "CacMenu"; expect_timeout_ms = 25000 } 45 | Out-Null
Start-Sleep -Seconds 1
Rpc $Port "ui_click" @{ id = "cac_class_button_0"; expect_timeout_ms = 20000 } 45 | Out-Null
Start-Sleep -Seconds 1
Rpc $Port "ui_back" @{} 15 | Out-Null
Start-Sleep -Seconds 1
Rpc $Port "ui_back" @{} 15 | Out-Null
Start-Sleep -Seconds 1
Rpc $Port "command" @{ command = "quit" } 10 | Out-Null
Start-Sleep -Seconds 4
if (-not $p1.HasExited) { Stop-Process -Id $p1.Id -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 3

# --- phase 2: the match must spawn with it ------------------------------------------------
$p2 = Start-Process -FilePath $Exe -ArgumentList @("-debugport", "$Port", "+set", "mwx_test_mode", "1", "+set", "g_gametype", "war", "+map", "mp_shipment") -WorkingDirectory $GameDir -PassThru
if (-not (Wait-InGame $Port $p2)) { throw "phase 2: no map" }
Start-Sleep -Seconds 5
# the listen host is a spectator until a team/class is picked (test mode shows the panel)
Rpc $Port "ui_click" @{ text = "TF 141"; wait = $false } 15 | Out-Null
Start-Sleep -Seconds 2
Rpc $Port "ui_click" @{ text = "Assault"; wait = $false } 15 | Out-Null
Start-Sleep -Seconds 5

$weapons = ""
for ($i = 0; $i -lt 30; $i++) {
    $players = Rpc $Port "players" @{} 20
    $me = @($players.result.players | Where-Object { -not $_.bot }) | Select-Object -First 1
    if ($me -and $me.weapons -and $me.weapons.Count -gt 0) {
        $weapons = ($me.weapons | ForEach-Object { $_.name }) -join ","
        break
    }
    Start-Sleep -Seconds 1
}
"phase 2: weapons = $weapons"

$screenshot = Join-Path $GameDir "mwx-logs\cac-smoke\match-m1-spawn.png"
Rpc $Port "screenshot" @{ path = $screenshot } 30 | Out-Null
Rpc $Port "command" @{ command = "quit" } 10 | Out-Null
Start-Sleep -Seconds 3
if (-not $p2.HasExited) { Stop-Process -Id $p2.Id -Force -ErrorAction SilentlyContinue }

if ($weapons -match "iw5_dlcgun23_mp") {
    "PASS: spawned with the saved class weapon (iw5_dlcgun23_mp)"
    exit 0
}
"FAIL: the saved class weapon is not in the loadout ($weapons)"
exit 1



