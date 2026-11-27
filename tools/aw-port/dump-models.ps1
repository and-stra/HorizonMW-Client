# dump AW xmodels - moved from _migration\archive\mwx-debug\aw-weapons\dump-models.ps1 on 27 Nov 2026.
param(
    [string]$ZoneFile = "C:\Games\cod-hwm\_migration\archive\mwx-debug\aw-weapons\model-zones.txt",
    [int]$InitSeconds = 95,
    [int]$MaxPerZoneSeconds = 180,
    [int]$StableSeconds = 5,
    [switch]$SkipExisting
)
$ErrorActionPreference = "Stop"
$aw = "C:\Games\cod-hwm\Call of Duty Advanced Warfare"
$tool = Join-Path $aw "zonetool.exe"
$dumpRoot = Join-Path $aw "dump\weapon_models"
$logDir = "C:\Games\cod-hwm\_migration\archive\mwx-debug\aw-weapons"
New-Item -ItemType Directory -Force -Path $dumpRoot, $logDir | Out-Null
$log = Join-Path $logDir "dump-models.log"

$zones = @(Get-Content $ZoneFile | Where-Object { $_ -and -not $_.StartsWith("#") })
Write-Host ("dump {0} AW model zones" -f $zones.Count)

function Log([string]$text) {
    $line = "{0} {1}" -f (Get-Date -Format "HH:mm:ss"), $text
    Write-Host $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $tool
$psi.Arguments = "-unbuffered-io"
$psi.WorkingDirectory = $aw
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
if ($p.HasExited) { Log ("tool exited during init with code {0}" -f $p.ExitCode); exit 1 }

function Wait-Marker([string]$zone, [int]$maxSeconds) {
    $marker = Join-Path $dumpRoot "$zone.csv"
    $deadline = (Get-Date).AddSeconds($maxSeconds)
    $lastSize = -1
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $marker) {
            $size = (Get-Item $marker).Length
            if ($size -gt 0 -and $size -eq $lastSize) {
                Start-Sleep -Seconds $StableSeconds
                if ((Get-Item $marker).Length -eq $size) { return $true }
            }
            $lastSize = $size
        }
        if ($p.HasExited) { return $false }
        Start-Sleep -Seconds 2
    }
    return $false
}

foreach ($zone in $zones) {
    $zone = $zone.Trim()
    if (-not $zone) { continue }
    $marker = Join-Path $dumpRoot "$zone.csv"
    if ($SkipExisting -and (Test-Path $marker)) { Log ("skip {0}" -f $zone); continue }
    Log ("dumpzone h1 {0}" -f $zone)
    $p.StandardInput.WriteLine("dumpzone h1 $zone")
    $p.StandardInput.Flush()
    $ok = Wait-Marker $zone $MaxPerZoneSeconds
    if (-not $ok -and -not $p.HasExited) {
        Log ("  no marker for {0}, retry" -f $zone)
        $p.StandardInput.WriteLine("dumpzone h1 $zone")
        $p.StandardInput.Flush()
        $ok = Wait-Marker $zone 120
    }
    if (-not $ok) { Log ("  no marker for {0}" -f $zone) }
}

Log "all zones sent, quitting"
try { $p.StandardInput.WriteLine("quit"); $p.StandardInput.Flush() } catch {}
if (-not $p.WaitForExit(15000)) { try { $p.Kill() } catch {} }
Log "finished"
