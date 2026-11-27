# drive a client through the lobby - moved from _migration\archive\mwx-debug\loadscreen\v2\drive.ps1 on 27 Nov 2026.
param([string]$Steps = '')
$ErrorActionPreference = 'Continue'
$v2 = 'C:\Games\cod-hwm\_migration\archive\mwx-debug\loadscreen\v2'
. 'C:\Games\cod-hwm\_migration\archive\mwx-debug\phase3\lib.ps1'
function Rpc2($m, $p) { $b = @{ method = $m }; if ($p) { $b.params = $p }; try { return Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:27099/rpc' -Body ($b | ConvertTo-Json -Compress -Depth 8) -ContentType 'application/json' -TimeoutSec 15 } catch { return $null } }
function Shot2($name) { [void](Focus-Game); Start-Sleep -Milliseconds 350; [void](Shot (Join-Path $v2 $name)); "saved $name" }
$keymap = @{ 'enter' = 0x0D; 'esc' = 0x1B; 'space' = 0x20; 'tab' = 0x09; 'down' = 0x28; 'up' = 0x26; 'left' = 0x25; 'right' = 0x27; 'a' = 0x41; 'd' = 0x44 }

foreach ($s in ($Steps -split ';')) {
    if (-not $s.Trim()) { continue }
    $p = $s.Split(':', 2)
    $op = $p[0].Trim()
    $arg = if ($p.Count -gt 1) { $p[1] } else { '' }
    switch ($op) {
        'focus' { [void](Focus-Game); 'focused' }
        'shot' { Shot2 $arg }
        'click' { [void](Focus-Game); Start-Sleep -Milliseconds 150; $xy = $arg.Split(','); $tx=[int]$xy[0]; $ty=[int]$xy[1]; [void][W]::SetCursorPos(960, 540); Start-Sleep -Milliseconds 300; [void][W]::SetCursorPos($tx, $ty); Start-Sleep -Milliseconds 400; [void](Click $tx $ty); "click $arg" }
        'key' { [void](Focus-Game); Start-Sleep -Milliseconds 150; Key ([byte]$keymap[$arg]); "key $arg" }
        'sleep' { Start-Sleep -Milliseconds ([int]$arg); "sleep $arg" }
        'status' { (Rpc2 'status' $null) | ConvertTo-Json -Depth 6 }
        'dvar' { $r = Rpc2 'get_dvar' @{ name = $arg }; "$arg = $($r.result.value)" }
        'console' { (Rpc2 'console' @{ lines = [int]$arg }).result }
        'cmd' { (Rpc2 'command' @{ command = $arg }) | ConvertTo-Json -Compress }
        default { "unknown $op" }
    }
}
