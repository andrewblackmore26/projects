# Run every gate of the current milestone and print one line per gate.
#
#   Tools\gates.ps1            # all gates
#   Tools\gates.ps1 -Quick     # skip the slow bot profiles
#
# Each capture goes through shoot.ps1, which exits 1 on an engine error, a
# missing frame or measurement, or any instrument reporting ok=0. The negative
# control at the end MUST fail: a gate battery that cannot fail proves nothing.
param([switch]$Quick)

$ErrorActionPreference = "Continue"
$env:PATH = "C:\Program Files\dotnet;$env:PATH"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$scratch = "docs\screenshots\scratch\gates"
$results = @()

function Gate($name, [scriptblock]$body, [bool]$expectFail = $false) {
    $global:LASTEXITCODE = 0
    $out = & $body 2>&1 | Out-String
    $code = $LASTEXITCODE
    $pass = if ($expectFail) { $code -ne 0 } else { $code -eq 0 }
    $script:results += [pscustomobject]@{ Gate = $name; Exit = $code; Pass = $pass }
    $keep = ($out -split "`n") | Where-Object { $_ -match "^(measure: |bot: profile|bench: |validate: |GATE FAIL|FAIL:)|Passed!|Failed!" } | Select-Object -Unique
    Write-Host ("{0,-28} exit={1} {2}" -f $name, $code, $(if ($pass) { "PASS" } else { "FAIL" }))
    $keep | ForEach-Object { Write-Host ("    " + $_.Trim()) }
}

dotnet build "$root\Lightship.sln" --nologo -v q | Out-Null
Gate "unit tests"        { dotnet test "$root\Core.Tests" --nologo --no-build }
Gate "validate ships"    { dotnet run --project "$root\Tools\Headless" --no-build -- validate }
Gate "headless bench"    { dotnet run --project "$root\Tools\Headless" -c Release -- bench --bullets 1000,2000 }
if (-not $Quick) {
    Gate "bot perfect"   { dotnet run --project "$root\Tools\Headless" -c Release --no-build -- bot --seconds 180 --runs 5 }
    Gate "bot novice"    { dotnet run --project "$root\Tools\Headless" -c Release --no-build -- bot --seconds 180 --runs 5 --novice }
}
Gate "playfield"         { & "$root\Tools\shoot.ps1" -Out "$scratch\bg.png" -Mode bg -Seconds 1 -NoBuild:$false }
Gate "sheet bloom"       { & "$root\Tools\shoot.ps1" -Out "$scratch\sheet.png" -Mode sheet -Seconds 2 -NoBuild }
Gate "sheet no bloom"    { & "$root\Tools\shoot.ps1" -Out "$scratch\sheet_nb.png" -Mode sheet -Seconds 2 -NoBuild -Extra "--no-bloom" }
Gate "play 45 s"         { & "$root\Tools\shoot.ps1" -Out "$scratch\play45.png" -Mode play -Bot -Seconds 45 -NoBuild }
Gate "play 140 s alpha"  { & "$root\Tools\shoot.ps1" -Out "$scratch\play140.png" -Mode play -Bot -Seconds 140 -NoBuild -Extra "--alpha=0.5" }
Gate "lock pulse"        { & "$root\Tools\shoot.ps1" -Out "$scratch\lock.png" -Mode lock -Seconds 45 -NoBuild }
Gate "bench 2000"        { & "$root\Tools\shoot.ps1" -Out "$scratch\bench.png" -Mode bench -Bullets 2000 -Frames 600 -NoBuild }
Gate "editor self-test"  { & "$root\Tools\shoot.ps1" -Out "$scratch\editor.png" -Mode editor -Seconds 0 -NoBuild }
Gate "NEGATIVE no halo"  { & "$root\Tools\shoot.ps1" -Out "$scratch\neg.png" -Mode sheet -Seconds 2 -NoBuild -Extra "--bloom-intensity=0" } $true

# Cross-engine determinism: the Godot player and the CLI must print the same fingerprint.
$godot = "C:\Users\admin\godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe"
$project = Join-Path $root "GodotProject"
foreach ($seed in 1, 9) {
    $o = [IO.Path]::GetTempFileName(); $e = [IO.Path]::GetTempFileName()
    $p = Start-Process -FilePath $godot -ArgumentList "--headless --path `"$project`" -- --hash --ticks=7200 --seed=$seed" -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
    $null = $p.WaitForExit(120000)
    $g = (Get-Content $o | Select-String "hash=").Line
    $c = (dotnet run --project "$root\Tools\Headless" -c Release --no-build -- hash --ticks 7200 --seed $seed | Select-String "hash=").Line
    Remove-Item $o, $e -Force -ErrorAction SilentlyContinue
    $same = ($g -ne $null) -and ($g.Trim() -eq $c.Trim())
    $script:results += [pscustomobject]@{ Gate = "hash seed $seed"; Exit = $(if ($same) { 0 } else { 1 }); Pass = $same }
    Write-Host ("{0,-28} {1}" -f "hash seed $seed", $(if ($same) { "PASS  $g" } else { "FAIL  godot=[$g] cli=[$c]" }))
}

$failed = @($results | Where-Object { -not $_.Pass })
Write-Host ""
Write-Host ("gates: {0} passed, {1} failed" -f ($results.Count - $failed.Count), $failed.Count)
if ($failed.Count -gt 0) { $failed | ForEach-Object { Write-Host ("  FAILED: " + $_.Gate) }; exit 1 }
exit 0
