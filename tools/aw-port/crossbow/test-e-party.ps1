# crossbow party-list check - moved from _migration\archive\mwx-debug\crossbow\test-e-party.ps1 on 27 Nov 2026.
$ErrorActionPreference = 'Continue'
$game = 'C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered'
$out = 'C:\Games\cod-hwm\_migration\archive\mwx-debug\crossbow'
$shots = Join-Path $out 'screenshots'
. 'C:\Games\cod-hwm\_migration\archive\mwx-debug\phase3\lib.ps1'
Add-Type -AssemblyName System.Drawing
function RpcM($m, $p) { $b = @{ method = $m }; if ($p) { $b.params = $p }; try { return (Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:27099/rpc' -Body ($b | ConvertTo-Json -Compress -Depth 8) -ContentType 'application/json' -TimeoutSec 8) } catch { return $null } }
function GameProcM { return (Get-Process mwx -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Sort-Object StartTime -Descending | Select-Object -First 1) }
function ShotM($path) { $p = GameProcM; if (-not $p) { return $false }; $r = New-Object W+RECT; [void][W]::GetWindowRect($p.MainWindowHandle, [ref]$r); $w = $r.R - $r.L; $h = $r.B - $r.T; $bmp = New-Object System.Drawing.Bitmap $w, $h; $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $h)); $g.Dispose(); $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); return $true }
[void](Focus-Game); Start-Sleep -Milliseconds 500
[void](Click 280 196)
"clicked play online"
Start-Sleep -Seconds 7
[void](ShotM (Join-Path $shots '07-play-online.png'))
$s = RpcM 'status' $null
if ($s) { $s.result | ConvertTo-Json -Depth 3 }
