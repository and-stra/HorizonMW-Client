# UI RPC helper - moved from _migration\archive\mwx-debug\autonomous\ui-rpc.ps1 on 27 Nov 2026.
param(
    [ValidateSet('start','snapshot','click','open','back','eval','status','quit')]
    [string]$Action = 'snapshot',
    [int]$Port = 27710,
    [string]$Id = '',
    [string]$Name = '',
    [string]$Code = '',
    [switch]$All
)
$g = 'C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered'
function Rpc([string]$method, $params = @{}, [int]$timeout = 25) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec $timeout } catch { return $null }
}
function Flatten($node, $depth, $out) {
    if ($null -eq $node) { return }
    $id = "$($node.id)"
    $text = "$($node.text)"
    $interesting = $All -or ($id -ne '') -or ($text -ne '')
    if ($interesting) {
        $out.Add(("  " * $depth) + "id=$id text='$text' vis=$($node.visible) enabled=$($node.enabled)")
    }
    if ($node.children) { foreach ($c in $node.children) { Flatten $c ($depth + 1) $out } }
}
switch ($Action) {
    'start' {
        $p = Start-Process -FilePath (Join-Path $g 'mwx.exe') -ArgumentList @('-debugport', "$Port", '+set', 'mwx_test_mode', '1') -WorkingDirectory $g -PassThru -RedirectStandardOutput "$env:TEMP\ui-$Port.log" -RedirectStandardError "$env:TEMP\ui-$Port.err"
        Write-Output "pid=$($p.Id) port=$Port"
    }
    'status' {
        $r = Rpc 'status' @{}
        $r | ConvertTo-Json -Depth 6
    }
    'snapshot' {
        $r = Rpc 'ui_snapshot' @{}
        if (-not $r) { Write-Output 'no answer'; break }
        $out = New-Object System.Collections.ArrayList
        Flatten $r.result 0 $out
        $out | Select-Object -First 400
        Write-Output "--- total $($out.Count)"
    }
    'click' {
        if (-not $Id) { Write-Output 'id required'; break }
        (Rpc 'ui_click' @{ id = $Id } 10) | ConvertTo-Json -Compress
    }
    'open' {
        if (-not $Name) { Write-Output 'name required'; break }
        (Rpc 'ui_open' @{ name = $Name } 10) | ConvertTo-Json -Compress
    }
    'back' {
        (Rpc 'ui_back' @{} 10) | ConvertTo-Json -Compress
    }
    'eval' {
        if (-not $Code) { Write-Output 'code required'; break }
        $r = Rpc 'lua_eval' @{ code = $Code } 25
        if ($r) { $r | ConvertTo-Json -Compress -Depth 8 } else { Write-Output 'no answer' }
    }
    'quit' {
        (Rpc 'command' @{ command = 'quit' } 5) | ConvertTo-Json -Compress
    }
}
