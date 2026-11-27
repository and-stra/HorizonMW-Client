# zone/script A/B bisect helper (-Snapshot refreshes the e snapshot) - moved from _migration\archive\mwx-debug\cac-bisect\variant.ps1 on 27 Nov 2026.
# CAC bisect: switch the custom weapon zones for one test run.
#
#   variant.ps1 -Variant a|b|c|d|e
#   variant.ps1 -Restore          # = -Variant e
#
# a = no custom zones, b = hmw_mwr_weapons only, c = crossbow-only hmw_aw_weapons,
# d = b + c, e = the current pilot (textured) state.
#
# Sources are copied once into src\<variant>\ so the .bak-* files in zone\ are never moved.
# NOTE: src\e is a SNAPSHOT of the zone pair, not "the current zone". After a zone rebuild run
# `variant.ps1 -Snapshot` once, otherwise -Variant e puts an old build back (this happened on
# 27 Nov: the suite/warnings ran against a pre-knife zone).
param(
    [ValidateSet("a", "b", "c", "d", "e")][string]$Variant = "e",
    [switch]$Restore,
    [switch]$Snapshot
)
$ErrorActionPreference = "Stop"
if ($Restore) { $Variant = "e" }

$game = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$zone = Join-Path $game "zone"
$root = "C:\Games\cod-hwm\_migration\archive\mwx-debug\backups\zone\bisect"
$src = Join-Path $root "src"
$tmp = Join-Path $root "current"
New-Item -ItemType Directory -Force -Path $src, $tmp | Out-Null

$aw = @("hmw_aw_weapons.ff", "hmw_aw_weapons.pak")
$mwr = @("hmw_mwr_weapons.ff")

# --- refresh the e snapshot from what is in zone\ right now ---------------------
if ($Snapshot) {
    New-Item -ItemType Directory -Force -Path (Join-Path $src "e") | Out-Null
    foreach ($f in $aw) { Copy-Item (Join-Path $zone $f) (Join-Path $src "e\$f") -Force }
    Write-Host "snapshot refreshed from zone\ (hmw_aw_weapons)"
}

# --- capture the sources once -------------------------------------------------
# e: the current (textured pilot) zone pair
if (-not (Test-Path (Join-Path $src "e\hmw_aw_weapons.ff"))) {
    New-Item -ItemType Directory -Force -Path (Join-Path $src "e") | Out-Null
    foreach ($f in $aw) { Copy-Item (Join-Path $zone $f) (Join-Path $src "e") }
}
# c: the crossbow-only build
if (-not (Test-Path (Join-Path $src "c\hmw_aw_weapons.ff"))) {
    New-Item -ItemType Directory -Force -Path (Join-Path $src "c") | Out-Null
    foreach ($f in $aw) { Copy-Item (Join-Path $zone "$f.bak-20261127-065757") (Join-Path $src "c\$f") }
}
# b: the B zone (hmw_mwr_weapons comes from the game folder, not from a .bak)
if (-not (Test-Path (Join-Path $src "b\hmw_mwr_weapons.ff"))) {
    New-Item -ItemType Directory -Force -Path (Join-Path $src "b") | Out-Null
    Copy-Item (Join-Path $zone "hmw_mwr_weapons.ff") (Join-Path $src "b")
}

# --- move everything out, then copy the variant in ----------------------------
foreach ($f in ($aw + $mwr)) {
    $p = Join-Path $zone $f
    if (Test-Path $p) { Move-Item $p (Join-Path $tmp $f) -Force }
}

$want = switch ($Variant) {
    "a" { @() }
    "b" { @(@{ dir = "b"; files = $mwr }) }
    "c" { @(@{ dir = "c"; files = $aw }) }
    "d" { @(@{ dir = "b"; files = $mwr }, @{ dir = "c"; files = $aw }) }
    "e" { @(@{ dir = "e"; files = $aw }, @{ dir = "b"; files = $mwr }) }
}
foreach ($group in $want) {
    foreach ($f in $group.files) {
        Copy-Item (Join-Path $src "$($group.dir)\$f") (Join-Path $zone $f) -Force
    }
}

Write-Host ("variant {0}:" -f $Variant)
foreach ($f in ($aw + $mwr)) {
    $p = Join-Path $zone $f
    if (Test-Path $p) {
        $i = Get-Item $p
        Write-Host ("  {0,-22} {1,12:N0}  {2}" -f $f, $i.Length, (Get-FileHash $p -Algorithm SHA1).Hash.Substring(0, 8))
    }
    else { Write-Host ("  {0,-22} absent" -f $f) }
}

