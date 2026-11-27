# cac-smoke: pick every ported weapon in Create-a-Class, read the saved class back.
#
#   powershell -File tools\test\cac-smoke.ps1 [-Port 27260] [-KeepOpen] [-ShotDir <dir>]
#
# The CAC is driven over the debug RPC (ui_click / ui_snapshot / lua_eval); no sv_cheats
# or `give` (both unavailable in a listen host). For each case it opens Primary/Secondary,
# switches to the category tab, clicks the row and compares the stored class weapon with
# the expected ref using Engine.GetPlayerData. A missing row, a rejected pick, a console
# Lua error or a screenshot failure fails the run.
#
# Cases are refs from stock_weapons_data.hpp: the AW pilot (iw5_dlcgun23 / iw5_dlcgun18 /
# iw5_exocrossbow) and one MWR DLC weapon (h1_m4).
param(
    [int]$Port = 27260,
    [switch]$KeepOpen,
    [string]$ShotDir = ""
)

$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$GameDir = Join-Path (Split-Path -Parent $Repo) "Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$Exe = Join-Path $GameDir "mwx.exe"
if (-not $ShotDir) { $ShotDir = Join-Path $GameDir "mwx-logs\cac-smoke" }
New-Item -ItemType Directory -Force -Path $ShotDir | Out-Null

# category, tab presses (0 = first tab), row text match, expected class ref
$cases = @(
    @{ cat = "Primary"; tabs = 0; text = "M1 GARAND"; ref = "iw5_dlcgun23" },
    @{ cat = "Primary"; tabs = 1; text = "MP40"; ref = "iw5_dlcgun18" },
    @{ cat = "Primary"; tabs = 0; text = "M4 CARBINE"; ref = "h1_m4" },
    @{ cat = "Secondary"; tabs = 3; text = "CROSSBOW"; ref = "iw5_exocrossbow" }
)

function Rpc([string]$method, $params = @{}, [int]$timeout = 30) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout
    } catch {
        return [pscustomobject]@{ error = "no answer: $($_.Exception.Message)" }
    }
}

function Menu { return (Rpc "ui_snapshot" @{} 20).result.menu }

