# dump an AW map - moved from _migration\archive\mwx-debug\aw-port\run-aw-dumpmap.ps1 on 27 Nov 2026.
param(
    [string]$Command = 'dumpmap h1 mp_greenband',
    [int]$InitSeconds = 20,
    [int]$StableSeconds = 60,
    [int]$MaxMinutes = 40,
    [string]$WatchPath = 'C:\Games\cod-hwm\Call of Duty Advanced Warfare\dump',
    [string]$ShotPath = 'C:\Games\cod-hwm\_migration\archive\mwx-debug\aw-port\console-dumpmap.png',
    [string]$WorkDir = 'C:\Games\cod-hwm\Call of Duty Advanced Warfare'
)
$ErrorActionPreference = 'Continue'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class TW {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct RECT { public int L,T,R,B; }
}
'@
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c "zonetool.exe"' -WorkingDirectory $WorkDir -PassThru
"cmd pid=$($p.Id)"
Start-Sleep -Seconds $InitSeconds
$p.Refresh()
$h = $p.MainWindowHandle
"console hwnd=$h"
if ($h -eq [IntPtr]::Zero) { "no console window"; exit 1 }

$fg = [TW]::GetForegroundWindow()
$fpid = 0
$ftid = [TW]::GetWindowThreadProcessId($fg, [ref]$fpid)
$gtid = 0
[void][TW]::GetWindowThreadProcessId($h, [ref]$gtid)
$my = [TW]::GetCurrentThreadId()
[void][TW]::AttachThreadInput($my, $ftid, $true)
[void][TW]::AttachThreadInput($my, $gtid, $true)
[void][TW]::ShowWindow($h, 9)
[void][TW]::SetForegroundWindow($h)
[void][TW]::BringWindowToTop($h)
[void][TW]::AttachThreadInput($my, $ftid, $false)
[void][TW]::AttachThreadInput($my, $gtid, $false)
Start-Sleep -Seconds 1
[System.Windows.Forms.SendKeys]::SendWait($Command + '{ENTER}')
"sent: $Command"

$deadline = (Get-Date).AddMinutes($MaxMinutes)
$lastSize = -1
$stableSince = Get-Date
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 10
    $size = 0
    if (Test-Path $WatchPath) {
        $m = Get-ChildItem $WatchPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum
        $size = [int64]$m.Sum
        $count = $m.Count
    }
    if ($size -ne $lastSize) { $lastSize = $size; $stableSince = Get-Date; "size=$size files=$count" }
    elseif (((Get-Date) - $stableSince).TotalSeconds -ge $StableSeconds -and $size -gt 0) { "stable at $size bytes"; break }
}
# screenshot the console
$r = New-Object TW+RECT
[void][TW]::GetWindowRect($h, [ref]$r)
$w = $r.R - $r.L; $hh = $r.B - $r.T
if ($w -gt 0 -and $hh -gt 0) {
    $bmp = New-Object System.Drawing.Bitmap $w, $hh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $hh))
    $g.Dispose()
    $bmp.Save($ShotPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    "screenshot: $ShotPath"
}
"done"
