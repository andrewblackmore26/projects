param([switch]$GPU)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$godotBinary = Join-Path $projectRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
$importOutput = & $godotBinary --headless --editor --path $projectRoot --import --quit 2>&1
if ($LASTEXITCODE -ne 0 -or ($importOutput -match 'SCRIPT ERROR:|^ERROR:')) { $importOutput | Write-Output; throw 'Project import failed.' }
$testFiles = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests') -Filter '*.gd' | Where-Object { $_.Name -match '_test\.gd$|_tests\.gd$|^ships_validation\.gd$' }
foreach ($testFile in $testFiles) {
    if ($testFile.Name -in @('ships_void_render_test.gd','ships_mesh_render_test.gd')) { continue }
    $testOutput = & $godotBinary --headless --path $projectRoot --script "res://tests/$($testFile.Name)" 2>&1
    $testOutput | Write-Output
    if ($LASTEXITCODE -ne 0 -or ($testOutput -match 'SCRIPT ERROR:|^ERROR:')) { throw "Test failed: $($testFile.Name)" }
}

if ($GPU) {
    foreach ($gpuTest in @('ships_void_render_test.gd','ships_mesh_render_test.gd')) {
        $gpuOutput = & $godotBinary --path $projectRoot --script "res://tests/$gpuTest" 2>&1
        $gpuOutput | Write-Output
        if ($LASTEXITCODE -ne 0 -or ($gpuOutput -match 'SCRIPT ERROR:|^ERROR:')) { throw "GPU test failed: $gpuTest" }
    }
}
