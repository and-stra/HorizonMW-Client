# walk the CAC category tabs - moved from _migration\archive\mwx-debug\mwr-weapons\cac-categories.ps1 on 27 Nov 2026.
# B: open Create-a-Class, enter a class, dump the loadout editor elements (to find the category
# tabs), screenshot it. Second step of the CAC check (see cac-inspect.ps1).
param(
    [int]$Port = 27962,
    [string]$OutDir = "C:\Games\cod-hwm\_migration\archive\mwx-debug\mwr-weapons",
    [int]$ClassIndex = 0
)
$ErrorActionPreference = "Stop"
$game = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$exe = Join-Path $game "mwx.exe"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Rpc([int]$port, [string]$method, $params = @{}, [int]$timeout = 30) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout }
    catch { return [pscustomobject]@{ error = "no answer: $($_.Exception.Message)" } }
}
function Click([int]$port, $params) {
    $answer = Rpc $port "ui_click" $params 40
    if ($answer.result -eq $null) { throw "ui_click failed: $($answer.error)" }
    if (-not $answer.result.ok) { throw "ui_click failed: $($answer.result.error)" }
    return $answer.result
}
function Wait-Menu([int]$port, [string]$name, [int]$seconds = 30) {
    for ($i = 0; $i -lt ($seconds * 2); $i++) {
        $snap = (Rpc $port "ui_snapshot" @{} 20).result
        if ($snap.menu -eq $name) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

$log = Join-Path $env:TEMP "mwx-cac-categories-$Port.log"
$p = Start-Process -FilePath $exe -ArgumentList @("-debugport", "$Port", "+set", "mwx_test_mode", "1") `
    -WorkingDirectory $game -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"

try {
    $up = $false
    for ($i = 0; $i -lt 240; $i++) {
        if ($p.HasExited) { throw "client exited ($($p.ExitCode))" }
        $s = Rpc $Port "status" @{} 3
        if ($s.result -and $s.result.main_menu) { $up = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $up) { throw "no main menu" }
    Start-Sleep -Seconds 3

    # main menu -> Play Online -> Private Match -> Create a Class
    $snap = (Rpc $Port "ui_snapshot" @{} 25).result
    if ($snap.menu -eq "menu_xboxlive_privatelobby") {
        # already there
    } elseif ($snap.menu -eq "mp_main_menu") {
        Click $Port @{ text = "PLAY ONLINE" } | Out-Null
        if (-not (Wait-Menu $Port "menu_xboxlive" 40)) { throw "PLAY ONLINE did not open menu_xboxlive" }
    }
    if (-not (Wait-Menu $Port "menu_xboxlive_privatelobby" 3)) {
        Click $Port @{ text = "PRIVATE MATCH"; expect_menu = "menu_xboxlive_privatelobby"; expect_timeout_ms = 30000 } | Out-Null
    }
    $create = @(((Rpc $Port "ui_snapshot" @{} 25).result).elements | Where-Object { $_.text -and (($_.text -replace "[\x01-\x1f]", "").Trim() -match "CREATE A CLASS") }) | Select-Object -First 1
    if (-not $create) { throw "no CREATE A CLASS element" }
    Click $Port @{ id = $create.id } | Out-Null
    Start-Sleep -Seconds 2

    $classButton = "cac_class_button_$ClassIndex"
    Click $Port @{ id = $classButton } | Out-Null
    Start-Sleep -Seconds 3

    # does the CAC data contain every MWR ref (the whitelist/customweapons rows)?
    $refs = @(
        "h1_g3", "h1_m14", "h1_xmlar", "h1_aprast", "h1_augast", "h1_febsmg", "h1_aprsmg", "h1_augsmg",
        "h1_junlmg", "h1_kam12", "h1_junsnp", "h1_aprpst", "h1_augpst",
        "h1_meleeapr1", "h1_meleeapr2", "h1_meleeapr3", "h1_meleeapr4",
        "h1_meleeaug1", "h1_meleeaug2", "h1_meleeaug3", "h1_meleeaug4",
        "h1_meleebayonet", "h1_meleeblade", "h1_meleebottle",
        "h1_meleefeb1", "h1_meleefeb2", "h1_meleefeb3", "h1_meleefeb4", "h1_meleefeb5",
        "h1_meleegladius", "h1_meleehatchet", "h1_meleeicepick",
        "h1_meleejun1", "h1_meleejun2", "h1_meleejun3", "h1_meleejun4", "h1_meleejun5",
        "h1_meleejun6", "h1_meleepaddle", "h1_meleeshovel", "h1_meleesickle"
    )
    $luaRefs = ($refs | ForEach-Object { "'$_'" }) -join ","
    $code = @"
local refs = { $luaRefs }
local seen = {}
for cat, sub in pairs(Cac.Weapons) do
    for k, list in pairs(sub) do
        if type(list) == "table" then
            for _, item in ipairs(list) do
                local r = item[1]
                if r then seen[r] = tostring(cat) .. "/" .. tostring(k) end
            end
        end
    end
end
local found, missing = 0, {}
for _, r in ipairs(refs) do
    if seen[r] then found = found + 1 else missing[#missing + 1] = r end
end
return found .. "|" .. tostring(#refs) .. "|" .. table.concat(missing, ",")
"@
    $eval = Rpc $Port "lua_eval" @{ code = $code } 30
    if ($eval.result -and $eval.result.ok) {
        $parts = "$($eval.result.result)".Split("|")
        Write-Host ("CAC data: {0}/{1} MWR refs found; missing: {2}" -f $parts[0], $parts[1], $parts[2])
        Add-Content -Path (Join-Path $OutDir "cac-check.txt") -Value ("{0:yyyy-MM-dd HH:mm} CAC data: {1}/{2} MWR refs; missing: {3}" -f (Get-Date), $parts[0], $parts[1], $parts[2])
    } else {
        Write-Host ("CAC data eval failed: $($eval.error) / $($eval.result.error)")
    }

    $snap2 = (Rpc $Port "ui_snapshot" @{} 25).result
    $snap2 | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $OutDir "cac-snapshot-class.json") -Encoding UTF8
    Rpc $Port "screenshot" @{ name = "cac-class-$ClassIndex" } 20 | Out-Null
    Write-Host ("menu: {0}" -f $snap2.menu)

    $categories = @(
        @{ name = "primary";   id = "CacLoadoutEditorMenu_optionsList_Primary_button_0" },
        @{ name = "secondary"; id = "CacLoadoutEditorMenu_optionsList_Secondary_button_0" },
        @{ name = "equipment"; id = "CacLoadoutEditorMenu_CacLoadoutEditorMenu_list_button_0" },
        @{ name = "tactical";  id = "CacLoadoutEditorMenu_CacLoadoutEditorMenu_list_button_1" }
    )
    foreach ($cat in $categories) {
        Click $Port @{ id = $cat.id } | Out-Null
        Start-Sleep -Seconds 2
        $snap3 = (Rpc $Port "ui_snapshot" @{} 25).result
        $snap3 | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $OutDir ("cac-$($cat.name).json")) -Encoding UTF8
        Rpc $Port "screenshot" @{ name = "cac-$($cat.name)" } 20 | Out-Null
        $texts = @($snap3.elements | Where-Object { $_.text -and $_.text.Trim() -ne '' } | ForEach-Object { (($_.text -replace "[\x01-\x1f]", " ").Trim()) })
        Write-Host ("== {0} ({1}): {2}" -f $cat.name, $snap3.menu, ($texts -join " | "))
        # back to the loadout editor for the next category
        Rpc $Port "ui_back" @{ expect_timeout_ms = 8000 } 20 | Out-Null
        Start-Sleep -Seconds 1
    }
} finally {
    if (-not $p.HasExited) {
        Rpc $Port "command" @{ command = "quit" } 5 | Out-Null
        if (-not $p.WaitForExit(10000)) { try { $p.Kill() } catch {} }
    }
}
