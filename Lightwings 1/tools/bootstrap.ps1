$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolRoot = Join-Path $projectRoot '.tools'
New-Item -ItemType Directory -Force -Path $toolRoot | Out-Null
$release = Invoke-RestMethod 'https://api.github.com/repos/godotengine/godot-builds/releases/tags/4.7.2-stable'
foreach ($item in @(@{Name='Godot_v4.7.2-stable_win64.exe.zip'; Archive='godot.zip'; Folder='godot'},@{Name='Godot_v4.7.2-stable_export_templates.tpz';Archive='export_templates.zip';Folder='export_templates'})) {
    $destination = Join-Path $toolRoot $item.Folder
    if (Test-Path -LiteralPath $destination) { continue }
    $asset = $release.assets | Where-Object name -eq $item.Name
    $archive = Join-Path $toolRoot $item.Archive
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archive
    Expand-Archive -LiteralPath $archive -DestinationPath $destination
}
& (Join-Path $toolRoot 'godot\Godot_v4.7.2-stable_win64_console.exe') --version
