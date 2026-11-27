# start a client for UI driving - moved from _migration\archive\mwx-debug\autonomous\ui-open-client.ps1 on 27 Nov 2026.
param([int]$Port = 27700)
$g = 'C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered'
$p = Start-Process -FilePath (Join-Path $g 'mwx.exe') -ArgumentList @('-debugport', "$Port", '+set', 'mwx_test_mode', '1') -WorkingDirectory $g -PassThru -RedirectStandardOutput "$env:TEMP\ui-client-$Port.log" -RedirectStandardError "$env:TEMP\ui-client-$Port.err"
Write-Output "pid=$($p.Id) port=$Port"
