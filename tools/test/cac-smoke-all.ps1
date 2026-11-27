# Run cac-smoke in slices, one fresh client per slice.
#   powershell -File tools\test\cac-smoke-all.ps1 [-Slice 8]
# The CAC LUI errors ("registerAnimationState" in cacdetails tabCreatorFn) after ~12 repeated
# list rebuilds in one session, so a long run restarts the client. Prints one line per case.
param(
    [int]$Slice = 8,
    [int]$Port = 27261
)
$ErrorActionPreference = "Continue"
$here = $PSScriptRoot
$manifest = Join-Path $env:TEMP "mwx-cac-manifest.json"
& py -3 (Join-Path $here "gen_cac_manifest.py") | Set-Content $manifest -Encoding UTF8
$all = @(); (Get-Content $manifest -Raw | ConvertFrom-Json) | ForEach-Object { $all += $_ }
"cac-smoke-all: $($all.Count) weapons in slices of $Slice"

$skip = 0
$results = @()
while ($skip -lt $all.Count) {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here "cac-smoke.ps1") -Skip $skip -Limit $Slice -Port $Port 2>&1
    $results += @($out)
    @($out) | Where-Object { $_ -match '^(PASS|FAIL|cac-smoke:)' } | ForEach-Object { $_ }
    $skip += $Slice
}
$passed = @($results | Where-Object { $_ -match '^PASS  ' }).Count
$failed = @($results | Where-Object { $_ -match '^FAIL  ' })
"cac-smoke-all: $passed passed, $($failed.Count) failed"
$failed | ForEach-Object { $_ }
if ($failed.Count -gt 0) { exit 1 }
