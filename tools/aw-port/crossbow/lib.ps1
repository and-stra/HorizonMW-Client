# crossbow test client library - moved from _migration\archive\mwx-debug\crossbow\lib.ps1 on 27 Nov 2026.
$ErrorActionPreference = 'Continue'
$game = 'C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered'
$out  = 'C:\Games\cod-hwm\_migration\archive\mwx-debug\phase3'

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  public struct RECT { public int L,T,R,B; }
  public struct POINT { public int X,Y; }
}
'@
Add-Type -AssemblyName System.Drawing

function Get-GameProc { return (Get-Process mwx -ErrorAction SilentlyContinue | Select-Object -First 1) }
function Rpc($method, $params) {
    $body = @{ method = $method }
    if ($null -ne $params) { $body.params = $params }
    try { return (Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:27099/rpc' -Body ($body | ConvertTo-Json -Compress -Depth 8) -ContentType 'application/json' -TimeoutSec 20) }
    catch { return $null }
}
function Get-Status { $r = Rpc 'status' $null; if ($r) { return $r.result } return $null }
function Shot($path) {
    $p = Get-GameProc
    if (-not $p) { return $false }
    $r = New-Object W+RECT
    [void][W]::GetWindowRect($p.MainWindowHandle, [ref]$r)
    $w = $r.R - $r.L; $h = $r.B - $r.T
    if ($w -le 0 -or $h -le 0) { return $false }
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [void][W]::PrintWindow($p.MainWindowHandle, $hdc, 2)
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return $true
}
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class FGX {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
}
'@
function Focus-Game {
    $p = Get-GameProc
    if (-not $p) { return $false }
    $fg = [FGX]::GetForegroundWindow()
    $fpid = 0
    $ftid = [FGX]::GetWindowThreadProcessId($fg, [ref]$fpid)
    $gtid = 0
    [void][FGX]::GetWindowThreadProcessId($p.MainWindowHandle, [ref]$gtid)
    $my = [FGX]::GetCurrentThreadId()
    [void][FGX]::AttachThreadInput($my, $ftid, $true)
    [void][FGX]::AttachThreadInput($my, $gtid, $true)
    [void][W]::ShowWindow($p.MainWindowHandle, 9)
    [void][FGX]::SetForegroundWindow($p.MainWindowHandle)
    [void][FGX]::BringWindowToTop($p.MainWindowHandle)
    [void][W]::SetFocus($p.MainWindowHandle)
    [void][FGX]::AttachThreadInput($my, $ftid, $false)
    [void][FGX]::AttachThreadInput($my, $gtid, $false)
    Start-Sleep -Milliseconds 500
    return $true
}
function Key([byte]$vk) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public class KEYX { [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra); }
'@ -ErrorAction SilentlyContinue
    [KEYX]::keybd_event($vk, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 90
    [KEYX]::keybd_event($vk, 0, 2, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 200
}
function Key-Esc { Key 0x1B }
function Key-Enter { Key 0x0D }
function Key-Up { Key 0x26 }
function Key-Down { Key 0x28 }
# click at client-area coordinates (0,0 = top-left of the game picture)
function Click($x, $y) {
    $p = Get-GameProc
    if (-not $p) { return $false }
    $pt = New-Object W+POINT
    $pt.X = $x; $pt.Y = $y
    [void][W]::ClientToScreen($p.MainWindowHandle, [ref]$pt)
    [void][W]::SetCursorPos($pt.X, $pt.Y)
    Start-Sleep -Milliseconds 120
    [W]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)  # left down
    Start-Sleep -Milliseconds 80
    [W]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)  # left up
    Start-Sleep -Milliseconds 250
    return $true
}
function Get-ClientSize {
    $p = Get-GameProc
    if (-not $p) { return $null }
    $r = New-Object W+RECT
    [void][W]::GetClientRect($p.MainWindowHandle, [ref]$r)
    return @{ W = $r.R - $r.L; H = $r.B - $r.T }
}
function Start-Client($extra) {
    $cmd = '"' + $game + '\mwx.exe"'
    if ($extra) { $cmd += ' ' + $extra }
    $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd; CurrentDirectory = $game }
    return $r.ProcessId
}
function Wait-State($prop, $maxSec) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $maxSec) {
        Start-Sleep -Seconds 1
        if (-not (Get-GameProc)) { return $false }
        $st = Get-Status
        if ($st -and $st.$prop -eq $true) { return $true }
    }
    return $false
}
