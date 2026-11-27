# the pre-runner test driver (superseded by tools/test/run-tests.ps1) - moved from _migration\archive\mwx-debug\autonomous\run-tests.ps1 on 27 Nov 2026.
<#
  Runs MWX game mode tests (GAME\mwx\tests\tests.json) through the debug RPC,
  without the MCP bridge (same logic as mcp.cpp run_test / run_all_tests).

  Usage:
    .\run-tests.ps1                      # all tests
    .\run-tests.ps1 -Name infect         # one test
    .\run-tests.ps1 -Name infect -KeepServer

  Writes one line per test to stdout and a JSON summary at the end.
#>
param(
    [string]$Name = "all",
    [string]$GameDir = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered",
    [string]$Manifest = "",
    [switch]$KeepServer,
    [int]$BasePort = 27200
)

$ErrorActionPreference = "Stop"

if (-not $Manifest) { $Manifest = Join-Path $GameDir "mwx\tests\tests.json" }
$exe = Join-Path $GameDir "mwx.exe"
if (-not (Test-Path $exe)) { throw "missing $exe" }
if (-not (Test-Path $Manifest)) { throw "missing $Manifest" }

$tests = Get-Content $Manifest -Raw | ConvertFrom-Json
if ($Name -ne "all") { $tests = @($tests | Where-Object { $_.name -eq $Name }) ; if (-not $tests) { throw "unknown test $Name" } }

$script:portCounter = $BasePort

