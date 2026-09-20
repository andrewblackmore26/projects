param([Parameter(Mandatory = $true)][string]$Arguments, [int]$TimeoutSec = 300, [int]$Tail = 40)
# Runs the pinned Godot once, the safe way (tools\lib.ps1): one quoted argument string, output to
# files, a timeout that kills the process tree. Use it for tools and one-off scripts, for example:
#   tools\godot.ps1 -Arguments '--headless --script "res://scripts/ships/export_catalog.gd" -- --rebuild'
# `--path <project>` is added for you. Exits with Godot's exit code (or 1 on timeout / engine error).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
$logDir = New-LogDirectory 'adhoc'
$run = Invoke-Godot $Arguments $logDir 'run' $TimeoutSec
$run.Out | Select-Object -Last $Tail | Write-Output
$errorLines = @(($run.Out + $run.Err) | Where-Object { $_ -cmatch $script:ErrorPattern })
if ($run.Err.Count -gt 0) { Write-Output ("--- stderr ({0} lines, first 20) ---" -f $run.Err.Count); $run.Err | Select-Object -First 20 | Write-Output }
Write-Output ("godot: exit={0} timed_out={1} seconds={2} engine_errors={3} logs={4}" -f $run.ExitCode, [int]$run.TimedOut, $run.Seconds, $errorLines.Count, $logDir)
if ($run.TimedOut -or $errorLines.Count -gt 0) { exit 1 }
exit $run.ExitCode
