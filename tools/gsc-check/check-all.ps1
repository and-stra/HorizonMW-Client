# MWX GSC cross-file check (Windows).
#
#   powershell -File tools\gsc-check\check-all.ps1 [-Root <repo>] [-Verbose]
#
# Checks every .gsc under data\ :
#   - cross-file calls  <path>::<function>(  must resolve to a script that exists in one of the
#     include roots and that defines <function>
#   - the HMW dump names maps\mp\gametypes\_gamescore as _gamescores.gsc: both are accepted
# Exits 1 when something is missing. This is the check that runs in the regression check; it does
# not compile the scripts (that needs gsct, see build.sh).

param(
  [string]$Root = "",
  [switch]$Quiet
)

if ($Root -eq "") {
  $Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

$roots = @(
  (Join-Path $Root "data\mwx"),
  (Join-Path $Root "data\cdata\scripts"),
  (Join-Path $Root "data\mods"),
  (Join-Path $Root "..\COD-GSC-Source\H1-GSC"),
  (Join-Path $Root "..\COD-GSC-Source\HMW-GSC")
) | ForEach-Object { (Resolve-Path $_ -ErrorAction SilentlyContinue).Path } | Where-Object { $_ }

if ($roots.Count -eq 0) {
  "no include roots found"
  exit 1
}

function Normalize([string]$path) {
  return ($path -replace '\\', '/')
}

# script path (maps/mp/gametypes/_utility) -> file
function Find-Script([string]$name) {
  $name = Normalize $name
  $candidates = @($name)
  # HMW's dump calls _gamescore _gamescores.gsc
  if ($name -match '(^|/)_gamescore$') { $candidates += ($name + 's') }
  if ($name -match '(^|/)_gamescores$') { $candidates += ($name -replace 's$', '') }

  foreach ($candidate in $candidates) {
    foreach ($root in $roots) {
      $file = Join-Path $root ($candidate + ".gsc")
      if (Test-Path -LiteralPath $file) { return (Resolve-Path -LiteralPath $file).Path }
    }
  }
  return $null
}

function Has-Function([string]$file, [string]$function) {
  $text = Get-Content -Raw -LiteralPath $file
  # definitions look like "name(args)" or "function name(args)" at the start of a line
  $pattern = '(?m)^\s*(?:function\s+)?' + [regex]::Escape($function) + '\s*\('
  return [regex]::IsMatch($text, $pattern)
}

$files = Get-ChildItem -Path (Join-Path $Root "data") -Recurse -Filter *.gsc -File
$errors = 0
$checks = 0

foreach ($file in $files) {
  $text = Get-Content -Raw -LiteralPath $file.FullName

  # strip line comments and strings so examples in comments do not count
  $clean = [regex]::Replace($text, '(?m)//.*$', '')
  $clean = [regex]::Replace($clean, '"(?:\\.|[^"\\])*"', '""')

  $matches = [regex]::Matches($clean, '([A-Za-z0-9_][A-Za-z0-9_\\/]*)::([A-Za-z0-9_]+)\s*\(')
  foreach ($match in $matches) {
    $scriptName = $match.Groups[1].Value
    $function = $match.Groups[2].Value
    $checks++

    $target = Find-Script $scriptName
    if ($null -eq $target) {
      $errors++
      "{0}: missing script '{1}' (called {2}::{3})" -f $file.FullName.Replace($Root, '.'), $scriptName, $scriptName, $function
      continue
    }

    if (-not (Has-Function $target $function)) {
      $errors++
      "{0}: missing function '{1}' in {2}" -f $file.FullName.Replace($Root, '.'), $function, $target.Replace($Root, '.')
    }
  }
}

if (-not $Quiet) {
  "checked {0} files, {1} cross-file calls, {2} problems" -f $files.Count, $checks, $errors
}

if ($errors -gt 0) { exit 1 }
exit 0

