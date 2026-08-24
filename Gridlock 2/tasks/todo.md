# Gridlock 2 — build plan (continuous-time spec)

Plan approved 2026-08-24. Spec: `docs/GRIDLOCK_SPEC.md`.

## M1 — headless core + tests
- [x] Scaffold: sln, Core (netstandard2.1/C#9 + package.json/asmdef/Directory.Build.props), Core.Tests (pinned xunit), Tools/Headless, build.ps1
- [x] Verbatim copies from old repo: Vec2, HexCoord, DeterministicRandom, MiniJson (+ adapted HexMath)
- [x] VertexCoord + vertex-lattice math — parity/edge/face-table tests green
- [x] Enums, Tuning (unit-commented), GameNode, Wire, Beam, Contest
- [x] LevelData/Loader/Writer/PathBuilder + DevBoards — LR1–LR9 rejection matrix green
- [x] Simulation phases (intents, charge, holds, sends, node resolution, cooldowns)
- [x] BeamPhase: contest step, event sweep, reinforcement, merge, net, chase, arrival ordering
- [x] Win/objectives, StateHash, HeadlessMatch, Headless CLI (match/balance/ladder/validate/hash/perf/gen, `--set` tuning overrides)
- [x] AI: AiDifficulty/CandidateScorer/AiController
- [x] Perf smoke

## Audits (multi-agent, adversarially verified)
- [x] Pass 1 — 7 dimensions: 21 raw findings, 7 confirmed, all fixed with regression tests
- [x] Pass 2 — beam/contest sweep + free hunt (the two dimensions lost to a usage limit in pass 1): 9 raw, 7 confirmed, all fixed
  - The high-severity one was real and reproduced by running the code: the
    "one contest per wire" invariant was false, and its guard corrupted state
    silently in Release while hard-crashing in Debug.

## M2 — Godot render
- [x] GodotProject (Godot.NET.Sdk/4.7.1, Core compile-glob, LangVersion 9 pinned, hdr_2d)
- [x] Wire/node/background shaders, ribbon meshes, contest sparks
- [x] Match viewer; cross-engine hash gate bit-identical
- [x] shoot.ps1 harness (fails loudly on shader errors) + in-engine frame measurement

## M3 — input
- [x] Press/hold/drag/release, targeting line, both cancels, tap-inspect dimming, 1-tick intent grace
- [x] Live tuning panel (F1) over every Tuning field

## M4 — Unity layer
- [x] UnityProject: local-package Core, mirrored view scripts, URP HLSL shaders, StreamingAssets levels
- [x] UnityCompileCheck with drift guard; verified sound and verified to have teeth (CS1069 negative test)
- [x] README documenting editor-side setup and what the check cannot prove

## M5 — AI tiers + balance (all measured on level_06_mirrorlock)
- [x] 1000-run mirrored equal-tier ∈ [45,55]% — **49.9%**
- [x] Raw side delta ≤ 4 pts — **0.2 pts**
- [x] Ladder monotone, t+1 ≥ 55% vs t for all t — **56.5% to 77.5%, MONOTONE**
- [x] Stall rate < 1% — **0.10%**
- [x] Unwinnable-send counter behaviour — filter active, 73.5k candidates rejected pre-noise across 1000 runs

## M6-lite / M7-lite — tooling + content
- [x] BoardBuilder + PathBuilder authoring pipeline (`gen`)
- [x] 7 levels: first light, long way round, tollbooth (capture), switchback, crossroads (capture), mirrorlock (fairness board), gauntlet (survive)

## Out of scope this session (recorded)
- In-engine level editor (M6 full), 15–20 level campaign (M7 full), M8 shell/menus/Steam/achievements, audio.
- Vignette / chromatic aberration / film grain (spec §8.3 items 2–4) — bloom does the work; a full-screen overlay is what corrupted the ancestor project's colour measurements.
- Unity editor verification: impossible here (no licence). Compile-checked only.

---

## Review — every number measured, not asserted

**Tests.** 91/91 green in both Debug and Release (the audit found a real
Debug/Release physics divergence; both configurations now agree). Includes the
discrete-Lanchester invariant as an exact oracle, hand-computed contest values,
determinism hashes, and a fuzz test that hammers random two-sided wire traffic
for 12,000 ticks asserting the single-contest invariant and that no opposing
pair ever ends up crossed.

**Balance** (`level_06_mirrorlock`, 1000 mirrored runs, tier 5 v 5):

| metric | gate | measured |
|---|---|---|
| equal-tier win rate | 45–55% | 49.9% |
| raw side delta | ≤ 4 pts | 0.2 pts |
| stall rate | < 1% | 0.10% |
| match length p50 / p90 | — | 118 s / 236 s |
| contests per 1000 runs | — | 6017 (2576 side-death, 3440 endpoint) |

**Ladder** (200 runs per pair, higher tier alternating sides): MONOTONE.
2v1 56.5, 3v2 59.5, 4v3 65.0, 5v4 77.5, 6v5 64.0, 7v6 71.1, 8v7 63.5,
9v8 66.2, 10v9 58.8.

**Performance.** mean 2.4 µs per tick, p50 1.0 µs, p99 6.3 µs (tier 8 duel on
mirrorlock, 8330 ticks). Budget was 100 µs mean; the simulation costs about
0.014% of a core at 60 Hz.

**Cross-engine determinism.** Godot headless and the dotnet CLI print
bit-identical fingerprints for the same level, tiers and seed:
`tick=3600 result=None hash=d06b148509755162`.

**Frame measurement** (mirrorlock, captured on the first tick a contest exists):
`bg=4,6,12` against the spec's `#05070D` = 5,7,13, `meanLuma=27.9`, `peak=255`,
`hdrPeak=55.2`, `brightPct=7.97`, `nearWhitePct=0.60`. Small-board re-shoot
after the bloom change: `meanLuma=12.8`, `nearWhitePct=0.012`, no blowout.

**Levels.** All 7 validate through the loader with zero warnings.

**Unity.** Compile check green; verified sound (no undeclared module is
referenced) and verified to have teeth (a `UnityEngine.NVIDIA` type fails it
with CS1069, the error class that once shipped green on the ancestor project).

### What is NOT verified
- How the Unity layer looks or feels: no licence on this machine, editor never opened.
- Human play. The input path is exercised by a smoke run and by reading it
  adversarially, not by hands on a mouse — the ancestor project records that
  screenshots cannot catch intent-latency bugs, only play can.
- The spec's "20-node board with 30+ simultaneous beams" figure: the largest
  authored board is 9 nodes. Perf headroom is four orders of magnitude, but the
  specific board does not exist yet.
