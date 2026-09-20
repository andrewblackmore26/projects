# Shared helpers for test.ps1 and gates.ps1. Dot-source this file.
#
# Why this exists (see tasks/lessons.md):
#  - the project path has a space, so arguments are passed as ONE explicitly quoted string;
#    an argument array leaves the space unquoted and Godot opens the project manager and never exits
#  - stdout and stderr go to FILES; piping a native exe's stderr in PowerShell 5.1 turns every
#    line into an ErrorRecord and, under ErrorActionPreference Stop, into a terminating failure
#  - every launch has a timeout and the whole process tree is killed when it expires

$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:GodotBinary = Join-Path $script:ProjectRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
$script:ErrorPattern = 'SCRIPT ERROR:|SHADER ERROR|^ERROR:'
$script:SummaryPattern = '(?i)\b(assertions|checks|failures)\b'

function New-LogDirectory([string]$label) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $script:ProjectRoot ("artifacts\test-logs\{0}-{1}" -f $stamp, $label)
    New-Item -ItemType Directory -Force $dir | Out-Null
    return $dir
}

# Runs Godot with one quoted argument string. Returns exit code, timeout flag, seconds and the log lines.
function Invoke-Godot([string]$arguments, [string]$logDir, [string]$name, [int]$timeoutSec) {
    if (-not (Test-Path -LiteralPath $script:GodotBinary)) { throw "Engine not found: $script:GodotBinary (run tools\bootstrap.ps1)" }
    $outFile = Join-Path $logDir "$name.out.txt"
    $errFile = Join-Path $logDir "$name.err.txt"
    $full = ('--path "{0}" {1}' -f $script:ProjectRoot, $arguments)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $script:GodotBinary -ArgumentList $full -NoNewWindow -PassThru `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $null = $process.Handle   # without this, ExitCode is empty after WaitForExit in PowerShell 5.1
    $timedOut = -not $process.WaitForExit($timeoutSec * 1000)
    if ($timedOut) {
        & taskkill.exe /PID $process.Id /T /F | Out-Null
        $exitCode = -1
    } else {
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    }
    $watch.Stop()
    $outLines = @(); $errLines = @()
    if (Test-Path -LiteralPath $outFile) { $outLines = @(Get-Content -LiteralPath $outFile -Encoding UTF8) }
    if (Test-Path -LiteralPath $errFile) { $errLines = @(Get-Content -LiteralPath $errFile -Encoding UTF8) }
    return [pscustomobject]@{
        Name = $name; ExitCode = $exitCode; TimedOut = $timedOut
        Seconds = [math]::Round($watch.Elapsed.TotalSeconds, 2)
        Out = $outLines; Err = $errLines; OutFile = $outFile; ErrFile = $errFile
    }
}

# Turns a run into a verdict. A test passes only if it exited 0, in time, printed a summary line,
# and neither stream carries an engine error. -cmatch: PowerShell's -match is case-insensitive.
function Get-TestVerdict($run, [bool]$requireSummary) {
    $reasons = @()
    if ($run.TimedOut) { $reasons += 'timed out' }
    elseif ($run.ExitCode -ne 0) { $reasons += "exit code $($run.ExitCode)" }
    $errorLines = @(($run.Out + $run.Err) | Where-Object { $_ -cmatch $script:ErrorPattern })
    if ($errorLines.Count -gt 0) { $reasons += "engine error: $($errorLines[0].Trim())" }
    $summary = @($run.Out | Where-Object { $_ -match $script:SummaryPattern }) | Select-Object -Last 1
    if ($requireSummary -and -not $summary) { $reasons += 'no summary line' }
    return [pscustomobject]@{
        Name = $run.Name; Passed = ($reasons.Count -eq 0); Reasons = ($reasons -join '; ')
        Seconds = $run.Seconds; ExitCode = $run.ExitCode; Summary = [string]$summary
    }
}
