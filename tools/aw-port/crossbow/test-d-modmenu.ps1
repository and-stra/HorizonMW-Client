# crossbow mod menu check - moved from _migration\archive\mwx-debug\crossbow\test-d-modmenu.ps1 on 27 Nov 2026.
$ErrorActionPreference = 'Continue'
$game = 'C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered'
$out = 'C:\Games\cod-hwm\_migration\archive\mwx-debug\crossbow'
$shots = Join-Path $out 'screenshots'
. 'C:\Games\cod-hwm\_migration\archive\mwx-debug\phase3\lib.ps1'
Add-Type -AssemblyName System.Drawing
function RpcM($m, $p) { $b = @{ method = $m }; if ($p) { $b.params = $p }; try { return (Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:27099/rpc' -Body ($b | ConvertTo-Json -Compress -Depth 8) -ContentType 'application/json' -TimeoutSec 8) } catch { return $null } }
function GameProcM { return (Get-Process mwx -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Sort-Object StartTime -Descending | Select-Object -First 1) }
function ShotM($path) { $p = GameProcM; if (-not $p) { return $false }; $r = New-Object W+RECT; [void][W]::GetWindowRect($p.MainWindowHandle, [ref]$r); $w = $r.R - $r.L; $h = $r.B - $r.T; $bmp = New-Object System.Drawing.Bitmap $w, $h; $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $h)); $g.Dispose(); $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); return $true }
$p = GameProcM
"pid=$($p.Id)"
$ci = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)"
"cmdline=$($ci.CommandLine)"
$ok = $false
for ($i = 0; $i -lt 120; $i++) { Start-Sleep -Seconds 2; $s = RpcM 'status' $null; if ($s -and $s.result -and $s.result.main_menu -eq $true) { $ok = $true; break } }
"menu=$ok after $($i*2)s"
[void](Focus-Game); Start-Sleep -Seconds 3
[void](ShotM (Join-Path $shots '06-mod-menu.png'))
$c = RpcM 'console' @{ lines = 1000 }
if ($c) { $c.result | Set-Content (Join-Path $out 'console-after-mod-load.txt'); $c.result | Where-Object { $_ -match '\[mods\]|Loading fastfile|iw5_exocrossbow|error|Error' } | Set-Content (Join-Path $out 'console-mod-lines.txt'); "console lines=$($c.result.Count)" }
$s = RpcM 'status' $null
if ($s) { $s.result | ConvertTo-Json -Depth 3 }
