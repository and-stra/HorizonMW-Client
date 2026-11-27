$ErrorActionPreference = 'Continue'
$aw = 'C:\Games\cod-hwm\Call of Duty Advanced Warfare'
$log = 'C:\Games\cod-hwm\_migration\archive\mwx-debug\aw-port\aw-dumpmap.log'
$dump = Join-Path $aw 'dump\mp_greenband'
$command = 'dumpmap h1 mp_greenband'

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

# wait for the zone tool to be ready (init line) by checking elapsed + process
Start-Sleep -Seconds 75
if ($p.HasExited) { "exited early code=$($p.ExitCode)"; exit 1 }
$p.StandardInput.WriteLine($command)
$p.StandardInput.Flush()
"sent: $command"

$lastCount = -1; $lastSize = -1; $stableSince = Get-Date; $done = $false
for ($i = 0; $i -lt 900; $i++) {
    Start-Sleep -Seconds 6
    $count = 0; $size = 0
    if (Test-Path $dump) {
        $m = Get-ChildItem $dump -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum
        $count = $m.Count; $size = [int64]$m.Sum
    }
    if ($count -ne $lastCount -or $size -ne $lastSize) {
        $lastCount = $count; $lastSize = $size; $stableSince = Get-Date
        if ($count -gt 0) { "files=$count size=$size" }
    } elseif ($count -gt 0 -and ((Get-Date) - $stableSince).TotalSeconds -ge 150) {
        "stable: files=$count size=$size"; $done = $true; break
    }
    if ($p.HasExited) { "exited code=$($p.ExitCode)"; break }
}
if (-not $p.HasExited) { $p.Kill(); Start-Sleep -Seconds 2 }
try { $out = $outTask.GetAwaiter().GetResult() } catch { $out = '' }
try { $err = $errTask.GetAwaiter().GetResult() } catch { $err = '' }
$out | Set-Content $log
if ($err) { $err | Add-Content $log }
"dump done=$done"
"log tail:"
Get-Content $log | Select-Object -Last 30
$m = Get-ChildItem $dump -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum
"final: files=$($m.Count) bytes=$($m.Sum)"
