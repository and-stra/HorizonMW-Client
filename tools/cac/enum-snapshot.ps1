# dump the playerdata Weapon enum - moved from _migration\archive\mwx-debug\cac-bisect\enum-snapshot.ps1 on 27 Nov 2026.
# Snapshot the playerdata Weapon enum after the client's extension, for the stability check.
#   powershell -File enum-snapshot.ps1 -Port 27140 -Out c:\...\enum-1.json
# Starts a client, enters PLAY ONLINE (the stats source exists there), waits for the
# extension, dumps the enum members and stops the client.
param(
    [int]$Port = 27140,
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$StartTimeout = 180,
    [int]$WaitSeconds = 12
)
$ErrorActionPreference = "Stop"
$GameDir = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$Exe = Join-Path $GameDir "mwx.exe"

function Rpc([string]$method, $params = @{}, [int]$timeout = 30) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout
    } catch {
        return [pscustomobject]@{ error = $_.Exception.Message }
    }
}

$p = Start-Process -FilePath $Exe -ArgumentList @("-debugport", "$Port", "+set", "mwx_test_mode", "1") -WorkingDirectory $GameDir -PassThru
$menu = $false
for ($i = 0; $i -lt $StartTimeout; $i++) {
    if ($p.HasExited) { throw "client exited during startup" }
    $s = Rpc "status" @{} 3
    if ($s.result -and $s.result.main_menu) { $menu = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $menu) { throw "no main menu after $StartTimeout s" }

Rpc "ui_click" @{ text = "PLAY ONLINE"; expect_menu = "menu_xboxlive"; expect_timeout_ms = 40000 } 45 | Out-Null
Start-Sleep -Seconds $WaitSeconds

$dump = Rpc "ddl_dump" @{ members = $true; enum = "Weapon" } 30
$enum = $dump.result.defs[0].enums | Where-Object { $_.name -eq "Weapon" } | Select-Object -First 1
if (-not $enum) { throw "no Weapon enum in ddl_dump: $($dump.error)" }

$doc = [pscustomobject]@{
    count = $enum.members.Count
    hash_count = $enum.hash_count
    members = $enum.members
}
$doc | ConvertTo-Json -Depth 5 | Set-Content -Path $Out -Encoding UTF8
"wrote ${Out}: $($doc.count) members"

Rpc "command" @{ command = "quit" } 10 | Out-Null
Start-Sleep -Seconds 2
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
