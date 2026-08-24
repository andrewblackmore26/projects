# Gridlock — Godot presentation layer

Godot 4.7 (.NET). Thin presentation over the shared `/Core` simulation: it reads
state and draws it, and sends input as intents. It never mutates simulation
state.

`scenes/Main.tscn` is a six-line bootstrap; everything else is built from code in
`scripts/`, driven by the level data.

## Run

```powershell
$godot = "C:\Users\admin\godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe"

# play (default): press-hold-drag-release, F1 for the live tuning panel
& $godot --path GodotProject -- --play --ai=5 --level=<abs path>.json

# watch the AI play itself
& $godot --path GodotProject -- --match --p=6 --a=5 --seed=3

# cross-engine determinism gate (headless; must equal the CLI's `hash` line)
& $godot --headless --path GodotProject -- --hash --ticks=3600 --p=5 --a=5 --seed=1 --level=<abs>.json
dotnet run --project Tools/Headless -- hash --level <abs>.json --ticks 3600 --p 5 --a 5 --seed 1

# capture and measure a frame (needs a real window; --headless renders nothing)
Tools\shoot.ps1 -Out docs\screenshots\board.png -Seconds contest -Level Levels\level_06_mirrorlock.json
```

`-Seconds` takes a number of sim-seconds or the word `contest`, which runs until
a front line actually exists — the contest is the visual the whole look hangs on,
so a capture that happens to miss it proves nothing.

## Controls (spec §7)

Press an owned node and it begins charging immediately — that brightening is
visible to the opponent, which is what makes feinting real. Drag to a connected
node and release to send; release anywhere else, or back on the origin, to cancel
for free. Hold past 1.4 s and the node flares: releasing then bursts. A tap with
no drag inspects: that node's wires stay lit and everything else dims for two
seconds. Mouse and touch share one path.

## The look is a pipeline, not art

Wires and node rings are ribbon meshes whose UVs run 0..1 along the path, so a
beam at simulation `t` maps exactly onto the mesh. Beams, the contest front, the
overcharge pulse and the capture flash are all **shader uniforms** — nothing is a
moving sprite. A board is a handful of draw calls and the motion is exact at any
framerate.

Colours are written with components above 1.0 and the glow pass turns them into
light. Two rules keep that measurable, both learned the hard way (see
`../tasks/lessons.md`):

- No `: source_color` hints on colour uniforms — that hint makes Godot convert
  the value from sRGB on the way in, on top of the conversion the canvas pipeline
  already does.
- The capture path encodes linear→sRGB before saving. The `hdr_2d` viewport
  texture is the linear buffer and `SavePng` does not re-encode, so an
  unconverted capture crushes the dark end and every colour measured from it is
  wrong.

`Tools/shoot.ps1` greps the engine log for shader and script errors and fails
loudly: a Godot shader that fails to compile renders its mesh **black**, which in
a screenshot is indistinguishable from "the change had no effect".

## Measured

`level_06_mirrorlock`, 5v5, seed 1, captured on the first tick a contest exists:

```
bg=4,6,12   (spec #05070D = 5,7,13)   meanLuma=27.9   peak=255   hdrPeak=55.2
brightPct=7.97   nearWhitePct=0.60
```

Background within 8-bit rounding of the spec, HDR peaks well above the glow
threshold, and mean luma far below the level where a board reads as fog. Re-shoot
a SMALL board too after any bloom change (`level_01_first_light`): a close camera
makes emitters huge on screen and blows out where a big board still looks fine.

## Not done here

Vignette, chromatic aberration and film grain (spec §8.3 items 2–4) are
deliberately absent for now: bloom does the heavy lifting, and a full-screen
overlay is exactly what corrupted this project's ancestor's colour measurements
for an entire version. Audio is out of scope for this pass.
