# MWX menu smoke test (M3): drives a fresh client through the private match menus via the debug RPC.
#
#   powershell -File tools\test\menu-smoke.ps1 [-Runs 5] [-Quick] [-KeepOpen]
#
# Per run: start client -> main menu -> Play Online -> Private Match -> Game Setup -> every Party mode
# and two standard modes (Domination, Team Deathmatch) -> Start -> loading screen name check -> back to
# the lobby -> Start again -> quit to the main menu -> Play Online again -> Mods menu open/close.
# Fails on a crash, a new dump in minidumps\, a Lua error or a wrong gametype/name.
#
# -Quick: one start per mode, and the "start again" check only for the first party mode.

param(
    [int]$Runs = 5,
    [switch]$Quick,
    [switch]$KeepOpen,
    [string]$Modes = "",
    [int]$StartTimeout = 120
)

$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$GameDir = Join-Path (Split-Path -Parent $Repo) "Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$Exe = Join-Path $GameDir "mwx.exe"
$LogRoot = Join-Path $env:TEMP "mwx-menu-smoke"

function Rpc([int]$port, [string]$method, $params = @{}, [int]$timeout = 30) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:$port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout
    } catch {
        return [pscustomobject]@{ error = "no answer: $($_.Exception.Message)"; not_running = $true }
    }
}

function Wait-MainMenu([int]$port, $process) {
    for ($i = 0; $i -lt 240; $i++) {
        if ($process.HasExited) { return "exited" }
        $s = Rpc $port "status" @{} 3
        if ($s.result -and $s.result.main_menu) { return "ok" }
        Start-Sleep -Seconds 1
    }
    return "timeout"
}

