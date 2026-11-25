param(
    [string]$RepoRoot = "",
    [string]$GameDir = "",
    [string[]]$Maps = @(),
    [switch]$Force,
    [int]$TimeoutSeconds = 240,
    [int]$DebugPort = 27240,
    [int]$NetPort = 27260
)

# MWX: generate the Prop Hunt prop list for every map that has an xmodels dump in refs\maps but
# no data\mwx\ph_props\ph_props_<map>.csv yet.
#
#   powershell -File tools\ph-props\generate-all.ps1                 # all missing maps
#   powershell -File tools\ph-props\generate-all.ps1 -Maps mp_afghan,mp_estate
#
# One dedicated server per map (started and stopped by this script), then generate.ps1 reads the
# XModel bounds from it. Results go to tools\ph-props\generate-all.log; a map that cannot load or
# yields too few props is logged and skipped.

$ErrorActionPreference = "Stop"

if ($RepoRoot -eq "") {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
if ($GameDir -eq "") {
    $GameDir = (Resolve-Path (Join-Path $RepoRoot "..\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered")).Path
}

$exe = Join-Path $GameDir "mwx.exe"
$refsMaps = (Resolve-Path (Join-Path $RepoRoot "..\refs\maps")).Path
$outDir = Join-Path $RepoRoot "data\mwx\ph_props"
$logPath = Join-Path $PSScriptRoot "generate-all.log"
$generate = Join-Path $PSScriptRoot "generate.ps1"

function Log([string]$text) {
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $text
    Write-Host $line
    Add-Content -Path $logPath -Value $line
}

function Invoke-Rpc([int]$Port, [string]$Method, $Params) {
    $body = @{ method = $Method; params = $Params } | ConvertTo-Json -Depth 6 -Compress
    return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/rpc" -Method Post -ContentType "application/json" -Body $body -TimeoutSec 30
}

# maps with a dump, without a list yet
$todo = @()
foreach ($dir in (Get-ChildItem $refsMaps -Directory)) {
    if (!(Test-Path (Join-Path $dir.FullName "xmodels.txt"))) { continue }
    $csv = Join-Path $outDir ("ph_props_{0}.csv" -f $dir.Name)
    if (!$Force -and (Test-Path $csv)) { continue }
    $todo += $dir.Name
}
if ($Maps.Count -gt 0) {
    $Maps = $Maps | ForEach-Object { $_ -split "," } | Where-Object { $_ }
    $todo = $todo | Where-Object { $Maps -contains $_ }
}

# a fallback list exists for the maps without a dump; do not regenerate those by accident
$todo = $todo | Where-Object { $_ -ne "hmw_patch_common_mp" }

Log ("maps to generate: {0}" -f ($todo -join " "))

$results = @()
foreach ($map in $todo) {
    Log ("--- {0}: starting server" -f $map)
    $arguments = @(
        "-dedicated", "-memoryfix", "-debugport", "$DebugPort",
        "+set", "net_port", "$NetPort",
        "+set", "mwx_test_mode", "1",
        "+set", "g_gametype", "war",
        "+map", $map
    )

    $process = $null
    $ok = $false
    $reason = ""
    try {
        $process = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $GameDir -PassThru
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $loaded = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            if ($process.HasExited) { $reason = "server exited (code $($process.ExitCode))"; break }
            try {
                $status = (Invoke-Rpc $DebugPort "status" @{}).result
                if ($status.sv_running -and $status.map -eq $map) { $loaded = $true; break }
            } catch {
                # debug server not up yet
            }
        }

        if (!$loaded -and $reason -eq "") { $reason = "map did not load within $TimeoutSeconds s" }

        if ($loaded) {
            Log ("--- {0}: loaded, reading bounds" -f $map)
            & powershell -NoProfile -File $generate -Map $map -Port $DebugPort -RepoRoot $RepoRoot 2>&1 |
                ForEach-Object { Log ("    " + $_) }
            if ($LASTEXITCODE -eq 0) {
                $ok = $true
            } else {
                $reason = "generate.ps1 failed (exit $LASTEXITCODE)"
            }
        }
    } catch {
        $reason = $_.Exception.Message
    } finally {
        if ($process -and !$process.HasExited) {
            try { Invoke-Rpc $DebugPort "command" @{ command = "quit" } | Out-Null } catch {}
            if (!$process.WaitForExit(20000)) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            }
        }
        Start-Sleep -Seconds 3
    }

    $count = 0
    $csv = Join-Path $outDir ("ph_props_{0}.csv" -f $map)
    if (Test-Path $csv) { $count = (Get-Content $csv).Count }

    if ($ok) {
        Log ("OK   {0}: {1} props" -f $map, $count)
    } else {
        Log ("FAIL {0}: {1}" -f $map, $reason)
    }
    $results += [pscustomobject]@{ map = $map; ok = $ok; props = $count; reason = $reason }
}

Log "=== summary ==="
foreach ($result in $results) {
    Log ("{0,-4} {1,-18} {2,3} props  {3}" -f ($(if ($result.ok) { "OK" } else { "FAIL" })), $result.map, $result.props, $result.reason)
}
