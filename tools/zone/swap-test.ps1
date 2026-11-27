# A/B a zone swap - moved from _migration\archive\mwx-debug\zone-stall\swap-test.ps1 on 27 Nov 2026.
# Step Z / hypothesis 2: swap the startup zone list and load mp_crash.
#
#   .\swap-test.ps1 -Case a -Zones "hmw_killstreak,hmw_attachments,hmw_ar1,hmw_smg,hmw_shotgun,hmw_rangers,hmw_stalltest"
#
# Writes mwx-logs/zone-list.txt (the temporary patches.cpp experiment reads it instead of the
# built-in list), starts one client, loads the map, and reports PASS/STALL with the last zone
# started. On a stall it writes a minidump and the process memory (call .\dump-process.ps1).
param(
    [Parameter(Mandatory = $true)][string]$Case,
    [Parameter(Mandatory = $true)][string]$Zones,
    [string]$Map = "mp_crash",
    [int]$Port = 27980,
    [int]$TimeoutSeconds = 180,
    [switch]$Dump,
    [switch]$Stacks
)
$ErrorActionPreference = "Stop"
$g = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered"
$exe = Join-Path $g "mwx.exe"
$logRoot = "C:\Games\cod-hwm\_migration\archive\mwx-debug\zone-stall"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$log = Join-Path $logRoot "$Case-$Map.log"
$err = "$log.err"
$zoneList = Join-Path $g "mwx-logs\zone-list.txt"

$ZoneNames = @($Zones -split ',' | Where-Object { $_ })
Set-Content -Path $zoneList -Value ($ZoneNames -join "`n") -NoNewline
Write-Host ("case {0}: {1} zones ({2})" -f $Case, $ZoneNames.Count, ($ZoneNames -join ', '))

$memSrc = @"
using System;
using System.Runtime.InteropServices;
public static class MemReader2 {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr baseAddr, byte[] buffer, IntPtr size, out IntPtr bytesRead);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr h);
}
"@
Add-Type -TypeDefinition $memSrc

