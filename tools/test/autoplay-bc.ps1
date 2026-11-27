# autoplay B/C driver - moved from _migration\archive\mwx-debug\autoplay-bc.ps1 on 27 Nov 2026.
$ErrorActionPreference = 'Continue'
$game = 'C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered'
$out  = 'C:\Games\cod-hwm\mwx-debug'
$log  = @()
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class PWin4 {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct RECT { public int L,T,R,B; }
}
'@
Add-Type -AssemblyName System.Drawing
function Rpc($m,$p){ $b=@{method=$m}; if($p){$b.params=$p}; try { return (Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:27099/rpc' -Body ($b|ConvertTo-Json -Compress) -ContentType 'application/json' -TimeoutSec 10) } catch { return $null } }
function Alive { [bool](Get-Process mwx -ErrorAction SilentlyContinue) }
function Start-Client($extra) {
    $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = ('"' + $game + '\mwx.exe" ' + $extra); CurrentDirectory = $game }
    return $r.ProcessId
}
function Shot($path) {
    $p = Get-Process mwx -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { return $false }
    $r = New-Object PWin4+RECT
    [void][PWin4]::GetWindowRect($p.MainWindowHandle, [ref]$r)
    $w=$r.R-$r.L; $h=$r.B-$r.T
    if ($w -le 0 -or $h -le 0) { return $false }
    $bmp = New-Object System.Drawing.Bitmap $w,$h
    $g=[System.Drawing.Graphics]::FromImage($bmp); $hdc=$g.GetHdc()
    [void][PWin4]::PrintWindow($p.MainWindowHandle,$hdc,2)
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return $true
}
function Quit-Client {
    [void](Rpc 'command' @{ command='quit' })
    $sw=[Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 45) { Start-Sleep -Seconds 2; if (-not (Alive)) { break } }
    if (Alive) { Get-Process mwx | Stop-Process -Force -ErrorAction SilentlyContinue }
}

# ---------- (b) autoplay off ----------
Get-Process mwx,hmw-mod -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
$pidB = Start-Client '+set mwx_autoplay 0'
$log += "B: started pid=$pidB (+set mwx_autoplay 0)"
$sw=[Diagnostics.Stopwatch]::StartNew()
$lobbySeen=$false
$poll=@()
while ($sw.Elapsed.TotalSeconds -lt 60) {
    Start-Sleep -Seconds 5
    if (-not (Alive)) { $log += "B: process died at $([math]::Round($sw.Elapsed.TotalSeconds,1))s"; break }
    $r = Rpc 'status' $null
    if ($r -and $r.result) {
        $poll += "t=$([math]::Round($sw.Elapsed.TotalSeconds,1)) main_menu=$($r.result.main_menu) vlobby=$($r.result.virtual_lobby) map=$($r.result.map)"
        if ($r.result.virtual_lobby -eq $true) { $lobbySeen=$true }
    }
}
$poll | Set-Content (Join-Path $out 'autoplay-b-poll.txt')
$log += "B: virtual_lobby seen=$lobbySeen during 60s"
$shotB = Shot (Join-Path $out 'autoplay-b.png')
$log += "B: screenshot=$shotB"
$stB = Rpc 'status' $null
if ($stB -and $stB.result) { $stB.result | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $out 'autoplay-b-status.json') }
$gB = Rpc 'get_dvar' @{ name='mwx_autoplay' }
$log += "B: get_dvar mwx_autoplay -> " + ($gB | ConvertTo-Json -Compress -Depth 5)
Quit-Client
$log += "B: quit (alive=$(Alive))"

# ---------- (c) value after restart ----------
Start-Sleep -Seconds 3
$pidC = Start-Client ''
$log += "C: started pid=$pidC"
$sw=[Diagnostics.Stopwatch]::StartNew()
$val=$null
while ($sw.Elapsed.TotalSeconds -lt 120) {
    Start-Sleep -Seconds 3
    if (-not (Alive)) { $log += "C: process died"; break }
    $g = Rpc 'get_dvar' @{ name='mwx_autoplay' }
    if ($g -and $g.result) { $val=$g.result.value; break }
}
$log += "C: get_dvar mwx_autoplay -> $val"
if ($val -eq '0') {
    $log += "C: value 0 -> set 1 and restart once"
    [void](Rpc 'set_dvar' @{ name='mwx_autoplay'; value='1' })
    Quit-Client
    Start-Sleep -Seconds 3
    $pidC = Start-Client ''
    $log += "C: restarted pid=$pidC"
    Start-Sleep -Seconds 8
    $g = Rpc 'get_dvar' @{ name='mwx_autoplay' }
    if ($g) { $log += "C: after restart get_dvar -> " + ($g | ConvertTo-Json -Compress -Depth 5) }
}
$stC = Rpc 'status' $null
if ($stC -and $stC.result) { $stC.result | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $out 'autoplay-c-status.json') }
Quit-Client
$log += "C: quit (alive=$(Alive))"
$log | Set-Content (Join-Path $out 'autoplay-bc.log')
"DONE"
