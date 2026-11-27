# zonetool command wrapper - moved from _migration\archive\mwx-debug\aw-weapons\W1.2\zonetool-command.ps1 on 27 Nov 2026.
param(
    [string]$Tool = 'C:\Games\cod-hwm\Call of Duty Advanced Warfare\zonetool.exe',
    [string]$WorkDir = 'C:\Games\cod-hwm\Call of Duty Advanced Warfare',
    [string[]]$ToolArgs = @('-unbuffered-io'),
    [string[]]$Commands = @('help'),
    [int]$ReadySeconds = 80,
    [int]$BetweenSeconds = 15,
    [int]$AfterSeconds = 10,
    [string]$Log = 'C:\Games\cod-hwm\_migration\archive\mwx-debug\aw-weapons\W1.2\zonetool-command.log'
)
$ErrorActionPreference = 'Continue'
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Tool
$psi.Arguments = ($ToolArgs -join ' ')
$psi.WorkingDirectory = $WorkDir
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
if ($p.HasExited) {
    "exited early code=$($p.ExitCode)"
} else {
    foreach ($c in $Commands) {
        "sent: $c"
        $p.StandardInput.WriteLine($c)
        $p.StandardInput.Flush()
        Start-Sleep -Seconds $BetweenSeconds
        if ($p.HasExited) { "exited code=$($p.ExitCode)"; break }
    }
    if (-not $p.HasExited) {
        $p.StandardInput.WriteLine('quit')
        $p.StandardInput.Flush()
        Start-Sleep -Seconds $AfterSeconds
    }
}
if (-not $p.HasExited) { $p.Kill(); Start-Sleep -Seconds 2 }
try { $out = $outTask.GetAwaiter().GetResult() } catch { $out = '' }
try { $err = $errTask.GetAwaiter().GetResult() } catch { $err = '' }
$out | Set-Content $Log
if ($err) { $err | Add-Content $Log }
"log: $Log"
Get-Content $Log | Select-Object -Last 40
