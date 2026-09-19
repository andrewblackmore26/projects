param([switch]$LinuxContainer)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$artifactRoot = Join-Path $projectRoot 'artifacts'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
foreach ($flavor in @('campaign','demo')) {
    $folder = Join-Path $projectRoot "builds\$flavor-windows"
    $log = Join-Path $artifactRoot "package-win-$flavor.log"
    $arguments = @('--headless','--max-fps','120','--quit-after','1200','--log-file',('"' + $log + '"'),'--','--verify-package')
    if ($flavor -eq 'demo') { $arguments += '--expected-demo' }
    $packageProcess = Start-Process -FilePath (Join-Path $folder 'Lightship.exe') -WorkingDirectory $folder -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    $output = Get-Content -LiteralPath $log -Raw
    if ($packageProcess.ExitCode -ne 0 -or $output -notmatch 'PACKAGE .*: [1-9][0-9]* checks, 0 failures' -or $output -match 'SCRIPT ERROR:|(?m)^ERROR:|ObjectDB instances leaked') { throw "Windows $flavor failed; see $log" }
    Write-Output "Windows $flavor`: runtime checks passed"
}
if ($LinuxContainer) {
    foreach ($flavor in @('campaign','demo')) {
        $log = Join-Path $artifactRoot "package-linux-$flavor.log"
        $arguments = @('run','--rm','--mount',"type=bind,source=$projectRoot,target=/project,readonly",'--workdir',"/project/builds/$flavor-linux",'python:3.12-slim',"/project/builds/$flavor-linux/Lightship.x86_64",'--headless','--max-fps','120','--quit-after','1200','--','--verify-package')
        if ($flavor -eq 'demo') { $arguments += '--expected-demo' }
        & docker @arguments *> $log
        $exitCode = $LASTEXITCODE
        $output = Get-Content -LiteralPath $log -Raw
        if ($exitCode -ne 0 -or $output -notmatch 'PACKAGE .*: [1-9][0-9]* checks, 0 failures' -or $output -match 'SCRIPT ERROR:|(?m)^ERROR:|ObjectDB instances leaked') { throw "Linux $flavor failed; see $log" }
        Write-Output "Linux $flavor`: runtime checks passed"
    }
}
