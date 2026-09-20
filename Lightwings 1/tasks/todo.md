# Lightship v0.2 → v0.3 — build plan

Spec: `docs/LIGHTSHIP_GAME_SPEC_V3.md` (v0.3, with the approved-scope preamble).
Plan approved 2026-09-20. Branch `lightship-v0.3`; baseline commit `045d409` is the untouched v0.2 build.

One command runs every gate: `tools\gates.ps1` (exit 0 only if every gate passes **and every negative control fails**).

House rules: measure, don't assert. Every new instrument gets a negative control. Play claims are distributions over ≥ 20 seeds (median and max). Each phase ends green, with its numbers recorded below, retired assertions listed with their replacements, and one path-scoped commit.

~~Mandatory stop for hands-on review: **after P7**.~~ **Waived by the user on 2026-09-20: "run through the entire spec, don't stop until you've finished everything."** Every phase still ends green with its numbers recorded and its own commit; what is gone is the pause for hands-on feedback. Human-feel questions (handling, warp, boss difficulty, whether testers push out rather than camp) therefore stay unverified at the end and are listed as such in the final record.

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

- [x] Schema v3 on `PartDefinition` / `ShipDefinition`; `group_definition.gd`
- [x] `scripts/ships/ship_motion.gd` (ShipRig / ShipPose / step); delete shader `inward()` and whole-ship `breathes`
- [x] Shader: lines out of the 128 uniform slots; `.z` radius scale, `.w` rim flare
- [x] GameTuning: 6 tiers, thresholds, T6 max 2300, TP 36, slots table. Element order (`GameTuning.ELEMENTS`) deliberately NOT reordered here: it only matters to the campaign's level reveal (`campaign_state.gd _initial_element`, `_region_elements`) and the evolution tie-break (`evolution_rules.gd ROOT_ORDER`); reordering now would move the v0.2 wedge world's element assignment for no benefit this step. **Deferred to P5**, alongside the world rewrite that already touches those files.
- [x] `scripts/ships/ship_generator.gd` + `ROSTER` manifest (named `roster_manifest()`); five element builders; growth by addition (id-subset, not full-attribute-subset — see P2b-1 review)
- [x] Roster 101 + 25 + 10 + 5 = 141 regenerated; no nearest-tier fallback (`ShipCatalog.pick_enemy` / `ShipGenerator.pick_enemy`, tagged `V02-ADAPTER`, hard-errors on an unknown element/faction)
- [x] `validate()` hard errors (parent graph, attachment, line ends, group caps, > 128 circles) — plus new P2b-1 rules: tier 1..MAX_TIER, TP x2.5 elite / x8 boss, player majority-light-blue
- [→ P2b-2] Editor: Body = circle + line (+ macros), Parent/Filled/Radius/HP inspector, Motion tab, derived literals, JSON §22 + v2 upgrade — unchanged this step; the editor still authors single hulls via `ShipCatalog.build_ship`, now forwarding to `ShipGenerator`
- [→ P2b-2] `EvolutionRules` fill rule — unchanged this step, per the plan's own phase split
- [x] Proof list (census, growth subset, roles, elite footprint, TP floor, element signatures, pick_enemy coverage) each with its negative control — see `tests/ship_roster_test.gd`; commit
- [x] Roster captures taken and looked at: growth by addition reads correctly (each tier keeps the previous arrangement and adds around it), corruption is irregular clusters with off-axis buds, void keeps its crescent and dashed reach rings, plasma rings unfilled. Gallery title was still hard-coded "81 PLAYER HULLS"; it now derives from the manifest (`ShipGenerator.player_hull_count()`)

**Regression found and fixed while verifying P2b-1** (`campaign_playthrough_test` was failing, 225/250 light):
each element is only authored across its campaign level's tier band, so a v0.2 wedge sector asking
for a low tier of a late element got a much higher-tier hull — carrying that hull's SLOT ALLOWANCE.
Measured against a stationary player over 10 s: a tier-1 corruption request fielded 2 mounts and
dealt 347 damage, plasma 3 mounts and 578, where `GameTuning.slots` grants tier 1 exactly one.
Slots are a hard cap in this game, so `ShipCatalog.trim_to_tier` now applies that cap to a
substituted hull, and a dropped ability takes its mount circle and that circle's line with it
(§17: every visible circle is an ability or a stat). After the fix: corruption 97, plasma 0, and
tier-3 requests unchanged (425 / 713). The route reaches 250 light in 14.0 s instead of stalling at
225. Locked by 706 checks in `ship_roster_test` incl. 12 negative controls; tagged `V02-ADAPTER`,
removed with the shim in P5.

- [→ P2b-2] `standard_a` and `standard_b` share geometry and differ only by primary weapon
  (standard_b carries ricochet). Legal per spec — roles are tags, not the menu, and the tier still
  spans three roles — but v0.2 gave standard_b a rear-biased arrangement, so the four cards read as
  three shapes. Worth a distinct arrangement when the editor work lands.

## P3 — Node geometry
- [x] `scripts/combat/circular_arena.gd` replaces `rounded_arena.gd`; analytic `boundary_hit`
- [x] Rim with 80 px dead space; membrane arcs for open exits only; heavy wall on sealed sides
- [x] Spawn placement, `sector_edges.gd`, MultiMesh AABB
- [x] Proof: hit within 0.01 px, 1000 bounces inside, membranes only where exits exist, benchmark `--assert`; commit

