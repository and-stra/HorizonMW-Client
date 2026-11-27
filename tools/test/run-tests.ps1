<#
  Runs MWX game mode tests (GAME\mwx\tests\tests.json) through the debug RPC,
  without the MCP bridge (same logic as mcp.cpp run_test / run_all_tests).

  Usage:
    .\run-tests.ps1                      # all tests, one server at a time
    .\run-tests.ps1 -Parallel 4          # four dedicated servers at once
    .\run-tests.ps1 -Name infect         # one test
    .\run-tests.ps1 -Name infect -KeepServer

  Writes one line per test to stdout and a JSON summary at the end. With -Parallel N the
  tests are split over N child runner processes (block, not round-robin: each child takes
  the next test when it is done); every test still gets its own debug and net port and its
  own log file, and the child result JSONs are merged into the one summary.
#>
param(
    [string]$Name = "all",
    [string]$GameDir = "C:\Games\cod-hwm\Call of Duty Horizon Modern Warfare\Call of Duty Modern Warfare Remastered",
    [string]$Manifest = "",
    [switch]$KeepServer,
    [int]$BasePort = 27200,
    [int]$BaseNetPort = 27016,
    [int]$Parallel = 4,
    # child-runner mode: write the summary here instead of the default location
    [string]$JsonOut = ""
)

$ErrorActionPreference = "Stop"

if (-not $Manifest) { $Manifest = Join-Path $GameDir "mwx\tests\tests.json" }
$exe = Join-Path $GameDir "mwx.exe"
if (-not (Test-Path $exe)) { throw "missing $exe" }
if (-not (Test-Path $Manifest)) { throw "missing $Manifest" }

$tests = Get-Content $Manifest -Raw | ConvertFrom-Json
if ($Name -ne "all") { $tests = @($tests | Where-Object { $_.name -eq $Name }) ; if (-not $tests) { throw "unknown test $Name" } }

$script:portCounter = $BasePort
$script:netPortCounter = $BaseNetPort
$script:assignedNetPorts = @{}

function Find-FreeNetPort([int]$start) {
    # Steam holds UDP ports in the 2700x-2704x range on some PCs (27036 here). A port that is
    # taken by another program never becomes free, so do not wait for it - take the next one.
    for ($p = $start; $p -lt ($start + 200); $p++) {
        if ($script:assignedNetPorts.ContainsKey($p)) { continue }
        $used = Get-NetUDPEndpoint -LocalPort $p -ErrorAction SilentlyContinue
        if (-not $used) {
            $script:assignedNetPorts[$p] = 1
            return $p
        }
    }
    return $start
}

