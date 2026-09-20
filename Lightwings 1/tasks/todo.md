# Lightship v0.2 → v0.3 — build plan

Spec: `docs/LIGHTSHIP_GAME_SPEC_V3.md` (v0.3, with the approved-scope preamble).
Plan approved 2026-09-20. Branch `lightship-v0.3`; baseline commit `045d409` is the untouched v0.2 build.

One command runs every gate: `tools\gates.ps1` (exit 0 only if every gate passes **and every negative control fails**).

House rules: measure, don't assert. Every new instrument gets a negative control. Play claims are distributions over ≥ 20 seeds (median and max). Each phase ends green, with its numbers recorded below, retired assertions listed with their replacements, and one path-scoped commit.

Mandatory stop for hands-on review: **after P7**. Non-blocking checkpoint: roster captures after P2.

---

## P0 — Baseline and harness
- [x] Branch `lightship-v0.3`; stage `Lightwings 1` only; foreign-path detector proven on a foreign path; baseline commit
- [x] `docs/LIGHTSHIP_GAME_SPEC_V3.md` with approved-scope preamble; v0.2 spec marked archived
- [x] `tasks/todo.md`, `tasks/lessons.md`
- [x] Record baseline suite counts and wall-clock times (before any code change)
- [x] Real v0.2 save fixtures: `tests/fixtures/campaign_v3.json`, `demo_v3.json` (generator: `tests/support/make_v3_fixtures.gd`)
- [x] Golden trace `tests/golden_trace_test.gd` (fixed seed, 11-step scripted life) + negative control (one reversed command)
- [x] Harden `tools/test.ps1` via `tools/lib.ps1`: file redirection, timeout, required summary line, `SHADER ERROR` grep, GPU tests by pattern, per-test timing, `artifacts/test-summary.json`, `-Only`
- [x] `test.ps1 -SelfTest` with `tests/harness_negative/{passing,failing,silent,error,hang}_test.gd` — positive control passes, each negative fails for its own reason
- [x] `tests/support/harness.gd` and `tests/support/bot_pilot.gd` (perfect + novice)
- [x] `tests/combat_benchmark.gd --assert` + negative controls `--budget-scale=0.01` and `--fill-scale=2`
- [x] `tools/gates.ps1 [-Quick] [-GPU] [-Exports]`
- [x] Exports verified (`gates.ps1 -GPU -Exports`: 8/8 ok in 55.6 s; both Windows packages rebuilt and 178/178 in-package checks each); commit

## P1 — Seams (no behaviour change, no test edits)
- [x] `scripts/ui/ui_kit.gd` (static builders; main.gd keeps one-line forwarders)
- [x] `scripts/world/mode_config.gd` answering exactly as v0.2 (`save_slot`, `max_tier`, `achievements_enabled`, `cloud_enabled`); replaces the `3 if campaign.demo else 5` literals in main.gd
- [x] `SCREEN_POLICY` table in main.gd (`pauses`, `escape_closes` per overlay kind) replacing the unconditional pause and the escape block
- [x] One `_achieve(id)` guard in main.gd (6 call sites)
- [→ P5] `scripts/ui/hud.gd` — **re-sequenced.** A pure move of UI-building code cannot be proven neutral today: no instrument measures HUD layout. It is extracted in P5 together with `MinimapModel`, where it gets model-based tests
- [→ P5–P7] `scripts/world/run_controller.gd` — **re-sequenced** for the same reason: the run/transition/death flows are rewritten in P5 (modes, levels), P6 (warp, save scheduling) and P7 (death card); each extraction lands with the tests for its new behaviour
- [x] `scripts/combat/combat_persistence.gd` (snapshot output byte-identical; static functions taking the world)
- [x] `scripts/combat/combat_broadphase.gd` — a pure move in P1. Integer handles / SoA move to P4, where per-circle registration needs them; changing collider identity here could not be proven behaviour-neutral
- [x] Integer sim `tick` member (NOT in the snapshot until P2: a new snapshot field would change the golden-trace fingerprint); deleted `collision_actor.gd` (zero references)
- [x] FX RNG: checked 2026-09-20 — every `_rng` call in `combat_world.gd` is sim-side, no visual draws from it. Nothing to separate yet; the rule "FX and trails use their own RNG" applies from P6/P8, with a test that sim state is identical with visuals on and off
- [x] `tests/facade_contract_test.gd` + negative control
- [x] Proof: counts identical to P0, no diff under `tests/` or in `package_validation.gd`, golden trace identical, exports verified; commit

## P2 — Ship model: two primitives, graph, groups, six tiers, 101 hulls

Done as four sequential steps, each ending green with its own commit (the files interlock too tightly for one step to be provable):
- **P2a-1 Primitives + parent graph.** `PartDefinition`: `shape` circle|line, `radius`, `filled`, `parent_id`, `hp`; `size`/`rotation`/`weapon_hp` and the ellipse/crescent/arc/ring/tether shapes removed; body part renamed `core`; `black` palette role. The OLD generator is adapted mechanically (ellipse → circle, crescent → rimmed + black circle, ring → unfilled circle, tether → line, parents assigned) and all 136 hulls regenerated. Still 5 tiers, same stats and mounts, so the sim should not move: **the golden trace is expected to stay identical.**
- **P2a-2 Motion evaluator + shader slots.** `ship_motion.gd` (ShipRig / ShipPose / step), `group_definition.gd`, lines out of the 128 uniform slots, `.z` radius scale, `.w` flare, `inward()` and whole-ship `breathes` deleted, reshape through the evaluator.
- **P2b-1 Six tiers + new generator + roster 141 + validate().**
- **P2b-2 Editor (Motion tab, inspector, JSON §22, v2 import) + evolution fill rule.**

- [ ] Schema v3 on `PartDefinition` / `ShipDefinition`; `group_definition.gd`
- [ ] `scripts/ships/ship_motion.gd` (ShipRig / ShipPose / step); delete shader `inward()` and whole-ship `breathes`
- [ ] Shader: lines out of the 128 uniform slots; `.z` radius scale, `.w` rim flare
- [ ] GameTuning: 6 tiers, thresholds, T6 max 2300, TP 36, slots table, element order
- [ ] `scripts/ships/ship_generator.gd` + `ROSTER` manifest; five element builders; growth by addition
- [ ] Roster 101 + 25 + 10 + 5 = 141 regenerated; no nearest-tier fallback
- [ ] `validate()` hard errors (parent graph, attachment, line ends, group caps, > 128 circles)
- [ ] Editor: Body = circle + line (+ macros), Parent/Filled/Radius/HP inspector, Motion tab, derived literals, JSON §22 + v2 upgrade
- [ ] `EvolutionRules` fill rule
- [ ] Proof list from the plan (pose = collider = muzzle, determinism, GPU orbit, 120-circle hull, census, growth subset, roles, footprint, rejected shapes, cache miss) each with its negative control; commit
- [ ] Post roster captures for a look (non-blocking)

## P3 — Node geometry
- [ ] `scripts/combat/circular_arena.gd` replaces `rounded_arena.gd`; analytic `boundary_hit`
- [ ] Rim with 80 px dead space; membrane arcs for open exits only; heavy wall on sealed sides
- [ ] Spawn placement, `sector_edges.gd`, MultiMesh AABB
- [ ] Proof: hit within 0.01 px, 1000 bounces inside, membranes only where exits exist, benchmark `--assert`; commit