function Rpc([int]$port, [string]$method, $params = @{}, [int]$timeout = 5) {
    $body = @{ method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    try {
        $answer = Invoke-RestMethod -Uri "http://127.0.0.1:$port/rpc" -Method Post -Body $body -ContentType "application/json" -TimeoutSec $timeout
        return $answer
    } catch {
        return [pscustomobject]@{ error = "no answer: $($_.Exception.Message)"; not_running = $true }
    }
}

function Stop-Server($process, [int]$port) {
    if (-not $process) { return }
    try { Rpc $port "command" @{ command = "quit" } 2 | Out-Null } catch {}
    if (-not $process.HasExited) {
        if (-not $process.WaitForExit(10000)) {
            try { $process.Kill() } catch {}
            return "terminated"
        }
    }
    return "quit"
}

function Run-Test($test) {
    $port = $script:portCounter++

    $dvars = @{}
    if ($test.dvars) { foreach ($p in $test.dvars.PSObject.Properties) { $dvars[$p.Name] = "$($p.Value)" } }
    $dvars["mwx_test"] = $test.script

    $argList = "-dedicated -memoryfix -debugport $port +set mwx_test_mode 1"
    foreach ($k in ($dvars.Keys | Sort-Object)) { $argList += " +set $k `"$($dvars[$k])`"" }
    if ($test.gametype) { $argList += " +set g_gametype `"$($test.gametype)`"" }
    if ($test.mod) { $argList += " -mod `"$($test.mod)`"" }
    if ($test.map) { $argList += " +map `"$($test.map)`"" }
    if ($test.args) { $argList += " $($test.args)" }

    $start = Get-Date
    $log = Join-Path $env:TEMP "mwx-test-$($test.name)-$port.log"
    $errLog = Join-Path $env:TEMP "mwx-test-$($test.name)-$port.err.log"
    # output goes to files: no console window opens, so the run does not take the focus
    $process = Start-Process -FilePath $exe -ArgumentList $argList -WorkingDirectory $GameDir -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError $errLog

    $result = [ordered]@{
        test = $test.name
        script = $test.script
        map = $test.map
        gametype = $test.gametype
        mod = $test.mod
        port = $port
        pid = $process.Id
        passed = 0
        failed = 0
        failures = @()
        steps = @()
        script_errors = 0
        done = $false
        duration_s = 0
        total_s = 0
    }

    try {
        $running = $false
        for ($i = 0; $i -lt 240; $i++) {
            $status = Rpc $port "status" @{} 2
            if ($status.result -and $status.result.sv_running) { $running = $true; break }
            if ($process.HasExited) { break }
            Start-Sleep -Seconds 1
        }

        if (-not $running) {
            $result.error = if ($process.HasExited) { "the server exited during the map load (exit code $($process.ExitCode), log $log)" } else { "the server did not start the map" }
            if (Test-Path $log) { $result.console_tail = Get-Content $log -Tail 25 }
            return $result
        }

        $bots = 0
        if ($dvars.ContainsKey("mwx_test_bots")) { $bots = [int]$dvars["mwx_test_bots"] }
        if ($bots -gt 0) {
            Rpc $port "command" @{ command = "spawnBot $bots" } 10 | Out-Null
            Start-Sleep -Seconds 3
        }

        $timeout = if ($test.timeout_s) { [int]$test.timeout_s } else { 300 }
        $deadline = (Get-Date).AddSeconds($timeout)
        $events = @()
        $handled = @{}

        while ((Get-Date) -lt $deadline) {
            $answer = Rpc $port "events" @{ since = 0; limit = 5000 } 20
            if ($answer.result -and $answer.result.events) { $events = $answer.result.events }
            foreach ($e in $events) {
                if ($e.type -eq "test_action" -and $e.data.command -and -not $handled[$e.id]) {
                    $handled[$e.id] = $true
                    Write-Host ("  test command: {0}" -f $e.data.command)
                    Rpc $port "command" @{ command = $e.data.command } 10 | Out-Null
                }
            }
            if ($events | Where-Object { $_.type -eq "test_done" }) { break }
            if ($process.HasExited) { break }
            Start-Sleep -Seconds 1
        }

        $startedMs = 0; $doneMs = 0
        $failures = New-Object System.Collections.ArrayList
        $steps = New-Object System.Collections.ArrayList

        foreach ($e in $events) {
            switch ($e.type) {
                "script_error" { $result.script_errors++ }
                "test_started" { $startedMs = [int64]$e.time_ms }
                "test_step" { [void]$steps.Add($e.data) }
                "test_done" { $doneMs = [int64]$e.time_ms; $result.done = ($e.data.ok -ne 0) }
                "test_assert" {
                    $ok = $false
                    if ($null -ne $e.data.ok) { $ok = ([double]$e.data.ok -ne 0) }
                    if ($ok) { $result.passed++ } else { $result.failed++; [void]$failures.Add($e.data) }
                }
            }
        }

        $result.failures = $failures.ToArray()
        $result.steps = $steps.ToArray()
        $result.duration_s = if ($doneMs -gt $startedMs) { [math]::Round(($doneMs - $startedMs) / 1000.0, 1) } else { 0 }
        if (-not ($events | Where-Object { $_.type -eq "test_done" })) {
            $result.error = "timeout waiting for test_done"
            # keep the tail of the console for the report
            $console = Rpc $port "console" @{ lines = 40 } 5
            if ($console.result) { $result.console_tail = $console.result }
        }
    } finally {
        if (-not $KeepServer) { $result.stop = Stop-Server $process $port }
        $result.total_s = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
    }

    return $result
}

$all = New-Object System.Collections.ArrayList
foreach ($test in $tests) {
    Write-Host ("=== {0} ({1} on {2}) ===" -f $test.name, $test.gametype, $test.map)
    $r = Run-Test $test
    [void]$all.Add($r)
    $state = if ($r.error) { "ERROR: $($r.error)" } elseif ($r.failed -eq 0 -and $r.script_errors -eq 0 -and $r.done) { "PASS" } else { "FAIL" }
    Write-Host ("{0}: passed={1} failed={2} script_errors={3} {4}s {5}" -f $test.name, $r.passed, $r.failed, $r.script_errors, $r.total_s, $state)
    foreach ($f in $r.failures) { Write-Host ("  FAIL {0}: expected {1}, got {2}" -f $f.name, $f.expected, $f.actual) }
}

$summary = [ordered]@{
    tests = $all.Count
    green = @($all | Where-Object { -not $_.error -and $_.failed -eq 0 -and $_.script_errors -eq 0 -and $_.done }).Count
    results = $all
}
$json = $summary | ConvertTo-Json -Depth 12
$out = Join-Path (Split-Path $PSCommandPath) ("test-results-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$json | Set-Content -Path $out -Encoding UTF8
Write-Host "summary written to $out"
Write-Host ("GREEN {0}/{1}" -f $summary.green, $summary.tests)