function Wait-NetPortFree([int]$netPort) {
    # a stopped server can hold its UDP port for a moment; the next server would exit on bind
    for ($i = 0; $i -lt 30; $i++) {
        $used = Get-NetUDPEndpoint -LocalPort $netPort -ErrorAction SilentlyContinue
        if (-not $used) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

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

function Run-TestOnce($test) {
    $port = $script:portCounter++
    $netPort = Find-FreeNetPort $script:netPortCounter
    $script:netPortCounter = $netPort + 1

    $dvars = @{}
    if ($test.dvars) { foreach ($p in $test.dvars.PSObject.Properties) { $dvars[$p.Name] = "$($p.Value)" } }
    $dvars["mwx_test"] = $test.script
    if (-not $dvars.ContainsKey("net_port")) { $dvars["net_port"] = "$netPort" }

    # the mod flag must come before +set commands (the game flag parser ignores it after them)
    $listen = [bool]$test.listen
    $argList = if ($listen) { "-memoryfix -debugport $port" } else { "-dedicated -memoryfix -debugport $port" }
    if ($test.mod) { $argList += " -mod `"$($test.mod)`"" }
    $argList += " +set mwx_test_mode 1"
    foreach ($k in ($dvars.Keys | Sort-Object)) { $argList += " +set $k `"$($dvars[$k])`"" }
    if ($test.gametype -and -not $listen) { $argList += " +set g_gametype `"$($test.gametype)`"" }
    if ($test.map -and -not $listen) { $argList += " +map `"$($test.map)`"" }
    if ($test.args) { $argList += " $($test.args)" }

    if (-not (Wait-NetPortFree $netPort)) {
        return [ordered]@{ test = $test.name; error = "net port $netPort is still in use"; port = $port; net_port = $netPort }
    }

    $start = Get-Date
    $log = Join-Path $env:TEMP "mwx-test-$($test.name)-$port.log"
    $errLog = Join-Path $env:TEMP "mwx-test-$($test.name)-$port.err.log"
    Write-Host ("  $($test.name): debug port $port, net port $netPort")
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
        net_port = $netPort
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
        # a listen client boots to the menu: wait for its debug server, set the gametype/map
        # dvars, then issue `map` (the engine's `map` works from the menu; a map on the command
        # line would load before the client is up)
        if ($listen) {
            $up = $false
            $status = $null
            for ($i = 0; $i -lt 240; $i++) {
                $status = Rpc $port "status" @{} 2
                if ($status.result) { $up = $true; break }
                if ($process.HasExited) { break }
                Start-Sleep -Seconds 1
            }

            if ($up) {
                Rpc $port "set_dvar" @{ name = "g_gametype"; value = "$($test.gametype)" } 5 | Out-Null
                Rpc $port "set_dvar" @{ name = "ui_gametype"; value = "$($test.gametype)" } 5 | Out-Null
                Rpc $port "set_dvar" @{ name = "ui_mapname"; value = "$($test.map)" } 5 | Out-Null
                Rpc $port "set_dvar" @{ name = "mwx_test"; value = "$($test.script)" } 5 | Out-Null
                foreach ($k in $dvars.Keys) {
                    if ($k -eq "mwx_test") { continue }
                    Rpc $port "set_dvar" @{ name = $k; value = "$($dvars[$k])" } 5 | Out-Null
                }
                Rpc $port "command" @{ command = "map $($test.map)" } 10 | Out-Null
            }
        }

        $running = $false
        for ($i = 0; $i -lt 240; $i++) {
            $status = Rpc $port "status" @{} 2
            if ($status.result -and $status.result.sv_running -and (-not $listen -or $status.result.in_game)) { $running = $true; break }
            if ($process.HasExited) { break }
            Start-Sleep -Seconds 1
        }

        if (-not $running) {
            $result.error = if ($process.HasExited) { "server exited (code $($process.ExitCode), log $log)" } else { "the server did not start the map" }
            if ($process.HasExited -and (Test-Path $log) -and (Get-Item $log).Length -eq 0) {
                # Startup hazard: the engine can exit before it writes a single console line
                # ("silent startup exit", no dump). A huge process-spacing window or a failed
                # startup lock is the usual reason - retry once like menu-smoke does.
                $result.silent_exit = $true
            }
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
        $logs = New-Object System.Collections.ArrayList
        $killWeapons = New-Object System.Collections.Generic.HashSet[string]
        $killCount = 0

        foreach ($e in $events) {
            switch ($e.type) {
                "script_error" { $result.script_errors++ }
                "test_started" { $startedMs = [int64]$e.time_ms }
                "test_step" { [void]$steps.Add($e.data) }
                "test_log" { [void]$logs.Add($e.data) }
                "test_done" { $doneMs = [int64]$e.time_ms; $result.done = ($e.data.ok -ne 0) }
                "kill" {
                    $killCount++
                    if ($e.data.weapon) { [void]$killWeapons.Add([string]$e.data.weapon) }
                }
                "test_assert" {
                    $ok = $false
                    if ($null -ne $e.data.ok) { $ok = ([double]$e.data.ok -ne 0) }
                    if ($ok) { $result.passed++ } else { $result.failed++; [void]$failures.Add($e.data) }
                }
            }
        }

        $result.kills = $killCount
        $result.kill_weapons = @($killWeapons)

        $result.failures = $failures.ToArray()
        $result.steps = $steps.ToArray()
        $result.logs = $logs.ToArray()
        $result.duration_s = if ($doneMs -gt $startedMs) { [math]::Round(($doneMs - $startedMs) / 1000.0, 1) } else { 0 }
        if (-not ($events | Where-Object { $_.type -eq "test_done" })) {
            if ($process.HasExited) {
                $result.error = "server exited (code $($process.ExitCode))"
            } else {
                $result.error = "timeout waiting for test_done"
            }
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

function Run-Test($test) {
    $first = Run-TestOnce $test
    if (-not $first.silent_exit) { return $first }

    Write-Host ("  {0}: silent startup exit; retrying once" -f $test.name)
    Start-Sleep -Seconds 20
    $second = Run-TestOnce $test
    $second.retried_after_silent_exit = $true
    return $second
}

function Write-Summary($all)
{
    $summary = [ordered]@{
        tests = $all.Count
        green = @($all | Where-Object { -not $_.error -and $_.failed -eq 0 -and $_.script_errors -eq 0 -and $_.done }).Count
        results = $all
    }
    try {
        $json = $summary | ConvertTo-Json -Depth 12
    } catch {
        # Windows PowerShell 5.1 ConvertTo-Json can throw on a nested event value ("Cannot convert
        # value ... to type System.String"); the child runner then never wrote its result file and
        # the parallel parent waited forever. Always write a flat, parseable summary.
        Write-Host ("summary serialization failed ({0}); writing the flat fallback" -f $_.Exception.Message)
        $flat = foreach ($r in $all) {
            [ordered]@{
                test = [string]$r.test
                passed = [int]$r.passed
                failed = [int]$r.failed
                script_errors = [int]$r.script_errors
                done = [bool]$r.done
                error = [string]$r.error
                total_s = [double]$r.total_s
                failures = @($r.failures | ForEach-Object {
                    [ordered]@{ name = [string]$_.name; expected = [string]$_.expected; actual = [string]$_.actual }
                })
            }
        }
        $json = [ordered]@{
            tests = @($flat).Count
            green = @($flat | Where-Object { -not $_.error -and $_.failed -eq 0 -and $_.script_errors -eq 0 -and $_.done }).Count
            results = @($flat)
        } | ConvertTo-Json -Depth 8
    }
    $out = if ($JsonOut) { $JsonOut } else { Join-Path (Split-Path $PSCommandPath) ("test-results-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss")) }
    $json | Set-Content -Path $out -Encoding UTF8
    Write-Host "summary written to $out"
    Write-Host ("GREEN {0}/{1}" -f $summary.green, $summary.tests)
    return $summary
}

function Write-TestResult($r, $name)
{
    $state = if ($r.error) { "ERROR: $($r.error)" } elseif ($r.failed -eq 0 -and $r.script_errors -eq 0 -and $r.done) { "PASS" } else { "FAIL" }
    Write-Host ("{0}: passed={1} failed={2} script_errors={3} {4}s {5}" -f $name, $r.passed, $r.failed, $r.script_errors, $r.total_s, $state)
    foreach ($f in $r.failures) { Write-Host ("  FAIL {0}: expected {1}, got {2}" -f $f.name, $f.expected, $f.actual) }
}

$all = New-Object System.Collections.ArrayList

if ($Parallel -gt 1 -and @($tests).Count -gt 1)
{
    # Child processes: one runner per slot, each child runs one test and writes its own JSON.
    $tmp = Join-Path $env:TEMP ("mwx-parallel-" + (Get-Date -Format "yyyyMMdd-HHmmss") + "-" + $PID)
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    $queue = New-Object System.Collections.Queue
    $i = 0
    foreach ($test in $tests) {
        $queue.Enqueue([pscustomobject]@{ index = $i; test = $test; port = $BasePort + $i; netPort = (Find-FreeNetPort ($BaseNetPort + $i)) })
        $i++
    }

    $workerArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Manifest) { $workerArgs += " -Manifest `"$Manifest`"" }

    $running = @()
    $results = @($null) * (@($tests).Count)
    $jobs = New-Object System.Collections.ArrayList

    function Start-Worker($item)
    {
        $outJson = Join-Path $tmp ("result-{0}-{1}.json" -f $item.index, $item.test.name)
        $outLog = Join-Path $tmp ("run-{0}-{1}.log" -f $item.index, $item.test.name)
        # dedupe -BasePort/-BaseNetPort: the child only needs the ports of its one test
        $a = $workerArgs + " -Name `"$($item.test.name)`" -BasePort $($item.port) -BaseNetPort $($item.netPort) -JsonOut `"$outJson`""
        $p = Start-Process -FilePath powershell.exe -ArgumentList $a -NoNewWindow -PassThru `
            -RedirectStandardOutput $outLog -RedirectStandardError ($outLog + ".err")
        return [pscustomobject]@{ process = $p; item = $item; json = $outJson; log = $outLog }
    }

    while ($queue.Count -gt 0 -or $running.Count -gt 0)
    {
        while ($running.Count -lt $Parallel -and $queue.Count -gt 0)
        {
            # The engine's early startup cannot overlap another instance's early startup: a
            # second process started while the first is still initializing exits silently (no
            # output, no dump). Start the next worker only after the previous game answers the
            # debug RPC. The client itself also serializes init with a named mutex
            # (load_timing::acquire_startup_lock), so manual launches are safe too.
            if ($running.Count -gt 0)
            {
                $previous = $running[$running.Count - 1]
                $deadline = (Get-Date).AddSeconds(180)
                while ((Get-Date) -lt $deadline -and -not $previous.process.HasExited)
                {
                    $ready = Rpc $previous.item.port "status" @{} 1
                    if ($ready.result) { break }
                    Start-Sleep -Milliseconds 500
                }
            }
            $running += Start-Worker $queue.Dequeue()
        }

        $finished = @($running | Where-Object { $_.process.HasExited })
        if (-not $finished) {
            Start-Sleep -Milliseconds 500
            continue
        }

        foreach ($w in $finished) {
            $running = @($running | Where-Object { $_.process.Id -ne $w.process.Id })
            $r = $null
            if (Test-Path $w.json) {
                try { $r = (Get-Content $w.json -Raw | ConvertFrom-Json).results[0] } catch { $r = $null }
            }
            if (-not $r) {
                $tail = @()
                if (Test-Path $w.log) { $tail = Get-Content $w.log -Tail 20 }
                $r = [ordered]@{ test = $w.item.test.name; error = "child runner failed (exit $($w.process.ExitCode))"; port = $w.item.port; net_port = $w.item.netPort; console_tail = $tail }
            }
            $results[$w.item.index] = $r
            Write-TestResult $r $w.item.test.name
        }
    }

    foreach ($r in $results) { [void]$all.Add($r) }
}
else
{
    foreach ($test in $tests) {
        Write-Host ("=== {0} ({1} on {2}) ===" -f $test.name, $test.gametype, $test.map)
        $r = Run-Test $test
        [void]$all.Add($r)
        Write-TestResult $r $test.name
    }
}

$summary = Write-Summary $all
