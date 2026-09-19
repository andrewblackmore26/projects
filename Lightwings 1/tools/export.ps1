param([ValidateSet('all','windows','linux')][string]$Platform='all',[switch]$Demo)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$godotBinary = Join-Path $projectRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
if (!(Test-Path -LiteralPath $godotBinary)) { throw 'Run tools/bootstrap.ps1 first.' }
$flavor = if ($Demo) { 'Demo' } else { 'Campaign' }
foreach ($target in @('windows','linux')) {
    if ($Platform -ne 'all' -and $Platform -ne $target) { continue }
    $preset = if ($target -eq 'windows') { "Windows $flavor" } else { "Linux $flavor" }
    $folder = Join-Path $projectRoot "builds\$($flavor.ToLower())-$target"
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $filename = if ($target -eq 'windows') { 'Lightship.exe' } else { 'Lightship.x86_64' }
    & $godotBinary --headless --path $projectRoot --export-release $preset (Join-Path $folder $filename)
    if ($LASTEXITCODE -ne 0) { throw "Export failed: $preset" }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md') -Destination $folder
}
