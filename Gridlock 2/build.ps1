# Build/test entry point. The machine PATH contains C:\Program Files\dotnet but shells
# spawned by tools may carry a stale PATH — always prepend explicitly (lessons.md).
param(
    [ValidateSet("build", "test", "balance", "headless")]
    [string]$Task = "build",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$env:PATH = "C:\Program Files\dotnet;$env:PATH"
$root = $PSScriptRoot

switch ($Task) {
    "build"    { dotnet build "$root\Gridlock.sln" }
    "test"     { dotnet test "$root\Core.Tests" --nologo }
    "balance"  { dotnet test "$root\Core.Tests" --nologo --filter Category=Balance }
    "headless" { dotnet run --project "$root\Tools\Headless" -- @Rest }
}
exit $LASTEXITCODE
