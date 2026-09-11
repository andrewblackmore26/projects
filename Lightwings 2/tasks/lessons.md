# Lessons

Rules accumulated from corrections and mistakes. Review at session start.
Seeded 2026-09-12 from `C:\.vscode\Gridlock 2\tasks\lessons.md` (same machine, same
Godot 4.7.1 mono + headless C# Core layout) — only the rules that bind a Godot HDR
project. Gridlock-domain rules (wires, contests, Unity) were left behind.

## Seeded

### Determinism and simulation
- (seed) Never use System.Random in Core — cross-runtime nondeterminism. Use
  DeterministicRandom everywhere, including AI jitter/noise.
- (seed) Timers are absolute tick indices, never float-second countdowns.
- (seed) Intent queues have a 1-tick latency: UI reading sim state right after enqueueing an
  intent needs a grace window or every interaction self-cancels. Screenshots can't catch this.
- (seed) `Step()` must keep advancing the tick after an end state (death, sector clear). A
  hard no-op turns every `while (tick < X) Step()` loop into an infinite loop.
- (seed) Match/run construction lives in ONE Core method that both the Godot player and the
  headless CLI call; building it by hand in each engine is how a hash gate quietly stops
  comparing the same thing.
- (seed) Two identical measurements from two "different" runs mean the run did not change, not
  that the change did nothing — check mtimes and logs before forming a theory (deterministic
  sim + fixed seed = bit-identical frames).
- (seed) Verify in the environment the USER gets: net8.0 exes on this machine need RollForward
  Major (.NET 10 runtime only).

### Editing and shells
- (seed) Never round-trip a source file through PowerShell Get-Content/Set-Content or a
  `-replace` one-liner (BOM-less UTF-8 mojibake; re-hit within hours on Gridlock 2). ALL source
  edits go through the Edit/Write tools, even "quick" mechanical rewires.
- (seed) `Start-Process -ArgumentList <array>` leaves arguments containing spaces unquoted.
  Godot then cannot find `--path C:\.vscode\Lightwings 2\...`, silently falls back to the
  PROJECT MANAGER, and never exits — a 180 s "hang" with no error. Build one explicitly quoted
  argument string. This project's path HAS a space.
- (seed) Piping a native exe's stderr in PowerShell 5.1 wraps every line in an ErrorRecord, so
  Godot's harmless startup warnings become terminating failures and hide the output the
  harness exists to read. Redirect to files instead.
- (seed) Workflow subagents can die on usage limits mid-run; check failures before trusting
  "empty" results. Analysis agents told not to write may still probe by editing the tree.

### Godot capture and colour pipeline (all measured on this machine)
- (seed) Any script that captures a Godot frame must grep the engine log for SHADER ERROR /
  SCRIPT ERROR / ERROR: and fail loudly — a failed shader renders the mesh BLACK, which looks
  identical to "no visible effect". Use the *_console.exe Godot binary (the other swallows
  stderr).
- (seed) Screenshots need a real window: `--headless` uses the dummy renderer and captures
  nothing. Hash gates are fine headless.
- (seed) Godot runs the DEBUG assembly. `dotnet build -c Release` leaves the player on a stale
  DLL, so screenshots silently verify the OLD code. Always build Debug before a capture run.
- (seed) hdr_2d viewport + glow: `Environment.glow_bloom` is NOT a bloom-amount knob (any value
  > 0 blooms the whole frame); a sub-pixel line cannot bloom — give lit strokes enough pixel
  width; colours that must MEASURE correctly go through a raw shader; Godot shading language
  forbids `return` inside fragment(); after any bloom change re-shoot a SMALL close-camera
  scene (big scenes won't catch blowout).
- (seed) The transfer is KNOWN, not fitted: a canvas shader's output is treated as sRGB and
  LINEARISED into the hdr_2d buffer, and `Image.SavePng` writes those linear floats to 8 bits
  with no re-encode. A raw capture is linear and the dark end dies in quantisation. Encoding
  linear->sRGB on the capture path makes the round trip exact (Gridlock 2 measured 4,6,12 vs
  spec 5,7,13, the residual being 8-bit rounding plus real bloom bleed). Never eyedrop a raw
  viewport capture and conclude anything about a colour.
- (seed) The `: source_color` uniform hint makes Godot convert the value from sRGB on the way
  IN. Combined with the pipeline's own conversion that is a double transfer. Any uniform whose
  value must be predictable carries NO hint.
- (seed) Glow levels are 0-indexed in `SetGlowLevel` (0..6) although the inspector labels the
  same sliders 1..7. Passing 7 is a hard engine error.
- (seed) The two widest glow mips are what turn a frame into fog (bg 11,30,36 / meanLuma 62
  with levels 6 and 7 up; 4,6,12 / 28 with them at zero). `glow_bloom` at 0 is a separate,
  necessary condition.
- (seed) A thick bright ring blooms INWARD and fills its own hole: a 5.5 px half-width ring at
  3x emission reads as a glowing disc and loses its silhouette. Thin the ring rather than
  dimming it. For this project: only the 2.6 px lit segment, the 3 px core and bullets go
  above 1.0; base strokes stay under the threshold.

### Godot/C#
- (seed) `Node.Owner` (a Godot property) shadows any Core `Owner` enum inside EVERY
  Node-derived class. Here the enum is named `Faction` from day one.
- (seed) A `Control` parented to a `Node2D` has no parent rect to anchor against, and its
  size in `_Ready` is not the final window size either. Full-screen UI goes on a
  `CanvasLayer`, whose children anchor to the viewport and follow resizes.
- (seed) A "brightness ladder" expressed as a multiplier only lands on its stated value for
  hues whose peak channel is 1.0. Drive anything above 1.0 through one emission helper so it
  does not clip to white and lose its identity.
- (seed) Build an authoring assertion and then not use it and you have built nothing: an
  audit is a DISTRIBUTION printed for every authored item, not a threshold nobody declares.

## This project
(append as they happen)

- Godot 4.7.1 canvas_item shaders expose `CUSTOM0`/`CUSTOM1` (verified in the exe's
  built-in table). Not relied on: per-vertex data is packed into vertex COLOR (unorm8, so
  small integers as k/255 decoded with `round()`) and UV, which every canvas mesh carries.
