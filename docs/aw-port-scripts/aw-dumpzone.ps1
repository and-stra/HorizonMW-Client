param(
    [string]$Command = 'dumpzone h1 common_mp',
    [string]$Watch = 'C:\Games\cod-hwm\Call of Duty Advanced Warfare\dump\common_mp',
    [string]$LogName = 'aw-dumpzone-common_mp.log',
    [int]$ReadySeconds = 75,
    [int]$StableSeconds = 150,
    [int]$MaxMinutes = 70
)
$ErrorActionPreference = 'Continue'
$aw = 'C:\Games\cod-hwm\Call of Duty Advanced Warfare'
$log = Join-Path 'C:\Games\cod-hwm\mwx-debug\aw-port' $LogName

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
$p.StandardInput.WriteLine($Command)
$p.StandardInput.Flush()
"sent: $Command"

$lastCount = -1; $lastSize = -1; $stableSince = Get-Date; $done = $false
$deadline = (Get-Date).AddMinutes($MaxMinutes)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 8
    $count = 0; $size = 0
    if (Test-Path $Watch) {
        $m = Get-ChildItem $Watch -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum
        $count = $m.Count; $size = [int64]$m.Sum
    }
    if ($count -ne $lastCount -or $size -ne $lastSize) {
        $lastCount = $count; $lastSize = $size; $stableSince = Get-Date
        if ($count -gt 0) { "files=$count size=$size" }
    } elseif ($count -gt 0 -and ((Get-Date) - $stableSince).TotalSeconds -ge $StableSeconds) {
        "stable: files=$count size=$size"; $done = $true; break
    }
    if ($p.HasExited) { "exited code=$($p.ExitCode)"; break }
}
if (-not $p.HasExited) { $p.Kill(); Start-Sleep -Seconds 2 }
try { $out = $outTask.GetAwaiter().GetResult() } catch { $out = '' }
try { $err = $errTask.GetAwaiter().GetResult() } catch { $err = '' }
$out | Set-Content $log
if ($err) { $err | Add-Content $log }
"done=$done"
Get-Content $log | Select-Object -Last 20
$m = Get-ChildItem $Watch -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum
"final: files=$($m.Count) bytes=$($m.Sum)"
