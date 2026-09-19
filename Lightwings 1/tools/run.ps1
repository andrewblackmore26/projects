param([switch]$Demo,[switch]$Editor,[switch]$Benchmark)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$godotBinary = Join-Path $projectRoot '.tools\godot\Godot_v4.7.2-stable_win64.exe'
if (!(Test-Path -LiteralPath $godotBinary)) { & (Join-Path $PSScriptRoot 'bootstrap.ps1') }
$arguments = @('--path', $projectRoot)
if ($Editor) { $arguments += '--editor' }
if ($Demo) { $arguments += @('--','--demo') }
if ($Benchmark) { $arguments += @('--','--benchmark') }
& $godotBinary @arguments
