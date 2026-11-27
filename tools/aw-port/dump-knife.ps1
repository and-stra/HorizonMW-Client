# dump the knife's assets - moved from _migration\archive\mwx-debug\aw-weapons\dump-knife.ps1 on 27 Nov 2026.
# Dump AW's common_mp with the S1/h1 dumper for the combat knife: models + their surfaces.
#   powershell -File dump-knife.ps1 [-Types "xmodelsurfs,xsurface"]
# The AW zonetool needs ~100 s before it accepts commands; the output goes to AW\dump\common_mp.
param(
    [string]$Types = "xmodelsurfs",
    [int]$InitSeconds = 110,
    [int]$AfterSeconds = 240
)
$ErrorActionPreference = "Stop"
$aw = "C:\Games\cod-hwm\Call of Duty Advanced Warfare"
$tool = Join-Path $aw "zonetool.exe"
$log = "C:\Games\cod-hwm\_migration\archive\mwx-debug\aw-weapons\dump-knife.log"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $tool
$psi.Arguments = "-unbuffered-io"
$psi.WorkingDirectory = $aw
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
[void]$p.Start()
$outTask = $p.StandardOutput.ReadToEndAsync()
$errTask = $p.StandardError.ReadToEndAsync()
"pid=$($p.Id) init ${InitSeconds}s"
Start-Sleep -Seconds $InitSeconds
if ($p.HasExited) { "exited early code=$($p.ExitCode)"; exit 1 }

foreach ($cmd in @("dumpzone h1 common_mp $Types", "dumpzone h1 common_mp xsurface")) {
    "sent: $cmd"
    $p.StandardInput.WriteLine($cmd)
    $p.StandardInput.Flush()
    Start-Sleep -Seconds 20
}
"waiting ${AfterSeconds}s for the dump"
Start-Sleep -Seconds $AfterSeconds
$p.StandardInput.WriteLine("quit")
$p.StandardInput.Flush()
Start-Sleep -Seconds 5
if (-not $p.HasExited) { $p.Kill() }
try { $out = $outTask.GetAwaiter().GetResult() } catch { $out = "" }
try { $err = $errTask.GetAwaiter().GetResult() } catch { $err = "" }
($out + "`n" + $err) | Set-Content $log
Get-Content $log | Select-Object -Last 25
foreach ($d in @("xsurface", "xmodelsurfs")) {
    $path = Join-Path $aw "dump\common_mp\$d"
    if (Test-Path $path) { "${d}: $((Get-ChildItem $path -File).Count) files" }
}
