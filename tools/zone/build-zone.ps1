# zone build wrapper (zonetool + zone-check) - moved from _migration\archive\mwx-debug\mwr-weapons\build-zone.ps1 on 27 Nov 2026.
param(
    [string]$Zone = "hmw_mwr_weapons",
    [int]$TimeoutSeconds = 2400
)
$ErrorActionPreference = "Stop"
$game = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$tool = Join-Path $game "x64zt.exe"
$csv = Join-Path $game "zone_source\$Zone.csv"
$src = Join-Path $game "zonetool\$Zone"
$outFf = Join-Path $game "zone\$Zone.ff"
$outPak = Join-Path $game "zone\$Zone.pak"
$logDir = "C:\Games\cod-hwm\_migration\archive\mwx-debug\mwr-weapons"
$log = Join-Path $logDir "build-$Zone.log"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

if (-not (Test-Path $csv)) { throw "missing $csv" }
if (-not (Test-Path $src)) { throw "missing $src" }
if (-not (Test-Path $tool)) { throw "missing $tool" }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
foreach ($f in @($outFf, $outPak)) {
    if (Test-Path $f) {
        $bak = "$f.bak-$stamp"
        Move-Item $f $bak
        Write-Host ("backed up {0} -> {1}" -f $f, $bak)
    }
}

Write-Host ("building {0} from {1}" -f $Zone, $src)
$p = Start-Process -FilePath $tool -ArgumentList @("-buildzone", $Zone) -WorkingDirectory $game -PassThru `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err"
if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
    try { $p.Kill() } catch {}
    throw ("build timed out after {0}s (log {1})" -f $TimeoutSeconds, $log)
}
Write-Host ("exit code {0}" -f $p.ExitCode)
$tail = Get-Content $log -Tail 30 -ErrorAction SilentlyContinue
$tail | ForEach-Object { Write-Host $_ }
if (-not (Test-Path $outFf)) {
    throw ("no output fastfile {0} (log {1})" -f $outFf, $log)
}
$ff = Get-Item $outFf
$pak = if (Test-Path $outPak) { Get-Item $outPak } else { $null }
Write-Host ("built {0}: {1:N1} MB{2}" -f $Zone, ($ff.Length / 1MB), $(if ($pak) { ", pak {0:N1} MB" -f ($pak.Length / 1MB) } else { "" }))

# --- zone-check: no asset name may exist in a zone loaded before ours with different content
$checker = "C:\Games\cod-hwm\cod-mwx\tools\zone-check\zone_check.py"
$index = "C:\Games\cod-hwm\cod-mwx\tools\zone-check\index\prior.json"
if ((Test-Path $checker) -and (Test-Path $index)) {
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) { & py -3 $checker check --zone-source $src --index $index } else { & python $checker check --zone-source $src --index $index }
    if ($LASTEXITCODE -ne 0) {
        throw ("zone-check failed for {0} (exit {1}); see docs/guides/zones.md" -f $Zone, $LASTEXITCODE)
    }
} else {
    Write-Warning "zone-check skipped: $index missing (run cod-mwx\tools\zone-check\build-index.ps1)"
}
