# dump the game's zones for the zone-check index - moved from _migration\archive\mwx-debug\mwr-weapons\dump-zones.ps1 on 27 Nov 2026.
param(
    [string]$ZoneFile = "C:\Games\cod-hwm\_migration\archive\mwx-debug\mwr-weapons\zone-dumps.txt",
    [string[]]$Zones = @(),
    [int]$InitSeconds = 120,
    [int]$MaxPerZoneSeconds = 180,
    [int]$StableSeconds = 5,
    [switch]$SkipExisting
)
$ErrorActionPreference = "Stop"
$game = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$tool = Join-Path $game "x64zt.exe"
$dumpRoot = Join-Path $game "dump"
# zones named mp_vm_* / mp_wm_* are weapon-model zones: x64zt merges them into dump\weapon_models
# and writes one <zone>.csv next to the assets.
$weaponModels = Join-Path $dumpRoot "weapon_models"
$logDir = "C:\Games\cod-hwm\_migration\archive\mwx-debug\mwr-weapons"
New-Item -ItemType Directory -Force -Path $dumpRoot, $logDir | Out-Null
$log = Join-Path $logDir "dump-zones.log"

if ($Zones.Count -eq 0) {
    $Zones = @(Get-Content $ZoneFile | Where-Object { $_ -and -not $_.StartsWith("#") })
}
Write-Host ("dump {0} zones, init {1}s, existing folders skipped: {2}" -f $Zones.Count, $InitSeconds, [bool]$SkipExisting)

function Log([string]$text) {
    $line = "{0} {1}" -f (Get-Date -Format "HH:mm:ss"), $text
    Write-Host $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $tool
$psi.Arguments = "-unbuffered-io"
$psi.WorkingDirectory = $game
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $false
$psi.RedirectStandardError = $false

$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
Log ("start {0}" -f $tool)
$null = $p.Start()
Log ("waiting {0}s for ZoneTool initialization" -f $InitSeconds)
Start-Sleep -Seconds $InitSeconds
if ($p.HasExited) {
    Log ("tool exited during init with code {0}" -f $p.ExitCode)
    exit 1
}

function Wait-ZoneMarker([string]$zone, [int]$maxSeconds) {
    # x64zt writes dump\weapon_models\<zone>.csv when a weapon-model zone is finished. The
    # assets are merged into that one folder, so the CSV is the per-zone completion marker.
    $marker = Join-Path $weaponModels "$zone.csv"
    $deadline = (Get-Date).AddSeconds($maxSeconds)
    $lastSize = -1
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $marker) {
            $size = (Get-Item $marker).Length
            if ($size -gt 0 -and $size -eq $lastSize) {
                # one more quiet check so the files behind the CSV are flushed too
                Start-Sleep -Seconds $StableSeconds
                if ((Get-Item $marker).Length -eq $size) {
                    return $true
                }
            }
            $lastSize = $size
        }
        if ($p.HasExited) { return $false }
        Start-Sleep -Seconds 2
    }
    return $false
}

$done = 0
foreach ($zone in $Zones) {
    $zone = $zone.Trim()
    if (-not $zone) { continue }
    $marker = Join-Path $weaponModels "$zone.csv"
    if ($SkipExisting -and (Test-Path $marker)) {
        Log ("skip {0} (csv exists)" -f $zone)
        $done++
        continue
    }

    Log ("dumpzone {0}" -f $zone)
    $p.StandardInput.WriteLine("dumpzone $zone")
    $p.StandardInput.Flush()

    $seen = Wait-ZoneMarker $zone $MaxPerZoneSeconds
    if (-not $seen -and -not $p.HasExited) {
        # a command sent before init finished is dropped; retry once
        Log ("  no csv yet for {0}, retry" -f $zone)
        $p.StandardInput.WriteLine("dumpzone $zone")
        $p.StandardInput.Flush()
        $seen = Wait-ZoneMarker $zone 120
    }
    if (-not $seen) {
        Log ("  no csv for {0}" -f $zone)
    }
    $done++
}

Log ("all zones sent ({0}), quitting" -f $done)
try {
    $p.StandardInput.WriteLine("quit")
    $p.StandardInput.Flush()
} catch {}
if (-not $p.WaitForExit(15000)) {
    try { $p.Kill() } catch {}
}
Log "finished"
