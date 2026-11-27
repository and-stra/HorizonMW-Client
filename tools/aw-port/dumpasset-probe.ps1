# probe asset existence in a zone - moved from _migration\archive\mwx-debug\aw-weapons\dumpasset-probe.ps1 on 27 Nov 2026.
# Probe: can dumpasset convert a single image to H1 (h1Image + .pixels) without a full zone dump?
param([int]$InitSeconds = 95)
$ErrorActionPreference = "Stop"
$aw = "C:\Games\cod-hwm\Call of Duty Advanced Warfare"
$log = "C:\Games\cod-hwm\_migration\archive\mwx-debug\aw-weapons\dumpasset-probe.log"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Join-Path $aw "zonetool.exe"
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
Write-Host ("pid={0}" -f $p.Id)
Start-Sleep -Seconds $InitSeconds
$commands = @(
    "loadzone patch_common_mp",
    "dumpasset h1 image tex_m1garand_action_base_col",
    "dumpasset image tex_m1garand_action_base_nml"
)
foreach ($c in $commands) {
    Write-Host ("sent: {0}" -f $c)
    $p.StandardInput.WriteLine($c)
    $p.StandardInput.Flush()
    Start-Sleep -Seconds 30
}
try { $p.StandardInput.WriteLine("quit"); $p.StandardInput.Flush() } catch {}
if (-not $p.WaitForExit(15000)) { try { $p.Kill() } catch {} }
try { $out = $outTask.GetAwaiter().GetResult() } catch { $out = "" }
try { $err = $errTask.GetAwaiter().GetResult() } catch { $err = "" }
$out | Set-Content $log
if ($err) { $err | Add-Content $log }
Select-String -Path $log -Pattern "dumpasset|Dumped|usage|does not exist|ERROR|invalid|Invalid" | Select-Object -Last 15 | ForEach-Object { $_.Line.Trim() }
Get-ChildItem (Join-Path $aw "dump\assets") -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 12 Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String -Width 80