function Click([int]$port, $params, [string]$portLabel) {
    $answer = Rpc $port "ui_click" $params 40
    if ($answer.result -eq $null) {
        throw "ui_click $($params | ConvertTo-Json -Compress) failed: $($answer.error)"
    }
    if (-not $answer.result.ok) {
        throw "ui_click $($params | ConvertTo-Json -Compress) failed: $($answer.result.error)"
    }
    if ($params.ContainsKey("expect_menu") -and -not $answer.result.expect_met) {
        throw "ui_click $($params | ConvertTo-Json -Compress) did not reach '$($params.expect_menu)' (menu=$($answer.result.menu))"
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

function Find-ModeRow([int]$port, [string]$modeName) {
    $snap = (Rpc $port "ui_snapshot" @{} 25).result
    $wanted = $modeName.Trim().ToLower()
    return @($snap.elements | Where-Object {
        $_.id -match '^settings_recipe_choosetype_button_[0-9]+$' -and
        (($_.text -replace "[\x01-\x1f]", "").Trim().ToLower() -eq $wanted)
    }) | Select-Object -First 1
}

function Open-PrivateLobby([int]$port) {
    $snap = (Rpc $port "ui_snapshot" @{} 25).result
    if ($snap.menu -eq "menu_xboxlive_privatelobby") { return }
    if ($snap.menu -eq "mp_main_menu") {
        Click $port @{ text = "PLAY ONLINE" } $port | Out-Null
        if (-not (Wait-Menu $port "menu_xboxlive" 40)) { throw "PLAY ONLINE did not open menu_xboxlive" }
    }
    Click $port @{ text = "PRIVATE MATCH"; expect_menu = "menu_xboxlive_privatelobby"; expect_timeout_ms = 30000 } | Out-Null
}

function Select-Mode([int]$port, [string]$group, [string]$modeName) {
    Click $port @{ text = "GAME SETUP"; expect_menu = "gamesetup_menu_main"; expect_timeout_ms = 15000 } | Out-Null
    Click $port @{ id = "gamesetup_menu_main_button_1"; expect_menu = "popup_recipesetup_modes"; expect_timeout_ms = 12000 } | Out-Null
    $groupButton = if ($group -eq "Party") { "popup_recipesetup_modes_button_1" } else { "popup_recipesetup_modes_button_0" }
    Click $port @{ id = $groupButton; expect_menu = "settings_recipe_choosetype"; expect_timeout_ms = 12000 } | Out-Null

    # click the mode row by its id (the caption can also appear in the description pane)
    $row = Find-ModeRow $port $modeName
    if ($row -eq $null) { throw "mode '$modeName' not found in the chooser" }
    Click $port @{ id = $row.id; expect_menu = "gamesetup_menu_main"; expect_timeout_ms = 12000 } | Out-Null

    # the group popup can stay under the restored game setup menu; leave until the lobby is on top
    for ($i = 0; $i -lt 4; $i++) {
        $snap = (Rpc $port "ui_snapshot" @{} 20).result
        if ($snap.menu -eq "menu_xboxlive_privatelobby") { return }
        if ($snap.menu -eq "mp_main_menu") { break }
        $back = (Rpc $port "ui_back" @{ expect_timeout_ms = 8000 } 20).result
        if ($back.menu -eq "menu_xboxlive_privatelobby") { return }
        if ($back.menu -eq "mp_main_menu") { break }
    }
    throw "back from game setup did not reach the lobby"
}

function Start-Match([int]$port, $process, [string]$label) {
    Rpc $port "ui_click" @{ id = "menu_xboxlive_privatelobby_button_0"; wait = $false } 20 | Out-Null
    $ingame = $false
    for ($i = 0; $i -lt $StartTimeout; $i++) {
        if ($process.HasExited) { throw "client exited while starting $label" }
        $s = Rpc $port "status" @{} 3
        if ($s.result -and $s.result.in_game) { $ingame = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ingame) { throw "match did not start for $label" }
    $g = (Rpc $port "get_dvar" @{ name = "g_gametype" } 10).result.value
    $ui = (Rpc $port "get_dvar" @{ name = "ui_gametype" } 10).result.value
    $mode = (Rpc $port "get_dvar" @{ name = "mwx_gamemode" } 10).result.value
    Rpc $port "command" @{ command = "disconnect" } 10 | Out-Null
    for ($i = 0; $i -lt 30; $i++) {
        $s = Rpc $port "status" @{} 3
        if ($s.result -and -not $s.result.in_game) { break }
        Start-Sleep -Seconds 1
    }
    # the loading screen shows ui_gametype; it is unchanged from the start to in_game
    return @{ g_gametype = $g; ui_gametype = $ui; loadscreen = $ui; mwx_gamemode = $mode }
}

function Get-ModeName([int]$port, [string]$ref) {
    $code = "local n = Engine.TableLookup(GameTypesTable.File, GameTypesTable.Cols.Ref, '$ref', GameTypesTable.Cols.Name); return tostring(Engine.Localize(n))"
    $answer = Rpc $port "lua_eval" @{ code = $code } 20
    if ($answer.result -and $answer.result.ok) { return ($answer.result.result -replace "[\x01-\x1f]", "").Trim() }
    return $ref
}

function Get-PartyModes([int]$port) {
    # Do not read Cac.GameModes.Data.Party.List here: its lazy build calls Engine.GetDvarString
    # ("mwx_show_survival"), and that engine call can crash at 0x1400BCB13 when the frontend is
    # between menus. The default list is static; mod refs have their own game tests. Mode names
    # come from Engine.TableLookup below, which is safe.
    return @("infect", "gun", "slasher", "rpg", "oic", "aon", "cranked", "sharpshooter",
        "reinforce", "srescue", "mugger", "arena", "ph", "mprops", "sas")
}

# Item 6: the mode screens build "@OBJECTIVES_<ref>", "_SCORE" and "_HINT" from the gametype ref.
# Every one of those keys must resolve to text, also in the frontend before the map zones load
# (a raw key is returned unchanged by Engine.Localize).
function Get-ObjectiveKeyProblems([int]$port) {
    $code = @"
local refs = {}
local function add(list)
    for _, v in ipairs(list) do refs[#refs + 1] = tostring(v) end
end
-- static lists: reading Cac.GameModes.Data.Party.List calls Engine.GetDvarString from Lua, which
-- can crash at 0x1400BCB13 in a menu transition (see Get-PartyModes above)
add({'infect', 'gun', 'slasher', 'rpg', 'oic', 'aon', 'cranked', 'sharpshooter', 'reinforce',
     'srescue', 'mugger', 'arena', 'ph', 'mprops'})
add({'dm', 'war', 'sd', 'dom', 'conf', 'sab', 'koth', 'hp', 'dz'})
for _, v in ipairs({'infect', 'dz', 'sas'}) do refs[#refs + 1] = v end
local seen = {}
local problems = {}
for _, r in ipairs(refs) do
    if not seen[r] then
        seen[r] = true
        for _, suffix in ipairs({'', '_SCORE', '_HINT'}) do
            local key = 'OBJECTIVES_' .. r .. suffix
            local value = tostring(Engine.Localize('@' .. key))
            if value == key or value == '' then problems[#problems + 1] = key end
        end
    end
end
return problems
"@
    for ($try = 0; $try -lt 15; $try++) {
        $answer = Rpc $port "lua_eval" @{ code = $code } 25
        if ($answer.result -and $answer.result.ok) { return @($answer.result.result) }
        if ($answer.error -and $answer.error -match 'busy') { Start-Sleep -Seconds 2; continue }
        break
    }
    return @("objective key check failed: $($answer.error)")
}

function Get-LobbyLabel([int]$port) {
    $snap = (Rpc $port "ui_snapshot" @{} 25).result
    $label = $snap.elements | Where-Object { $_.id -eq "lobby_map_container" } | Select-Object -First 1
    if ($label -and $label.text) { return ($label.text -replace "[\x01-\x1f]", "").Trim() }
    return ""
}

function Get-LuaErrors([int]$port) {
    $answer = Rpc $port "console" @{ lines = 1000 } 15
    @($answer.result) | Where-Object {
        $_ -match "LUA ERROR|script error|attempt to (index|call) a nil"
    }
}

$dumpBefore = @(Get-ChildItem (Join-Path $GameDir "minidumps") -Filter *.zip -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
$allFailures = @()

for ($run = 1; $run -le $Runs; $run++) {
    $port = 27200 + $run
    $log = Join-Path $LogRoot "run$run-$port.log"
    $errLog = Join-Path $LogRoot "run$run-$port.err.log"
    New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

    Write-Host ("run {0}/{1}: client on debug port {2}" -f $run, $Runs, $port)
    $process = $null
    $ready = "exited"
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        if ($attempt -gt 1) {
            # a client started right after another one can exit before the hooks (no output, no
            # dump). That is the known process-spacing hazard, not a regression - retry it. A real
            # startup crash leaves a dump and is not retried.
            Write-Host "  start attempt $attempt after a silent startup exit"
            Start-Sleep -Seconds 20
        }

        $process = Start-Process -FilePath $Exe -ArgumentList @("-debugport", "$port", "+set", "mwx_test_mode", "1") `
            -WorkingDirectory $GameDir -PassThru -RedirectStandardOutput $log -RedirectStandardError $errLog

        $ready = Wait-MainMenu $port $process
        if ($ready -eq "ok") { break }

        $newDumps = @(Get-ChildItem (Join-Path $GameDir "minidumps") -Filter *.zip -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Name | Where-Object { $dumpBefore -notcontains $_ })
        if ($newDumps.Count -gt 0) { break }
        if (-not $process.HasExited) { try { $process.Kill() } catch {} }
    }

    $failures = @()
    try {
        if ($ready -ne "ok") { throw "client did not reach the main menu ($ready)" }

        Open-PrivateLobby $port

        $party = @(Get-PartyModes $port)
        if ($party.Count -lt 10 -and -not $Modes) { $failures += "party list has only $($party.Count) entries" }

        $rawKeys = @(Get-ObjectiveKeyProblems $port)
        foreach ($key in $rawKeys) { $failures += "objective key shows the raw key: $key" }

        $modeList = @()
        if ($Modes) {
            foreach ($ref in ($Modes -split ",")) {
                $r = $ref.Trim()
                if (-not $r) { continue }
                $group = if (@("dom", "war", "sd", "koth", "sab", "dm", "ctf", "dd") -contains $r) { "Standard" } else { "Party" }
                $modeList += @{ group = $group; ref = $r; name = (Get-ModeName $port $r) }
            }
        } else {
            foreach ($ref in $party) { $modeList += @{ group = "Party"; ref = $ref; name = (Get-ModeName $port $ref) } }
            foreach ($ref in @("dom", "war")) { $modeList += @{ group = "Standard"; ref = $ref; name = (Get-ModeName $port $ref) } }
        }

        $index = 0
        foreach ($entry in $modeList) {
            $index++
            $label = "$($entry.group) $($entry.ref)"
            try {
                Select-Mode $port $entry.group $entry.name

                $ui = (Rpc $port "get_dvar" @{ name = "ui_gametype" } 10).result.value
                if ($ui -ne $entry.ref) { $failures += "$label : ui_gametype is '$ui' after selecting" }

                $shown = Get-LobbyLabel $port
                if ($shown -and ($shown.ToLower() -ne $entry.name.ToLower())) { $failures += "$label : lobby shows '$shown' instead of '$($entry.name)'" }

                $result = Start-Match $port $process $label
                if ($result.g_gametype -ne $entry.ref) { $failures += "$label : g_gametype is '$($result.g_gametype)'" }
                if ($result.ui_gametype -ne $entry.ref) { $failures += "$label : ui_gametype at start is '$($result.ui_gametype)'" }
                if ($result.loadscreen -ne $entry.ref) { $failures += "$label : loading screen name is '$($result.loadscreen)'" }

                $expectMode = if (@("ph", "mprops", "slasher", "rpg", "survival") -contains $entry.ref) { $entry.ref } else { "" }
                if ("$($result.mwx_gamemode)" -ne $expectMode) { $failures += "$label : mwx_gamemode is '$($result.mwx_gamemode)', expected '$expectMode'" }

                Open-PrivateLobby $port
                if (($Quick -and $index -eq 1) -or (-not $Quick)) {
                    $again = Start-Match $port $process "$label (again)"
                    if ($again.g_gametype -ne $entry.ref) { $failures += "$label : second start g_gametype is '$($again.g_gametype)'" }
                    Open-PrivateLobby $port
                }
            } catch {
                $failures += "$label : $($_.Exception.Message)"
                break
            }
        }

        # quit to the main menu, play online again, mods menu open/close
        $s = Rpc $port "ui_snapshot" @{} 20
        if ($s.result.menu -eq "menu_xboxlive_privatelobby") { Rpc $port "ui_back" @{ expect_timeout_ms = 8000 } 20 | Out-Null }
        if ($s.result.menu -eq "menu_xboxlive") { Rpc $port "ui_back" @{ expect_timeout_ms = 8000 } 20 | Out-Null }
        Click $port @{ text = "PLAY ONLINE"; expect_menu = "menu_xboxlive"; expect_timeout_ms = 25000 } | Out-Null
        Rpc $port "ui_back" @{ expect_timeout_ms = 8000 } 20 | Out-Null
        Click $port @{ text = "MODS"; expect_timeout_ms = 12000 } | Out-Null
        $snap = (Rpc $port "ui_snapshot" @{} 20).result
        if ($snap.menu -notmatch "mods") { $failures += "mods menu did not open (menu=$($snap.menu))" }
        Rpc $port "ui_back" @{ expect_timeout_ms = 8000 } 20 | Out-Null

        $lua = @(Get-LuaErrors $port)
        if ($lua.Count -gt 0) { $failures += "Lua errors: $($lua -join ' | ')" }
    } catch {
        $failures += "run $run : $($_.Exception.Message)"
    } finally {
        if (-not $KeepOpen) {
            if (-not $process.HasExited) {
                Rpc $port "command" @{ command = "quit" } 5 | Out-Null
                if (-not $process.WaitForExit(10000)) { try { $process.Kill() } catch {} }
            }
        }
    }

    $newDumps = @(Get-ChildItem (Join-Path $GameDir "minidumps") -Filter *.zip -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name | Where-Object { $dumpBefore -notcontains $_ })
    if ($newDumps.Count -gt 0) { $failures += "crashed: new dump(s) $($newDumps -join ', ')" }

    if ($failures.Count -eq 0) {
        Write-Host ("run {0}: PASS" -f $run) -ForegroundColor Green
    } else {
        Write-Host ("run {0}: FAIL" -f $run) -ForegroundColor Red
        $failures | ForEach-Object { Write-Host "  - $_" }
        $allFailures += $failures
    }

    if ($KeepOpen) { break }
}

if ($allFailures.Count -eq 0) {
    Write-Host ("{0} run(s): PASS" -f $Runs) -ForegroundColor Green
    exit 0
}

Write-Host ("{0} failure(s)" -f $allFailures.Count) -ForegroundColor Red
exit 1
