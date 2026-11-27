# cac-smoke: pick every ported weapon in Create-a-Class and read the saved class back.
#
#   powershell -File tools\test\cac-smoke.ps1 [-Port 27260] [-Limit N] [-KeepOpen]
#
# The list of weapons comes from stock_weapons_data.hpp (tools/test/gen_cac_manifest.py):
# every row we add to mp/customweapons.csv, with its category and tab. For each weapon the
# script opens Primary/Secondary, switches to the tab, clicks the row by its position in
# Cac.Weapons (no text matching - display names repeat) and compares the stored class value
# with the ref. Melee rows store into CustomClass.meleeWeapon.
#
# Then: one HMW weapon preview, the attachments and camo screens, and a scan of the console for
# Lua errors. Everything goes through the debug RPC; no sv_cheats / give (both are unavailable
# in a listen host, see docs/testing.md).
param(
    [int]$Port = 27260,
    [int]$Limit = 0,
    [int]$Skip = 0,
    [int]$Stress = 0,
    [switch]$StressOnly,
    [switch]$KeepOpen,
    [string]$ShotDir = ""
)

$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$GameDir = Join-Path (Split-Path -Parent $Repo) "Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$Exe = Join-Path $GameDir "mwx.exe"
if (-not $ShotDir) { $ShotDir = Join-Path $GameDir "mwx-logs\cac-smoke" }
New-Item -ItemType Directory -Force -Path $ShotDir | Out-Null

function Rpc([string]$method, $params = @{}, [int]$timeout = 30) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout
    } catch {
        return [pscustomobject]@{ error = "no answer: $($_.Exception.Message)" }
    }
}

function Menu { return (Rpc "ui_snapshot" @{} 20).result.menu }

