# loading-screen burst in a mode - moved from _migration\archive\mwx-debug\loadscreen\v2\burst-mode.ps1 on 27 Nov 2026.
param([string]$Mode = 'slasher', [string]$Tag = 'slasher', [int]$Count = 140, [int]$DelayMs = 60)
$ErrorActionPreference = 'Continue'
$v2 = 'C:\Games\cod-hwm\_migration\archive\mwx-debug\loadscreen\v2'
. 'C:\Games\cod-hwm\_migration\archive\mwx-debug\phase3\lib.ps1'
Add-Type -AssemblyName System.Drawing
function Rpc2($m, $p) { $b = @{ method = $m }; if ($p) { $b.params = $p }; try { return Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:27099/rpc' -Body ($b | ConvertTo-Json -Compress -Depth 8) -ContentType 'application/json' -TimeoutSec 5 } catch { return $null } }
function GameProc2 { return (Get-Process mwx -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Sort-Object StartTime -Descending | Select-Object -First 1) }
function ShotFast($path) {
    $p = GameProc2
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

if ($Mode -eq 'slasher') {
    [void](Rpc2 'command' @{ command = 'set mwx_party_mode slasher' })
    [void](Rpc2 'command' @{ command = 'set ui_mapname mp_rust' })
} else {
    [void](Rpc2 'command' @{ command = 'reset mwx_party_mode' })
    [void](Rpc2 'command' @{ command = 'set ui_gametype dm' })
    [void](Rpc2 'command' @{ command = 'set ui_mapname mp_rust' })
}
Start-Sleep -Seconds 2
$g1 = (Rpc2 'get_dvar' @{name='ui_gametype'}).result.value
$g2 = (Rpc2 'get_dvar' @{name='mwx_party_mode'}).result.value
$g3 = (Rpc2 'get_dvar' @{name='ui_mapname'}).result.value
"state: ui_gametype=$g1 party=$g2 map=$g3"

$dir = Join-Path $v2 ("fast-" + $Tag)
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $dir | Out-Null
[void](Focus-Game)
Start-Sleep -Milliseconds 400
$r = Rpc2 'command' @{ command = 'xpartygo' }
"xpartygo: $($r | ConvertTo-Json -Compress)"
$t0 = Get-Date
for ($i = 0; $i -lt $Count; $i++) {
    $f = Join-Path $dir ("{0}-{1:D2}.png" -f $Tag, $i)
    [void](ShotFast $f)
    Start-Sleep -Milliseconds $DelayMs
}
"burst done in $([int]((Get-Date)-$t0).TotalSeconds)s"
$c = Rpc2 'console' @{ lines = 1000 }
if ($c) { $c.result | Set-Content (Join-Path $v2 ("console-" + $Tag + ".txt")) }
"console saved"
[void](ShotFast (Join-Path $v2 ("87-" + $Tag + "-end.png")))
"done"
