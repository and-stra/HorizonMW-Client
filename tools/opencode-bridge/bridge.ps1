# MWX opencode bridge: Claude drops tasks into inbox\, this script runs them one at a time
# through `opencode run` and writes the report + a done marker into outbox\.
param([string]$Root = $PSScriptRoot)
$ErrorActionPreference = 'Stop'

$inbox   = Join-Path $Root 'inbox'
$work    = Join-Path $Root 'work'
$outbox  = Join-Path $Root 'outbox'
$archive = Join-Path $Root 'archive'
foreach ($d in $inbox, $work, $outbox, $archive) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

$cfg = Get-Content (Join-Path $Root 'bridge.json') -Raw | ConvertFrom-Json
$rules = Get-Content (Join-Path $Root 'executor-rules.md') -Raw
$timeoutMs = [int]$cfg.timeoutMinutes * 60 * 1000

function Write-Status([string]$state, [string]$task) {
    $s = @{ state = $state; task = $task; pid = $PID; time = (Get-Date).ToString('o') } | ConvertTo-Json -Compress
    Set-Content -Path (Join-Path $Root 'status.json') -Value $s -Encoding ascii
}

Write-Host "MWX bridge: watching $inbox (model: $($cfg.model)). Ctrl+C to stop."
while ($true) {
    $next = Get-ChildItem $inbox -Filter '*.task.md' | Sort-Object Name | Select-Object -First 1
    if (-not $next) { Write-Status 'idle' ''; Start-Sleep -Seconds 3; continue }

    $id       = $next.Name -replace '\.task\.md$', ''
    $taskFile = Join-Path $work "$id.task.md"
    $report   = Join-Path $outbox "$id.report.md"
    $log      = Join-Path $outbox "$id.log"
    $doneFile = Join-Path $outbox "$id.done.json"
    $start    = Get-Date
    $exitCode = $null; $timedOut = $false; $err = ''

    try {
        $body = Get-Content $next.FullName -Raw
        Set-Content -Path $taskFile -Value ($rules.Replace('{{REPORT}}', $report) + "`r`n`r`n# Task $id`r`n`r`n" + $body) -Encoding utf8
        Remove-Item $next.FullName
        Write-Status 'running' $id
        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] running $id"

        $msg = "You are the executor. Read the task file $taskFile and do exactly what it says. Write your report to $report."
        $model = ''
        if ($cfg.model) { $model = "-m $($cfg.model)" }
        $inner = "$($cfg.opencode) run $model `"$msg`" > `"$log`" 2>&1"
        $p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/s /c `"$inner`"" -WorkingDirectory $cfg.workdir -NoNewWindow -PassThru
        $null = $p.Handle
        if (-not $p.WaitForExit($timeoutMs)) {
            $timedOut = $true
            & taskkill.exe /T /F /PID $p.Id | Out-Null
        } else {
            $exitCode = $p.ExitCode
        }
    } catch {
        $err = $_.Exception.Message
    }

    $done = @{
        id = $id; exitCode = $exitCode; timedOut = $timedOut; error = $err
        seconds = [int]((Get-Date) - $start).TotalSeconds
        report = (Test-Path $report); finished = (Get-Date).ToString('o')
    } | ConvertTo-Json
    Set-Content -Path $doneFile -Value $done -Encoding ascii
    if (Test-Path $taskFile) { Move-Item -Force $taskFile (Join-Path $archive "$id.task.md") }
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] finished $id (exit $exitCode, timedOut $timedOut)"
}
