# dump AW materials - moved from _migration\archive\mwx-debug\aw-weapons\dump-material.ps1 on 27 Nov 2026.
# D: dump the AW materials for the pilot guns (with their techsets and images) using the S1
# dumper, into AW\dump\assets (its own folder), so they can be copied into the zone source.
param(
    [int]$InitSeconds = 95
)
$ErrorActionPreference = "Stop"
$aw = "C:\Games\cod-hwm\Call of Duty Advanced Warfare"
$tool = Join-Path $aw "zonetool.exe"
$log = "C:\Games\cod-hwm\_migration\archive\mwx-debug\aw-weapons\dump-material.log"
$watch = Join-Path $aw "dump\assets"

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
Write-Host ("pid={0}, waiting {1}s" -f $p.Id, $InitSeconds)
Start-Sleep -Seconds $InitSeconds
if ($p.HasExited) { Write-Host "exited during init"; exit 1 }

$commands = @(
    "loadzone patch_common_mp",
    "dumpasset material mtl_m1garand_action",
    "dumpasset material mtl_m1garand_stock",
    "dumpasset material mtl_m1garand_sight",
    "dumpasset material mtl_m1garand_adapter_base",
    "dumpasset material mtl_ger_mp40_base"
)
foreach ($c in $commands) {
    Write-Host ("sent: {0}" -f $c)
    $p.StandardInput.WriteLine($c)
    $p.StandardInput.Flush()
    Start-Sleep -Seconds 25
    if ($p.HasExited) { break }
}
try { $p.StandardInput.WriteLine("quit"); $p.StandardInput.Flush() } catch {}
if (-not $p.WaitForExit(15000)) { try { $p.Kill() } catch {} }
try { $out = $outTask.GetAwaiter().GetResult() } catch { $out = "" }
try { $err = $errTask.GetAwaiter().GetResult() } catch { $err = "" }
$out | Set-Content $log
if ($err) { $err | Add-Content $log }
Select-String -Path $log -Pattern "dumpasset|Dumped|usage|does not exist|ERROR|Loading zone|loaded" | Select-Object -Last 25 | ForEach-Object { $_.Line.Trim() }
$m = Get-ChildItem $watch -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum
Write-Host ("dump/assets: files={0} MB={1}" -f $m.Count, [math]::Round($m.Sum / 1MB, 1))
