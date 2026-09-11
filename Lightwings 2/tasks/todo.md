# Lightship — build plan

Spec: `docs/LIGHTSHIP_GAME_SPEC.md` (v0.1). Plan approved 2026-09-12: C#, headless Core + thin
Godot layer, M1 through M3 in this run, then hands-on review.

One command runs every gate of the current milestone, including a negative control that must fail:

    Tools\gates.ps1          # exit 0 only if every gate passes (and the negative control fails)

## M1 — Prototype (does the loop feel good?)
- [x] 0 Scaffold: sln, four csproj, project.godot, Main.tscn, capture harness, README/todo/lessons —
      playfield measured 5,5,7 in all four corners (commit ec0fcf7)
- [x] 1 Core geometry: outlines for all 11 primitives, ear clipping, ribbon (mitre + bevel), light
      segment maths, mesh packing
- [x] 2 Ship data: JSON schema, loader (hard errors + soft warnings), catalog, id-stable light
      schedule, reshape tween, `replaces` for growth by addition; 4 ships (commit 19c2e27)
- [x] 3 Ship renderer: one mesh + one shader per ship (data in CUSTOM0), own bloom layer (Godot glow is
      blind to < 12 px emitters), sheet instrument (commit 895ba76)
- [x] 4 Bullets/pickups/hash: struct-of-arrays pools, spatial hash, side-based collisions,
      MultiMesh layers, SDF bullet and pickup shaders, bench mode
- [x] 5 Loop: run/game/meta, evolution offers, rewards, HP, events, state hash, pilots, camera, input,
      HUD, effects; component abilities (infect, spread, hatch drones) with a loadout per form
- [x] 6 Editor: ShipEditor + EditorPanel + scripted self-test (16 checks)
- [x] 7 Review: adversarial review workflow (5 lenses, 3 skeptics per finding): 53 findings, 39
      upheld, all fixed (below); damage-sheds-light decided by measurement; gates battery

### Adversarial review of M1 (39 upheld findings, fixed)
The largest: player parts did nothing (no ability system) — now a loadout per form with infect /
spread / hatch, each with a differential sim test and each seen in play (bot runs count infections,
spreads and drones). Others: the ship did not lock/pulse at the threshold; tethers were fully hidden
and the sheet skipped occluded parts; the Trojan dropped Worm parts (now enforced: `replaces`);
bullets were drawn a tick ahead of ships (now proven by a differential probe that fails on the old
code at 4.63 px vs 3.90 predicted); effects ran on wall-clock time; evolving during a reshape; seed
tier ignored; shed light rounding and wall clamping; bounding-circle hit tests; asymmetric Glitch;
light schedule jumping at the tween's midpoint; editor rename/duplicate/stale-list bugs; bot gate
using arena ticks that restart at death; four tests that could not fail.

### Open decision 1: does damage shed light? — NO (HP only)
Measured with bot runs, 300 s x 5 seeds, shed fraction 0 vs 0.3, perfect and no-dodge profiles:
energy at 300 s stayed within the same 1007-1114 spread and the first evolution did not move,
because shed light is flown back to. It costs code and contradicts spec 4 ("energy only goes up")
for no measurable change. `Tuning.DamageShedsLightFraction` keeps the knob (with a fractional carry).

## M2 — World
- [ ] Sector/WorldGrid/Veil/Gate/Meta, death reset, teleport; RivalPilot (delay, aim error, retreat);
      minimap + full map with radiation icons; WorldTests / RivalTests / DeathCostsMinutesNotTheRun;
      gate-icon capture; commit

## M3 — Elements
- [ ] 20 ship JSONs; lightning/void/corruption patterns; typed pickups; territory colouring; component
      steal; laser prong telegraph; per-element PatternTests, StealTests, LaserTests; 20-ship sheet
      lit=P/P, void hull 0,0,0; commit. STOP for hands-on review.

## M4 — Character (outline) · M5 — Demo (outline)
- [ ] Not in this run.

## Review — every number measured, not asserted (M1, `Tools\gates.ps1`: 16/16)

| metric | gate | measured |
|---|---|---|
| unit tests | all | 161/161 |
| validate ships / warnings | 0 warnings | 4 / 0 |
| playfield bg (sRGB re-encoded capture) | 5,5,7 ±2 | 5,5,7 (all four corners) |
| first evolution, perfect bot, seeds 1–5 | ≤ 120 s | 21.3–22.6 s |
| first evolution, novice bot (10° aim error, 60 % trigger, 250 ms late, no dodge) | ≤ 120 s | 21.4–24.1 s |
| infections / spreads / drones per 180 s run (perfect) | all > 0 | 40 / 7–12 / 26–28 |
| dodge differential (hits over 5 × 120 s) | dodge < no dodge | 34 < 84 |
| ambient share of energy | "most light from enemies" | 4–7 % |
| sheet: every part lit, bloom on / off | P/P | 50/50 / 50/50 (0 never visible) |
| sheet: every light moved 0.5 s later | P/P | 50/50 |
| palette fills, no bloom | exact, every ship | 7/7 |
| footprint, measured vs geometry, no bloom | ≤ 3 px | 2 px |
| light blue outside the player's team (sheet, play at 45 s, 140 s, lock) | 0 | 0 |
| halo luma at +0/3/6/10/16/24 px | monotone, +6 > bg+10, +24 < bg+8 | 255,107,64,12,5,5 |
| draw order (enemy bullet over player bullet) | rim green, never blue | 13–16/16 green, 0 blue |
| MultiMesh layout (bullet on its pixel, playfield at 16 px) | luma > 120 / < bg+20 | 170–214 / 5 |
| hollow pickup (centre dark, rim lit) | < bg+25 / > 80 | 15–22 / 254 |
| interpolation: bullet vs ship at alpha 0 / 0.5 | ≤ 1.5 px, sensitive | 0.71 / 0.52 px (lead would be 3.0 / 2.7) |
| lock pulse (bright player strokes, on vs off step) | on > 1.5 × off | 61 vs 9 |
| headless ms/tick @1000 / @2000 bullets | < 2.0 | 0.042 / 0.038 |
| engine avg frame @2000 bullets (one tick per frame, uncapped) | < 16 ms | 0.650 ms, 5 draw calls |
| editor self-test | all | 16/16 |
| hash Godot == CLI (7200 ticks, seeds 1 and 9) | equal | 9b7797f863b9da8f, 796d1e90a60e06f2 |
| negative control (bloom intensity 0) | must FAIL | fails (haloOk=0, exit 1) |
| void hull | 0,0,0 | (M3) |

### What is NOT verified
- **Human feel of the loop** (hands on mouse). The bots evolve at ~22 s; spec 5 only bounds it
  from above (2 minutes). Whether that is too fast is a hands-on call.
- **"A tester can point at each part and say what it does"** needs a tester. What is measured:
  every part carries an ability that the sim executes and the bot runs trigger (above).
- **Steam Deck timing** (M5). Bench numbers are from an RTX 5070 Ti.
- **Controller input** is mapped but was not exercised with a pad.
