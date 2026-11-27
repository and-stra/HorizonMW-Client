# MCP self test - moved from _migration\archive\mwx-debug\autonomous\mcp-selftest.ps1 on 27 Nov 2026.
$ErrorActionPreference = 'Stop'
$exe = 'C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered\mwx.exe'
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exe
$psi.Arguments = '-mcp'
$psi.WorkingDirectory = Split-Path $exe
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
$note = '{"jsonrpc":"2.0","method":"notifications/initialized"}'
$list = '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
$p.StandardInput.WriteLine($init)
$p.StandardInput.WriteLine($note)
$p.StandardInput.WriteLine($list)
$p.StandardInput.Flush()
Start-Sleep -Seconds 3
$p.StandardInput.Close()
$out = @()
while (-not $p.HasExited -and $out.Count -lt 200) {
    $line = $p.StandardOutput.ReadLine()
    if ($null -eq $line) { break }
    $out += $line
}
Start-Sleep -Milliseconds 500
if (-not $p.HasExited) { $p.Kill() }
Write-Output "lines=$($out.Count) exit=$($p.ExitCode)"
foreach ($l in $out) {
    if ($l.Length -gt 500) { Write-Output ($l.Substring(0, 500) + '...') } else { Write-Output $l }
}
$err = $p.StandardError.ReadToEnd()
if ($err) { Write-Output '--- stderr'; Write-Output $err }
