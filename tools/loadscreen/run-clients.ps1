# multi-client load timing - moved from _migration\archive\mwx-debug\loadscreen\v2\run-clients.ps1 on 27 Nov 2026.
$ErrorActionPreference = 'Continue'
$game = 'C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered'
$v2 = 'C:\Games\cod-hwm\_migration\archive\mwx-debug\loadscreen\v2'
. 'C:\Games\cod-hwm\_migration\archive\mwx-debug\phase3\lib.ps1'
Add-Type -AssemblyName System.Drawing
function Rpc2($m, $p) { $b = @{ method = $m }; if ($p) { $b.params = $p }; try { return Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:27099/rpc' -Body ($b | ConvertTo-Json -Compress -Depth 8) -ContentType 'application/json' -TimeoutSec 10 } catch { return $null } }
function Get-GameProc2 { return (Get-Process mwx -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Sort-Object StartTime -Descending | Select-Object -First 1) }
function ShotFast($path) {
    $p = Get-GameProc2
    if (-not $p) { return $false }
    $r = New-Object W+RECT
    [void][W]::GetWindowRect($p.MainWindowHandle, [ref]$r)
    $w = $r.R - $r.L; $h = $r.B - $r.T
    if ($w -le 0 -or $h -le 0) { return $false }
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size $w, $h))
    $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return $true
}
function Burst($tag, $count, $delayMs) {
    $dir = Join-Path $v2 "fast-$tag"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [void](Focus-Game)
    $r = Rpc2 'command' @{ command = 'xpartygo' }
    "xpartygo($tag): $($r | ConvertTo-Json -Compress)"
    $log = @()
    for ($i = 0; $i -lt $count; $i++) {
        $f = Join-Path $dir ("{0}-{1:D2}.png" -f $tag, $i)
        $t0 = Get-Date
        $ok = ShotFast $f
        $state = $null
        try { $st = Rpc2 'status' $null; if ($st) { $state = "$($st.result.in_game)|$($st.result.map)|$($st.result.gametype)" } } catch {}
        $log += "{0} shot={1} state={2} ms={3}" -f $i, $ok, $state, [int]((Get-Date) - $t0).TotalMilliseconds
        Start-Sleep -Milliseconds $delayMs
    }
    $log | Set-Content (Join-Path $dir 'log.txt')
}
function DumpConsole($name) {
    $r = Rpc2 'console' @{ lines = 1000 }
    if ($r) { $r.result | Set-Content (Join-Path $v2 $name) }
    "console saved: $name"
}

# --- stop old client first ---
[void](Rpc2 'command' @{ command = 'quit' })
for ($i = 0; $i -lt 30; $i++) { Start-Sleep -Seconds 2; if (-not (Get-GameProc2)) { break } }
$p = Get-GameProc2; if ($p) { Stop-Process -Id $p.Id -Force }
Start-Sleep -Seconds 3

$ps = Start-Process -FilePath "$game\mwx.exe" -WorkingDirectory $game -ArgumentList @('+set', 'mwx_autoplay', '1', '+set', 'mwx_debug_gamemodes', '1', '+set', 'mwx_gsc_print', '1') -PassThru -RedirectStandardOutput (Join-Path $v2 'client-console.txt') -RedirectStandardError (Join-Path $v2 'client-console.err.txt')
"started pid=$($ps.Id)"
$ok = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    $s = Rpc2 'status' $null
    if ($s -and $s.result -and ($s.result.main_menu -eq $true -or $s.result.virtual_lobby -eq $true)) { $ok = $true; "menu after $($i*2)s"; break }
}
Start-Sleep -Seconds 25
[void](Focus-Game)
Start-Sleep -Seconds 2
[void](ShotFast (Join-Path $v2 '80-menu.png'))

# ---------- SLASHER ----------
[void](Rpc2 'command' @{ command = 'set mwx_party_mode slasher' })
[void](Rpc2 'command' @{ command = 'set ui_mapname mp_rust' })
[void](Rpc2 'command' @{ command = 'set ui_gametype war' })
Start-Sleep -Seconds 2
"ui_gametype = $((Rpc2 'get_dvar' @{name='ui_gametype'}).result.value) party=$((Rpc2 'get_dvar' @{name='mwx_party_mode'}).result.value) map=$((Rpc2 'get_dvar' @{name='ui_mapname'}).result.value)"
Burst 'slasher' 120 60
Start-Sleep -Seconds 4
DumpConsole 'console-slasher.txt'
[void](Rpc2 'command' @{ command = 'spawnBot 2' })
Start-Sleep -Seconds 2
[void](ShotFast (Join-Path $v2 '81-slasher-ingame.png'))

# ---------- TDM ----------
[void](Rpc2 'command' @{ command = 'disconnect' })
Start-Sleep -Seconds 12
[void](Rpc2 'command' @{ command = 'set mwx_party_mode ' })
[void](Rpc2 'command' @{ command = 'set ui_gametype dm' })
[void](Rpc2 'command' @{ command = 'set ui_mapname mp_rust' })
Start-Sleep -Seconds 2
"TDM ui_gametype = $((Rpc2 'get_dvar' @{name='ui_gametype'}).result.value) party=$((Rpc2 'get_dvar' @{name='mwx_party_mode'}).result.value)"
Burst 'tdm' 120 60
Start-Sleep -Seconds 4
DumpConsole 'console-tdm.txt'
[void](Rpc2 'command' @{ command = 'spawnBot 2' })
Start-Sleep -Seconds 2
[void](ShotFast (Join-Path $v2 '82-tdm-ingame.png'))
"done"
