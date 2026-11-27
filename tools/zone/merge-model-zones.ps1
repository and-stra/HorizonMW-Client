# merge model-zone asset lists - moved from _migration\archive\mwx-debug\mwr-weapons\merge-model-zones.ps1 on 27 Nov 2026.
param(
    [string]$ZoneFile = "C:\Games\cod-hwm\_migration\archive\mwx-debug\mwr-weapons\zone-dumps.txt"
)
$ErrorActionPreference = "Stop"
$game = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$dumpRoot = Join-Path $game "dump"
$dst = Join-Path $game "zonetool\hmw_mwr_weapons"
$zones = @(Get-Content $ZoneFile | Where-Object { $_ -and -not $_.StartsWith("#") })
New-Item -ItemType Directory -Force -Path $dst | Out-Null

$merged = 0
foreach ($zone in $zones) {
    $src = Join-Path $dumpRoot $zone
    if (-not (Test-Path $src)) {
        Write-Host ("missing dump folder: {0}" -f $zone)
        continue
    }
    $files = @(Get-ChildItem $src -Recurse -File)
    if ($files.Count -eq 0) {
        Write-Host ("empty dump folder: {0}" -f $zone)
        continue
    }
    $r = robocopy $src $dst /E /MT:4 /NFL /NDL /NJH /NJS /R:1 /W:1
    if ($LASTEXITCODE -ge 8) {
        throw ("robocopy failed for {0}: {1}" -f $zone, $LASTEXITCODE)
    }
    $merged++
    Write-Host ("merged {0}: {1} files" -f $zone, $files.Count)
}
Write-Host ("merged {0}/{1} zones into {2}" -f $merged, $zones.Count, $dst)
