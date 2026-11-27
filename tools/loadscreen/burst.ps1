# loading-screen burst capture - moved from _migration\archive\mwx-debug\loadscreen\v2\burst.ps1 on 27 Nov 2026.
param([string]$Prefix='s', [int]$Count=90, [int]$DelayMs=100)
$ErrorActionPreference = 'Continue'
$v2 = 'C:\Games\cod-hwm\_migration\archive\mwx-debug\loadscreen\v2'
. 'C:\Games\cod-hwm\_migration\archive\mwx-debug\phase3\lib.ps1'
function Rpc2($m, $p) { $b = @{ method = $m }; if ($p) { $b.params = $p }; try { return Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:27099/rpc' -Body ($b | ConvertTo-Json -Compress -Depth 8) -ContentType 'application/json' -TimeoutSec 10 } catch { return $null } }
$dir = Join-Path $v2 ("burst-" + $Prefix)
New-Item -ItemType Directory -Force -Path $dir | Out-Null
[void](Focus-Game)
$r = Rpc2 'command' @{ command = 'xpartygo' }
"xpartygo: $($r | ConvertTo-Json -Compress)"
$log = @()
for ($i = 0; $i -lt $Count; $i++) {
    $f = Join-Path $dir ("{0}-{1:D2}.png" -f $Prefix, $i)
    $t0 = Get-Date
    $ok = Shot $f
    $state = $null
    try { $st = Rpc2 'status' $null; if ($st) { $state = "$($st.result.in_game)|$($st.result.map)" } } catch {}
    $log += "{0} shot={1} state={2} ms={3}" -f $i, $ok, $state, [int]((Get-Date) - $t0).TotalMilliseconds
    Start-Sleep -Milliseconds $DelayMs
}
$log | Set-Content (Join-Path $dir 'log.txt')
"done"