function Read-RemoteBytes([int]$procId, [long]$address, [int]$length) {
    $h = [MemReader2]::OpenProcess(0x0010, $false, $procId)
    if ($h -eq [IntPtr]::Zero) { throw "OpenProcess failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    $buf = New-Object byte[] $length
    $read = [IntPtr]::Zero
    try {
        $ok = [MemReader2]::ReadProcessMemory($h, [IntPtr]$address, $buf, [IntPtr]$length, [ref]$read)
    } finally { [MemReader2]::CloseHandle($h) | Out-Null }
    if (-not $ok) { throw "ReadProcessMemory failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    return $buf
}

# engine state at the stall: g_zoneCount (0x3D10088) and g_zones (0x5F292B0, XZone 504 B, name at +32)
function Write-ZoneState([int]$procId, [string]$case, [string]$map) {
    $base = 0x140000000
    $countBuf = Read-RemoteBytes $procId ($base + 0x3D10088) 8
    $count = [BitConverter]::ToUInt32($countBuf, 0)
    $zoneIndex = [BitConverter]::ToUInt32($countBuf, 4)
    $names = @()
    $raw = Read-RemoteBytes $procId ($base + 0x5F292B0) (504 * 200)
    for ($i = 0; $i -lt 200; $i++) {
        $off = $i * 504 + 32
        $str = [Text.Encoding]::ASCII.GetString($raw, $off, 64)
        $nul = $str.IndexOf([char]0)
        if ($nul -ge 0) { $str = $str.Substring(0, $nul) }
        if ($str) { $names += ("{0}:{1}" -f $i, $str) }
    }
    $line = "zone state: count={0}, zoneIndex={1}, non-empty slots={2}" -f $count, $zoneIndex, $names.Count
    Add-Content -Path (Join-Path $logRoot "swap-results.txt") -Value $line
    Write-Host $line
    Set-Content -Path (Join-Path $logRoot ("{0}-{1}-zones.txt" -f $case, $map)) -Value $names
}

function Rpc([int]$port, [string]$method, $params = @{}, [int]$timeout = 4) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 10 -Compress
    try { return Invoke-RestMethod -Uri "http://127.0.0.1:$port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout }
    catch { return [pscustomobject]@{ error = $_.Exception.Message } }
}

$p = $null
$inGame = $false
$elapsed = 0
$startup = 0
$menuMem = 0
$stallMem = 0
try {
    $startProcess = Get-Date
    $p = Start-Process -FilePath $exe -ArgumentList @("-memoryfix", "-debugport", "$Port", "+set", "mwx_test_mode", "1") `
        -WorkingDirectory $g -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
    $up = $false
    for ($i = 0; $i -lt 240; $i++) {
        if ($p.HasExited) { break }
        $s = Rpc $Port "status" @{} 2
        if ($s.result -and $s.result.main_menu) { $up = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $up) { throw "client did not reach the menu (exit=$($p.HasExited))" }
    $startup = [math]::Round(((Get-Date) - $startProcess).TotalSeconds, 1)
    $perf = Rpc $Port "perf" @{} 4
    if ($perf.result) { $menuMem = $perf.result.working_set_mb }

    foreach ($d in @(@{ name = "g_gametype"; value = "war" }, @{ name = "ui_gametype"; value = "war" }, @{ name = "ui_mapname"; value = $Map })) {
        Rpc $Port "set_dvar" $d 5 | Out-Null
    }
    Start-Sleep -Seconds 5
    Rpc $Port "command" @{ command = "map $Map" } 10 | Out-Null

    $start = Get-Date
    $countLog = @()
    $lastCount = -1
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
        if ($p.HasExited) { break }
        try {
            $countBuf = Read-RemoteBytes $p.Id (0x140000000 + 0x3D10088) 4
            $currentCount = [BitConverter]::ToUInt32($countBuf, 0)
            if ($currentCount -ne $lastCount) {
                $countLog += ("{0:N0}s count={1}" -f ((Get-Date) - $start).TotalSeconds, $currentCount)
                $lastCount = $currentCount
            }
        } catch {}
        # 1 s timeouts: at a stall every status call hangs until its timeout
        $s = Rpc $Port "status" @{} 1
        if ($s.result -and $s.result.in_game) { $inGame = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if ($countLog.Count -gt 0) {
        Set-Content -Path (Join-Path $logRoot ("{0}-{1}-zonecount.txt" -f $Case, $Map)) -Value $countLog
        Write-Host ("zone count: {0}" -f ($countLog -join ', '))
    }
    $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 0)
    if ($inGame) {
        Rpc $Port "command" @{ command = "loadedzones" } 5 | Out-Null
        Start-Sleep -Seconds 2
        try { Write-ZoneState $p.Id $Case $Map } catch { Write-Host "zone state read failed: $_" }
    }
    if (-not $inGame -and -not $p.HasExited) {
        try { Write-ZoneState $p.Id $Case $Map } catch { Write-Host "zone state read failed: $_" }
        if ($Stacks) {
            $st = Rpc $Port "stacks" @{} 20
            if ($st.result) {
                $stackFile = Join-Path $logRoot ("{0}-{1}-stacks.txt" -f $Case, $Map)
                Set-Content -Path $stackFile -Value @($st.result)
                Write-Host ("stacks written to {0} ({1} lines)" -f $stackFile, @($st.result).Count)
            } else {
                Write-Host "stacks rpc failed: $($st.error)"
            }
        }
        # the RPC loop runs on the stalled thread, so read the counters from outside
        $proc = Get-Process -Id $p.Id
        $stallMem = [math]::Round($proc.WorkingSet64 / 1MB, 0)
        $stallPrivate = [math]::Round($proc.PrivateMemorySize64 / 1MB, 0)
        $stallVirtual = [math]::Round($proc.VirtualMemorySize64 / 1MB, 0)
        $threads = @($proc.Threads | ForEach-Object {
            "{0}:{1}:{2}:{3:N1}s" -f $_.Id, $_.ThreadState, $_.WaitReason, $_.TotalProcessorTime.TotalSeconds
        })
        $threadFile = Join-Path $logRoot ("{0}-{1}-threads.txt" -f $Case, $Map)
        Set-Content -Path $threadFile -Value $threads
        $os = Get-CimInstance Win32_OperatingSystem
        $memLine = "stall memory: ws={0} MB private={1} MB virtual={2} MB; system free={3} MB commit={4} MB" -f `
            $stallMem, $stallPrivate, $stallVirtual, `
            [math]::Round($os.FreePhysicalMemory / 1KB, 0), [math]::Round(($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / 1KB, 0)
        Add-Content -Path (Join-Path $logRoot "swap-results.txt") -Value $memLine
        Write-Host $memLine
        if ($Dump) {
            $dmp = Join-Path $logRoot ("{0}-{1}.dmp" -f $Case, $Map)
            & (Join-Path $logRoot "..\dump-process.ps1") -ProcessId $p.Id -Out $dmp
        }
    }
} finally {
    if ($p -and -not $p.HasExited) {
        Rpc $Port "command" @{ command = "quit" } 5 | Out-Null
        if (-not $p.WaitForExit(8000)) { try { $p.Kill() } catch {} }
    }
}

$loadLog = Join-Path $g "mwx-logs\load_times.log"
$tail = @(Get-Content $loadLog -Tail 120 -ErrorAction SilentlyContinue)
$lastStart = @($tail | Where-Object { $_ -match '^\s+\d+ ms\s+start\s+' } | Select-Object -Last 1)
$lastStartName = ""
if ($lastStart) { $lastStartName = ($lastStart -replace '^\s+\d+ ms\s+start\s+', '').Trim() }
$pakInfo = ""
if ($lastStartName -match '^imagefile(\d+)$') {
    $pak = Join-Path $g ("zone\" + $lastStartName + ".pak")
    if (Test-Path $pak) { $pakInfo = "{0:N0} MB" -f ((Get-Item $pak).Length / 1MB) }
}
$result = if ($inGame) { "PASS" } else { "STALL" }
$line = "{0} {1} zones -> {2} in {3}s (startup {4}s, menu {5:N0} MB, stall {6:N0} MB); lastStart='{7}' {8}" -f `
    $Case, $ZoneNames.Count, $result, $elapsed, $startup, $menuMem, $stallMem, $lastStartName, $pakInfo
Write-Host $line
Add-Content -Path (Join-Path $logRoot "swap-results.txt") -Value $line
