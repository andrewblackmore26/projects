# Lessons

Rules accumulated from corrections and mistakes. Review at session start.
Seeded 2026-08-24 from the old Gridlock project's lessons.md (c:\.vscode\Gridlock\tasks\lessons.md) — only the rules that bind this continuous-time rebuild.

## Seeded from old project

- (seed) Core sources must stay netstandard2.1 / C# 9 — Unity 6 compatibility is
  compiler-enforced via the Core csproj; never bump LangVersion without checking Unity.
  GodotProject must pin LangVersion 9.0 too, or the main dev loop bypasses the guardrail.
- (seed) Never use System.Random in Core — cross-runtime nondeterminism. Use
  DeterministicRandom everywhere, including AI jitter/noise.
- (seed) Dimensional constants must be re-derived when a unit regime changes. Grep every
  constant's UNIT when its denominator changes meaning. Every Tuning field carries a unit
  comment. Known t-space trap: CONTEST_PUSH_SPEED is contactT/s — world speed scales with
  wire length (long wires surge). Do not multiply by length "to fix" it without a measured reason.
- (seed) Timers are absolute tick indices, never float-second countdowns. Burst boundary is an
  integer tick compare (holdTicks >= OverchargeTicks), never accumulated-float >= 1.4f.
- (seed) Intent queues have a 1-tick latency: UI reading sim state right after enqueueing an
  intent needs a grace window or every interaction self-cancels. Screenshots can't catch this.
- (seed) A folder cannot be both a .NET SDK project dir and a Unity package folder without a
  scoped Directory.Build.props redirecting bin/obj (CS0579/CS0436/CS1704). Scope it to Core/ —
  a repo-root props file breaks Godot.NET.Sdk output placement.
- (seed) A stand-in Unity compile check must derive its reference set from manifest.json, not
  by globbing module folders — globbing shipped a proven false negative (CS1069).
- (seed) AI utility scoring: exploitation (low noise, fast cadence) AMPLIFIES any argmax error;
  tier ladders invert silently. Verify tier monotonicity empirically after ANY combat-mechanics
  change, not just equal-tier balance. Measure on real campaign boards, not only the dev duel.
- (seed) Old project has an UNRESOLVED mirror-match side bias (player side 5W–15L at high tiers).
  Defenses here from day one: controllers tick in alternating order by tick parity; balance
  harness runs every seed both ways (side swap) and reports the raw side delta explicitly.
- (seed) Symmetric boards can deadlock/stall when defense ≈ capacity and travel times are uniform.
  Unequal travel times break simultaneous-arrival grind. A deliberately long wire is often
  load-bearing for balance — never "tidy" one without re-running balance.
- (seed) Never round-trip a source file through PowerShell Get-Content/Set-Content (BOM-less
  UTF-8 mojibake). Use the Edit/Write tools or python for text edits.
- (seed) Any script that captures a Godot frame must grep the engine log for SHADER ERROR /
  SCRIPT ERROR / ERROR: and fail loudly — a failed shader renders the mesh BLACK, which looks
  identical to "no visible effect". Use the *_console.exe Godot binary (the other swallows stderr).
- (seed) Godot: hdr_2d viewport + glow; Environment.glow_bloom is NOT a bloom-amount knob (any
  value > 0 blooms the whole frame); a sub-pixel line cannot bloom — give wire cores enough
  pixel width; colours that must MEASURE correctly go through a raw shader (StandardMaterial/
  AlbedoColor does sRGB conversion); Godot shading language forbids `return` inside fragment();
  after any bloom change re-shoot a SMALL close-camera level (big boards won't catch blowout).
- (seed) Verify in the environment the USER gets: reconstruct a fresh shell's PATH from the
  registry when checking runnability; net8.0 exes on this machine need RollForward Major
  (.NET 10 runtime only).
- (seed) Two identical measurements from two "different" runs mean the run did not change, not
  that the change did nothing — check mtimes and logs before forming a theory (deterministic sim
  + fixed seed = bit-identical frames).
- (seed) Workflow subagents can die on usage limits mid-run; check failures before trusting
  "empty" workflow results. Analysis agents told not to write may still probe by editing the
  tree — don't run them concurrently with your own edits on the same files.

## This project
(append as they happen)

- BFS on the vertex lattice MUST be bounded: the lattice is infinite, so a goal made
  unreachable by blockers (e.g. an anchor corner whose only radial entry is consumed)
  sends an unbounded BFS exploring forever. PathBuilder clamps to the board bounding
  box + padding. Symptom was a silent full-CPU hang, not an error.
- Simulation.Step() must keep advancing the tick after the match ends (doing nothing
  else). A hard no-op turns every `while (sim.Tick < X) sim.Step()` loop into an
  infinite loop the moment a match finishes mid-window — this bit a test within the
  first hour. Loops in callers still check Result first, but the sim no longer traps.
- I re-hit the seeded PowerShell mojibake trap within hours: a `-replace` one-liner on
  Program.cs corrupted every em-dash. The seeded rule stands with zero exceptions:
  ALL source edits go through the Edit/Write tools, even "quick" mechanical rewires.
- Test scenarios that capture a side's LAST node end the match and freeze all timers —
  a lock/disable-expiry assertion after that silently tests a frozen sim. Give the
  losing side a second node when the test needs post-capture time to keep flowing.