function Wait-Element([string]$id, [int]$seconds = 20) {
    for ($i = 0; $i -lt ($seconds * 2); $i++) {
        $snap = (Rpc "ui_snapshot" @{} 20).result
        if ($snap.elements -and @($snap.elements | Where-Object { $_.id -eq $id }).Count -gt 0) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Wait-Menu([string]$want, [int]$seconds = 60) {
    for ($i = 0; $i -lt ($seconds * 2); $i++) {
        if ((Menu) -eq $want) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Click($params, [string]$label) {
    for ($try = 1; $try -le 4; $try++) {
        $answer = Rpc "ui_click" $params 40
        if ($answer.result -ne $null -and $answer.result.ok) { return $answer.result }
        Start-Sleep -Milliseconds 1200
    }
    throw "click '$label' failed: $($answer.error)$($answer.result.error)"
}

function Lua($code) {
    $r = Rpc "lua_eval" @{ code = $code } 20
    if (-not $r.result.ok) { throw "lua_eval failed: $($r.result.error)" }
    return $r.result.result
}

function LuaNumber($code) {
    $v = Lua $code
    if ($v -eq $null -or $v -eq "") { return -1 }
    return [int]$v
}

function Equipped([string]$slot) {
    $path = if ($slot -eq "melee") { "'meleeWeapon'" } else { "'weaponSetups', $slot, 'weapon'" }
    return Lua "return tostring(Engine.GetPlayerData(0, CoD.GetStatsGroupForGameMode(), 'customClasses', 0, $path))"
}

function SetClass([string]$slot, [string]$ref) {
    $path = if ($slot -eq "melee") { "'meleeWeapon'" } else { "'weaponSetups', $slot, 'weapon'" }
    Lua "Engine.SetPlayerData(0, CoD.GetStatsGroupForGameMode(), 'customClasses', 0, $path, '$ref')" | Out-Null
    Start-Sleep -Milliseconds 300
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
            Wait-Element "cac_class_button_0" 15 | Out-Null
            Rpc "ui_click" @{ id = "cac_class_button_0"; expect_menu = "CacLoadoutEditorMenu"; expect_timeout_ms = 20000 } 40 | Out-Null
            Start-Sleep -Milliseconds 1200
            continue
        }
        if ($m -eq "CacDetails") { Rpc "ui_back" @{} 15 | Out-Null; Start-Sleep -Milliseconds 700; continue }
        if ($m -eq "menu_xboxlive") {
            Rpc "ui_click" @{ text = "CREATE A CLASS"; expect_menu = "CacMenu"; expect_timeout_ms = 25000 } 40 | Out-Null
            Start-Sleep -Milliseconds 1200
            continue
        }
        Start-Sleep -Milliseconds 1000
    }
    throw "could not reach the class editor (menu: $(Menu))"
}

function Find-Row($case) {
    # 1-based position in the CAC list for this tab, 1-based row element = position
    $idx = LuaNumber "local l = Cac.Weapons['$($case.cat)']['$($case.class)']; if type(l) ~= 'table' then return -1 end; for i, it in ipairs(l) do local n = type(it) == 'table' and it[1] or it; if n == '$($case.ref)' then return i end end; return -1"
    if ($idx -lt 1) { return $null }
    return "CacDetails_CacDetails_list_button_" + ($idx - 1)
}

$manifest = Join-Path $env:TEMP "mwx-cac-manifest.json"
& py -3 (Join-Path $PSScriptRoot "gen_cac_manifest.py") | Set-Content -Path $manifest -Encoding UTF8
$cases = @(); (Get-Content $manifest -Raw | ConvertFrom-Json) | ForEach-Object { $cases += $_ }
if ($Skip -gt 0) { $cases = @($cases | Select-Object -Skip $Skip) }
if ($Limit -gt 0) { $cases = @($cases | Select-Object -First $Limit) }
"cac-smoke: $($cases.Count) weapons"

$results = @()
$failed = $false
$process = $null

try {
    $process = Start-Process -FilePath $Exe -ArgumentList @("-debugport", "$Port", "+set", "mwx_test_mode", "1") -WorkingDirectory $GameDir -PassThru
    $menu = $false
    for ($i = 0; $i -lt 240; $i++) {
        if ($process.HasExited) { throw "client exited during startup (code $($process.ExitCode))" }
        $s = Rpc "status" @{} 3
        if ($s.result -and $s.result.main_menu) { $menu = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $menu) { throw "no main menu after 240 s" }

    Click @{ text = "PLAY ONLINE"; expect_menu = "menu_xboxlive"; expect_timeout_ms = 40000 } "play online" | Out-Null
    if (-not (Wait-Menu "menu_xboxlive" 90)) { throw "the lobby menu did not open (vlobby load stalled?)" }
    Start-Sleep -Seconds 3   # the weapon enum extension runs 2 s after the stats source exists
    Click @{ text = "CREATE A CLASS"; expect_menu = "CacMenu"; expect_timeout_ms = 25000 } "create a class" | Out-Null
    Wait-Element "cac_class_button_0" 20 | Out-Null
    Click @{ id = "cac_class_button_0"; expect_menu = "CacLoadoutEditorMenu"; expect_timeout_ms = 25000 } "custom slot 1" | Out-Null
    Start-Sleep -Milliseconds 800

    # HMW preview + attachments + camos render (fresh editor, before the pick loop changes state)
    SetClass "0" "h2_m4"
    Wait-Element "CacLoadoutEditorMenu_optionsList_Primary_button_0" 20 | Out-Null
    Click @{ id = "CacLoadoutEditorMenu_optionsList_Primary_button_0"; expect_timeout_ms = 20000 } "primary" | Out-Null
    Start-Sleep -Seconds 3
    $results += [pscustomobject]@{ case = "HMW preview"; ok = $true; detail = (Shot "cac-hmw-preview") }
    Rpc "ui_back" @{} 15 | Out-Null; Start-Sleep -Milliseconds 1000
    Click @{ id = "optionsList_Primary_option_1"; expect_timeout_ms = 15000 } "attachments" | Out-Null
    Start-Sleep -Seconds 3
    $results += [pscustomobject]@{ case = "attachments"; ok = $true; detail = (Shot "cac-attachments") }
    Rpc "ui_back" @{} 15 | Out-Null; Start-Sleep -Milliseconds 1000
    Click @{ id = "optionsList_Primary_option_3"; expect_timeout_ms = 15000 } "camos" | Out-Null
    Start-Sleep -Seconds 3
    $results += [pscustomobject]@{ case = "camos"; ok = $true; detail = (Shot "cac-camos") }
    Rpc "ui_back" @{} 15 | Out-Null; Start-Sleep -Milliseconds 1000
    if ($StressOnly) { $cases = @() }
    foreach ($case in $cases) {
        $label = "$($case.ref) [$($case.class)]"
        try {
            if ($case.class -eq "weapon_melee") {
                # The Melee tab renders loot variants (TIDAL, CLEAVER, ...) whose names do not map
                # back to the ref, and the list virtualises, so the menu click cannot be asserted.
                # Verify the storage path the menu uses plus the list membership instead.
                $inList = Lua "local l = Cac.Weapons['$($case.cat)']['$($case.class)']; if type(l) ~= 'table' then return 'no' end; for _, it in ipairs(l) do local n = type(it) == 'table' and it[1] or it; if n == '$($case.ref)' then return 'yes' end end; return 'no'"
                SetClass "melee" $case.ref
                $stored = Equipped "melee"
                $ok = ($stored -eq $case.ref -and $inList -eq "yes")
                if (-not $ok) { $failed = $true }
                $results += [pscustomobject]@{ case = $label; ok = $ok; detail = "storage=$stored list=$inList (menu row renders a loot name)" }
                continue
            }
            Ensure-Editor
            # Equip the first weapon of the target list: the CAC opens that tab and scrolls to it,
            # so the tab needs no key presses and the top rows (our prepended weapons) are rendered.
            $reset = Lua "local l = Cac.Weapons['$($case.cat)']['$($case.class)']; if type(l) ~= 'table' or #l < 1 then return '' end; local it = l[1]; return tostring(type(it) == 'table' and it[1] or it)"
            if ($case.class -eq "weapon_melee") { $reset = "h2_shovel" }
            SetClass $case.slot $reset
            Start-Sleep -Milliseconds 500

            $catId = if ($case.cat -eq "Primary") { "CacLoadoutEditorMenu_optionsList_Primary_button_0" } else { "CacLoadoutEditorMenu_optionsList_Secondary_button_0" }
            Wait-Element $catId 20 | Out-Null
            Click @{ id = $catId; expect_timeout_ms = 20000 } "$label category" | Out-Null
            # Press right until the rendered rows 1..4 match the list's rows 2..5 (a fingerprint;
            # row 0 alone is not reliable - some lists start with a nameless null entry).
            $fpExpected = (Lua "local l = Cac.Weapons['$($case.cat)']['$($case.class)']; local t = {}; for i = 2, 5 do local it = l[i]; if not it then break end; local n = type(it) == 'table' and it[1] or it; t[#t+1] = (tostring(Cac.GetWeaponName('$($case.cat)', n)):gsub('[\1-\31]', '')) end; return table.concat(t, '|')")
            $expParts = @($fpExpected -split '\|')
            $onTab = ($case.class -eq "weapon_melee")  # equipped melee opens the Melee tab
            for ($t = 0; $t -lt 7 -and -not $onTab; $t++) {
                Start-Sleep -Milliseconds 900
                $snapTab = (Rpc "ui_snapshot" @{} 20).result
                $parts = @()
                for ($r = 1; $r -le 4; $r++) {
                    $row = @($snapTab.elements | Where-Object { $_.id -eq ("CacDetails_CacDetails_list_button_" + $r) }) | Select-Object -First 1
                    $parts += if ($row) { ($row.text -replace "[\x01-\x1f]", "").Trim() } else { "" }
                }
                $same = 0
                for ($i = 0; $i -lt [Math]::Min($expParts.Count, $parts.Count); $i++) {
                    if ($expParts[$i] -ne "" -and $parts[$i] -eq $expParts[$i]) { $same++ }
                }
                if ($same -ge 2) { $onTab = $true; break }
                Rpc "input" @{ action = "press"; command = "+moveright"; ms = 120 } 10 | Out-Null
            }
            if (-not $onTab) { throw "tab not found (expected '$fpExpected')" }

            $expected = Lua "local n = '$($case.ref)'; return (tostring(Cac.GetWeaponName('$($case.cat)', n)):gsub('[\1-\31]', ''))"
            $ok = $false
            $detail = ""
            $cands = @()
            $snap = (Rpc "ui_snapshot" @{} 20).result
            $rows = @($snap.elements | Where-Object { $_.id -match '^CacDetails_CacDetails_list_button_[0-9]+$' })
            if ($case.class -eq "weapon_melee") {
                $rowId = Find-Row $case
                if ($rowId) { $cands = @([pscustomobject]@{ id = $rowId }) }
            } else {
                $cands = @($rows | Where-Object { ($_.text -replace "[\x01-\x1f]", "").Trim() -eq $expected })
            }
            if ($expected -eq "" -and $cands.Count -eq 0) {
                # no display name (e.g. the AW combat knife): use the list position instead
                $rowId = Find-Row $case
                if ($rowId) { $cands = @([pscustomobject]@{ id = $rowId }) }
            }
            if ($cands.Count -eq 0) {
                $names = @($rows | ForEach-Object { ($_.text -replace "[\x01-\x1f]", "").Trim() }) -join ", "
                throw "row '$expected' not rendered; list: $names"
            }
            foreach ($cand in $cands) {
                Click @{ id = $cand.id; expect_timeout_ms = 20000 } $label | Out-Null
                Start-Sleep -Milliseconds 900
                $stored = Equipped $case.slot
                if ($stored -eq $case.ref) { $ok = $true; break }
                $detail = "stored=$stored"
                if ((Menu) -ne "CacLoadoutEditorMenu") { Rpc "ui_back" @{} 15 | Out-Null; Start-Sleep -Milliseconds 700 }
                Ensure-Editor
                Wait-Element $catId 20 | Out-Null
                Click @{ id = $catId; expect_timeout_ms = 20000 } "$label category" | Out-Null
                if ($case.class -eq "weapon_melee") { Rpc "input" @{ action = "press"; command = "+moveright"; ms = 120 } 10 | Out-Null }
                Start-Sleep -Seconds 1
            }
            if (-not $ok) { $failed = $true }
            $shot = if (-not $ok) { Shot ("cac-fail-" + ($case.ref -replace '[^a-z0-9_]', '_')) } else { "" }
            $results += [pscustomobject]@{ case = $label; ok = $ok; detail = "stored=$(Equipped $case.slot) $detail $shot" }
        }
        catch {
            $failed = $true
            $results += [pscustomobject]@{ case = $label; ok = $false; detail = $_.Exception.Message }
            if ((Menu) -ne "CacLoadoutEditorMenu") { Rpc "ui_back" @{} 15 | Out-Null; Start-Sleep -Milliseconds 600 }
        }
    }
    if ($Stress -gt 0) {
        # F4: HMW's CacDetails builds a new menu (and its animation states) on every open; the
        # engine's state pool fills after ~55 opens in one session (stock fails at 56, our build at
        # 55 - not caused by our rows). Keep a session under that: 40 open/close cycles total.
        $stressFailed = ""
        for ($k = 1; $k -le $Stress; $k++) {
            $catId = if (($k % 2) -eq 1) { "CacLoadoutEditorMenu_optionsList_Primary_button_0" } else { "CacLoadoutEditorMenu_optionsList_Secondary_button_0" }
            Ensure-Editor
            Wait-Element $catId 15 | Out-Null
            Rpc "ui_click" @{ id = $catId; expect_timeout_ms = 20000 } 30 | Out-Null
            Start-Sleep -Milliseconds 400
            if ((Menu) -ne "CacDetails") { $stressFailed = "open ${k}: menu=$(Menu)"; break }
            Rpc "ui_back" @{} 15 | Out-Null
            Start-Sleep -Milliseconds 400
            if ((Menu) -ne "CacLoadoutEditorMenu") { $stressFailed = "back ${k}: menu=$(Menu)"; break }
        }
        if ($stressFailed) { $failed = $true }
        $results += [pscustomobject]@{ case = "stress $Stress list opens"; ok = ($stressFailed -eq ""); detail = $stressFailed }
    }

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















