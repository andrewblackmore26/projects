# Gridlock 2 — build plan (continuous-time spec)

Plan approved 2026-08-24. Spec: `docs/GRIDLOCK_SPEC.md`. Design detail: `C:\Users\admin\.claude\plans\cached-singing-cosmos.md`.

## M1 — headless core + tests
- [ ] Scaffold: sln, Core (netstandard2.1/C#9 + package.json/asmdef/Directory.Build.props), Core.Tests (pinned xunit), Tools/Headless, build.ps1 — gate: build+test green offline
- [ ] Verbatim copies from old repo: Vec2, HexCoord, DeterministicRandom, MiniJson (+ adapted HexMath)
- [ ] VertexCoord + vertex-lattice math — gate: parity/edge/face-table tests green
- [ ] Enums, Tuning (unit-commented), GameNode, Wire, Beam, Contest
- [ ] LevelData/Loader/Writer/PathBuilder + TestBoards — gate: LR1–LR9 rejection matrix green
- [ ] Simulation phases 1–4 + arrivals (intents, charge, holds, sends, node resolution, cooldowns)
- [ ] BeamPhase: contest step, event sweep, reinforcement, merge, chase, arrival ordering — gate: interaction matrix + Lanchester invariant green
- [ ] Win/objectives, StateHash, HeadlessMatch, Headless CLI (match/validate/probe/hash/perf/gen)
- [ ] AI: AiDifficulty/CandidateScorer/AiController + balance/ladder commands — gate: AI-vs-AI terminates, prints winner; 100-run smoke: 0 stalls, 0 unwinnable sends
- [ ] Perf smoke: 20 nodes / 30+ beams, mean Step < 100 µs (measured)
- [ ] Milestone commit (scoped: `git commit -- "Gridlock 2"`)

## Ultracode review (post-M1)
- [ ] Workflow: parallel spec-section auditors + adversarial verify; fix confirmed findings; rerun tests

## M2 — Godot render
- [ ] GodotProject scaffold (Godot.NET.Sdk/4.7.1, Core compile-glob, LangVersion 9 pinned, hdr_2d)
- [ ] Wire shader (ownerColorA/B, boundaryT, pulses, baseIntensity), node visuals, contest hot point + sparks
- [ ] Match viewer over HeadlessMatch; headless hash gate: Godot hash == dotnet hash (bit-identical)
- [ ] Screenshot harness (SHADER ERROR grep) + pixel measurements (bg #05070D, HDR peaks)

## M3 — input
- [ ] Press/hold/drag/release, targeting line, both cancels, tap-inspect dimming; 1-tick intent grace

## M4 — Unity layer
- [ ] UnityProject local-package wiring + view scripts + manifest-derived compile check (no editor licence — documented limit)

## M5 — AI tiers + balance (all measured)
- [ ] 1000-run mirrored equal-tier ∈ [45,55]%
- [ ] Raw side delta ≤ 4 pts
- [ ] Ladder monotone: t+1 ≥ 55% vs t for all t∈1..9
- [ ] Stall rate < 1%; unwinnable-send counter == 0

## M6-lite / M7-lite — tooling + content
- [ ] PathBuilder + gen authoring pipeline
- [ ] ~6 levels: intro, winding-lie, hub, switchback, bigger board, symmetric duel (travel-time asymmetry)

## Out of scope this session (recorded)
- In-engine level editor (M6 full), 15–20 level campaign (M7 full), M8 shell/menus/Steam/achievements, audio.

## Review
(to be filled at end with measured numbers)
