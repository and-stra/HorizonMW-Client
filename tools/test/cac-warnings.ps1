# Count CAC "missing asset / default material" warnings for the current zone set.
#   powershell -File tools\test\cac-warnings.ps1 -Label e
# The compare run: switch zones with _migration\archive\mwx-debug\cac-bisect\variant.ps1 -Variant a, run it as
# -Label a, then variant.ps1 -Variant e.
param(
    [string]$Label = "run",
    [int]$Port = 27280
)
$ErrorActionPreference = "Stop"
$GameDir = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$Exe = Join-Path $GameDir "mwx.exe"
$OutDir = Join-Path $GameDir "mwx-logs"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Rpc([string]$method, $params = @{}, [int]$timeout = 30) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 10 -Compress
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout }
    catch { return [pscustomobject]@{ error = $_.Exception.Message } }
}
function Menu { return (Rpc "ui_snapshot" @{} 20).result.menu }
function Click($params) { Rpc "ui_click" $params 40 | Out-Null; Start-Sleep -Milliseconds 700 }
function Shot([string]$n) { Rpc "screenshot" @{ path = (Join-Path $OutDir ("cac-warn-" + $Label + "-" + $n + ".png")) } 30 | Out-Null }

$p = Start-Process -FilePath $Exe -ArgumentList @("-debugport", "$Port", "+set", "mwx_test_mode", "1") -WorkingDirectory $GameDir -PassThru
for ($i = 0; $i -lt 240; $i++) { if ($p.HasExited) { throw "client exited" }; $s = Rpc "status" @{} 3; if ($s.result -and $s.result.main_menu) { break }; Start-Sleep -Seconds 1 }
Click @{ text = "PLAY ONLINE"; expect_menu = "menu_xboxlive"; expect_timeout_ms = 40000 }
Start-Sleep -Seconds 3
Click @{ text = "CREATE A CLASS"; expect_menu = "CacMenu"; expect_timeout_ms = 25000 }
Start-Sleep -Milliseconds 800
Click @{ id = "cac_class_button_0"; expect_timeout_ms = 20000 }
Start-Sleep -Milliseconds 800
Click @{ id = "CacLoadoutEditorMenu_optionsList_Primary_button_0"; expect_timeout_ms = 20000 }
Start-Sleep -Seconds 3
Shot "assault"
Rpc "ui_back" @{} 15 | Out-Null; Start-Sleep -Milliseconds 800
Click @{ id = "CacLoadoutEditorMenu_optionsList_Secondary_button_0"; expect_timeout_ms = 20000 }
Start-Sleep -Seconds 3
Shot "secondary"
Rpc "input" @{ action = "press"; command = "+moveright"; ms = 120 } 10 | Out-Null
Start-Sleep -Seconds 2
Shot "secondary2"
Rpc "ui_back" @{} 15 | Out-Null; Start-Sleep -Milliseconds 800
Rpc "ui_click" @{ id = "CacLoadoutEditorMenu_optionsList_Primary_button_0"; expect_timeout_ms = 15000 } 30 | Out-Null
Rpc "ui_back" @{} 15 | Out-Null; Start-Sleep -Milliseconds 800
Click @{ id = "optionsList_Primary_option_3"; expect_timeout_ms = 15000 }
Start-Sleep -Seconds 3
Shot "camo"
Rpc "ui_back" @{} 15 | Out-Null; Start-Sleep -Milliseconds 800
Click @{ id = "optionsList_Primary_option_1"; expect_timeout_ms = 15000 }
Start-Sleep -Seconds 3
Shot "attachments"

$lines = @((Rpc "console" @{ lines = 1000 } 20).result)
$hits = @($lines | Where-Object { $_ -match 'missing|default material|Create2DTexture|Couldn''t find|Missing material' })
$hits | Set-Content (Join-Path $OutDir ("cac-warnings-" + $Label + ".txt")) -Encoding UTF8
"$Label`: $($hits.Count) warning(s) in $($lines.Count) console lines"
$hits | Select-Object -First 20

Rpc "command" @{ command = "quit" } 10 | Out-Null
Start-Sleep -Seconds 3
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }

