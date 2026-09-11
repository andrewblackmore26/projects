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
- [x] Fire T2 Flare and T3 Scorch (JSON), burning trail and wide cone; corruption enemy pattern
      (spores that infect, the player's core included); enemy patterns scale with tier
- [x] Core world: 5 x 5 sectors in Chebyshev layers, safe dark origin, fire east / corruption west,
      one veil (300) crossed only through the gate (2,0), lock-in until its gatekeeper falls, beaten
      gate = checkpoint, clearing = player territory (quiet for good, regrowth ground), per-life
      sector memory, death reset with border drift (contiguous, never territory), teleport from the
      map, 0.2 s push to cross an edge; arena ticks and ship ids never restart within a game
- [x] RivalPilot: 150-300 ms perception (bullets, target and noticing), 2-5 deg aim error per
      burst, 0.5 s aim line kept through the burst, retreat < 35 % until 70 %, regenerates, grabs
      light, biggest target, rivals fight each other; WorldPilot (the world bot); sweep command
- [x] Godot: world by default (`--sandbox` = M1 arena), minimap + full map (Tab, pauses, click a
      checkpoint to jump), edge barriers, aim lines, HUD notices / gate warning / gatekeeper bar
- [x] Instruments: `map`, `approach`, `gate` world probes; world hash in gates; negatives for the
      map padlock, the minimap padlock and the veil label
- [x] Adversarial review (5 lenses, a refuting verifier per lens): 37 findings, 30 upheld, all fixed
- [x] Commit

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

## Review — M2, every number measured (`Tools\gates.ps1`: 28 gates incl. 4 negative controls)

### Decisions taken (spec left them open)
- **Sandbox vs world.** The origin is safe by spec, so the M1 loop gates run in `GameMode.Sandbox`
  (the M1 arena, kept for probes and the bench); play and the M2 gates run the world.
- **Player territory is quiet for good.** Spec 7 says clearing flips a sector to the player and
  territory persists through death, but not what it holds. Measured consequence first: when
  territory refilled with the rival's garrison it was only a map colour (review finding). Now no
  garrison returns; its former owner's light still flows as 5-energy pickups every 0.5 s from a
  200-energy pool per life, so a new life can regrow there (flight-limited to ~3 energy/s, a pool
  that runs dry, fighting pays more while rival land remains).
- **Aim line 0.5 s, not "brief".** Spec 8 asks for brief aim lines; spec 9 requires 0.5 s of warning
  for an attack that cannot be dodged on reaction, and Scorch's triple cone up close is one.
- **Crossing needs a 0.2 s push.** A novice bot backing away from a cone ping-ponged across one edge
  six times; a brush no longer leaves the fight.

| metric | gate | measured |
|---|---|---|
| unit tests (incl. bot and perf categories) | all | 199/199 |
| ships / warnings | 0 warnings | 6 / 0 (Flare 43.1 px, Scorch 60.4 px vs 45 / 65) |
| M1 loop in the sandbox: first evolution, perfect / novice | ≤ 120 s | 22.6 / 24.1 s max |
| first evolution in the world (leaving the safe origin), perfect / novice | ≤ 120 s | 23.7–25.5 / 23.9–27.5 s |
| world bot beats the gate, perfect, seeds 1–5 | first try, ≤ 300 s | 129.6–138.0 s, 0 failed attempts |
| world bot beats the gate, novice (no dodge), 20 seeds | median ≤ 300 s, all ≤ 1200 s | median 154.1 s, max 398.5 s |
| death after the gate, back in the checkpoint by teleport, perfect / novice | ≤ 240 s | 85.8–91.2 / 83.5–113.9 s |
| a fresh tier-1 life in a layer-1 sector, each owner (sweep) | perfect clears, no deaths | fire 22.4 s, corruption 23.2 s; novice 23.8 / 26.4 s, 0 deaths |
| rival perception delay (300 pilots) | 150–300 ms | 9–18 ticks, both ends reached |
| rival reacts to a bullet / notices a target | ≥ its delay; zero-delay control earlier | exactly at the delay; control at tick 1 |
| rival aim error per burst (still target) | 2–5 deg | every burst 2–5 deg, varies between bursts |
| aim line before every burst (its own), shots with no line up | ≥ 30 ticks / 0 | ≥ 30 / 0 |
| gate warning before the lock-in (flying straight at it) | ≥ 60 ticks | passes (WorldTests) |
| map: padlock on the unexplored gate / after it falls | > 40 / ≤ 5 px | 987 / 0 px (diamond 796 px) |
| map: radiation icons, territory, rival colours, unexplored dark | all | 16/16, 2/2, 2/2, 18/18 |
| map: veil ring, threshold label, current-sector frame | ≥ 85 %, ≥ 60 px, ≥ 80 % | 34/34, 204 px, 118/118 |
| minimap padlock (outside its "+N"), "+N", rects disjoint | ≥ 12, ≥ 6, yes | 89, 44, yes |
| approach: warning text / dashed gate edge / lit fraction | says "LOCKS EVERY EXIT" + needs | 8321 px / dashed / 0.70 |
| locked in: barrier lit / aim line on its segment / boss bar | ≥ 90 % / ≥ 80 % / ≥ 80 % | 149/149 / 16/16 / 3840/3840 |
| world play at 150 s: probes, light blue outside the player's team | 3/3, 0 | 3/3, 0 (territory edge bands allowed where drawn) |
| interpolation in the world at 150 s (alpha 0.5) | ≤ 1.5 px, sensitive | 0.82 px (one-tick lead 2.70 px) |
| negative controls: no halo / no map padlock / no minimap padlock / no veil label | must FAIL | all four fail |
| hash Godot == CLI, sandbox seeds 1 / 9 | equal | bdf186a96b1c2515 / 40d7955434aa9465 |
| hash Godot == CLI, world seeds 1 / 9 | equal | 798b525ec8aad918 / 8acd04352e46d2df |
| headless ms/tick @2000 / engine frame @2000 | < 2.0 / < 16 ms | 0.038 / 0.736 ms |

The sandbox hash moved from M1's 9b7797f863b9da8f for three recorded reasons: the new fire forms
(the bot evolves into the Flare), velocity now equals real displacement (a wall-pinned ship stood
"moving"), and the bot steers off walls. With only the M1 ships and before those two fixes the
refactored sandbox reproduced 9b7797f863b9da8f / 796d1e90a60e06f2 exactly.

### Adversarial review of M2 (30 upheld of 37, all fixed)
World: territory was only a map colour (refilled at death); infection damage walked through the
reshape's invulnerability (one choke point now); drift could flip a sector through player territory
or flip it back in the same death; the border-shift notice was always overwritten. Rivals: steered
onto their own fresh shed light; a 0.3 s aim line under spec 9's 0.5 s; later volleys flew along
lines never shown; a cancelled line flashed for one tick; new targets were seen with zero delay;
rival drones counted as rivals. Sim: velocity was the commanded one (trail while pinned, lead into
walls); layer-2 enemies' vents and nucleus did nothing. View: minimap "+2" on the padlock; veil's
second line off-screen on two edges; clicking "HERE" closed the map for nothing; a checkpoint click
fired the weapon on arrival; `-Ship` ignored in world captures. Verification: the minimap and
veil-label instruments could pass with the element missing; the aim-line test counted volleys; the
retreat test skipped both thresholds; the death test passed without the checkpoint; the rider
could spawn off-screen. Rejected by the verifiers (7), among them: an infection caught next door
still ticking in the origin (the origin spawns nothing; a status carried in is not a threat there),
the hash omitting per-life sector memory (it only matters through state the hash does cover), and
a rival under sustained fire never ending its retreat (it does, at 70 %, and retreating is the point).

### What is NOT verified (M2)
- **Whether a human understands lock-in before entering a gate** (spec 19 M2). Measured: the map's
  padlock and caption on the unexplored gate, the minimap padlock, the dashed gate edge with
  padlocks, and the warning text, all present before entry. Understanding needs a tester.
- **Boss feel.** The perfect bot beats Scorch in ~13 s; the no-dodge novice loses about half its
  first attempts. `RivalHpMultiplier` (2.5) and the burst timings are the knobs.
- **Quiet territory as a design.** It makes the world progress and keeps regrowth to ~1.5 minutes
  in the bots' runs; whether it feels right is a hands-on call (see Decisions).