function Wait-Menu([string]$want, [int]$seconds = 40) {
    for ($i = 0; $i -lt ($seconds * 2); $i++) {
        if ((Menu) -eq $want) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Click($params, [string]$label) {
    for ($try = 1; $try -le 4; $try++) {
        $answer = Rpc "ui_click" $params 40
        if ($answer.result -ne $null -and $answer.result.ok) {
            return $answer.result
        }
        Start-Sleep -Milliseconds 1200
    }
    throw "click '$label' failed: $($answer.error)$($answer.result.error)"
}

function Equipped([string]$cat) {
    $slot = if ($cat -eq "Primary") { 0 } else { 1 }
    $code = "return tostring(Engine.GetPlayerData(0, CoD.GetStatsGroupForGameMode(), 'customClasses', 0, 'weaponSetups', $slot, 'weapon'))"
    $r = Rpc "lua_eval" @{ code = $code } 20
    if (-not $r.result.ok) { throw "lua_eval failed: $($r.result.error)" }
    return $r.result.result
}

# The weapon list opens on the tab of the equipped weapon; a stock weapon in the first
# tab makes the tab presses deterministic.
function Reset-Class([string]$cat) {
    $slot = if ($cat -eq "Primary") { 0 } else { 1 }
    $ref = if ($cat -eq "Primary") { "h2_m4" } else { "h2_usp" }
    $code = "Engine.SetPlayerData(0, CoD.GetStatsGroupForGameMode(), 'customClasses', 0, 'weaponSetups', $slot, 'weapon', '$ref')"
    Rpc "lua_eval" @{ code = $code } 20 | Out-Null
    Start-Sleep -Milliseconds 400
}

function Shot([string]$name) {
    $path = Join-Path $ShotDir ($name + ".png")
    $r = Rpc "screenshot" @{ path = $path } 30
    if ($r.error) { throw "screenshot failed: $($r.error)" }
    return $path
}

function Ensure-Editor {
    for ($i = 0; $i -lt 8; $i++) {
        $m = Menu
        if ($m -eq "CacLoadoutEditorMenu") { return }
        if ($m -eq "CacMenu") {
            Rpc "ui_click" @{ id = "cac_class_button_0"; expect_menu = "CacLoadoutEditorMenu"; expect_timeout_ms = 20000 } 40 | Out-Null
            Start-Sleep -Milliseconds 1500
            continue
        }
        if ($m -eq "CacDetails") {
            Rpc "ui_back" @{} 15 | Out-Null
            Start-Sleep -Milliseconds 800
            continue
        }
        if ($m -eq "menu_xboxlive") {
            Rpc "ui_click" @{ text = "CREATE A CLASS"; expect_menu = "CacMenu"; expect_timeout_ms = 25000 } 40 | Out-Null
            Start-Sleep -Milliseconds 1500
            continue
        }
        Start-Sleep -Milliseconds 1000
    }
    throw "could not reach the class editor (menu: $(Menu))"
}

$results = @()
$failed = $false
$process = $null

try {
    $process = Start-Process -FilePath $Exe -ArgumentList @("-debugport", "$Port", "+set", "mwx_test_mode", "1") -WorkingDirectory $GameDir -PassThru
    for ($i = 0; $i -lt 240; $i++) {
        if ($process.HasExited) { throw "client exited during startup (code $($process.ExitCode))" }
        $s = Rpc "status" @{} 3
        if ($s.result -and $s.result.main_menu) { break }
        Start-Sleep -Seconds 1
    }

    Click @{ text = "PLAY ONLINE"; expect_menu = "menu_xboxlive"; expect_timeout_ms = 40000 } "play online" | Out-Null
    # the CAC storage enum is extended by the client after the stats source is up (the
    # loop ticks every 2 s); give it a moment before the first pick
    Start-Sleep -Seconds 4
    Click @{ text = "CREATE A CLASS"; expect_menu = "CacMenu"; expect_timeout_ms = 25000 } "create a class" | Out-Null
    Start-Sleep -Milliseconds 800
    Click @{ id = "cac_class_button_0"; expect_menu = "CacLoadoutEditorMenu"; expect_timeout_ms = 25000 } "custom slot 1" | Out-Null
    Start-Sleep -Milliseconds 800

    foreach ($case in $cases) {
        $label = "$($case.cat)/$($case.text)"
        $id = if ($case.cat -eq "Primary") { "CacLoadoutEditorMenu_optionsList_Primary_button_0" } else { "CacLoadoutEditorMenu_optionsList_Secondary_button_0" }
        Ensure-Editor
        Reset-Class $case.cat
        Start-Sleep -Milliseconds 600
        Click @{ id = $id; expect_timeout_ms = 20000 } "$label category" | Out-Null
        # the A/D category keys only take effect right after the list opens
        for ($t = 0; $t -lt $case.tabs; $t++) {
            Rpc "input" @{ action = "press"; command = "+moveright"; ms = 150 } 10 | Out-Null
            Start-Sleep -Milliseconds 500
        }
        Start-Sleep -Seconds 3

        $snap = (Rpc "ui_snapshot" @{} 25).result
        $row = @($snap.elements | Where-Object {
            $_.id -match '^CacDetails_CacDetails_list_button_[0-9]+$' -and
            (($_.text -replace "[\x01-\x1f]", "").Trim() -match [regex]::Escape($case.text))
        }) | Select-Object -First 1
        if (-not $row) {
            $names = @($snap.elements | Where-Object { $_.id -match '^CacDetails_CacDetails_list_button_' } | ForEach-Object { ($_.text -replace "[\x01-\x1f]", "").Trim() }) -join ", "
            $results += [pscustomobject]@{ case = $label; ok = $false; detail = "row not found; list: $names" }
            $failed = $true
            continue
        }

        $shot = Shot (("cac-" + ($case.ref -replace '[^a-z0-9_]', '_')))
        Click @{ id = $row.id; expect_timeout_ms = 20000 } $label | Out-Null
        Start-Sleep -Seconds 1
        $stored = Equipped $case.cat
        $ok = ($stored -eq $case.ref)
        if (-not $ok) { $failed = $true }
        $results += [pscustomobject]@{ case = $label; ok = $ok; detail = "stored=$stored expected=$($case.ref) shot=$shot" }
        Start-Sleep -Milliseconds 800
    }

    # an HMW weapon preview must still render (no default material)
    Ensure-Editor
    Click @{ id = "CacLoadoutEditorMenu_optionsList_Primary_button_0"; expect_timeout_ms = 20000 } "primary" | Out-Null
    Start-Sleep -Seconds 2
    $shot = Shot "cac-hmw-m4a1-preview"
    $results += [pscustomobject]@{ case = "HMW preview"; ok = $true; detail = $shot }

    $lines = @((Rpc "console" @{ lines = 400 } 20).result)
    $errs = @($lines | Where-Object { $_ -match 'Error processing event|LUA ERROR|\[string "' })
    if ($errs.Count -gt 0) {
        $failed = $true
        $results += [pscustomobject]@{ case = "console"; ok = $false; detail = ($errs -join " | ") }
    }
}
finally {
    if ($process -and -not $process.HasExited -and -not $KeepOpen) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
}

$results | ForEach-Object { "{0}  {1}  {2}" -f $(if ($_.ok) { "PASS" } else { "FAIL" }), $_.case, $_.detail }
$passed = @($results | Where-Object { $_.ok }).Count
"cac-smoke: $passed/$($results.Count) passed"
if ($failed) { exit 1 }
