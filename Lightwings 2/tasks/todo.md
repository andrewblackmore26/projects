# Lightship — build plan

Spec: `docs/LIGHTSHIP_GAME_SPEC.md` (v0.1). Plan approved 2026-09-12: C#, headless Core + thin
Godot layer, M1 through M3 in this run, then hands-on review.

## M1 — Prototype (does the loop feel good?)
- [ ] 0 Scaffold: sln, four csproj, project.godot, Main.tscn, Main.cs (environment + background +
      capture), build.ps1, shoot.ps1, measure_frame.py, README/todo/lessons — `bg` capture measures
      5,5,7 (±2) with no engine errors
- [ ] 1 Core geometry: Vec2, Outline per primitive, Triangulator, Ribbon, PartGeometry, ShipGeometry,
      LightSegment, MeshData, ShipMeshBuilder + GeometryTests / MeshBuilderTests / LightTests
- [ ] 2 Ship data: schema, ShipLoader, ShipCatalog, LightSchedule, ShipTween; fire_t1_ember +
      corruption_t1/t2/t3 JSONs; `validate` zero warnings; LoaderTests / TweenTests
- [ ] 3 Ship renderer: Palette, ship.gdshader, ShipMeshFactory, ShipView, SheetLayout, Capture sidecar;
      sheet capture lit=P/P, footprints ±20 %, lightBlueOutsidePlayer=0, lightdiff moved=P/P, halo
      monotone, hdrPeak>1
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
| playfield bg (sRGB re-encoded capture) | 5,5,7 ±2 | |
| first evolution (bot, seeds 1–5) | ≤ 120 s | |
| sheet lit parts | P/P | |
| lightdiff moved | P/P | |
| void hull | 0,0,0 | (M3) |
| light blue outside player | 0 | |
| hdrPeak | > 1.0 | |
| halo luma at +0/3/6/10/16/24 px | monotone | |
| headless ms/step @1000 / @2000 | < 2.0 | |
| engine avg frame ms @2000 | < 16 | |
| hash Godot == CLI | equal | |
| validate warnings | 0 | |

### What is NOT verified
- Human feel of the loop (hands on mouse).
- Steam Deck timing (M5).
