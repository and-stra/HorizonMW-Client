$ErrorActionPreference = 'Continue'
$game = 'C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered'
$out = 'C:\Games\cod-hwm\mwx-debug\aw-port'
$con = Join-Path $out 'server4-rpc-console.txt'
if (Test-Path $con) { Remove-Item $con -Force }
function RpcS($m, $p) { $b = @{ method = $m }; if ($p) { $b.params = $p }; try { return Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:27098/rpc' -Body ($b | ConvertTo-Json -Compress -Depth 8) -ContentType 'application/json' -TimeoutSec 8 } catch { return $null } }
function DumpCon($tag) {
    $c = RpcS 'console' @{ lines = 1000 }
    if ($c -and $c.result) { "===== $tag =====" | Add-Content $con; $c.result | Add-Content $con; "console($tag): $($c.result.Count)" } else { "console($tag): NULL" }
}
$existing = Get-NetTCPConnection -LocalPort 27098 -ErrorAction SilentlyContinue
if ($existing) { "port 27098 in use"; exit 1 }
# no stdout redirect: avoids the 10.6 KB pipe stall; console is captured via RPC
$p = Start-Process -FilePath "$game\mwx.exe" -WorkingDirectory $game -ArgumentList @('-dedicated','-memoryfix','+set','net_port','27016','+set','mwx_gsc_print','1','+set','sv_hostname','mwx greenband test') -PassThru
"server pid=$($p.Id)"
$ok = $false
for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Seconds 2; $s = RpcS 'status' $null; if ($s -and $s.result) { $ok = $true; "up after $($i*2)s"; break } }
if (-not $ok) { "no server"; exit 1 }
[void](RpcS 'command' @{ command = 'set g_gametype war' }); Start-Sleep -Seconds 2
[void](RpcS 'command' @{ command = 'map mp_greenband' })
for ($i = 0; $i -lt 75; $i++) { Start-Sleep -Seconds 4; $s = RpcS 'status' $null; if ($s -and $s.result -and $s.result.map -eq 'mp_greenband') { "map loaded after $($i*4)s"; break } }
Start-Sleep -Seconds 5
DumpCon 'after-map'
[void](RpcS 'command' @{ command = 'spawnBot 4' })
"bots spawned"
for ($i = 0; $i -lt 8; $i++) {
    Start-Sleep -Seconds 30
    $s = RpcS 'status' $null
    if ($s -and $s.result) {
        "t+$((($i+1)*30))s map=$($s.result.map) players=$($s.result.players.Count)"
        $s.result.players | ForEach-Object { "  $($_.name) team=$($_.team) score=$($_.score) bot=$($_.bot)" }
    }
}
DumpCon 'after-bots'
$s = RpcS 'status' $null
if ($s) { $s.result | ConvertTo-Json -Depth 4 }
[void](RpcS 'command' @{ command = 'quit' })
Start-Sleep -Seconds 5
$p.Refresh(); if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
"server test done"
