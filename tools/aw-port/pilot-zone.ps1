# build the AW pilot zone - moved from _migration\archive\mwx-debug\aw-weapons\pilot-zone.ps1 on 27 Nov 2026.
# D pilot: dump the M1 Garand + MP40 model zones from AW, merge them into the pilot zone source
# and build the H1 zone. Uses the same drivers as the crossbow (dump-models.ps1, build-zone.ps1).
param(
    [switch]$SkipDump,
    [switch]$SkipMerge
)
$ErrorActionPreference = "Stop"
$aw = "C:\Games\cod-hwm\Call of Duty Advanced Warfare"
$g = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$pilot = "C:\Games\cod-hwm\_migration\archive\mwx-debug\aw-weapons"

if (-not $SkipDump) {
    Write-Host "=== dump model zones ==="
    & (Join-Path $pilot "dump-models.ps1") -ZoneFile (Join-Path $pilot "model-zones.txt")
}

if (-not $SkipMerge) {
    Write-Host "=== merge dumped models into the pilot zone source ==="
    $src = Join-Path $aw "dump\weapon_models"
    $dst = Join-Path $g "zonetool\hmw_aw_pilot"
    robocopy $src $dst /E /MT:4 /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed: $LASTEXITCODE" }
    Write-Host "merged $src -> $dst"
}

Write-Host "=== build hmw_aw_pilot ==="
& (Join-Path $pilot "..\mwr-weapons\build-zone.ps1") -Zone "hmw_aw_pilot"
