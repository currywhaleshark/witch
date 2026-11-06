<#
.SYNOPSIS
Runs the Godot regression suite (game/tests/regression_suite.json) to the end and summarizes it.

.DESCRIPTION
Unlike run_godot.ps1 -Verify, every test runs even after a failure. Each test gets its own log
and --output folder under reports/regression/runs/<stamp>/. Tracked files under reports/ that a
test rewrites are restored afterwards (use -KeepReports to keep them); other changed or new files
are only listed. With -Baseline the exit code reflects only tests that newly fail.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File tools/run_regression.ps1 -Jobs 3
powershell -ExecutionPolicy Bypass -File tools/run_regression.ps1 -Baseline reports/regression/baseline.json
powershell -ExecutionPolicy Bypass -File tools/run_regression.ps1 -Only items,boss -GodotPath C:\Godot\Godot_v4.6.2-stable_win64.exe
#>
param(
    [string]$GodotPath,
    [string[]]$Only,
    [ValidateSet('all', 'headless', 'gpu')][string]$Group = 'all',
    [int]$Jobs = 1,
    [int]$TimeoutSec = 600,
    [int]$StallSec = 45,
    [string]$Baseline,
    [switch]$SaveBaseline,
    [switch]$KeepReports,
    [switch]$NoImport
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$gamePath = Join-Path $projectRoot 'game'
$suitePath = Join-Path $gamePath 'tests/regression_suite.json'
$baselineDefault = Join-Path $projectRoot 'reports/regression/baseline.json'

# --- Godot executable: -GodotPath, GODOT_BIN, PATH, then a portable download (as run_godot.ps1).
if (-not $GodotPath) { $GodotPath = $env:GODOT_BIN }
if (-not $GodotPath) {
    $engineCommand = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($engineCommand) { $GodotPath = $engineCommand.Source }
}
if (-not $GodotPath) {
    $downloadsPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
    $candidates = @()
    foreach ($entry in Get-ChildItem -LiteralPath $downloadsPath -Filter 'Godot_v4*win64*' -ErrorAction SilentlyContinue) {
        if ($entry.PSIsContainer) {
            $candidates += Get-ChildItem -LiteralPath $entry.FullName -Filter '*.exe' -File
        } elseif ($entry.Extension -eq '.exe') {
            $candidates += $entry
        }
    }
    $GodotPath = ($candidates | Sort-Object Name -Descending | Select-Object -First 1).FullName
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Godot 4.6 executable not found. Pass -GodotPath <path> or set GODOT_BIN.'
}

# --- Suite: every test script must be classified, so new tests are not silently skipped.
$suite = Get-Content -LiteralPath $suitePath -Raw -Encoding UTF8 | ConvertFrom-Json
$excludedPatterns = @($suite.excluded.PSObject.Properties.Name)
$listed = @{}
foreach ($name in @($suite.headless) + @($suite.gpu)) {
    if ($listed.ContainsKey($name)) { throw "Test '$name' is listed twice in regression_suite.json" }
    $listed[$name] = $true
}
$unlisted = @()
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $gamePath 'tests') -Filter '*.gd' -File) {
    $name = $file.BaseName
    if ($listed.ContainsKey($name)) { continue }
    if ($excludedPatterns | Where-Object { $name -like $_ }) { continue }
    $unlisted += $name
}
foreach ($name in @($suite.output_file) + @($suite.output_dir)) {
    if ($name -and -not $listed.ContainsKey($name)) { throw "output_file/output_dir names unknown test '$name'" }
}
foreach ($name in $listed.Keys) {
    if (-not (Test-Path -LiteralPath (Join-Path $gamePath "tests/$name.gd"))) { throw "Suite lists missing test '$name'" }
}

$plan = @()
if ($Group -ne 'gpu') { foreach ($name in @($suite.headless)) { $plan += [pscustomobject]@{ name = $name; group = 'headless' } } }
if ($Group -ne 'headless') { foreach ($name in @($suite.gpu)) { $plan += [pscustomobject]@{ name = $name; group = 'gpu' } } }
if ($Only) {
    $wanted = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($name in $wanted) { if (-not $listed.ContainsKey($name)) { throw "-Only '$name' is not in the suite" } }
    $plan = @($plan | Where-Object { $wanted -contains $_.name })
}
if ($plan.Count -eq 0) { throw 'Nothing to run.' }

# --- Run folder and git snapshot (to restore reports the tests rewrite).
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDir = Join-Path $projectRoot "reports/regression/runs/$stamp"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

function Get-GitState {
    Push-Location $projectRoot
    try {
        # git status, not git diff: with core.autocrlf a rewrite that only changes line endings
        # shows as modified in status while diff is empty, and it should be restored too.
        $modified = @(& git -c core.quotepath=off status --porcelain=v1 --untracked-files=no |
            Where-Object { $_.Length -gt 3 -and $_[1] -ne ' ' } | ForEach-Object { $_.Substring(3) })
        $untracked = @(& git ls-files --others --exclude-standard)
    } finally { Pop-Location }
    return [pscustomobject]@{ modified = $modified; untracked = $untracked }
}
$before = Get-GitState

