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

- Vertex COLOR on a canvas mesh does NOT arrive as written: packed role/flags/perimeter
  bytes decoded as role 0 for every part (the alpha byte carried data; colour channels are
  treated as a colour). Per-vertex data goes in `CUSTOM0` (float4,
  `ArrayCustomFormat.RgbaFloat << FormatCustom0Shift`), which has no colour semantics and
  is present in 4.7.1 canvas_item shaders. Measured: fills exact 7/7 after the switch.
- The 2D HDR transfer, measured with FLOAT uniforms: a canvas shader's OUTPUT is not
  converted (0.5 written lands as 0.50 in the buffer), and `Color` values passed to
  `SetShaderParameter` (also `Color[]` for vec4 arrays) ARRIVE linearised. Below 1.0 this is
  indistinguishable from the seeded "output is linearised" reading; above 1.0 it is not:
  white x 1.8 lands as 1.8, a float 1.8 lands as 1.8, a Color #2a0b08 lands as its linear
  value. So the palette is passed as Color and emission multiplies the linear value.
- Godot's built-in glow is blind to small emitters. Measured size x emission ladder: a 1.8x
  emitter adds nothing at 4 and 8 px and only +0.44 at 16 px; a 6 px emitter needs 8x to
  bloom, a 3 px one needs 32x; and the halo is WIDE (a 6 px emitter at 8x still reads 74 luma
  at +12 px). The bright pass lives on a coarse mip chain. Every running light (2.6 px), core
  (6 px) and bullet in this game is below its floor, so `BloomLayer` does the spec's bloom
  itself: BackBufferCopy + a 9x9 gaussian tap grid over +-8 px, threshold 1.0, additive.
  HDR values survive the back-buffer copy (a 1.8 emitter halos with threshold 1.0). The
  probe core measures 255,107,64,12,5,5 at +0/3/6/10/16/24 px. Built-in glow stays off;
  `--godot-glow` turns it on for comparison and `--emitter` (bg mode) prints the ladder.
- Diagnostics must not overlap the thing being measured: the emitter ladder placed on the
  sheet rows flooded three cells and the halo probe, and every number lied for one run.
  Probes live in their own mode.
- Measuring a running light: sample tiny parts (perimeter < 30 px) at the exact pixel with a
  lower lit threshold (MSAA leaves 1-2 px quads short of full white), and keep the dark
  candidate search within +-0.12 of a lap of the antipode; a wider search wrapped back next
  to the light and reported every small part as never dark.
- Palette exactness and bloom are measured in separate runs: with bloom on, fills near a
  light legitimately read +10..+30; `--no-bloom` is the palette gate, bloom-on is the halo
  and lit/moved gate.
- Tooling: a Bash tool command above a few KB fails to parse as a whole (a quoted heredoc
  loses its terminator and every apostrophe after it becomes a shell error); nothing in it
  runs. Keep shell calls short; write source files with the Write tool.
