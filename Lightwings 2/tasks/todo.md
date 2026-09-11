# Lightship — build plan

Spec: `docs/LIGHTSHIP_GAME_SPEC.md` (v0.1). Plan approved 2026-09-12: C#, headless Core + thin
Godot layer, M1 through M3 in this run, then hands-on review.

## M1 — Prototype (does the loop feel good?)
- [x] 0 Scaffold: sln, four csproj, project.godot, Main.tscn, Main.cs (environment + background +
      capture), build.ps1, shoot.ps1, measure_frame.py, README/todo/lessons — `bg` capture measured
      5,5,7 in all four corners, no engine errors (commit ec0fcf7)
- [x] 1 Core geometry: Vec2, Outline per primitive, Triangulator, Ribbon, PartGeometry, ShipGeometry,
      LightSegment, MeshData, ShipMeshBuilder + GeometryTests / MeshBuilderTests / LightTests — 68 tests
- [x] 2 Ship data: schema, ShipLoader, ShipCatalog, LightSchedule, ShipTween; fire_t1_ember +
      corruption_t1/t2/t3 JSONs; `validate` ships=4 warnings=0; 90 tests (commit 19c2e27)
- [x] 3 Ship renderer: Palette, ship.gdshader (CUSTOM0 packing), ShipMeshFactory, ShipView, SheetLayout,
      BloomLayer (own bloom: Godot glow is blind to < 12 px emitters, see lessons) — sheet bloom=on:
      litParts=36/36, lightdiff moved=36/36, halo=255,107,64,12,5,5 haloOk=1, hdrPeak=2.11,
      lightBlueOutsidePlayer=0, footprintErrMaxPx=6; bloom=off: fillOk=7/7 exact, footprintErrMaxPx=3
- [ ] 4 Bullets/pickups/hash: pools, SpatialHash, Arena collisions, patterns, MultiMesh layers,
      bullet/pickup shaders; headless bench < 2 ms/step @2000; engine < 16 ms/frame @2000;
      draw-order capture ok
- [ ] 5 Loop: Ship/Run/Game, Evolution offers, Rewards, Health, Events, StateHash, pilots (Human,
      Enemy, Bot); GameController, ArenaView, CameraRig, InputController, Hud; first evolution ≤ 120 s
      for seeds 1–5; Godot hash == CLI hash; hand play
- [ ] 6 Editor: ShipEditor + EditorPanel; edit → save → validate → sheet still lit=P/P; tween slider
- [ ] 7 Review: fill the measured table; damage-sheds-light decision (bot runs at 0 vs 0.3); commit

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

## Review — every number measured, not asserted

| metric | gate | measured |
|---|---|---|
| playfield bg (sRGB re-encoded capture) | 5,5,7 ±2 | 5,5,7 (all four corners) |
| first evolution (bot, seeds 1–5) | ≤ 120 s | |
| sheet lit parts (bloom on / off) | P/P | 36/36 / 36/36 (10 occluded by later parts at t=2.0) |
| lightdiff moved (bloom on / off) | P/P | 36/36 / 36/36 |
| palette fills, no bloom | exact | 7/7 |
| void hull | 0,0,0 | (M3) |
| light blue outside player | 0 | 0 |
| hdrPeak | > 1.0 | 2.11 (bloom on), 1.80 (off) |
| halo luma at +0/3/6/10/16/24 px | monotone, +6 > bg+10, +24 < bg+8 | 255,107,64,12,5,5 |
| validate ships / warnings | 0 warnings | 4 / 0 |
| headless ms/step @1000 / @2000 | < 2.0 | |
| engine avg frame ms @2000 | < 16 | |
| hash Godot == CLI | equal | |
| validate warnings | 0 | |

### What is NOT verified
- Human feel of the loop (hands on mouse).
- Steam Deck timing (M5).