# Newly added assets need their import cache, or tests fail to load them (same as run_godot.ps1).
if (-not $NoImport) {
    Write-Host 'Importing project resources...'
    $log = Join-Path $runDir '_import.log'
    $p = Start-Process -FilePath $GodotPath -PassThru -WindowStyle Hidden -ArgumentList `
        "--headless --path `"$gamePath`" --editor --import --quit --log-file `"$log`""
    $null = $p.Handle
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) { throw "Godot import exited with $($p.ExitCode); see $log" }
}

$outputFile = @($suite.output_file)
$outputDir = @($suite.output_dir)

function Start-Test($item) {
    # --output means a file for some tests and a folder for others (regression_suite.json says
    # which); the rest write their default reports, restored from git afterwards.
    $log = Join-Path $runDir "$($item.name).log"
    $mode = if ($item.group -eq 'headless') { '--headless ' } else { '' }
    $arguments = "$mode--audio-driver Dummy --path `"$gamePath`" --log-file `"$log`" --script res://tests/$($item.name).gd"
    $outRoot = Join-Path $runDir 'out'
    if ($outputFile -contains $item.name) {
        New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
        $arguments += " -- --output=`"$((Join-Path $outRoot "$($item.name).json").Replace('\', '/'))`""
    } elseif ($outputDir -contains $item.name) {
        $folder = Join-Path $outRoot $item.name
        New-Item -ItemType Directory -Force -Path $folder | Out-Null
        $arguments += " -- --output=`"$($folder.Replace('\', '/'))`""
    }
    $process = Start-Process -FilePath $GodotPath -PassThru -WindowStyle Hidden -ArgumentList $arguments
    $null = $process.Handle  # Keeps ExitCode readable after exit on Windows PowerShell.
    $now = Get-Date
    return [pscustomobject]@{ item = $item; process = $process; log = $log; started = $now; log_size = -1; log_changed = $now }
}

# A SceneTree test whose coroutine dies on a SCRIPT ERROR never calls quit(); stop waiting once
# such a log has been silent for $StallSec.
function Test-Stalled($run) {
    if (-not (Test-Path -LiteralPath $run.log)) { return $false }
    $size = (Get-Item -LiteralPath $run.log).Length
    if ($size -ne $run.log_size) { $run.log_size = $size; $run.log_changed = Get-Date; return $false }
    if (((Get-Date) - $run.log_changed).TotalSeconds -lt $StallSec) { return $false }
    return [bool](Select-String -LiteralPath $run.log -Pattern '^SCRIPT ERROR' -Quiet)
}

function Read-Result($run, [bool]$timedOut, [bool]$stalled) {
    $seconds = [math]::Round(((Get-Date) - $run.started).TotalSeconds, 1)
    $lines = @()
    if (Test-Path -LiteralPath $run.log) { $lines = @(Get-Content -LiteralPath $run.log -Encoding UTF8) }
    $scriptErrors = @($lines | Where-Object { $_ -match '^SCRIPT ERROR' })
    $errors = @($lines | Where-Object { $_ -match '^ERROR:' })
    # Most tests print a final JSON report with checks/failures; read it when present.
    $checks = $null; $failureCount = $null; $failureNames = @()
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i].Trim()
        if (-not $line.StartsWith('{') -or $line -notmatch '"failures"') { continue }
        try {
            $report = $line | ConvertFrom-Json
            $checks = if ($report.checks -is [array]) { $report.checks.Count } else { $report.checks }
            $failureNames = @($report.failures | ForEach-Object { if ($_ -is [string]) { $_ } else { $_ | ConvertTo-Json -Compress -Depth 3 } })
            $failureCount = $failureNames.Count
        } catch { }
        break
    }
    $exitCode = if ($timedOut -or $stalled) { $null } else { $run.process.ExitCode }
    $status = if ($stalled) { 'script_error' }
        elseif ($timedOut) { 'timeout' }
        elseif ($exitCode -ne 0) { 'fail' }
        elseif ($scriptErrors.Count -gt 0) { 'script_error' }
        else { 'pass' }
    return [pscustomobject]@{
        name = $run.item.name; group = $run.item.group; status = $status; exit_code = $exitCode
        seconds = $seconds; checks = $checks; failures = $failureCount
        failure_names = @($failureNames | Select-Object -First 20)
        script_errors = @($scriptErrors | Select-Object -First 10); error_lines = $errors.Count
        log = $run.log.Substring($projectRoot.Length + 1).Replace('\', '/')
    }
}

# --- Execute with up to $Jobs concurrent engines.
$queue = New-Object System.Collections.Queue
foreach ($item in $plan) { $queue.Enqueue($item) }
$running = @()
$results = @()
$total = $plan.Count
$suiteStart = Get-Date
Write-Host "Running $total tests with $Jobs job(s) -> $runDir"
while ($queue.Count -gt 0 -or $running.Count -gt 0) {
    while ($running.Count -lt $Jobs -and $queue.Count -gt 0) { $running += Start-Test $queue.Dequeue() }
    Start-Sleep -Milliseconds 300
    $still = @()
    foreach ($run in $running) {
        $timedOut = ((Get-Date) - $run.started).TotalSeconds -gt $TimeoutSec
        $stalled = (-not $run.process.HasExited) -and (Test-Stalled $run)
        if ($run.process.HasExited -or $timedOut -or $stalled) {
            if (-not $run.process.HasExited) { try { $run.process.Kill() } catch { } }
            else { $run.process.WaitForExit() }
            $result = Read-Result $run $timedOut $stalled
            $results += $result
            $detail = if ($result.checks -ne $null) { " checks=$($result.checks) failures=$($result.failures)" } else { '' }
            Write-Host ("[{0,3}/{1}] {2,-12} {3,-34} {4,6}s{5}" -f $results.Count, $total, $result.status.ToUpper(), $result.name, $result.seconds, $detail)
        } else { $still += $run }
    }
    $running = $still
}

# --- Restore reports the tests rewrote; list everything else that changed.
$after = Get-GitState
$newlyModified = @($after.modified | Where-Object { $before.modified -notcontains $_ })
$newUntracked = @($after.untracked | Where-Object { $before.untracked -notcontains $_ -and -not $_.StartsWith('reports/regression/') })
$restored = @()
if (-not $KeepReports) {
    $restored = @($newlyModified | Where-Object { $_.StartsWith('reports/') })
    if ($restored.Count -gt 0) {
        Push-Location $projectRoot
        try { & git checkout -- @restored } finally { Pop-Location }
    }
}
$otherModified = @($newlyModified | Where-Object { $restored -notcontains $_ })

# --- Compare with a baseline and write the summary.
$comparison = $null
$regressions = @()
if ($Baseline) {
    $baselineData = Get-Content -LiteralPath $Baseline -Raw -Encoding UTF8 | ConvertFrom-Json
    $known = @{}
    foreach ($row in $baselineData.results) { $known[$row.name] = $row.status }
    $fixed = @()
    foreach ($row in $results) {
        $old = $known[$row.name]
        if ($row.status -ne 'pass' -and $old -eq 'pass') { $regressions += $row.name }
        if ($row.status -ne 'pass' -and $old -eq $null) { $regressions += $row.name }
        if ($row.status -eq 'pass' -and $old -ne $null -and $old -ne 'pass') { $fixed += $row.name }
    }
    $comparison = [ordered]@{ baseline = $Baseline; new_failures = $regressions; newly_passing = $fixed }
}

$failed = @($results | Where-Object { $_.status -ne 'pass' })
Push-Location $projectRoot
try { $commit = (& git rev-parse --short HEAD).Trim() } finally { Pop-Location }
$summary = [ordered]@{
    started = $suiteStart.ToString('s'); minutes = [math]::Round(((Get-Date) - $suiteStart).TotalMinutes, 1)
    commit = $commit; dirty_files_before = $before.modified.Count
    godot = $GodotPath; jobs = $Jobs; group = $Group
    counts = [ordered]@{ total = $results.Count; pass = $results.Count - $failed.Count; not_pass = $failed.Count }
    unlisted_tests = $unlisted
    restored_reports = $restored; other_modified_files = $otherModified; new_untracked_files = $newUntracked
    comparison = $comparison
    results = @($plan | ForEach-Object { $n = $_.name; $results | Where-Object { $_.name -eq $n } })
}
$summaryJson = $summary | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText((Join-Path $runDir 'summary.json'), $summaryJson + "`n", (New-Object Text.UTF8Encoding $false))
if ($SaveBaseline) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $baselineDefault) | Out-Null
    [IO.File]::WriteAllText($baselineDefault, $summaryJson + "`n", (New-Object Text.UTF8Encoding $false))
}

Write-Host ''
Write-Host ("{0}/{1} passed in {2} min. Summary: {3}" -f $summary.counts.pass, $summary.counts.total, $summary.minutes, (Join-Path $runDir 'summary.json'))
foreach ($row in $failed) { Write-Host ("  {0,-12} {1}  ({2})" -f $row.status.ToUpper(), $row.name, $row.log) }
if ($unlisted.Count -gt 0) { Write-Host "Unclassified tests (add to regression_suite.json): $($unlisted -join ', ')" }
if ($restored.Count -gt 0) { Write-Host "Restored $($restored.Count) tracked report file(s) the tests rewrote." }
if ($otherModified.Count -gt 0) { Write-Host "Tracked files outside reports/ changed during the run (left as is): $($otherModified -join ', ')" }
if ($newUntracked.Count -gt 0) { Write-Host "$($newUntracked.Count) new untracked file(s) appeared during the run; see summary.json." }
if ($SaveBaseline) { Write-Host "Baseline saved: $baselineDefault" }

if ($Baseline) {
    if ($regressions.Count -gt 0) { Write-Host "NEW FAILURES vs baseline: $($regressions -join ', ')"; exit 1 }
    Write-Host 'No new failures vs baseline.'
    exit 0
}
if ($failed.Count -gt 0) { exit 1 }
exit 0
