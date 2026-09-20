param([switch]$GPU, [switch]$SelfTest, [string]$Only = '', [int]$TimeoutSec = 900)
# Runs the headless GDScript suite (and, with -GPU, the Vulkan pixel tests).
# Discovery and fail-fast are unchanged from v0.2; what changed is how a run is judged (tools\lib.ps1):
# output goes to files, every launch has a timeout, a test must print a summary line, and
# SHADER ERROR counts as a failure. -SelfTest proves the runner itself can fail.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

function Write-Verdict($verdict) {
    $state = 'FAIL'; if ($verdict.Passed) { $state = 'PASS' }
    $detail = $verdict.Summary; if (-not $verdict.Passed) { $detail = $verdict.Reasons }
    Write-Output ("{0}  {1,7:N2}s  {2}  {3}" -f $state, $verdict.Seconds, $verdict.Name, $detail)
}

if ($SelfTest) {
    # Each negative must be reported FAILED for its own reason; the positive control must PASS.
    $logDir = New-LogDirectory 'selftest'
    $cases = @(
        @{ Name = 'passing'; Expect = $true;  Reason = '' },
        @{ Name = 'failing'; Expect = $false; Reason = 'exit code 1' },
        @{ Name = 'silent';  Expect = $false; Reason = 'no summary line' },
        @{ Name = 'error';   Expect = $false; Reason = 'engine error' },
        @{ Name = 'hang';    Expect = $false; Reason = 'timed out' }
    )
    $bad = 0
    foreach ($case in $cases) {
        $run = Invoke-Godot ('--headless --script "res://tests/harness_negative/{0}_test.gd"' -f $case.Name) $logDir $case.Name 15
        $verdict = Get-TestVerdict $run $true
        $ok = ($verdict.Passed -eq $case.Expect) -and ($case.Expect -or $verdict.Reasons.Contains($case.Reason))
        if (-not $ok) { $bad++ }
        Write-Output ("selftest: {0,-8} passed={1} reasons='{2}' expected_passed={3} ok={4}" -f $case.Name, [int]$verdict.Passed, $verdict.Reasons, [int]$case.Expect, [int]$ok)
    }
    if ($bad -gt 0) { throw "Harness self-test failed: $bad case(s) misjudged. Logs: $logDir" }
    Write-Output 'selftest: the runner fails what must fail and passes what must pass'
    exit 0
}

$logDir = New-LogDirectory 'suite'
$suiteWatch = [System.Diagnostics.Stopwatch]::StartNew()
$results = @()

$import = Get-TestVerdict (Invoke-Godot '--headless --editor --import --quit' $logDir 'import' 600) $false
Write-Verdict $import
if (-not $import.Passed) { throw "Project import failed. Logs: $logDir" }
$results += $import

$testFiles = Get-ChildItem -LiteralPath (Join-Path $script:ProjectRoot 'tests') -Filter '*.gd' |
    Where-Object { $_.Name -match '_test\.gd$|_tests\.gd$|^ships_validation\.gd$' } |
    Where-Object { -not $Only -or $_.Name -like "*$Only*" }
# GPU pixel tests need a real window; they are selected by name pattern so a new one can never be skipped silently.
$headlessTests = @($testFiles | Where-Object { $_.Name -notmatch '_render_test\.gd$' })
$gpuTests = @($testFiles | Where-Object { $_.Name -match '_render_test\.gd$' })

$failed = $null
foreach ($testFile in $headlessTests) {
    $run = Invoke-Godot ('--headless --script "res://tests/{0}"' -f $testFile.Name) $logDir $testFile.BaseName $TimeoutSec
    $verdict = Get-TestVerdict $run $true
    Write-Verdict $verdict
    $results += $verdict
    if (-not $verdict.Passed) { $run.Out + $run.Err | Select-Object -Last 40 | Write-Output; $failed = $testFile.Name; break }
}
if (-not $failed -and $GPU) {
    foreach ($testFile in $gpuTests) {
        $run = Invoke-Godot ('--script "res://tests/{0}"' -f $testFile.Name) $logDir $testFile.BaseName $TimeoutSec
        $verdict = Get-TestVerdict $run $true
        Write-Verdict $verdict
        $results += $verdict
        if (-not $verdict.Passed) { $run.Out + $run.Err | Select-Object -Last 40 | Write-Output; $failed = $testFile.Name; break }
    }
}
$suiteWatch.Stop()

$summary = [pscustomobject]@{
    finished_at = (Get-Date -Format 's'); gpu = [bool]$GPU; only = $Only
    total_seconds = [math]::Round($suiteWatch.Elapsed.TotalSeconds, 2)
    passed = @($results | Where-Object { $_.Passed }).Count; failed = @($results | Where-Object { -not $_.Passed }).Count
    gpu_tests_skipped = $(if ($GPU) { 0 } else { $gpuTests.Count })
    log_directory = $logDir; results = $results
}
$summaryPath = Join-Path $script:ProjectRoot 'artifacts\test-summary.json'
$summary | ConvertTo-Json -Depth 4 | Out-File -LiteralPath $summaryPath -Encoding utf8
Write-Output ("suite: {0} passed, {1} failed, {2} GPU test(s) skipped, {3:N1}s total. Summary: {4}" -f $summary.passed, $summary.failed, $summary.gpu_tests_skipped, $summary.total_seconds, $summaryPath)
if ($failed) { throw "Test failed: $failed. Logs: $logDir" }