## P4 — Enemies as graphs
- [ ] Per-circle HP arrays; every alive circle in the broadphase; queries replace actor loops
- [ ] Detachment → debris (velocity kept, spin, 1 s fade, light drop; flushed on node exit)
- [ ] Remove armoured-core rule; rewards half limbs / half core
- [ ] `scripts/combat/combat_ai.gd`: archetypes, 150–300 ms decisions, 2–5° aim error
- [ ] Bosses: sub-cores, shield generators, no respawn, `boss_defeated(level_id)`
- [ ] Snapshot allow-list + packed codecs; remap by id on definition edit
- [ ] Editor elite preview: per-circle HP, what detaches
- [ ] `V02-ADAPTER` descriptor shim
- [ ] Proof list + play census per level, each with its negative control; commit

## P5 — World, modes, saves, minimap
- [ ] `CampaignState` v4: epoch, level seed, Chebyshev rings, bounded levels, membrane function, boss cell, archetype table, element blocks
- [ ] Starter pickups from the descriptor; unlock on absorb
- [ ] ModeConfig rows campaign / dev / demo; menu; level select; dev evolution tabs; `dev_console.gd`
- [ ] Level-complete flow
- [ ] `MinimapModel`; minimap; map screen; extract `scripts/ui/hud.gd` here (moved from P1) with `tests/hud_model_test.gd`
- [ ] Extract `scripts/world/run_controller.gd` here (moved from P1) as the new/continue/enter/level flows are rewritten; the warp and save scheduling join it in P6, the death card in P7
- [ ] Save schema 4; v3 → v4 migration; slots; dev never cloud-synced; demo import
- [ ] Remove `V02-ADAPTER` (token count 0)
- [ ] New tests: world generation (200 seeds × 5 levels, 4 mutants), mode isolation, unlock/offers, HUD model
- [ ] Rewrites: world rules, campaign playthrough, UI flow, world platform, package validation
- [ ] Exports verified; commit

## P6 — Handling and the warp
- [ ] Momentum per role; rim slow; enemy easing
- [ ] Dash: command, bindings, Steam Input action, HUD icon, no i-frames
- [ ] `scripts/combat/trail_pool.gd`; ship lightstreams
- [ ] Compositor zoom + focus; `screen_to_world`
- [ ] Warp state machine (sim) + presentation; reduced-warp option; Options reflow
- [ ] Saves moved to calm moments; `_save_game` timed
- [ ] Proof list with negative controls; commit

## P7 — Pace and the run loop → STOP for hands-on review
- [ ] `_update_pace`: decay, combo, sized pickups + 3× enemy light, pool refill, respawn
- [ ] `run_stats()`
- [ ] Death: immediate rebuild, 1.2 s non-pausing card, fresh-press dismissal, best ring
- [ ] HUD: combo, evolve pill, regression flash, poison/slow marker
- [ ] `tests/acceptance_bot.gd` → `artifacts/acceptance_v03.json` (novice first evolution, camper vs pusher, death → control, boss bearing, fire-seeker)
- [ ] Rewritten combat assertions (`:37-38`, `:199`, `:71-74`); commit
- [ ] **Stop. Hands-on review. Feedback into `tasks/lessons.md` before P8.**

## P8 — Attack and impact animation
- [ ] `scripts/combat/combat_fx.gd` pool + templates + ≥ 0.25 s choke point
- [ ] Target rim flare, dark collar
- [ ] Projectile radii, interiors, per-weapon trails, seeker weave, rocket wallow, beam, virus
- [ ] Background density by ring; mine telegraph ≥ 0.5 s; damage numbers
- [ ] Proof list + benchmark `--assert` (2000 bullets, 40 ribbons, boss, elites, drones); commit

## P9 — Narrative, demo, docs, exports
- [ ] `scripts/ui/dialogue_director.gd` with immediate lane; boss and unlock lines; coverage test
- [ ] Demo flavour (levels 1–2)
- [ ] README, INTERFACES, VALIDATION (old → `VALIDATION_V02.md`), RELEASE_CHECKLIST, STORE_DRAFT, workshop doc, STEAM_SETUP
- [ ] `tools/package.py` 0.3.0; presets; four exports verified; commit

