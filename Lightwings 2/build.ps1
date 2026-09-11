# Build/test entry point. The machine PATH contains C:\Program Files\dotnet but shells
# spawned by tools may carry a stale PATH -- always prepend explicitly (tasks/lessons.md).
#
#   .\build.ps1 build                       # whole solution, including the Godot project
#   .\build.ps1 test                        # fast xunit categories
#   .\build.ps1 perf                        # Release, the bullet-budget benchmark
#   .\build.ps1 bot --seconds 180 --runs 5  # scripted player runs (first evolution time)
#   .\build.ps1 headless validate GodotProject\data\ships
#   .\build.ps1 shoot -Mode sheet -Out docs\screenshots\sheet.png
param(
    [ValidateSet("build", "test", "perf", "bot", "headless", "shoot")]
    [string]$Task = "build",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$env:PATH = "C:\Program Files\dotnet;$env:PATH"
$root = $PSScriptRoot

switch ($Task) {
    "build"    { dotnet build "$root\Lightship.sln" --nologo }
    "test"     { dotnet test "$root\Core.Tests" --nologo --filter "Category!=Perf&Category!=Bot" }
    "perf"     { dotnet test "$root\Core.Tests" --nologo -c Release --filter "Category=Perf" }
    "bot"      { dotnet run --project "$root\Tools\Headless" -c Release -- bot @Rest }
    "headless" { dotnet run --project "$root\Tools\Headless" -- @Rest }
    "shoot"    { & "$root\Tools\shoot.ps1" @Rest }
}
exit $LASTEXITCODE
