param(
    [Parameter(Mandatory = $true)][string]$Command,
    [string]$LogName = 'h1-tool.log',
    [int]$ReadySeconds = 75,
    [int]$MaxMinutes = 20,
    [string]$WatchFile = '',
    [int]$StableSeconds = 20
)
$ErrorActionPreference = 'Continue'
$g = 'C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered'
$log = Join-Path 'C:\Games\cod-hwm\mwx-debug\aw-port' $LogName
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Join-Path $g 'x64zt.exe'
$psi.Arguments = '-unbuffered-io'
$psi.WorkingDirectory = $g
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
if ($p.HasExited) { "exited early code=$($p.ExitCode)"; $p.StandardInput.Close(); $o=$outTask.GetAwaiter().GetResult(); $o | Set-Content $log; Get-Content $log | Select-Object -Last 10; exit 1 }
$p.StandardInput.WriteLine($Command)
$p.StandardInput.Flush()
"sent: $Command"
$deadline = (Get-Date).AddMinutes($MaxMinutes)
$lastWrite = $null
$stableSince = Get-Date
$done = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    if ($WatchFile -ne '') {
        if (Test-Path $WatchFile) {
            $w = (Get-Item $WatchFile).LastWriteTime
            if ($w -ne $lastWrite) { $lastWrite = $w; $stableSince = Get-Date; "watch updated $w" }
            elseif (((Get-Date) - $stableSince).TotalSeconds -ge $StableSeconds) { "watch stable"; $done = $true; break }
        }
    }
    if ($p.HasExited) { "exited code=$($p.ExitCode)"; break }
}
if (-not $p.HasExited) { $p.Kill(); Start-Sleep -Seconds 2 }
try { $out = $outTask.GetAwaiter().GetResult() } catch { $out = '' }
try { $err = $errTask.GetAwaiter().GetResult() } catch { $err = '' }
$out | Set-Content $log
if ($err) { $err | Add-Content $log }
"done=$done"
Get-Content $log | Select-Object -Last 25
