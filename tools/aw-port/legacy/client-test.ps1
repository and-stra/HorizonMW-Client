$ErrorActionPreference = 'Continue'
$game = 'C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered'
$out = 'C:\Games\cod-hwm\_migration\archive\mwx-debug\aw-port'
. 'C:\Games\cod-hwm\_migration\archive\mwx-debug\phase3\lib.ps1'
Add-Type -AssemblyName System.Drawing
function RpcC($m, $p) { $b = @{ method = $m }; if ($p) { $b.params = $p }; try { return Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:27099/rpc' -Body ($b | ConvertTo-Json -Compress -Depth 8) -ContentType 'application/json' -TimeoutSec 5 } catch { return $null } }
function GameProc { return (Get-Process mwx -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Sort-Object StartTime -Descending | Select-Object -First 1) }
function ShotFast($path) {
    $p = GameProc
    if (-not $p) { return $false }
    $r = New-Object W+RECT
    [void][W]::GetWindowRect($p.MainWindowHandle, [ref]$r)
    $w = $r.R - $r.L; $h = $r.B - $r.T
    if ($w -le 0 -or $h -le 0) { return $false }
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $h))
    $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return $true
}
$ps = Start-Process -FilePath "$game\mwx.exe" -WorkingDirectory $game -ArgumentList @('+set','mwx_gsc_print','1') -PassThru -RedirectStandardOutput (Join-Path $out 'client2-console.txt') -RedirectStandardError (Join-Path $out 'client2-console.err.txt')
"client pid=$($ps.Id)"
$ready = $false
for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Seconds 3; $d = RpcC 'get_dvar' @{ name = 'ui_gametype' }; if ($d -and $d.result -and $d.result.value) { $ready = $true; "ready after $($i*3)s"; break } }
if (-not $ready) { "not ready"; exit 1 }
[void](RpcC 'command' @{ command = 'set g_gametype war' })
[void](RpcC 'command' @{ command = 'map mp_greenband' })
"map requested"
$ingame = $false
for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Seconds 4; $s = RpcC 'status' $null; if ($s -and $s.result) { if ($s.result.map -eq 'mp_greenband') { $ingame = $true; "map after $($i*4)s"; break } } }
[void](Focus-Game)
$dir = Join-Path $out 'shots'
New-Item -ItemType Directory -Force $dir | Out-Null
for ($i = 0; $i -lt 30; $i++) { [void](ShotFast (Join-Path $dir ("shot-{0:D2}.png" -f $i))); Start-Sleep -Seconds 2 }
$c = RpcC 'console' @{ lines = 600 }
if ($c) { $c.result | Set-Content (Join-Path $out 'client2-console-last.txt'); "console: $($c.result.Count)" }
$s = RpcC 'status' $null
if ($s) { $s.result | ConvertTo-Json -Depth 4 }
[void](RpcC 'command' @{ command = 'quit' })
Start-Sleep -Seconds 6
$p = GameProc; if ($p) { Stop-Process -Id $p.Id -Force }
"client test done"
