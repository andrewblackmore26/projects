param([switch]$Quick, [switch]$GPU, [switch]$Exports)
# The one command that says whether the build is good.
# Exit 0 only if every gate passes AND every negative control fails the way it must.
#   -Quick    self-test, suite and benchmark budgets only (no negative controls, no exports)
#   -GPU      adds the Vulkan pixel tests (needs a real window)
#   -Exports  exports the Windows builds and runs the in-package verification
# Every line ends ok=1 or ok=0. A NEGATIVE gate is ok=1 when the sabotaged run was caught.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
$logDir = New-LogDirectory 'gates'
$script:gateResults = @()

function Add-Gate([string]$name, [bool]$ok, [double]$seconds, [string]$detail) {
    $script:gateResults += [pscustomobject]@{ Name = $name; Ok = $ok; Seconds = $seconds; Detail = $detail }
    Write-Output ("gate: {0,-34} seconds={1,7:N1} {2} ok={3}" -f $name, $seconds, $detail, [int]$ok)
}

# Runs another PowerShell script in its own process with output in files (never a stderr pipe).
function Invoke-Script([string]$name, [string]$scriptArguments, [int]$timeoutSec) {
    $outFile = Join-Path $logDir "$name.out.txt"; $errFile = Join-Path $logDir "$name.err.txt"
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File ' + $scriptArguments) `
        -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $null = $process.Handle
    $timedOut = -not $process.WaitForExit($timeoutSec * 1000)
    if ($timedOut) { & taskkill.exe /PID $process.Id /T /F | Out-Null; $code = -1 } else { $process.WaitForExit(); $code = $process.ExitCode }
    $watch.Stop()
    $lines = @(); if (Test-Path -LiteralPath $outFile) { $lines = @(Get-Content -LiteralPath $outFile -Encoding UTF8) }
    return [pscustomobject]@{ ExitCode = $code; Seconds = [math]::Round($watch.Elapsed.TotalSeconds, 1); Out = $lines }
}

function Get-LastLine($lines, [string]$pattern) {
    return [string](@($lines | Where-Object { $_ -cmatch $pattern }) | Select-Object -Last 1)
}

# Counts "measure:" lines matching $filter that end ok=0 / ok=1. -cmatch with delimiters: "fillOk=0" must not match "ok=0".
function Measure-Lines($lines, [string]$filter) {
    $selected = @($lines | Where-Object { $_ -cmatch '^measure:' -and $_ -cmatch $filter })
    return [pscustomobject]@{
        Total = $selected.Count
        Failed = @($selected | Where-Object { $_ -cmatch '(^|\s)ok=0(\s|$)' }).Count
        Passed = @($selected | Where-Object { $_ -cmatch '(^|\s)ok=1(\s|$)' }).Count
    }
}

$testScript = '"' + (Join-Path $PSScriptRoot 'test.ps1') + '"'

$run = Invoke-Script 'selftest' ($testScript + ' -SelfTest') 300
Add-Gate 'harness self-test' ($run.ExitCode -eq 0) $run.Seconds (Get-LastLine $run.Out '^selftest: the runner')

$suiteArguments = $testScript; if ($GPU) { $suiteArguments += ' -GPU' }
$run = Invoke-Script 'suite' $suiteArguments 3600
Add-Gate 'test suite' ($run.ExitCode -eq 0) $run.Seconds (Get-LastLine $run.Out '^suite:')

$bench = Invoke-Godot '--headless --script "res://tests/combat_benchmark.gd" -- --assert' $logDir 'benchmark' 600
$lines = Measure-Lines $bench.Out '.'
Add-Gate 'benchmark budgets' ($bench.ExitCode -eq 0 -and $lines.Total -gt 0 -and $lines.Failed -eq 0) $bench.Seconds (Get-LastLine $bench.Out '^COMBAT BENCHMARK GATE')

if (-not $Quick) {
    # Each instrument line gets its own sabotage: budgets at 1 % must fail the timing lines,
    # a doubled fill requirement must fail the pool-fill lines.
    $bench = Invoke-Godot '--headless --script "res://tests/combat_benchmark.gd" -- --assert --budget-scale=0.01' $logDir 'benchmark-negative-budget' 600
    $timing = Measure-Lines $bench.Out '(mean|p95)_ms='
    Add-Gate 'NEGATIVE benchmark budgets at 1%' ($bench.ExitCode -ne 0 -and $timing.Total -gt 0 -and $timing.Failed -eq $timing.Total) $bench.Seconds ("timing lines failed {0}/{1}" -f $timing.Failed, $timing.Total)

    $bench = Invoke-Godot '--headless --script "res://tests/combat_benchmark.gd" -- --assert --fill-scale=2' $logDir 'benchmark-negative-fill' 600
    $fill = Measure-Lines $bench.Out 'required='
    Add-Gate 'NEGATIVE benchmark fill doubled' ($bench.ExitCode -ne 0 -and $fill.Total -gt 0 -and $fill.Failed -eq $fill.Total) $bench.Seconds ("fill lines failed {0}/{1}" -f $fill.Failed, $fill.Total)
}

if ($Exports -and -not $Quick) {
    foreach ($flavor in @('', ' -Demo')) {
        $label = 'campaign'; if ($flavor) { $label = 'demo' }
        $run = Invoke-Script "export-$label" ('"' + (Join-Path $PSScriptRoot 'export.ps1') + '" -Platform windows' + $flavor) 1800
        Add-Gate "export windows $label" ($run.ExitCode -eq 0) $run.Seconds ''
    }
    $run = Invoke-Script 'verify-exports' ('"' + (Join-Path $PSScriptRoot 'verify_exports.ps1') + '"') 900
    $verified = @($run.Out | Where-Object { $_ -cmatch 'runtime checks passed' }).Count
    Add-Gate 'exported packages verify' ($run.ExitCode -eq 0 -and $verified -eq 2) $run.Seconds ("packages passed {0}/2" -f $verified)
}

$failed = @($script:gateResults | Where-Object { -not $_.Ok })
$total = [math]::Round((($script:gateResults | Measure-Object -Property Seconds -Sum).Sum), 1)
[pscustomobject]@{ finished_at = (Get-Date -Format 's'); quick = [bool]$Quick; gpu = [bool]$GPU; exports = [bool]$Exports; total_seconds = $total; gates = $script:gateResults } |
    ConvertTo-Json -Depth 4 | Out-File -LiteralPath (Join-Path $script:ProjectRoot 'artifacts\gates-summary.json') -Encoding utf8
Write-Output ("gates: {0}/{1} ok, {2:N1}s. Logs: {3}" -f ($script:gateResults.Count - $failed.Count), $script:gateResults.Count, $total, $logDir)
if ($failed.Count -gt 0) { Write-Output ('FAILED: ' + (($failed | ForEach-Object { $_.Name }) -join ', ')); exit 1 }
exit 0
