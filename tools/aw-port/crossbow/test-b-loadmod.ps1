# crossbow mod load check - moved from _migration\archive\mwx-debug\crossbow\test-b-loadmod.ps1 on 27 Nov 2026.
$ErrorActionPreference = 'Continue'
$game = 'C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered'
$out = 'C:\Games\cod-hwm\_migration\archive\mwx-debug\crossbow'
$shots = Join-Path $out 'screenshots'
New-Item -ItemType Directory -Force $shots | Out-Null
. 'C:\Games\cod-hwm\_migration\archive\mwx-debug\phase3\lib.ps1'
Add-Type -AssemblyName System.Drawing

function RpcM($m, $p) {
    $b = @{ method = $m }
    if ($p) { $b.params = $p }
    try { return (Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:27099/rpc' -Body ($b | ConvertTo-Json -Compress -Depth 8) -ContentType 'application/json' -TimeoutSec 8) } catch { return $null }
}
function GameProcM { return (Get-Process mwx -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Sort-Object StartTime -Descending | Select-Object -First 1) }
function ShotM($path) {
    $p = GameProcM
    if (-not $p) { return $false }
    $r = New-Object W+RECT
    [void][W]::GetWindowRect($p.MainWindowHandle, [ref]$r)
    $w = $r.R - $r.L; $h = $r.B - $r.T
    if ($w -le 0 -or $h -le 0) { return $false }
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $h))
    $g.Dispose(); $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    return $true
}

$old = GameProcM
if (-not $old) { "no game"; exit 1 }
"old pid=$($old.Id)"
[void](Focus-Game)
Start-Sleep -Milliseconds 500
[void](Click 280 215)
"clicked Sticks and Stones"
$new = $null
for ($i = 0; $i -lt 90; $i++) { Start-Sleep -Seconds 2; $new = GameProcM; if ($new -and $new.Id -ne $old.Id) { break } }
"new pid=$($new.Id)"
$ok = $false
for ($i = 0; $i -lt 120; $i++) { Start-Sleep -Seconds 2; $s = RpcM 'status' $null; if ($s -and $s.result -and $s.result.main_menu -eq $true) { $ok = $true; break } }
"menu=$ok after $($i*2)s"
[void](Focus-Game)
Start-Sleep -Seconds 3
[void](ShotM (Join-Path $shots '03-mod-loaded-menu.png'))
$c = RpcM 'console' @{ lines = 1000 }
if ($c) {
    $c.result | Set-Content (Join-Path $out 'console-after-mod-load.txt')
    $c.result | Where-Object { $_ -match '\[mods\]|Loading fastfile|iw5_exocrossbow|error|Error' } | Set-Content (Join-Path $out 'console-mod-lines.txt')
    "console lines=$($c.result.Count)"
}
$s = RpcM 'status' $null
if ($s) { $s.result | ConvertTo-Json -Depth 3 }