## P10 — Adversarial review
- [ ] Review by lens; findings challenged; upheld findings fixed with a test each
- [ ] Final `tools\gates.ps1 -GPU -Exports`; review + "what is NOT verified" below; commit

---

## Review — P0 (numbers measured, not asserted)

No game code changed in P0. Everything below was measured on the untouched v0.2 build (`045d409`), development desktop, Godot 4.7.2.

| What | Measured | Gate |
|---|---|---|
| Baseline commit | 331 files, all under `Lightwings 1/`; 0 under `.godot/ .tools/ builds/ artifacts/` | foreign-path detector fired on a foreign control path; ignored-dir regex fired on a control path |
| v0.2 headless suite | 13/13 pass in 10.1 s. campaign 157 · combat 138 · meshes 5362 · reshapes 5874 (100 routes) · ships 5324 · UI 32 · platform 31 · world rules 164 — identical to `docs/VALIDATION.md` | — |
| v0.2 GPU pixel tests | 2/2 pass in a real window: core widths 6/6, outline widths 2/2; void halo 0.545, masked 0.0 | selected by `_render_test.gd` pattern |
| Harness self-test | passing → PASS; failing → "exit code 1"; silent → "no summary line"; error → "engine error"; hang → "timed out" (killed at 15 s, 0 orphan processes) | 5/5 judged correctly |
| Save fixtures | campaign and demo, 69 111 bytes each, schema 3, demo flag false/true, deaths 1, 1 waypoint, hull `player_fire_t2_standard_b` T2, light 184.05; file hashes differ | generator exits 1 unless both written |
| Golden trace | 11 steps (new game → fight → evolve → regress → map → die → reboot), final snapshot `9a9e4016fb468afd`; identical twice in one process and from 2 fresh processes | reversed-command control caught |
| Headless benchmark | 1000 bullets: mean 3.6–3.8 ms, p95 4.3–4.8 ms. 2000 bullets: mean 5.9–6.9 ms, p95 7.0–9.3 ms, max up to 15.7 ms; pool rejected 0 (5 runs) | budgets 5.5/7.0 and 9.0/12.0 ms; `--budget-scale=0.01` fails 4/4 timing lines; `--fill-scale=2` fails 2/2 fill lines |
| `tools\gates.ps1 -GPU` | 5/5 gates ok in 46.9 s; suite now 16 tests (13 + golden trace + 2 GPU) | both NEGATIVE gates ok=1 |

**Plan correction found by measuring.** The plan's P8 budget "sim mean ≤ 4.5 ms at 2000 bullets" is below the v0.2 baseline (5.9–6.9 ms) and was never measured; it came from a design estimate. The P0 gate uses budgets derived from the measurements above. Before P8 the target must be re-derived: either the perf reclaimers in P1–P4 (integer broadphase, analytic arena, no per-tick allocation in `_sync_visuals`) are shown by measurement to reach it, or the budget is restated from what the frame actually has to spare. The rendered-frame p95 (16.5 ms in `docs/VALIDATION.md`) has not been re-measured in P0.

**Not verified in P0:** Linux exports (need Docker), rendered-frame benchmark (`main.gd --benchmark`), anything about v0.3 behaviour.

## Review — P1 (seams; no behaviour change)

