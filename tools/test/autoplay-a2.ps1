# autoplay A/B driver - moved from _migration\archive\mwx-debug\autoplay-a2.ps1 on 27 Nov 2026.
$ErrorActionPreference = 'Continue'
$game = 'C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered'
$out  = 'C:\Games\cod-hwm\mwx-debug'
$log  = @()
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class PWin3 {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct RECT { public int L,T,R,B; }
}
'@
Add-Type -AssemblyName System.Drawing
function Rpc($m,$p){ $b=@{method=$m}; if($p){$b.params=$p}; try { return (Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:27099/rpc' -Body ($b|ConvertTo-Json -Compress) -ContentType 'application/json' -TimeoutSec 10) } catch { return $null } }
$sw=[Diagnostics.Stopwatch]::StartNew()
$lobby=$false; $lobbyAt=$null; $menuAt=$null
while ($sw.Elapsed.TotalSeconds -lt 200) {
  Start-Sleep -Seconds 5
  if (-not (Get-Process mwx -ErrorAction SilentlyContinue)) { $log += "process died"; break }
  $r = Rpc 'status' $null
  if ($r -and $r.result) {
    $t=[math]::Round($sw.Elapsed.TotalSeconds,1)
    if ($r.result.main_menu -eq $true -and -not $menuAt) { $menuAt=$t }
    $log += "t=$t main_menu=$($r.result.main_menu) vlobby=$($r.result.virtual_lobby) map=$($r.result.map)"
    if ($r.result.virtual_lobby -eq $true) { $lobby=$true; $lobbyAt=$t; break }
  }
}
$log += "RESULT: main_menu_at=$menuAt virtual_lobby=$lobby at=$lobbyAt"
$p = Get-Process mwx -ErrorAction SilentlyContinue | Select-Object -First 1
if ($p) {
  $r = New-Object PWin3+RECT
  [void][PWin3]::GetWindowRect($p.MainWindowHandle, [ref]$r)
  $w=$r.R-$r.L; $h=$r.B-$r.T
  if ($w -gt 0 -and $h -gt 0) {
    $bmp = New-Object System.Drawing.Bitmap $w,$h
    $g=[System.Drawing.Graphics]::FromImage($bmp); $hdc=$g.GetHdc()
    [void][PWin3]::PrintWindow($p.MainWindowHandle,$hdc,2)
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save((Join-Path $out 'autoplay-a2-lobby.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $log += "screenshot saved"
  }
}
$st = Rpc 'status' $null
if ($st -and $st.result) { $st.result | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $out 'autoplay-a2-status.json') }
$c = Rpc 'console' @{ lines = 500 }
if ($c -and $c.result) {
  $c.result | Set-Content (Join-Path $out 'autoplay-a2-console.txt')
  $hits = ($c.result -split "`n") | Select-String -Pattern 'error|lua' -CaseSensitive:$false
  $hits | ForEach-Object { $_.Line } | Set-Content (Join-Path $out 'autoplay-a2-errors.txt')
  $log += "console hits (error|lua) = $($hits.Count)"
}
[void](Rpc 'command' @{ command='quit' })
$qs=[Diagnostics.Stopwatch]::StartNew()
while ($qs.Elapsed.TotalSeconds -lt 45) { Start-Sleep -Seconds 2; if (-not (Get-Process mwx -ErrorAction SilentlyContinue)) { break } }
if (Get-Process mwx -ErrorAction SilentlyContinue) { Get-Process mwx | Stop-Process -Force }
$log += "quit done"
$log | Set-Content (Join-Path $out 'autoplay-a2.log')
if ($lobby) { "LOBBY_OK at=$lobbyAt" } else { "LOBBY_TIMEOUT" }
