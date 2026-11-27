# Build tools/zone-check/index/prior.json from the zone dumps on this machine.
#
#   powershell -File tools\zone-check\build-index.ps1            # index what is dumped
#   powershell -File tools\zone-check\build-index.ps1 -List      # show the index
#
# The console prints the index for every zone that is still missing; without those
# the check cannot see a collision in them (common_mp is the big one: dump it with
# -Dump once, it needs ~20 GB while dumping - see docs/zone-check.md).
param(
    [string]$Out = "",
    [switch]$List,
    [switch]$Dump,
    [int]$InitSeconds = 90
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$game = Join-Path (Split-Path -Parent $repo) "Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$tool = Join-Path $PSScriptRoot "zone_check.py"
$python = Get-Command py -ErrorAction SilentlyContinue
if ($python) { $pythonArgs = @("-3") } else { $python = Get-Command python -ErrorAction SilentlyContinue; $pythonArgs = @() }
if (-not $python) { throw "python is required for zone-check (py -3 or python on PATH)" }
if (-not $Out) { $Out = Join-Path $PSScriptRoot "index\prior.json" }
$refs = Join-Path (Split-Path -Parent $repo) "refs\dumps"

# zones loaded before ours, in load order (stock MWR first, then HMW's own zones)
$required = @(
    "common_mp", "patch_common_mp", "ui_mp", "patch_ui_mp",
    "code_post_gfx_mp", "pre_gfx", "post_gfx",
    "hmw_patch_common_mp", "hmw_patch_ui_mp",
    "hmw_killstreak", "hmw_attachments", "hmw_ar1", "hmw_smg", "hmw_shotgun", "hmw_rangers"
)

# dump folder -> zone name (the "workbench_" prefix is the dump tool's)
$dumps = [ordered]@{
    (Join-Path $refs "patch_common_mp")        = "patch_common_mp"
    (Join-Path $refs "patch_ui_mp")            = "patch_ui_mp"
    (Join-Path $refs "ui_mp")                  = "ui_mp"
    (Join-Path $refs "hmw_patch_common_mp")    = "hmw_patch_common_mp"
    (Join-Path $refs "hmw_patch_ui_mp")        = "hmw_patch_ui_mp"
    (Join-Path $game "dump\workbench_hmw_attachments") = "hmw_attachments"
    (Join-Path $game "dump\workbench_hmw_ar1")         = "hmw_ar1"
    (Join-Path $game "dump\workbench_hmw_rangers")     = "hmw_rangers"
    (Join-Path $game "dump\workbench_hmw_patch_common_mp") = "hmw_patch_common_mp"
    (Join-Path $game "dump\workbench_hmw_post_gfx")    = "post_gfx"
    (Join-Path $game "dump\workbench_hmw_dlc_factions") = "hmw_dlc_factions"
}

if ($List) {
    & $python @pythonArgs $tool list --index $Out
    exit $LASTEXITCODE
}

if (Test-Path $Out) { Remove-Item $Out }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Out) | Out-Null

foreach ($path in $dumps.Keys) {
    if (Test-Path $path) {
        & $python @pythonArgs $tool index --zone $dumps[$path] --dump $path --out $Out
        if ($LASTEXITCODE -ne 0) { throw "index failed for $path" }
    }
}

$indexed = @{}
if (Test-Path $Out) {
    $doc = Get-Content $Out -Raw | ConvertFrom-Json
    foreach ($p in $doc.zones.PSObject.Properties) { $indexed[$p.Name] = $true }
}
$missing = @($required | Where-Object { -not $indexed.ContainsKey($_) })
if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host ("NOT indexed ({0}): {1}" -f $missing.Count, ($missing -join ", "))
    Write-Host "dump them with: powershell -File tools\zone-check\build-index.ps1 -Dump"
}

if ($Dump -and $missing.Count -gt 0) {
    # x64zt interactive console: one session, one "dumpzone <zone>" per missing zone
    $zones = $missing
    Write-Host ("dumping {0} zones (this takes a while)" -f $zones.Count)
    foreach ($zone in $zones) {
        & (Join-Path $PSScriptRoot "..\..\mwx-debug\mwr-weapons\dump-zones.ps1") -Zones @($zone, "workbench_$zone") -InitSeconds $InitSeconds
    }
    Write-Host "re-run build-index.ps1 after dumping"
}
Write-Host ("index: {0}" -f $Out)
