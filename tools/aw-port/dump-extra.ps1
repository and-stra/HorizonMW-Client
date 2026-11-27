# dump extra AW asset types - moved from _migration\archive\mwx-debug\aw-weapons\dump-extra.ps1 on 27 Nov 2026.
# D: dump the combat knife model zones, the AW patch_common_mp materials (for the missing gun
# materials) and the knife weapon JSON (h2 target, weapons only) in one zonetool session.
param(
    [int]$InitSeconds = 95,
    [int]$MaxMinutes = 25
)
$ErrorActionPreference = "Stop"
$aw = "C:\Games\cod-hwm\Call of Duty Advanced Warfare"
$tool = Join-Path $aw "zonetool.exe"
$log = "C:\Games\cod-hwm\_migration\archive\mwx-debug\aw-weapons\dump-extra.log"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $tool
$psi.Arguments = "-unbuffered-io"
$psi.WorkingDirectory = $aw
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
[void]$p.Start()
$outTask = $p.StandardOutput.ReadToEndAsync()
$errTask = $p.StandardError.ReadToEndAsync()
Write-Host ("pid={0}, waiting {1}s for init" -f $p.Id, $InitSeconds)
Start-Sleep -Seconds $InitSeconds
if ($p.HasExited) { Write-Host "exited during init"; exit 1 }

$commands = @(
    "dumpzone h1 mp_vm_tacticalknife_tr",
    "dumpzone h1 mp_wm_tacticalknife_tr",
    "dumpzone h1 patch_common_mp material",
    "dumpzone h2 patch_common_mp"
)
foreach ($c in $commands) {
    Write-Host ("sent: {0}" -f $c)
    $p.StandardInput.WriteLine($c)
    $p.StandardInput.Flush()
    Start-Sleep -Seconds 45
    if ($p.HasExited) { break }
}
Write-Host "quit"
try { $p.StandardInput.WriteLine("quit"); $p.StandardInput.Flush() } catch {}
if (-not $p.WaitForExit(15000)) { try { $p.Kill() } catch {} }
try { $out = $outTask.GetAwaiter().GetResult() } catch { $out = "" }
try { $err = $errTask.GetAwaiter().GetResult() } catch { $err = "" }
$out | Set-Content $log
if ($err) { $err | Add-Content $log }
Get-Content $log | Select-String -Pattern "Dumping zone|dumped\.|Invalid|does not exist|ERROR" | Select-Object -Last 20 | ForEach-Object { $_.Line }
