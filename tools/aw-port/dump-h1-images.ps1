# dump AW images with the h1 target - moved from _migration\archive\mwx-debug\aw-weapons\W1.2\dump-h1-images.ps1 on 27 Nov 2026.
param(
    [int]$ReadySeconds = 85,
    [int]$StableSeconds = 120,
    [int]$MaxMinutes = 60,
    [double]$MinFreeGB = 21.0
)
$ErrorActionPreference = 'Continue'
$aw = 'C:\Games\cod-hwm\Call of Duty Advanced Warfare'
$watch = Join-Path $aw 'dump\common_mp'
$log = 'C:\Games\cod-hwm\_migration\archive\mwx-debug\aw-weapons\W1.2\dump-h1-images.log'

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Join-Path $aw 'zonetool.exe'
$psi.Arguments = '-unbuffered-io'
$psi.WorkingDirectory = $aw
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
[void]$p.Start()
"pid=$($p.Id)"
$outTask = $p.StandardOutput.ReadToEndAsync()
$errTask = $p.StandardError.ReadToEndAsync()
Start-Sleep -Seconds $ReadySeconds
if ($p.HasExited) { "exited early code=$($p.ExitCode)"; exit 1 }
$p.StandardInput.WriteLine('dumpzone h1 common_mp image')
$p.StandardInput.Flush()
"sent: dumpzone h1 common_mp image"

$lastCount = -1; $lastSize = -1; $stableSince = Get-Date; $done = $false
$deadline = (Get-Date).AddMinutes($MaxMinutes)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 10
    $free = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
    $count = 0; $size = 0
    if (Test-Path $watch) {
        $m = Get-ChildItem $watch -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum
        $count = $m.Count; $size = [int64]$m.Sum
    }
    if ($free -lt $MinFreeGB) {
        "free space $free GB below $MinFreeGB GB - stopping"; $done = $true; break
    }
    if ($count -ne $lastCount -or $size -ne $lastSize) {
        $lastCount = $count; $lastSize = $size; $stableSince = Get-Date
        "files=$count size=$size free=$free"
    } elseif ($count -gt 0 -and ((Get-Date) - $stableSince).TotalSeconds -ge $StableSeconds) {
        "stable: files=$count size=$size free=$free"; $done = $true; break
    }
    if ($p.HasExited) { "exited code=$($p.ExitCode)"; break }
}
if (-not $p.HasExited) {
    $p.StandardInput.WriteLine('quit'); $p.StandardInput.Flush(); Start-Sleep -Seconds 5
}
if (-not $p.HasExited) { $p.Kill(); Start-Sleep -Seconds 2 }
try { $out = $outTask.GetAwaiter().GetResult() } catch { $out = '' }
try { $err = $errTask.GetAwaiter().GetResult() } catch { $err = '' }
$out | Set-Content $log
if ($err) { $err | Add-Content $log }
"done=$done"
Get-Content $log | Select-Object -Last 25