| What | Measured |
|---|---|
| `combat_world.gd` | 1346 → 1143 lines. Persistence and broadphase moved verbatim; forwarders kept for `snapshot`, `restore`, `_rebuild_actor_grid` (used by tests, main.gd, package_validation); `sector_cache` / `encounter_records` stay members because tests read them |
| `main.gd` | 1138 → 1117 lines. UiKit, ModeConfig, SCREEN_POLICY, `_achieve` |
| Suite counts vs P0 | identical: campaign 157 · combat 138 · meshes 5362 · reshapes 5874 · ships 5324 · UI 32 · platform 31 · world rules 164 |
| Golden trace | unchanged fingerprints at all 11 steps (mode, overlay, paused flag, hull, tier, light, offers, profile, snapshot, dialogue); recorded file not touched |
| Files changed under `tests/`, `scripts/platform/` | none, except the new `tests/facade_contract_test.gd` |
| Facade contract | 78 checks, 0 failures; control "a name main.gd does not define" caught |
| `gates.ps1 -GPU -Exports` | 8/8 ok in 55.7 s; 17 tests; both Windows packages rebuilt, 178/178 in-package checks each; benchmark within budget |
| CAMPAIGN_COMPLETE now behind `_achieve` | neutral: `CampaignState.defeat_core` only sets `completed` in the non-demo branch, so a demo campaign can never reach those sites |

Left alone on purpose (not ModeConfig questions): menu-time `OS.has_feature("demo")` button and preview gating, the "DEMO"/"CAMPAIGN" sector label, the demo ending branch, the demo minimap filter. They are rewritten in P5.

Noted, not fixed: `SCREEN_POLICY["intro"]` and `_show_rival_intro` are dead code in main.gd (no caller). `_gun_position` is called across files from the broadphase; it goes away with integer handles in P4.

## Review — P2a-1 (primitives + parent graph)

| What | Measured |
|---|---|
| Schema | `PartDefinition`: `shape` (circle\|line), `radius: float`, `filled: bool`, `parent_id: String`, `hp: float` replace `size`, `rotation`, `weapon_hp`; `"tether"`→`"line"`, `"ring"`→circle+`filled=false`, `"ellipse"`/`"crescent"`/`"arc"` removed. `ShipDefinition.schema_version` 2→3. Body part id `"body"`→`"core"` everywhere. New palette role `"black"` (rim/fill/light all black), used for the void crescent's covering disc. |
| Regenerated roster | 136/136 hulls rebuilt via `export_catalog.gd --rebuild`, 0 failures; `ships_validation` census: 81 player / 25 enemy / 25 elite / 5 rival unchanged |
| Shape census | Only `circle` and `line` appear across all 136 hulls (asserted in `ships_validation.gd`); no ellipse/ring/arc/crescent/tether survives |
| `footprint` / `tp_used` movement | `tp_used`: 0 delta on every corruption and void hull (the black crescent-cover circle is TP-free, like the geometry it replaces). `footprint`: void 0 delta on all 27 hulls; corruption -2.25 px to 0 px (elites and T1 unaffected; T2–T5 lobes shrink slightly because a circle keeps the *mean* of the old ellipse's two half-axes instead of the larger one) |
| Golden trace | Identical at all steps, not re-recorded (mounts, stats and every id but `body`→`core` were kept byte-identical) |
| `test.ps1 -GPU` | 17/17 pass. Per-ship-test check counts, old → new: `ships_mesh_test` 5362→5416, `ships_reshape_test` 5874→5958 (100 routes), `ships_validation` 5324→6779 (new parent-graph and shape negative controls) |
| `gates.ps1 -GPU -Exports` | 8/8 ok in 57.7 s |
| Screenshots | Player gallery: corruption hulls render as round blobs (lobes are circles, not ellipses). Direct `ShipRenderer` captures of `enemy_void_t3`: the "maw" shows as a rimmed circle with a visible gap in its rim where the black cover circle sits — reads as a crescent; plasma orbit rings render unfilled. Nothing rendered black-on-black by accident (checked at 8x zoom) |

Retired/rewritten assertions: `tests/ships_validation.gd:51-52` ("Ellipse restricted to corruption") replaced with "Ellipse is never legal" plus new negative controls for `ring`/`tether`/`crescent`/`arc`, a parent cycle, a parent chain that never reaches the core, and a line ending on a line. `ship_catalog.gd`'s "circular geometry must have equal dimensions" rule was removed (no longer representable: a circle only ever has one radius).

## Retired assertions

_Each retired assertion is listed here with the phase, the reason, and its replacement._
