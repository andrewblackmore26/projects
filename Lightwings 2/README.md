# Lightship (working title)

Top-down twin-stick bullet-hell where you absorb light to grow and reshape your
lightship. Every rival AI you consume changes what you become. Spec:
[docs/LIGHTSHIP_GAME_SPEC.md](docs/LIGHTSHIP_GAME_SPEC.md).

Engine: Godot 4.7.1 mono (C#). The simulation is an engine-free C# library
stepped at a fixed 60 Hz by xunit, by a headless CLI and by Godot alike.

## Layout

```
Core/            Lightship.Core — deterministic simulation, ship data, geometry (no engine refs)
Core.Tests/      xunit; every spec rule and acceptance number has a test
Tools/Headless/  lightship-headless: validate | bot | bench | hash | sheet-info
Tools/shoot.ps1  capture + MEASURE a frame (fails loudly on engine errors)
GodotProject/    presentation: rendering, input, HUD, ship editor, capture instruments
  data/ships/    the ship definitions (JSON), shared by tests, CLI and game
docs/            spec, reference captures
tasks/           todo.md (plan + measured review), lessons.md (rules learned)
```

## Build and run

```powershell
$env:PATH = "C:\Program Files\dotnet;$env:PATH"   # spawned shells can carry a stale PATH
.\build.ps1 build                                  # whole solution incl. the Godot project
.\build.ps1 test                                   # fast xunit categories
.\build.ps1 perf                                   # Release bullet-budget benchmark
.\build.ps1 bot --seconds 180 --runs 5             # scripted player: first evolution time
.\build.ps1 headless validate GodotProject\data\ships

$godot = "C:\Users\admin\godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe"
& $godot --path GodotProject -- --play             # play (WASD, mouse, E evolve, Tab map, F auto-fire)
& $godot --path GodotProject -- --editor           # ship editor
Tools\shoot.ps1 -Out docs\screenshots\sheet.png -Mode sheet   # capture + measure every ship
```

## The look is a pipeline, not art

Colours are passed as `Color` (they arrive linearised; shader output is not
converted); running lights, cores and bullets are written above 1.0 and the
bloom turns them into light; base strokes sit just under the threshold. The
bloom is our own (`BloomLayer`: back-buffer copy, threshold 1.0, 9x9 gaussian
over +-8 px) because Godot's built-in glow measurably ignores emitters under
about 12 px. The hdr_2d buffer is linear, so the capture path re-encodes to
sRGB before measuring. A shader that fails to compile renders black, which
looks like "no change": `shoot.ps1` greps the engine log and fails. Per-vertex
data rides in `CUSTOM0`, never in vertex COLOR. See `tasks/lessons.md`.

## Where it stands

| milestone | state |
|---|---|
| M1 prototype | in progress |
| M2 world | not started |
| M3 elements | not started |
| M4 character | not started |
| M5 demo | not started |

Measured numbers live in `tasks/todo.md` under "Review".

## House rules

**Measure, don't assert.** Every visual and balance claim is a number a command
printed. Silent failure is the normal failure here.

**Make invariants true, not asserted.** Close the hole an invariant depends on
rather than hardening the assert.