## P4 — Enemies as graphs
- [x] Per-circle HP arrays; every alive circle in the broadphase; queries replace actor loops (P4a)
- [x] Detachment → debris (velocity kept, spin, 1 s fade, light drop; flushed on node exit) (P4a)
- [x] Remove armoured-core rule; rewards half limbs / half core (P4a)
- [x] `scripts/combat/combat_ai.gd`: archetypes, 150–300 ms decisions, 2–5° aim error (P4b, see review below)
- [x] Bosses: sub-cores, shield generators, no respawn, `boss_defeated(level_id)` (P4b, see review below)
- [x] Snapshot allow-list + packed codecs; remap by id on definition edit (P4a)
- [ ] Editor elite preview: per-circle HP, what detaches — not done in P4b either, still open
- [x] `V02-ADAPTER` descriptor shim (P4a)
- [x] Proof list + play census per level, each with its negative control; commit (P4b: `tests/enemy_ai_test.gd`)

## P5 — World, modes, saves, minimap

Split into P5a (the world model, done below) and P5b (modes, save schema 4, minimap/HUD model, run_controller) per the session brief.

- [x] `CampaignState` v4: epoch, level seed, Chebyshev rings, bounded levels, membrane function, boss cell, archetype table, element blocks
- [x] Starter pickups from the descriptor; unlock on absorb
- [→ P5b] ModeConfig rows campaign / dev / demo; menu; level select; dev evolution tabs; `dev_console.gd`
- [x] Level-complete flow (`CampaignState.complete_level()`; the menu-facing level-complete SCREEN is P5b)
- [→ P5b] `MinimapModel`; real map screen; extract `scripts/ui/hud.gd` (P5a shipped a minimal compiling stand-in in main.gd's `_show_map`/`_draw_minimap` so the build keeps running - no waypoints/teleport, a single boss marker, a sealed-perimeter ring)
- [→ P5b] Extract `scripts/world/run_controller.gd`
- [→ P5b] Save schema 4 migration test suite, slots, dev never cloud-synced, demo import (P5a bumped `CampaignState.GAMEPLAY_VERSION` to 4 and fixed the `SaveService._validate_snapshot` schema-4 rejection bug this uncovered - see review below - but the full v3->v4 migration proof is P5b's)
- [x] Remove `V02-ADAPTER` (count before 15 occurrences across 4 files -> 0; asserted by `unlock_offers_test.gd`'s recursive scan with its own negative control)
- [x] New tests: `world_generation_test.gd` (200 seeds x 5 levels, 4 mutants), `unlock_offers_test.gd`. Mode isolation and HUD model tests are P5b (nothing to isolate/model yet)
- [x] Rewrites: world rules, campaign playthrough, UI flow, world platform. `package_validation.gd` needed no change (grepped - no removed API used)
- [x] Exports verified; commit pending

### Review — P5a (the world model)

| What | Measured |
|---|---|
| `CampaignState` v4 fields | Persistent: `mode`, `world_seed`, `epoch`, `deaths`, `unlocked`, `levels_completed`, `best_ring`, `story_flags`. Per-life (reset on epoch change - death OR `travel_to_level`): `level`, `current_sector`, `discovered`, `ring_reached`, `boss_down`, private `_node_state` (light-pool bookkeeping). `level_seed()=hash(world_seed,epoch,level)` |
| Descriptor contract | `sector_at(coord,now=0.0)` keys documented in `docs/INTERFACES.md`: `coord,id,in_bounds,ring,tier,element,archetype,kind,exits,encounter_seed,encounter_epoch,pool_size,pool_remaining,resource_budget,respawn_cooldown,boss_down,cleared,enemy_hulls,elite_hulls,boss_hull,starter_pickups` |
| Membrane construction | Each cell's Manhattan-closer neighbour is its structural "parent" (always open, hash-chosen among candidates); every other edge opens via a hash of the canonical/sorted pair below `EDGE_OPEN_PROBABILITY=0.30`. Measured over 40 seeds x 5 levels (78,920 sampled nodes): exit-count histogram `{0:0, 1:4985, 2:36340, 3:27677, 4:9918}`; <4-exit share **87.4%** (>=25% required); dead-end (<=1 exit) share **6.3%** (within the 3%-25% band); BFS distance to boss median **14**, max **23** |
| Boss placement | Always ring R, never a corner, never with the free coordinate <=1 (axis-adjacent); >=12 distinct positions confirmed at both the 40-seed full-scan sample size and the cheap 200-seed check |
| Archetype shares | Within +/-0.05 of `GameTuning.ARCHETYPE_TABLE` in every (level, ring-band) bucket sampled; elite-lair share non-decreasing band-to-band, confirmed by the same scan |
| Tier / enemy population | `tier==1+ring/2` clamped to 6 held on every sampled node (0 mismatches); enemy count does not fall sharply as ring rises (checked band-to-band) |
| Element pools | Every rolled element stayed inside `ELEMENTS[0..level-1]` across all 40 seeds x 5 levels x every in-bounds node |
| Fresh seed every life | 0/200 seeds produced an identical layout fingerprint after `on_death()` |
| Four mutants | `NoParentMutant`: connectivity check fails (36,065/39,460 unreachable at 20 seeds). `OrderedPairMutant`: symmetry check fails (15,827/75,040 mismatched edges). `OffByOneBossMutant`: perimeter check fails (100/100 boss placements wrong) and distinctness collapses to 5 positions. `IgnoredSeedMutant`: fresh-seed check fails (>0/20 identical fingerprints after death). All 4 caught as `h.control(...)` in `world_generation_test.gd`, with **zero raw engine `ERROR:` lines** (a `SilentProbe` inner class replaces `Harness.check`'s `push_error` for the intentionally-sabotaged scratch runs, so `test.ps1`'s log-grep gate does not misread an expected mutant failure as a real one) |
| `V02-ADAPTER` | 15 occurrences across `combat_world.gd`, `ship_catalog.gd`, `ship_generator.gd`, `ship_roster_test.gd` before this step -> 0 after, asserted by `unlock_offers_test.gd`'s recursive `res://scripts` scan (its own negative control seeds a throwaway file with the marker and confirms the scan reports it) |
| Descriptor-named hulls | `ShipCatalog.pick_enemy`/`trim_to_tier` deleted outright. Replaced by `ShipGenerator.hull_id(faction,kind,element,tier)` (deterministic band-clamp, no nearest-candidate search) and `ShipCatalog.cap_to_tier` (same slot-capping behaviour, renamed, no longer tagged as a legacy shim since a node whose block-rolled element sits outside its authored tier band is now a legitimate, expected v0.3 case, not a wedge-world artifact) |
| Bug found and fixed (not part of the brief, but blocking every save) | `scripts/platform/save_service.gd:157` `_validate_snapshot` hard-capped `schema_version>3`, silently rejecting every profile once `CampaignState.GAMEPLAY_VERSION` became 4 - `_atomic_write`'s own read-back verification then failed and EVERY `save_snapshot` call returned `ERR_FILE_CORRUPT` (16). Found via `ui_flow_test.gd`'s "Pending evolution writes to isolated save" failing; fixed by introducing `SaveService.MAX_KNOWN_GAMEPLAY_SCHEMA=4` in place of the literal `3` |
| `test.ps1` (headless) | 22/22 tests, 0 failures (up from 0/13 compiling at the start of this step) |
| `tools\gates.ps1 -GPU -Exports` | 8/8 ok in 111.0s: harness self-test, suite 26/26 (22 headless + 4 GPU), benchmark budgets + both negative controls, both Windows exports built and verified (2/2 packages) |
| Golden trace | Re-recorded (expected: `CampaignState.to_dict()` schema changed outright). Checked first, per the plan's own rule: `new_game` step matched on every field through `offers` (mode, overlay, paused, sector, hull, tier, light=40.0, enemies, bullets, offers) - only `profile`'s digest moved, from the schema change alone. `godot_errors=0` on the record run. New final digest `5cdb0d1bdce1d7de`. Route coordinates `Vector2i(1,0)`/`Vector2i(2,0)` stayed legal without an edit: both are on-axis cells whose membrane back to `(0,0)`/`(1,0)` is a structural "parent" link, always open by construction |
| Live capture | `--play` (origin, tick 90): HUD reads "CAMPAIGN · NODE 0,0 · RING 0", minimap shows a single boss marker (yellow, bearing/distance) and the sealed-perimeter ring outline, no waypoint UI. `--show-combat` (node (-3,2), ring 3, tier 4): a plasma T4 player hull firing a beam at real spawned Lightning-element enemies (a radial elite with concentric rings, several drones with red weapon markings), minimap boss marker distinct from the local node marker, `engine_errors=0` both captures |
| Retired assertions | See the table below |

Not completed / stated plainly: `main.gd`'s map screen, minimap and death/reboot copy are P5a stand-ins only (waypoints and teleport removed outright per spec, but no level-select or mode menu exists yet - that is explicitly P5b). Node light-pool refill (`CampaignState.node_pool_state`/`record_node_left`) and the boss-only no-respawn rule are wired into the descriptor and `combat_world.start_sector`, but the real-time "enemies respawn on a cooldown" per-enemy timer is not simulated tick-by-tick (P7 "pace" territory) - within one epoch, leaving and returning to a regular node restores the exact state you left it in (the same `sector_cache`/`encounter_records` mechanism kept from v0.2), not a partial respawn. Demo mode's element/tier-cap semantics were left untouched (still v0.2's three-element/T3 cap via `ModeConfig`) even though the spec preamble now says the demo is "campaign levels 1-2, no tier cap" - that is `ModeConfig`'s P5b item. `CampaignState.import_demo` is a stopgap (always resets to level 1/epoch 0), not the real demo-import flow.

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
- [ ] **Found in a P4a live capture:** every projectile is a radius-3 quad whose element colour is
  multiplied by 1.8 emission, so plasma violet saturates toward pale blue-white on screen. That
  collides with pillar 5, "light blue is the player — no other ship, pickup or enemy projectile uses
  it". Measured in the `--show-combat` scene: 78 of 80 live bullets were enemy plasma shots. Fix
  when projectile appearance is built (per-weapon radius, interiors above 7 px, path identity), and
  add a pixel gate that no enemy projectile lands inside the player's light-blue hue band.
- [ ] Re-measure the RENDERED frame (`main.gd --benchmark`, v0.2 recorded p95 16.5 ms against a
  16.67 ms frame). P4a restated the headless 1000-bullet budgets because per-circle hitboxes raised
  the simulation floor; the render path is the binding constraint and has not been re-measured since.
- [ ] Proof list + benchmark `--assert` (2000 bullets, 40 ribbons, boss, elites, drones); commit

## P9 — Narrative, demo, docs, exports
- [ ] `scripts/ui/dialogue_director.gd` with immediate lane; boss and unlock lines; coverage test
- [ ] Demo flavour (levels 1–2)
- [ ] README, INTERFACES, VALIDATION (old → `VALIDATION_V02.md`), RELEASE_CHECKLIST, STORE_DRAFT, workshop doc, STEAM_SETUP
- [ ] `tools/package.py` 0.3.0; presets; four exports verified; commit

## P10 — Adversarial review
- [ ] Review by lens; findings challenged; upheld findings fixed with a test each
- [ ] Final `tools\gates.ps1 -GPU -Exports`; review + "what is NOT verified" below; commit

Carried forward for the review pass (found while verifying earlier phases, none of them gate-breaking):
- [ ] Enemy-only components are thin on elites: measured across the roster, `egg` and
  `deployment_ramp` sit on the 5 bosses only, `droid_bay` on 3 enemy hulls, `turret_ring` on bosses
  as real orbiting weapon circles (correct per §14 — the component IS the ring of circles, so it
  carries no `ability_id`). §14 does not require every elite to carry one, but elites are what M4
  says should kill the player. Consider one enemy-only component per elite.
- [ ] `turret_ring` still exists as an entry in `ability_catalog.gd` that nothing mounts, and its
  `_activate_component` case is dead code left commented in `combat_world.gd`. Remove both, or
  mount it somewhere, so the catalogue does not advertise an ability the game never uses.
- [ ] Bosses never get `_add_enemy_body_feature`, so a void boss has no `bullet_eater` mouth and a
  plasma boss no `projectile_orbit` — the body stats their element implies.
- [ ] `standard_a` and `standard_b` player hulls share geometry and differ only by primary weapon,
  so a tier's four offers read as three shapes (see the P2b-1 review).
- [ ] `SCREEN_POLICY["intro"]` and `_show_rival_intro` in `main.gd` are dead code with no caller.

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

## Review — P2a-2 (motion evaluator, groups, lines out of the uniform slots)

| What | Measured |
|---|---|
| `GroupDefinition` | `root_id, orbit_radius, orbit_speed (signed), drift_amp, drift_freq, breathe_amp, chain_mode, reach_ring`. `ShipDefinition.groups: Array[GroupDefinition]` |
| `ShipMotion` | `ShipRig` (circles only, pre-order DFS from `core`, so a subtree is `[i, i+subtree_size[i])`; parent/rest/radius/subtree_size/group_index/group_root_index/chain_position/mirror_index/line_from/line_to); cached content-addressed on `[circle id, position, radius, filled, parent_id]` + every group field, `MAX_CACHE_ENTRIES=96`, evicted like `ShipMesh`. `ShipPose` (`local, scale, flare` PackedArrays, no back-reference). `step(rig,pose,tick)` writes in place from `tick/60.0`; orbit/drift/breathe are closed-form; a group's subtree orbits the point where its root attaches to its PARENT (not around itself — a childless root orbiting itself would never move) |
| Lines off the 128 uniform slots | A line no longer takes a `part_indices` slot; its period/phase/authored-perimeter travel per-vertex in `CUSTOM0.xyz` (`ship_mesh.gd::_append_line`, `ship_outline.gdshader` branches on `primitive_kind>0.5` before touching `CUSTOM0.z` as an index). Measured new limits: circles (incl. synthesized reach rings) ≤ 128, lines ≤ 512 (`ShipCatalog.MAX_LINES`), both enforced in `validate()` with negative controls. `.z` is now a radius scale (1.0 normal, 0.0 hidden, reproduces the old `hidden_part_ids` alpha-cutoff exactly and additionally shrinks the rim geometrically); `.w` is a reserved rim flare, written 0.0 everywhere |
| 120-circle/119-line render check | New `tests/ship_motion_render_test.gd` (GPU): before this step's line change the old assert (`parts.size()<=128` counting lines) would have rejected a 120+119 hull outright; after, it builds and the synthesized hull's LAST line renders (pixel found), plus an orbiting circle's rim is found at the sim-reported position and not at rest (control: pose upload disabled ⇒ check fails, caught) |
| Hulls whose motion changed | corruption (all tiers/families, player+enemy+elite+rival): `motion_signature "breathe"` (whole-hull shader term) → `motion_signature "smooth"` + a group on `core` (`breathe_amp=0.05`, matches the old 1.00→1.05/2s curve, now also read by `_muzzle`/`_gun_position` so a corruption mount visibly breathes with the hull instead of only the old shader-only pulse). Corruption tier>1 hulls additionally get a mirrored orbit group per lobe pair (`lobe_i_l`/`lobe_i_r`, opposite `orbit_speed`, orbiting around `core`); lobes carry no mount, so this cannot move a bullet spawn point. void (all tiers/factions): `motion_signature "inward"` (whole-hull shader pull) removed outright — per spec, not a regression; the authored dashed "reach" part shrunk to a near-invisible stat carrier (radius 1.0, undashed) and a `reach_ring=true` group on it now synthesizes the visible dashed ring at the same `hull_radius+9` radius. lightning, fire, plasma: unchanged (`rigid`/no group; plasma's `orbit_N` rings are centered on their own rotation origin so a geometric orbit group would be a no-op — left as `counter_rotate` running-light only, real orbiting "ring rider" geometry does not exist yet and is P2b-1 content work) |
| Golden trace | Identical, not re-recorded (`GOLDEN TRACE: 4 checks, 0 failures`). The seed hull, fire T2 hulls and fire enemies carry no groups, so `_local_position()` (new helper behind `_muzzle`/`_gun_position`/the bullet-eater mouth) returns the old static fallback unchanged |
| `test.ps1 -GPU` | 19/19 pass. New/changed check counts: `ships_mesh_test` unchanged shape (4305, rewritten to check circles individually and lines via per-vertex CUSTOM0 instead of the old shared `part_indices` assumption), `ships_validation` 6779→6790 (11 new group negative controls), new `ship_motion_test` 19 checks/5 controls, new `ship_motion_render_test` (2 checks, 1 control) |
| `gates.ps1 -GPU -Exports` | 8/8 ok in 60.8s |
| Negative controls added | group root naming a nonexistent circle; two groups on one root; `|orbit_speed|>3`; `breathe_amp>0.08`; `drift_amp` over the mount-aware limit; unknown `chain_mode`; a sway/whip subtree that branches; mirrored roots spinning the same way; >128 circles+reach-rings; >512 lines; sim/render pose compared against a pose stepped to `tick-1`; a wall-clock-derived tick; 50 `RefCounted.new()` calls (allocation control); a mirrored pair with matching (not opposite) `orbit_speed`; a reach-ring group with a bad `root_id`; GPU pose-upload-disabled control. All confirmed caught |
| Gallery | Player gallery (81 hulls): corruption renders as round blobs, nothing black-on-black. Enemy/elite gallery: plasma ("Ion") rings render unfilled; nothing missing or broken across fire/lightning/corruption/plasma elites. Void's crescent/mask numbers re-measured unchanged by `ships_void_render_test` (halo 0.5449, masked 0.0, threat visible) — confirms the reach-ring rework did not disturb the maw/mask pipeline |
| Not completed / deferred (stated plainly) | Full physically-simulated follow-the-leader `sway`/`whip` chains are NOT implemented; `ShipMotion.step` gives them a closed-form travelling-sine approximation (deterministic in `(rig,tick)` as the spec allows for "as far as possible") — no content currently authors `sway`/`whip`, so this path is validated and unit-tested but unexercised in the shipped roster. Plasma "ring rider" satellites (spec's example of an orbit-group target) do not exist as authored geometry yet; that is P2b-1 scope. The editor has no Motion tab (P2b-2 scope, per the plan); groups can only be authored through `ShipCatalog.build_ship`/`GroupDefinition` directly today. `ShipMotion`'s nested-group compounding (an outer group whose subtree contains another group's root) is scoped/claimed correctly by `_build_rig` but a nested group's own motion is not composed on top of its parent's — no shipped hull nests groups, so this is untested in practice. Of the three body-feature stats, only the bullet-eater mouth offset was routed through `_local_position` (`combat_broadphase.gd`) because it is the only one whose `.offset` is actually read positionally; `void_pull` reads `actor.pos` directly and `projectile_orbit` reads only `.value`, so neither has a position to wire up. `body_features` entries now also carry `part_id` so a future group on `maw`/`reach`/`orbit_0` would only need the call site, not a schema change |

## Review — P3 (node geometry: circular arena)

| What | Measured |
|---|---|
| `CircularArena` (`scripts/combat/circular_arena.gd`) | `center: Vector2`, `radius: float` (`GameTuning.ARENA_RADIUS=800`, `GameTuning.ARENA_CENTER=(896,560)`), `membrane_half_angle` (`asin(64/800)`≈0.0800 rad), `exits: Array[Vector2i]`, `bounds: Rect2` (computed square `center±radius`, kept because `bot_pilot.gd` and package code read `.size`/`.get_center()`), `membrane_at(point)->Vector2i`, `membrane_anchor(direction)->Vector2`, plus the same method names as `RoundedArena` (`contains`, `clamp_point`, `boundary_hit`, `normal_at`, `exit_direction`, `entry_position`, `outline`, `in_opening`) so call sites needed minimal changes. `boundary_hit` is now closed-form ray/circle intersection (quadratic, larger root), not a 20-step bisection |
| Call sites | `combat_world.gd`: `Arena` preload repointed; every `arena.bounds.get_center()` → `arena.center`; enemy spawn ellipse `Vector2(550,330)` → `arena.radius*0.55` (a single scalar, no RNG involved so spawn counts/RNG draw order are unchanged). `arena_backdrop.gd`: rim drawn as `draw_arc` circle, one brighter arc per open exit (`MEMBRANE_COLOR`, `direction_angle`+`membrane_half_angle`), traces skip any segment whose endpoint is beyond `radius+GameTuning.ARENA_MARGIN` (the dead zone), contact flash logic untouched. `sector_edges.gd`: iterates the 4 cardinal directions but only draws a label when `direction in world.arena.exits`, anchored at `membrane_anchor(direction)`. `combat_canvas.gd`: fixed `custom_aabb` widened to `AABB((-400,-800,-1),(2600,2800,2))` (arena centre (896,560) radius 800 plus the black-hole `special_radius` reach of 171 and slack on every side). `main.gd`: 7x `GameTuning.ARENA_SIZE*0.5` → `GameTuning.ARENA_CENTER`. `game_tuning.gd`: `ARENA_SIZE` removed (grepped, no remaining rectangle consumer), `ARENA_CENTER`/`ARENA_RADIUS` added, `ARENA_MARGIN` (already declared, previously unused) now consumed by `arena_backdrop.gd`'s dead-zone clip. `bot_pilot.gd` needed NO change: it steers off `arena.bounds.size*0.5`/`get_center()`, both still correct on the new computed `bounds` |
| Rim hit accuracy | Ray from centre to a point 3×radius away lands within 0.01 px of `radius` (`tests/arena_test.gd`, exact — measured 0.0000 in practice since the geometry is closed-form) |
| 1000-bounce containment | A ricocheting bullet (`vel.bounce(normal)` each hit, matching `combat_world.gd`'s own ricochet code) never exceeds `radius+0.5` px over 1000 bounces |
| Playable area | Old rectangle 1792×1120 = 2,007,040 px²; new circle π·800² = 2,010,619 px²; ratio 1.0018 (printed by `arena_test.gd`) |
| Benchmark (`tests/combat_benchmark.gd --assert`) | Before (P0 baseline, v0.2 rounded-rect arena, 20-step bisection): 2000 bullets mean 5.9–6.9 ms, p95 7.0–9.3 ms. After (circular arena, analytic `boundary_hit`): mean 5.656 ms, p95 7.893 ms, max 9.114 ms, pool rejected 0 — inside budgets (9.0/12.0 ms) with the same headroom as before; the analytic hit test did not regress the benchmark |
| `tools\gates.ps1 -GPU -Exports` | 8/8 ok in 60.8s: harness self-test ok=1, suite 22/22 ok=1, benchmark budgets ok=1, both NEGATIVE benchmark controls ok=1 (4/4 timing lines, 2/2 fill lines), both Windows exports built and verified (2/2 packages) |
| `test.ps1 -GPU` | 22/22 pass (17 headless + 5 GPU): new `arena_test` (21 checks, 4 negative controls), new `arena_render_test` (0 failures, 2/2 controls), `combat_tests` 137 checks (was 138 — the rectangle-specific "1.4 viewport dimensions" line has no circular equivalent and was retired outright, see below), all others unchanged in count |
| GPU rendering (`tests/arena_render_test.gd`) | Real Vulkan capture, `get_image()` on this viewport returns LINEAR colour (measured: nominal sRGB fill `#050507` reads back as channel-sum ≈0.0052, not the naive sRGB sum ≈0.066), so every brightness check is relative to a measured background sample, never an absolute constant picked by hand. Measured: background 0.0052, open membrane 0.8575, sealed wall 0.1237 (membrane >6× the sealed wall), dead zone (max pixel beyond radius+margin+10) 0.0052 — indistinguishable from background, i.e. no trace pixels leaked past the rim. With the dead-zone clip forced off (test-only `ArenaBackdrop.dead_zone_clip_enabled` flag): 0.0208, 4× the clipped baseline, confirming the instrument can see the pre-fix behaviour |
| Golden trace | Re-recorded (spec: node geometry changes every wall interaction, this is expected). First difference before → after: `origin_flown.bullets` expected `6.0` got `5.0` (the player's flight path and rim distance changed with the new radius, altering how many of the continuously-fired shots are in flight at that exact sampled tick). Checked before re-recording: `new_game` step light still 40.0, tier 1 (unchanged); `entered_1_0` enemy count still 4 (same population spawns); godot run reported `engine_errors=0`; the reversed-command negative control still fails the trace as expected. Later steps also move (e.g. `fought_as_t2` keeps a tier-2 hull instead of regressing — the changed enemy-spawn geometry changed how much damage the fight took), which is the same expected geometry ripple, not treated as a second issue |
| Rendered frame (captured, looked at) | One-off capture of real `main.gd` play (not a checked-in test): the node rim renders as a visibly curved arc (distinguishable from the old rounded-rectangle's mostly-straight edges), the open membrane toward the next node reads as a brighter blue-white arc than the rest of the wall, there is clearly empty dead space beyond the wall before the screen edge, and `combat.bullets.count()` was nonzero (28) with no engine errors while player and enemy ships rendered normally after crossing into a second node |
| Not verified by measurement (stated plainly) | Human "does the circle actually feel bigger/smaller to fly in" is not measured (out of scope until the P7 stop). The MultiMesh AABB fix is sized generously by calculation, not fuzzed against every possible bullet special-radius combination |

Retired: `tests/combat_tests.gd` "Arena is 1.4 viewport dimensions" (rectangle `bounds.size` has no circular equivalent — the playable-area comparison moved to `arena_test.gd`'s dedicated measurement), "Rounded corner excludes rectangular corner" → "Circular rim excludes a point just past the radius", "Corner clamp is inside wall" → "Clamp of a far point lands inside the wall", the four `exit_direction`/`entry_position` checks rewritten in polar terms (`arena.center+Vector2.from_angle(...)`/`arena.center-Vector2(radius-44,0)` instead of literal rectangle corners), "Slowed ships can traverse openings…" rewritten to enter via `arena.center-Vector2(radius-4,0)` and check `pos.x<center.x-radius` instead of the rectangle-specific `pos.x<0`. `tests/campaign_playthrough_test.gd`'s inline bot pilot: `GameTuning.ARENA_SIZE*0.5`/`GameTuning.ARENA_SIZE*0.5-Vector2.ONE*100.0` → `GameTuning.ARENA_CENTER`/`GameTuning.ARENA_RADIUS-100.0`. No change was needed to `tests/ui_flow_test.gd` (its `bounds.end`/`bounds.get_center()` usage stayed correct against the new computed square `bounds`) or `tests/support/bot_pilot.gd` (same reason).

## Review — P4b (archetype behaviour, human-like limits, bosses)

Note: no `## Review — P4a` section exists above (P4a's own numbers were folded into the "This project" entry in `tasks/lessons.md` instead); this section covers P4b only, per-circle HP/detachment/debris/reward-split already having landed in P4a.

| What | Measured |
|---|---|
| `scripts/combat/combat_ai.gd` | New file: `CombatAI.update(world,actor,dt)` dispatches on `archetype_of(actor)` (`hull_id` prefix, or `rival==true` -> "boss"). Drone/chain: `_update_regular` (flat 0.3 s movement cadence, full current-position aim, no error — spec "fixed patterns"). Sentry: `_update_sentry` (`speed=0` always, continuous full-information tracking, fires through the existing `laser_prong`/`_queue_attack` telegraph). Radial/irregular/boss: `_update_decision_driven` (`REACTION_MIN/MAX=0.15/0.30` s decision cadence IS the reaction delay — `_decide` stores the target's position/velocity captured at decision *k-1* as `_delayed_pos/vel`, used at decision *k*; retreat when `_should_retreat` — alive weapon circles from `gun_indices`/`gun_total` fall below `RETREAT_LIMB_FRACTION=0.5` of the count authored at spawn; `_protect_bias` turns the ship up to `PROTECT_BIAS_MAX_RAD` (~26°) toward whichever authored side (`rig.rest[i].x` sign) has more surviving circles). Per-gun aim error is resampled once per decision in `combat_world.gd::_update_guns`'s `new_decision` branch: `CombatAI.sample_aim_error(_rng)`, stored per-circle in `actor.part_aim_error`. `world.ai_reaction_disabled`/`ai_aim_error_disabled` are test-only negative-control flags (never touched by gameplay code). |
| Reaction lag (measured in ticks) | Tick-exact: `_decide` stamps `actor._decided_tick`/`_delayed_tick` with the sim tick the observation was captured at; `now_tick-_delayed_tick` read directly. Measured 228.5 ms (13.7 ticks) — inside the 150–300 ms band. Control (`ai_reaction_disabled=true`, which also collapses the decision cadence to every tick): 0.0 ms |
| Aim error distribution | 500 draws of `CombatAI.sample_aim_error`: min/max stayed inside [2°,5°], 500/500 distinct values at 0.01° resolution (resampled, not fixed). In real gameplay an elite's single gun showed >1 distinct applied-error value across 300 ticks (multiple decisions). Control (`ai_aim_error_disabled=true`): every applied error forced to exactly 0 across 120 ticks/every gun |
| Strafing hit rate | 0.353 with both limits on (band: strictly between 0.05 and 0.6). Control (`ai_reaction_disabled=true` AND `ai_aim_error_disabled=true`, elite at 150 px, player strafing at low amplitude): 0.681, above 0.6 — proves the limits, not perfect aim, are what suppresses the hit rate |
| Sentry | Never moves (`Vector2(sentry.pos).distance_to(start_pos) < 0.01` over 6 s) while a drone control moved > 1 px in 2 s. Telegraph observed with `warn=0.8` s (>= the 0.5 s spec floor) before landing |
| Retreat | An elite with fewer than half its spawn-time gun count (`gun_total`) alive gained 336.6 px of distance from the player over 4 s; a full-health elite orbiting at the same range gained only 15.2 px (orbit-turn drift, not retreat) — control: the full-health gain is required to stay under half the retreating elite's gain |
| Boss (spec §14 shielded core / multiple cores) | Core takes 0 damage while any `shield_generator` circle lives (single choke point `_boss_shield_active`, checked at the top of `_damage_actor`'s enemy branch); damage resumes once every generator is destroyed. Core hp can reach and stay at 0 while a `sub_core` circle is still alive/attached (`actor.dead` stays false — gated by `_boss_can_die`, re-checked both on the qualifying core hit and the moment the last sub_core dies via `_damage_part`); the boss dies once the core AND every sub_core are dead. Control: an identical boss with the generator already destroyed takes core damage immediately. `boss_defeated(level_id)` now emits alongside the existing `rival_defeated(core_id)` (tagged `V02-ADAPTER`) on every rival/boss kill. No boss health bar exists in the HUD to remove — the only per-enemy HP readout found (`health_readout` passive, `combat_world.gd` `_draw`/`draw_projectiles`) is a general player-unlockable numeric readout for any enemy, not a boss-specific bar, and was left alone |
| Boss capture (looked at, `--show-combat-boss`) | T1 fire boss: a pale ring (`fff3b0`, drawn at `footprint*0.62`) is clearly visible around the whole hull while the shield generator lives, with the small olive `shield_generator` circle visible at the core's base and small red-rimmed `turret_ring` circles and red dashed mine-layer telegraphs around it. After scripted destruction of the generator and both sub-cores (same capture flag, forced via `_damage_part` before the auto-capture at tick 90): the ring and the generator circle are both gone, core dark-red and exposed. Limbs coming off is otherwise the same P4a debris mechanism, unit-tested separately (`enemy_ai_test.gd`'s chain-severing check, `enemy_parts_test.gd`) |
| Chain severing | Damaging `tail_2` on `enemy_chain_fire_t3` detaches exactly one debris record covering the rest of the tail (`tail_2..tail_4`, `subtree_size=3`) |
| Determinism | Same seed (42) produces a byte-identical 600-tick trace (positions/bullets/debris sampled every 30 ticks) across two fresh runs. Control: re-randomizing `_rng` mid-run (simulating a wall-clock-derived decision) produces a different trace |
| Play census (60 simulated s, one representative hull per archetype) | drone (fire) fired, sentry (lightning) fired, chain (fire) fired, radial elite (fire) fired, irregular elite (fire) fired, boss (fire) fired; droid_bay (corruption drone) produced drones; egg burst produced homing bullets on demand; deployment_ramp spawned a new enemy on demand; turret_ring produced a bullet/telegraph on demand. Control (`ai_firing_disabled=true`, gates `_fire_primary`/`_use_secondary`/`_update_guns`/the egg reactive branch): every one of the 10 counts is exactly 0 |
| Enemy-only components: what was faked/unmounted, and the fix | `egg`, `deployment_ramp` and `turret_ring` were never mounted on ANY roster hull (`ELITE_WEAPON_ROTATION` in `ship_generator.gd` listed them but nothing ever read that constant — dead code, left in place and now flagged in a comment rather than silently misleading). `turret_ring`'s own `_activate_component` case additionally faked the whole component as one instantaneous 6-direction spread computed from `actor.age`, not real geometry. Fix: `build_boss` (`ship_generator.gd`) now authors 6 real orbiting weapon circles (`turret_ring_0..5`, each its own `GroupDefinition` orbit, each with independent per-circle HP through the existing P4a machinery) plus real `deployment_ramp` and `egg` mounts, as bonus mounts outside `secondaries` (so the loadout-slot invariants `ship_roster_test.gd` checks are untouched). The old `turret_ring` ability case in `_activate_component` is now dead code (no circle carries that `ability_id` any more) — left in place rather than deleted, since retiring an `AbilityCatalog` entry outright was judged out of scope for this step. `droid_bay` was already real (corruption regular enemies) and unaffected |
| `ai` benchmark section (2000 bullets, `combat_benchmark.gd`) | Before (task prompt's own baseline): 1.54 ms of 8.64 ms total. After: 1.252 ms of 6.741 ms total — no regression (per-gun aim/error is now resampled once per ~225 ms decision instead of every tick, which is cheaper, not more expensive, than the old always-refresh code) |
| `tools\gates.ps1 -GPU -Exports` | 8/8 ok in 76.0 s: harness self-test, 24/24 suite (20 headless + 4 GPU, including the new `enemy_ai_test`), benchmark budgets (2000 bullets mean 6.741 ms / p95 9.819 ms, both inside the 9.0/12.0 ms budgets with headroom), both NEGATIVE benchmark controls, both Windows exports built and verified (2/2 packages) |
| Golden trace | Re-recorded. Checked first per the plan's own rule: at the `new_game` step (before any AI runs) mode/overlay/sector/hull/tier/light(40)/enemies/bullets/offers/profile all matched the old recording exactly; only the raw `snapshot` digest moved, because `_configure_parts` now draws one extra `_rng` sample per circle (`part_aim_error`, needed for every ship including the player's own single core circle) — a legitimate RNG-stream shift from new instrumentation, not a gameplay bug. No engine errors. Re-recorded, new final digest `59dd9ece473e3cac` |
| `tests/campaign_playthrough_test.gd` fix | `_test_core_escape`'s single 1,000,000-damage `_damage_actor` call on the rival no longer kills it outright now that a boss can be shielded/multi-cored — updated to destroy the shield generator and every sub-core first (mirroring real play), then the qualifying hit. `debug_clear()` (`combat_world.gd`) also now zeroes `shield_generator_indices`/`sub_core_indices`, not just `gun_indices`, so a debug full-clear (used by `_test_campaign_route`) still actually kills a boss |
| Not completed / stated plainly | `egg`/`deployment_ramp` were only added to the BOSS archetype, not to elites/regulars, given the time budget — the spec does not name which archetype must carry each component, and bosses ("all of the above layered") are the least risky place to add new mounted circles without touching the already-locked elite/regular roster invariants (`ship_roster_test.gd`'s 825 checks). The editor's elite/boss preview (per-circle HP, what detaches) is still P4's own unchecked line and was not touched this step. `_add_enemy_body_feature` (void `bullet_eater`/`void_pull`, plasma `projectile_orbit`) is authored on regular/elite hulls but never on bosses — found while reading `ship_generator.gd`, not fixed (out of scope: not part of P4b's brief, and touching `build_boss` further risked the TP/circle-count margins already spent on the new mounts) |

## Retired assertions

| Phase | Assertion | Why it no longer applies | Replacement |
|---|---|---|---|
| P2a-1 | `ships_validation.gd` "Ellipse restricted to corruption" | An ellipse is not representable at all under two primitives | "Ellipse is never legal", plus new rejections of ring / tether / crescent / arc |
| P2a-1 | `ship_catalog.gd` "circular geometry must have equal dimensions" | A circle carries one `radius`; unequal dimensions cannot be expressed | — (the rule became unstateable) |
| P3 | `combat_tests.gd` "Arena is 1.4 viewport dimensions" | A circle has no rectangle `.size` to compare; the same measurement (playable area vs the old rectangle) now lives in `tests/arena_test.gd`'s dedicated area check with its own negative control | `arena_test.gd` "Playable area is within a few percent of the old 1792x1120 rectangle" |
| P2a-2 | `ships_mesh_test.gd` per-LINE "has an animated perimeter" (1111 checks) | Lines left the 128 uniform slots, so a line has no `part_indices` entry to carry a perimeter. Checks fell 5416 → 4305, which is exactly the 1111 lines | Each line's authored period/phase is now asserted in its per-vertex `CUSTOM0` data instead; circles keep both original checks |
| P5a | `world_rules_test.gd` `_test_world`/`_test_progression`: wedges (`_initial_element`/`_region_elements`), five cores at radii 8/14/20/26/32 (`core_coordinate`, `CORE_DISTANCES`), waypoints at distance 6/12 (`checkpoints`, `can_teleport`), region-entry unlock, infinite-map `in_bounds`, "Reboot preserves seed" phrased around `current_sector`/waypoints, `START_ELEMENTS` as the live three-element start | v0.3 replaces the whole world model (spec §11: Chebyshev rings, bounded discs, one boss per level; §8: Lightning-only start, absorb-to-unlock) | New `_test_world`/`_test_progression` in the same file: Chebyshev `ring()`, `in_bounds` as a radius-6 disc for L1, `unlock_element`, `on_death` epoch semantics, `complete_level` idempotency, legacy (schema<4) migration resetting unlocks to Lightning. Full coverage moved to `tests/world_generation_test.gd` (200 seeds × 5 levels) and `tests/unlock_offers_test.gd` |
| P5a | `campaign_playthrough_test.gd`: `_test_campaign_route`/`_test_core_escape` walking to `core_coordinate(element)` for five hard-coded elements, asserting `defeated_leaders` | No core objectives or `core_coordinate` exist; a level has one boss on its perimeter, found by BFS through real (possibly sealed) membranes | Rewritten as a BFS bot (`_bfs_path`) that reaches `campaign.boss_coord()`, beats it via `debug_clear()`, and checks `complete_level()`'s `level_completed`/`revealed_element` against the spec §8 reveal table; `_test_full_campaign` walks all five levels in order |
| P5a | `combat_tests.gd` "Same-life node return never respawns or replenishes" | v0.3 removes the permanent per-node `cleared` flag for regular nodes (spec §7: a node is a losing strategy to camp, not a one-time clear) | "Leaving and returning within one epoch restores the exact state left behind" (same underlying `sector_cache`/`encounter_records` cache as before, now exercised through the new `enemy_hulls` descriptor key instead of `enemy_count`) |
| P5a | `combat_tests.gd`/`enemy_parts_test.gd` raw sector dicts keyed on `enemy_count`/`elite_count`/`core_defeated`/`kind:"core"` | `combat_world.start_sector` now spawns exactly the hulls the descriptor names (`enemy_hulls`/`elite_hulls`/`boss_hull`), never a count resolved through a runtime picker | Fixtures now build hull ids directly via `ShipGenerator.hull_id(faction,kind,element,tier)` |
| P5a | `ship_roster_test.gd`/`ship_catalog.gd`: `ShipCatalog.pick_enemy`, `ShipCatalog.trim_to_tier` (`V02-ADAPTER`) | Deleted outright per the P5a brief; the world descriptor now names hulls directly instead of a runtime nearest-tier picker | `ShipGenerator.hull_id(faction,kind,element,tier)` (deterministic band clamp, no search) and `ShipCatalog.cap_to_tier` (same slot-cap behaviour, renamed and no longer tagged as a legacy shim) |
