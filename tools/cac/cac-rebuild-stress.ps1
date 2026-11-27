# CAC list rebuild stress (F4 limit) - moved from _migration\archive\mwx-debug\cac-bisect\cac-rebuild-stress.ps1 on 27 Nov 2026.
# Stress the CAC list rebuilds: open/close a category list N times in one client session.
#   powershell -File cac-rebuild-stress.ps1 [-Max 60] [-Category Primary] [-Port 27295]
# Reports the rebuild at which the LUI errors (registerAnimationState / "Error processing event"),
# the menu state, and the console tail.
param(
    [int]$Max = 60,
    [string]$Category = "Primary",
    [int]$Port = 27295,
    [switch]$GC
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
function Wait-Menu([string]$want, [int]$seconds = 60) {
    for ($i = 0; $i -lt ($seconds * 2); $i++) {
        if ((Menu) -eq $want) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

$p = Start-Process -FilePath $Exe -ArgumentList @("-debugport", "$Port", "+set", "mwx_test_mode", "1") -WorkingDirectory $GameDir -PassThru
$menu = $false
for ($i = 0; $i -lt 240; $i++) {
    if ($p.HasExited) { throw "client exited during startup" }
    $s = Rpc "status" @{}
    if ($s.result -and $s.result.main_menu) { $menu = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $menu) { throw "no main menu" }
Rpc "ui_click" @{ text = "PLAY ONLINE"; wait = $false } 10 | Out-Null
if (-not (Wait-Menu "menu_xboxlive" 90)) { throw "no lobby" }
Start-Sleep -Seconds 2
Rpc "ui_click" @{ text = "CREATE A CLASS"; wait = $false } 10 | Out-Null
if (-not (Wait-Menu "CacMenu" 30)) { throw "no CacMenu" }
Start-Sleep -Milliseconds 800
Rpc "ui_click" @{ id = "cac_class_button_0"; wait = $false } 10 | Out-Null
if (-not (Wait-Menu "CacLoadoutEditorMenu" 30)) { throw "no class editor" }
Start-Sleep -Milliseconds 800

$catId = if ($Category -eq "Primary") { "CacLoadoutEditorMenu_optionsList_Primary_button_0" } else { "CacLoadoutEditorMenu_optionsList_Secondary_button_0" }
$failedAt = 0
$detail = ""
for ($n = 1; $n -le $Max; $n++) {
    $c = Rpc "ui_click" @{ id = $catId; expect_timeout_ms = 20000 } 30
    Start-Sleep -Milliseconds 500
    $m = Menu
    if ($m -ne "CacDetails") {
        $failedAt = $n; $detail = "open: menu=$m"; break
    }
    Rpc "ui_back" @{} 15 | Out-Null
    if ($GC) { Rpc "lua_eval" @{ code = "collectgarbage('collect')" } 10 | Out-Null }
    Start-Sleep -Milliseconds 500
    $m = Menu
    if ($m -ne "CacLoadoutEditorMenu") {
        $failedAt = $n; $detail = "back: menu=$m"; break
    }
    $lines = @((Rpc "console" @{ lines = 60 } 10).result)
    $err = @($lines | Where-Object { $_ -match 'Error processing event|registerAnimationState' })
    if ($err.Count -gt 0) {
        $failedAt = $n; $detail = ($err -join " | "); break
    }
}
"$Category`: failed at rebuild $failedAt of $Max; $detail"
$lines = @((Rpc "console" @{ lines = 200 } 10).result)
$lines | Select-Object -Last 6
Rpc "command" @{ command = "quit" } 10 | Out-Null
Start-Sleep -Seconds 3
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
if ($failedAt -ne 0) { exit 1 }


