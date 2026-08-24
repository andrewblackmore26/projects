# Capture and MEASURE a frame of the Godot board.
#
# The measurement is the point. A Godot shader that fails to compile renders its
# mesh black, which on screen is indistinguishable from "the change had no
# effect" -- this harness therefore greps the engine log for shader and script
# errors and fails loudly, and prints the frame's measured pixel statistics.
#
#   Tools/shoot.ps1 -Out docs/screenshots/board.png -Seconds 20 -Level Levels/level_06_mirrorlock.json
param(
    [Parameter(Mandatory = $true)][string]$Out,
    # A number of sim-seconds, or "contest" to run until a front line exists.
    [string]$Seconds = "20",
    [string]$Level = "",
    [int]$PlayerTier = 5,
    [int]$AiTier = 5,
    [int]$Seed = 1
)

$ErrorActionPreference = "Stop"
$env:PATH = "C:\Program Files\dotnet;$env:PATH"

$root = Split-Path $PSScriptRoot -Parent
# The _console build is mandatory: the plain one swallows stderr, and stderr is
# where Godot reports the shader errors this script exists to catch.
$godot = "C:\Users\admin\godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe"
$project = Join-Path $root "GodotProject"

if (-not (Test-Path $godot)) { Write-Error "Godot console binary not found at $godot" }

$outPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $Out))
$outDir = Split-Path $outPath -Parent
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
if (Test-Path $outPath) { Remove-Item $outPath -Force }

$buildLog = dotnet build (Join-Path $project "Gridlock.Godot.csproj") --nologo -v q 2>&1
if ($LASTEXITCODE -ne 0) {
    $buildLog | Write-Host
    Write-Error "build failed"
}

# Build ONE quoted argument string. Passing an array to Start-Process leaves
# paths containing spaces unquoted, and Godot then cannot find the project and
# silently falls back to the project manager -- which never exits.
$godotArgs = "--path `"$project`" -- `"--screenshot=$($outPath):$Seconds`"" +
             " --p=$PlayerTier --a=$AiTier --seed=$Seed"
if ($Level -ne "") {
    $levelPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $Level))
    $godotArgs += " `"--level=$levelPath`""
}

# Run through Start-Process with redirected streams. Piping a native exe's
# stderr in PowerShell 5.1 wraps every line in an ErrorRecord, which turns
# Godot's harmless startup warnings into terminating failures and hides the
# output this script exists to read.
$stdoutFile = [IO.Path]::GetTempFileName()
$stderrFile = [IO.Path]::GetTempFileName()
$proc = Start-Process -FilePath $godot -ArgumentList $godotArgs -NoNewWindow -PassThru `
    -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
if (-not $proc.WaitForExit(180000)) {
    $proc.Kill()
    Write-Error "FAIL: Godot did not exit within 180s"
}
$lines = @()
if (Test-Path $stdoutFile) { $lines += Get-Content $stdoutFile }
if (Test-Path $stderrFile) { $lines += Get-Content $stderrFile }
Remove-Item $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
$lines | Write-Host

# Warnings are fine; errors are not. A failed shader renders its mesh BLACK,
# which is indistinguishable from "the change had no effect" in a screenshot.
$bad = $lines | Select-String -Pattern "SHADER ERROR", "SCRIPT ERROR", "Shader compilation failed", "^ERROR:", "^\s*ERROR:"
if ($bad) {
    Write-Host "--- engine reported errors ---"
    $bad | ForEach-Object { Write-Host $_.Line }
    Write-Error "FAIL: engine errors in the capture run (a failed shader renders BLACK and looks like no change)"
}

if (-not (Test-Path $outPath)) { Write-Error "FAIL: no screenshot was written to $outPath" }

$measure = $lines | Select-String -Pattern "^measure:" | Select-Object -First 1
if (-not $measure) { Write-Error "FAIL: no measurement line in the engine output" }
Write-Host ""
Write-Host "OK  $outPath"
Write-Host "    $($measure.Line)"
