# drive the AW zonetool UI - moved from _migration\archive\mwx-debug\aw-port\drive-tool.ps1 on 27 Nov 2026.
param(
    [string]$Command = 'verifyzone mp_greenband',
    [int]$InitSeconds = 25,
    [int]$MaxMinutes = 40,
    [string]$Shot = 'C:\Games\cod-hwm\_migration\archive\mwx-debug\aw-port\console-shot.png',
    [string]$DonePath = '',
    [int]$StableSeconds = 60
)
$ErrorActionPreference = 'Continue'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class CW {
  [DllImport("kernel32.dll")] public static extern bool FreeConsole();
  [DllImport("kernel32.dll")] public static extern bool AttachConsole(uint pid);
  [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct RECT { public int L,T,R,B; }
}
'@
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c "zonetool.exe"' -WorkingDirectory 'C:\Games\cod-hwm\Call of Duty Advanced Warfare' -PassThru
"cmd pid=$($p.Id)"
Start-Sleep -Seconds $InitSeconds
$zt = Get-Process zonetool -ErrorAction SilentlyContinue | Sort-Object StartTime -Descending | Select-Object -First 1
if (-not $zt) { "zonetool not running"; exit 1 }
"zonetool pid=$($zt.Id)"

[void][CW]::FreeConsole()
$attached = [CW]::AttachConsole([uint32]$zt.Id)
$h = [CW]::GetConsoleWindow()
[void][CW]::FreeConsole()
"attached=$attached hwnd=$h"
if ($h -eq [IntPtr]::Zero) { "no console window"; exit 1 }

[void][CW]::ShowWindow($h, 9)
[void][CW]::SetForegroundWindow($h)
[void][CW]::BringWindowToTop($h)
Start-Sleep -Milliseconds 800
[System.Windows.Forms.SendKeys]::SendWait($Command + '{ENTER}')
"sent: $Command"

$deadline = (Get-Date).AddMinutes($MaxMinutes)
$last = -1; $stable = Get-Date
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 10
    if ($DonePath -ne '') {
        $size = 0
        if (Test-Path $DonePath) { $size = (Get-ChildItem $DonePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
        if ($size -ne $last) { $last = $size; $stable = Get-Date; "size=$size" }
        elseif ($size -gt 0 -and ((Get-Date) - $stable).TotalSeconds -ge $StableSeconds) { "stable at $size"; break }
    }
    $zt.Refresh()
    if ($zt.HasExited) { "zonetool exited"; break }
}
Start-Sleep -Seconds 2
$r = New-Object CW+RECT
[void][CW]::GetWindowRect($h, [ref]$r)
$w = $r.R - $r.L; $hh = $r.B - $r.T
if ($w -gt 0 -and $hh -gt 0) {
    $bmp = New-Object System.Drawing.Bitmap $w, $hh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $hh))
    $g.Dispose()
    $bmp.Save($Shot, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    "screenshot: $Shot"
}
"done"
