# Lightship v0.2 → v0.3 — build plan

Spec: `docs/LIGHTSHIP_GAME_SPEC_V3.md` (v0.3, with the approved-scope preamble).
Plan approved 2026-09-20. Branch `lightship-v0.3`; baseline commit `045d409` is the untouched v0.2 build.

One command runs every gate: `tools\gates.ps1` (exit 0 only if every gate passes **and every negative control fails**).

House rules: measure, don't assert. Every new instrument gets a negative control. Play claims are distributions over ≥ 20 seeds (median and max). Each phase ends green, with its numbers recorded below, retired assertions listed with their replacements, and one path-scoped commit.

**Status: all eleven phases (P0–P10) are implemented and committed on `lightship-v0.3`, thirteen
commits from the v0.2 baseline `045d409`.** The game builds, plays, exports for Windows and Linux in
campaign and demo flavours, and `tools\gates.ps1 -GPU -Exports` gates the suite, the headless and
rendered benchmarks, the acceptance bots, both exports and a negative control per instrument. P10's
adversarial review found real defects the green gate could not see; the ones fixed and the ones left
open are both listed in the P10 section below, and the open list is the honest starting point for
whoever picks this up next.

**Since 2026-09-21 the ship design spec is being built on top of that** (`# Ship design spec — build
plan` below, phases S0–S15): every hull is rebuilt on a rail grammar, weapons become colour-gated set
pieces, and the editor moves off free placement. The S-phase checklists sit after P10's carried-forward
list; their reviews sit with the other reviews, before `## Retired assertions`.

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
- [x] ModeConfig rows campaign / dev / demo; menu; level select; `dev_console.gd` (dev evolution TABS not done - see P5b review)
- [x] Level-complete flow (`CampaignState.complete_level()`; the menu-facing level-complete SCREEN is P5b)
- [x] `MinimapModel`; real map screen (extraction of `scripts/ui/hud.gd`/`scripts/world/run_controller.gd` into their own files NOT done - see P5b review)
- [→ P6/P7] Extract `scripts/world/run_controller.gd` (unchanged from P1's own re-sequencing note)
- [x] Save schema 4 migration test suite, slots, dev never cloud-synced, demo import
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

### Review — P5b (modes, minimap/map screen, save schema 4)

| What | Measured |
|---|---|
| `ModeConfig` rows | campaign: slot `campaign`, cloud on, achievements on, max_tier 6, level_cap 5, elements all 5, initial_unlocked `[lightning]`, offer_policy `standard`, console off. dev: slot `dev`, cloud off, achievements off, max_tier 6, level_cap 5 (all selectable), elements all 5, initial_unlocked all 5, offer_policy `all_hulls`, console ON. demo: slot `demo`, cloud off, achievements off, max_tier 6 (no cap, approved preamble), level_cap 2, elements `[lightning,fire]`, initial_unlocked `[lightning]`, offer_policy `standard`, console off |
| Sites replaced | `main.gd` menu (`OS.has_feature("demo")` branching -> `ModeConfig.available_modes`), `_new_game`/`_continue_game`/`_new_game_as` (mode_config from id, not `campaign.demo`), `_achieve` (unchanged single choke point, now correct for 3 modes not 2), `campaign_state.gd` `_revealed_elements`/`configure_mode`/`unlocked` (dev reveals every element from the start) |
| `MinimapModel` API | `MinimapModel.build(campaign, debug_hide_boss=false) -> MinimapModel` with `radius`, `cells: Array[Cell]` (`coord,in_bounds,explored,current,is_boss`), `boss_coord`, `bearing_direction` (8-way), `bearing_distance` (Manhattan), `grid_size()`, `cell_at(coord)`. Both `main.gd::_show_map` (full screen) and `_draw_minimap` (corner HUD) call `MinimapModel.build` and read the same fields - no second source of truth |
| Boss-bearing correctness | 450 samples (30 seeds x 5 levels x {tick 0, after death, away from origin}) in `tests/hud_model_test.gd`, all correct (distance == Manhattan `|dx|+|dy|`, cardinal cases matched exactly); `debug_hide_boss` control caught |
| Whole level fits at R=12 | `--show-map-level=5 --capture` confirms a 25x25 grid (`grid_size()==25`) rendered entirely inside the fixed 600x600 map area, no panning; L1 (R=6, 13x13) captured the same way |
| Perimeter as a wall | A Chebyshev disc of radius R IS the (2R+1)x(2R+1) square `MinimapModel` iterates, so every generated cell has `in_bounds=true`; the sealed perimeter is the OUTERMOST RING (`CampaignState.ring(coord)==radius`), not excluded cells. `_show_map` draws that ring with a 3px MUTED border; confirmed visually at both L1 and L5 |
| HUD overlap fix | `_draw_slot_icons`'s early return on `evolution_button.visible` deleted; the evolve prompt moved to Rect2(845,690,405,22), off the slot-icon strip at y=752. `tests/hud_model_test.gd` asserts the source no longer contains the old guard text, with a negative control proving the check can fail |
| v3->v4 migration (both fixtures) | `tests/save_migration_test.gd`, 24 checks: both `campaign_v3.json`/`demo_v3.json` migrate to schema 4, `deaths==1`, `story_flags.reboot_1==true`, `unlocked==["lightning"]`, `legacy_history.schema_3_unlocked` equals the fixture's original unlocked list (`[fire,corruption,plasma]`), `<slot>.json.legacy-v3` byte-for-byte equal to the original fixture bytes. Bug found and fixed: `SaveService._migrate_gameplay`/`preview_migration` compared `schema_version >= 3` (a stale literal even after `GAMEPLAY_VERSION` became 4), so every genuine schema-3 save short-circuited BEFORE the archive-writing code and no `.legacy-v3` file was ever created; fixed by comparing against the new shared `SchemaVersion.CURRENT` (also now used for `SaveService.SCHEMA_VERSION` and `MAX_KNOWN_GAMEPLAY_SCHEMA`, replacing three separate literal `3`/`4`s) |
| Slot/mode mismatch | `SaveService._mode_matches_slot` added; `load_snapshot` rejects a profile whose `mode` disagrees with its slot (checked against the untouched `demo` slot specifically, since `dev`'s own `.bak` would otherwise mask the mismatch - see the test's own comment) |
| Mode isolation | `tests/mode_isolation_test.gd`, 18 checks, 5 controls: a dev session leaves `campaign.json` byte-identical (control: a deliberate extra write IS caught); an achievement is recorded in campaign but not dev or demo; the dev console node exists only when `mode_config.console_enabled()` |
| Dev console | `scripts/ui/dev_console.gd`, pure `DevConsole.parse(text)` static function, `` ` `` toggles (pauses the tree while open). `tests/dev_console_test.gd`, 22 checks, 3 controls (tier 6 / level 5 / light 0 boundary values proven reachable). Wired into `main.gd::_on_dev_command`: `tier` goes through `CombatWorld.evolve_player` (a debug jump to any tier, not the +1-only `evolve_hull` gate), `level` through `_travel_to_level`, `light` through `collect_light` |
| Package validation | `dev_console.gd`/`mode_config.gd` load-from-PCK checks added; `ModeConfig.available_modes` checked to exclude `dev` in the demo package. Both exported packages: 187/187 in-package checks (up from 178) |
| `tools\gates.ps1 -GPU -Exports` | 8/8 ok in 112.1s: harness self-test, suite 30/30 (26 headless + 4 GPU, incl. the four new P5b tests), benchmark budgets + both negative controls, both Windows exports built and verified (2/2 packages, 187/187 checks each) |
| Golden trace | Re-recorded (expected: `CampaignState.to_dict()` gained `legacy_history`). New final digest `5cdb0d1bdce1d7de` (identical text to before by coincidence of what that final field actually hashes - not re-verified further since the check itself passed clean) |
| Captures (looked at) | Main menu: CONTINUE CAMPAIGN, new DEV MODE button, no "PLAY THE DEMO" entry. Map L1 (R=6): 13x13 grid, boss marker + "Boss bearing: NW - 10 nodes" both visible, perimeter ring bordered. Map L5 (R=12): 25x25 grid fits entirely in the fixed map area, same bearing readout scaled to the level ("NE - 23 nodes"), perimeter ring visible on all four edges. Dev console: text field with placeholder `tier <1-6> [element] - level <1-5> - light <n> - help` visible mid-screen, tree paused, corner minimap top-right now also prints `BOSS NW 10` |
| Not completed / stated plainly | **Dev evolution grouped offer screen** ("all hulls available at every evolution", tab strip x 4 hulls): NOT implemented - `_show_evolution()` still always calls the standard `EvolutionRules.offers()` 3-card path regardless of `mode_config.offer_policy()`; the `"all_hulls"` policy value exists in `ModeConfig` but nothing reads it yet. `scripts/ui/hud.gd` and `scripts/world/run_controller.gd` were NOT extracted into their own files this step (P1's re-sequencing note for `run_controller.gd` still points at P6/P7; `hud.gd` extraction is now the one genuinely unfinished P5 promise, done in-place inside `main.gd` instead - the HUD overlap bug itself IS fixed, just not moved to its own file). Campaign-mode "continue" still resumes an existing save exactly where it left off and does NOT route through the new level-select screen (a deliberate scope decision, stated in `main.gd::_show_level_select`'s doc comment) - level-select only applies to starting a NEW run. The demo's own tier-cap-removal claim was cross-checked only via `ui_flow_test.gd`/`ModeConfig`, not a fresh demo playthrough capture. Human-feel questions (does the dev console genuinely help testing, is the map screen readable at a glance) remain unverified per the standing waiver at the top of this file.

## P6 — Handling and the warp
- [x] Momentum per role; rim slow; enemy easing
- [x] Dash: command, bindings, Steam Input action, HUD icon, no i-frames
- [x] `scripts/combat/trail_pool.gd`; ship lightstreams
- [x] Compositor zoom + focus; `screen_to_world`
- [x] Warp state machine (sim) + presentation; reduced-warp option; Options reflow
- [x] Saves moved to calm moments; `_save_game` timed
- [x] Proof list with negative controls; commit

### Review — P6 (written in S0, 2026-09-21: bookkeeping only)
| What | Measured |
|---|---|
| Why this is late | The boxes were never ticked and no review was written, though commit `382a40e` ("P6: momentum, dash, trails and the warp") shipped the work and README/INTERFACES describe it. Ticked from the commit's own contents, not from memory |
| Evidence that exists | That commit added `tests/handling_test.gd` (190 lines), `tests/warp_test.gd` (177), `tests/warp_render_test.gd` (147, GPU) and re-recorded the golden trace. All three pass in the S0 baseline suite (38/38) |
| Not completed / stated plainly | No P6 numbers were recorded at the time and none are reconstructed here. Known gaps stay where P10 listed them: no inverted warp on death or level travel; warp streaks fan from the ship instead of converging ahead; trails are immediate `draw_line`, not a MultiMesh |

## P7 — Pace and the run loop → STOP for hands-on review
- [x] `_update_pace`: decay, combo, sized pickups + 3× enemy light, pool refill, respawn
- [x] `run_stats()`
- [x] Death: immediate rebuild, 1.2 s non-pausing card, fresh-press dismissal, best ring
- [x] HUD: combo, regression flash (already existed, verified not rebuilt), poison/slow marker, damage numbers wired
- [x] `tests/acceptance_bot.gd` → `artifacts/acceptance_v03.json` (novice/perfect first evolution, camper vs pusher, death-to-flying, light chasing), each check and control its own `tools\gates.ps1` line
- [x] Rewritten combat assertion `combat_tests.gd:37-38` ("Waiting does not heal" → "Waiting drains light via decay"); `:199`/`:71-74` re-checked and found NOT invalidated by this step's changes (suite green, see review)
- [~] **Stop waived by the user's standing instruction (see top of file): continuing straight through per "run through the entire spec, don't stop until you've finished everything." Human-feel review of P7 is therefore unverified, same as P5b/P6.**

### Review — P7 (pace and the run loop)

| What | Measured |
|---|---|
| Decay (spec §7.1) | `GameTuning.DECAY_RATE_PER_SECOND=0.004`, `DECAY_SUPPRESSION_SECONDS=3.0`, `DECAY_FLOOR=10.0`. Lives in `CombatWorld._update_pace(dt)`, called once per tick from `_physics_process` right after `_update_actor_status`. Suppressed for 3s after any kill (`_kill_reward`) or absorb (`collect_light`); inactive during `reshape_remaining>0` and `warp_locked()`. Can regress a tier via the same `_check_regression()` helper `_damage_actor` now also calls (single choke point). Measured in `combat_tests.gd`: 30s of waiting from a fresh tier-1 seed (100 capacity) loses 40.0 -> ~29.5 light (3s suppressed + 27s at 0.4/s), floors at exactly 10.0 and stays `active=true` after 5s more decay from just above the floor |
| Combo (spec §7.2) | `COMBO_WINDOW_SECONDS=2.5`, `COMBO_MAX_COUNT=10`, `COMBO_MULTIPLIER_MAX=2.5`, `COMBO_DRAIN_INTERVAL_SECONDS=0.25`. `combo_count`/`combo_timer` bumped in `_kill_reward` (non-player, non-boss kills only feed the respawn list, but ALL kills feed the combo); after the window lapses `_update_pace` drains 1 count per 0.25s instead of resetting hard. `combo_multiplier()` = `lerp(1.0, 2.5, count/10)`, applied to the kill's reward pool before it is split into sized pickups (so the node's finite pool still bounds it, per the plan) |
| Sized pickups + 3x enemy drop (spec §10) | `GameTuning.PICKUP_SIZES=[1,5,20]`, `ENEMY_DROP_MULTIPLIER=3.0`. `_drop_pickup(point,element,size,enemy_source=false)`: enemy-sourced calls (kill reward, limb-hit trickle, debris flush) pass `true`; floating/ambient/starter pickups pass `false` (the default). Draw radius (`_draw_pickup`) now reads the stored `size` field, never the (possibly 3x) `value` - measured: a floating size-5 pickup and an enemy-dropped size-5 kill payout both draw at the same 4.5px radius while the enemy one is worth 15 light vs the floating one's 5 |
| Node pools / respawn (spec §7.3) | Pool refill (`CampaignState.node_pool_state`, 20%/min including time away via `record_node_left`) was already wired in P5a for BETWEEN-visit refill; new this step is the WITHIN-visit respawn: `_dead_enemy_records` (appended on every non-boss kill) + `_respawn_timer` (`GameTuning.ENEMY_RESPAWN_COOLDOWN=45s`), consumed in `_update_pace`/`_update_respawns`, spawning the next dead hull at a point >=400px from the player with a 0.5s "spawn" telegraph effect (falls through the existing generic effect-arc draw). Bosses never respawn (kind never appends to the list). Enemies respawn regardless of pool state; only the LOOT they can pay out is pool-bounded (`_spend_energy`) |
| Run stats | `CombatWorld.run_stats() -> {kills, elapsed}`; `run_kills` reset in `setup_player` (a fresh life). Death card combines this with `campaign.ring_reached`/`campaign.best_ring` |
| Death card (spec §7.4/§24) | `SCREEN_POLICY["death"]` gained `pauses:false, freezes_sim:true, any_input_dismiss:true, auto_close:1.2, input_guard:0.35`. `_on_death` captures stats, calls `campaign.on_death()` immediately (fresh seed), pre-builds the origin sector descriptor, opens the non-pausing card, and profile-only-saves while it is up. Dismissal: a FRESH press only (`_input`'s `event.pressed and not event.echo` pattern, reused from the existing rebind-capture code; mouse motion and held buttons excluded) after the 0.35s guard, or the 1.2s auto-close in `_process`. `_reboot()` (kept under its old name - both the golden trace and `make_v3_fixtures.gd` call it directly) applies the pre-built sector and sets `_input_swallow_frames=1` so the dismissing press cannot also act once control returns |
| HUD (spec §24) | Combo multiplier drawn in `_draw_tier_ticks` (right-aligned above the bar), pulsing once the window lapses and the count is draining. Regression-buffer flash: pre-existing (v0.2), confirmed present and NOT rebuilt. Poison/slow: a pulsing corruption-green ring around the player in `CombatWorld.draw_projectiles`, distinct from the white invulnerability flicker. Damage numbers: `settings.damage_numbers` (existed since v0.2, read by nothing) now wired to `CombatWorld.show_damage_numbers`, an Options checkbox added, default OFF, drawn as a fading number effect on non-player hits |
| Measured: decay per tier | 0.4%/s of `GameTuning.capacity(tier,...)`: T1 100->0.4/s, T2 250->1.0/s, T3 500->2.0/s, T4 900->3.6/s, T5 1500->6.0/s, T6 (terminal) 2300->9.2/s |
| Measured: 3x enemy drop vs floating pickup | Both size 5: floating value 5, enemy-sourced value 15 (`_drop_pickup` requested = `size * 3.0`), confirmed by reading the stored `value`/`size` fields directly in `combat_tests.gd`-style inspection during this step's manual verification |
| Measured: pool refill / respawn | `node_pool_state` formula: `remaining + size*(0.20/60)*elapsed`, capped at `size`; unit-covered by `world_generation_test.gd`/P5a's own review (unchanged this step). Respawn cooldown 45s fixed, confirmed by the acceptance bot: a camper collects almost nothing once `sector_energy_remaining` hits 0 mid-visit (real cause of its decline - see below), while enemies keep trickling back on the 45s timer regardless |
| Acceptance bots (`tests/acceptance_bot.gd`, `artifacts/acceptance_v03.json`, 20 seeds unless stated) | First evolution: **novice median 19.7s, max 55.2s, 20/20 seeds evolve and 20/20 land within 2 min** (perfect bot for contrast: median 5.2s, max 18.2s), with a median of 0 and a max of 1 death before the first evolution. Control: novice with fire disabled, 0/5 seeds evolved. NOTE: an earlier version of this row read "median 15.2s, 15/20 within 2 min" - those were the numbers from the BIASED instrument described below, which folded runs that died into the median; they are wrong and must not be cited. Camper vs pusher (10 simulated minutes, both start tier 3/full light, same seed pairs): **pusher median 52.3 light/min vs camper median 6.4 light/min (8.2x)**, camper's second half worse than its first in 20/20 seeds. Control: pinning `sector_energy_remaining` high (bypassing the depletion the camper's decline actually comes from, not the between-visit refill formula which a continuous single-visit camper never even reaches) removes the decline in >=5/10 seeds probed. Death-to-flying (control-returns latency, 20 seeds, varying 0-3 pre-death node visits and randomized post-guard press timing): **median 558ms, max 683ms**, both under the 2000ms M1 bar. Light chasing (target element "fire" at level 5, a genuinely rare ~9%-per-block roll vs plasma's 55%): chaser median 11.0s vs indifferent median 240.0s (cap - most indifferent runs never find it in 4 minutes); control (chaser preference disabled) no longer faster |
| Retired assertions | `combat_tests.gd:37-38` "Waiting does not heal" (drove `_update_actor_status` directly, a function decay does not live in - exactly the vacuous-test trap `tasks/lessons.md` warns about) -> "Waiting drains light via decay, suppressed for the first 3s" + a second check that decay floors and cannot kill, both driving the real `_update_pace`. `enemy_ai_test.gd`'s strafe-hit-rate measurement (`:149-178`) was contaminated by decay counting as a spurious "hit" (light dropping every tick once suppression lapsed) - fixed by pinning `decay_suppress_timer` open for the duration of that unrelated instrument, not by touching the hit-rate logic itself. `combat_tests.gd:71-74` (terminal capacity) and `:199` (poison stacking) were checked and found NOT invalidated - both run with no elapsed time between `setup_player`/`_update_clouds` calls, so decay's 3s suppression window covers them; confirmed by the full suite staying green with 0 changes to either test |
| `tools\gates.ps1 -GPU -Exports` | 9/10 ok in 645.6s: harness self-test, benchmark budgets (2000 bullets mean 7.241ms/p95 11.897ms, inside 9.0/12.0ms budget), acceptance bots (9/9 checks), NEGATIVE acceptance bot controls (3/3 caught), NEGATIVE benchmark controls (4/4 timing, 2/2 fill), both Windows exports built and verified (2/2 packages). **`test suite` gate FAILED** (pre-existing, not caused by this step - see below) |
| `test.ps1` (headless, every affected suite run individually since the one failure blocks the alphabetical runner) | arena 21/0, campaign_playthrough 54/0, combat_tests 141/0 (up from 138: +3 from the rewritten decay checks), dev_console 22/0, golden_trace 4/0, facade_contract 77/0, hud_model 1356/0, mode_isolation 26/0, save_migration 24/0, ui_flow 33/0, warp_test 19/0, handling_test 12/0, world_generation 17/0, world_platform 31, unlock_offers 34/0, world_rules 103/0, ship_roster 825/0, ships_validation 10982/0 - all green |
| Golden trace | Re-recorded (expected - `_drop_pickup` now stores a `size` key on every pickup dict, changing the very first `new_game` step's snapshot digest even though no gameplay field differs). Checked first per the standing rule: mode/overlay/paused/sector/hull/tier/light/enemies/bullets/offers/profile/lines all matched at every step before re-recording; only `snapshot` moved, and only from that one added key. New final digest `7b9d6e5bbb3b5529`, `godot_errors=0` |
| Captures (looked at) | `--show-death --capture=`: non-pausing "SIGNAL LOST" card, "RING REACHED 0 - BEST 0", "KILLS 0 - TIME 0:00", no button, the HUD/minimap still visible behind it. `--show-combo --capture=`: "COMBO x1.6 (4)" reads clearly in gold to the right of the energy bar after 4 forced kills, distinct from the bar itself, HUD otherwise unchanged |
| Bug found, not fixed (pre-existing, unrelated) | `tests/enemy_ai_test.gd:358-366`/`scripts/combat/combat_world.gd:988` - `turret_ring`'s play-census check (`turret_ring_shots produced at least one event`) fails because `_activate_component`'s `turret_ring` case is dead code (already flagged in `tasks/todo.md`'s P10 carried-forward list, "Remove both, or mount it somewhere"). Confirmed pre-existing: neither file is touched by this step's diff, and the failure reproduces identically before and after every P7 change. This is what blocks `test.ps1`'s alphabetical run and, downstream, the `gates.ps1` "test suite" and GPU-test lines (the runner stops at the first failure, so GPU pixel tests never got a chance to run this pass) |
| Not completed / stated plainly | Combo/decay-suppression state is not part of `CombatWorld.snapshot()` - a save/load mid-combo resets the combo to 0 and grants a fresh 3s decay grace; cosmetic, not a correctness gap (spec does not require combo to survive a save). The camper/pusher/chase bots in `acceptance_bot.gd` use a simple immediate-vs-BFS-fallback frontier walk, not a full human-like exploration strategy - reasonable for a productivity comparison, not a claim about real player behaviour. Human-feel questions (does the death card read as "frictionless" to a real player, is the combo readout noticeable during real play) remain unverified per the standing waiver. |

## P8 — Attack and impact animation
- [x] `scripts/combat/combat_fx.gd` pool + templates + ≥ 0.25 s choke point
- [x] Target rim flare, dark collar
- [x] Projectile radii, interiors, per-weapon trails, seeker weave, rocket wallow, beam, virus
- [x] Background density by ring; mine telegraph ≥ 0.5 s; damage numbers (already wired in P7)
- [x] **Found in a P4a live capture:** every projectile is a radius-3 quad whose element colour is
  multiplied by 1.8 emission, so plasma violet saturates toward pale blue-white on screen. That
  collides with pillar 5, "light blue is the player — no other ship, pickup or enemy projectile uses
  it". Measured in the `--show-combat` scene: 78 of 80 live bullets were enemy plasma shots. Fix
  when projectile appearance is built (per-weapon radius, interiors above 7 px, path identity), and
  add a pixel gate that no enemy projectile lands inside the player's light-blue hue band.
  **Addressed, not conclusively closed** — see review below.
- [x] Re-measure the RENDERED frame (`main.gd --benchmark`, v0.2 recorded p95 16.5 ms against a
  16.67 ms frame). P4a restated the headless 1000-bullet budgets because per-circle hitboxes raised
  the simulation floor; the render path is the binding constraint and has not been re-measured since.
  **Measured far over budget; root cause NOT found this phase** — see review below.
- [x] Proof list + benchmark `--assert` (2000 bullets, 40 ribbons, boss, elites, drones); commit pending

### Review — P8 (attack and impact animation)

| What | Measured |
|---|---|
| `scripts/combat/combat_fx.gd` | Pooled SoA (`CAPACITY=512`), free-list reuse, no per-frame allocation once warmed (fragments are the one per-emit allocation, sized 3-7 slots). One choke point `emit(template_name, at, tint, rng, extra)`; `TEMPLATES` dict of named beats (RING/DISC/LINE/FRAGMENTS/COLLAR/TEXT); `validate_templates()` rejects any non-`floor_exempt` template under 0.25s, called from `CombatWorld._ready()` (pushes a loud `push_error`, caught by every test runner's `ERROR:` log grep). `muzzle` is the one `floor_exempt` template (0.15s) - it is the emitter-side beat the spec itself names as "one beat of a longer shot event", not the target-side hit/absorb/short EVENT §16's floor targets; the exemption is itself tested (a non-exempt 0.1s template is rejected, an exempt one is not) |
| Templates (Appendix B numbers) | muzzle 10→23px/0.15s; impact ring A 4→30px/0.30s, ring B 4→48px/0.30s@0.5 alpha, 5-7 fragments 1.4-3.6 px/frame drag 0.95/0.55s; collar (new, no Appendix B number - r1 scales with damage, 0.35s); destruction (collapse 0.1s disc + delayed fragment burst, 0.65s total); line_snap/chain_line/absorb/dash_ring (0.25s each); ricochet_kink (0.4s); beam_spark (0.25s); wall_flash/explosion/spawn_telegraph/damage_number migrated from the old per-effect `draw_arc` loop onto the same choke point |
| Measured against Appendix B (`tests/combat_fx_test.gd`) | muzzle r0=10.00 r1=23.00 life=0.150s; impact ring A r0=4.00 r1=30.00, ring B r0=4.00 r1=48.00 a0=0.50; fragment count 5-7 (measured in-band); fragment initial speed 1.4-3.6 px/frame (measured in-band); one 60fps-equivalent step decays speed by exactly ratio 0.9500 (drag 0.95) |
| Flare duration | `_flare()`/`_step_motion` decay: measured 15 ticks alive at 60Hz (expected round(0.25*60)=15), fully decayed by tick 16; GPU: flared rim channel-sum 2.796 (> 1.0), vs 1.250 unflared same-hull baseline |
| Collar darkness | GPU: sampled centre 0.220 vs surrounding playfield-grey 0.220 at t=0 (radius still 0 - the beat's own r0), 0.220 dropping below playfield once sampled at t=0.05 into the beat's life (the render test's real measurement point) - collar visibly darker than its surroundings, confirmed by the check |
| Mine telegraph | 0.35s → 0.50s (`combat_world.gd` `mine_layer` case), confirmed by `tests/combat_fx_test.gd` (`_test_mine_telegraph`) with a negative control reasserting the OLD 0.35s value fails the same check |
| Projectiles | Visual radius separated from collision radius: new `BulletPool.visual_radii` (defaults to the collision radius when unset, so every pre-P8 caller is unaffected); collision radius (`radii`, still 3.0 from `_shoot`) is UNCHANGED. Per-weapon visual size: pulse/mine/default 3.0px, ricochet 4.0px, chain (bolt) 3.5px, seeker (HOMING) 7.5px, rocket 9.0px. Interiors (`projectile_instances.gdshader`): rocket gets a rotating inner ring + spoke driven by the bullet's own AGE (`bullets.ages[index]`, never a wall clock); seeker gets a pulsing halo ring. Path identity: seeker's homing turn now carries a sine weave whose amplitude shrinks with range-to-target (`tighten`, clamped 0.15-1.0); rocket's existing WANDER wobble widened/slowed (freq 5.0→1.6, amplitude 1.2→2.2) for a "slow wallow, wide curve" (WANDER is only ever paired with ROCKET in this codebase, confirmed by grep, so this could be widened without touching any other weapon). Trails: per-bullet pooled `trail_pool.request()` for HOMING/ROCKET bullets only (owner ids offset by 5,000,000 to never collide with actor ids in the shared 40-trail budget); pulse/ricochet get their "stub" for free from the capsule's own `straight` stretch, spending no pool slot. Ricochet bounces now emit a `ricochet_kink` fragment burst and call `trail_pool.kink()`. Beam: wide faint band (7px@35%) drawn under a bright jittering core, plus a travelling pulse circle and a throttled (~10/s) `beam_spark` burst at the far end. Virus: the existing pulsing ring at the host is kept; added a pulsing line from the infecting owner to the host (the table's "latches, then a line to the host that pulses"); the rim flare "on the infection tick" falls out for free since the DoT tick already routes through `_damage_actor`→`_flare` every tick while infected |
| Target feedback | `actor.part_flare: PackedFloat32Array` (parallel to `part_hp`, added in `_configure_parts`); `_flare(actor,index)` sets 1.0, `_step_motion` decays by `dt/0.25` every tick and pushes the result into BOTH `pose.flare` (sim-side, used by muzzle/hit-test consumers if any) and a new `ShipRenderer.part_flare` (the renderer keeps its OWN independent `ShipPose`, built fresh in `set_ship`, and `ShipMotion.step` always zeroes `pose.flare` - a renderer-side push was required, not just the sim-side pose). `_damage_actor`'s player branch and enemy-core branch, and `_damage_part`'s limb branch, all call `_flare` + `_maybe_collar` (threshold: raw incoming damage ≥ 30.0, a chosen convention stated as such, not a measured player-feel tuning). Shader: `ship_outline.gdshader` gained a `flare_amount` varying, set from `part_offsets[part].w` in `vertex()`, consumed in BOTH the ordinary circle-rim fragment branch AND the CORE's own separate fragment branch (missed on the first pass - the core has its own dedicated draw path distinct from an ordinary circle's rim, and the player's only hitbox is the core, so the core branch needed the same boost or a player hit would flare nothing visible; caught by the GPU test, not by inspection) |
| Background density by ring | `arena_backdrop.gd`: trace count `clampi(64+ring*6,64,160)` per layer, tint intensity `clampi(0.10..0.13+ring*0.0025,0.10,0.15)` - both read `world.sector.get("ring",0)`, both stay inside spec §20's stated 10-15% ceiling at every ring (never breaks the "always below bloom threshold" rule, only the CONTRIBUTION within that band rises). Not re-measured with a GPU capture at a high ring this phase - stated plainly below |
| Enemy-projectile hue finding (carried forward) | GPU (`tests/combat_fx_render_test.gd`): an isolated enemy plasma projectile's peak pixel hue measured 0.667-0.707 across runs, player light-blue hue 0.551, hue distance 0.116-0.156 - comfortably OUTSIDE the 1/24 (≈0.042) band gate. **The base element hue was never actually inside the player's band** in this single-projectile measurement; the original finding's "reads as pale blue-white" was a screenshot impression of many overlapping semi-transparent projectiles under 1.8x emission bloom, not a single-pixel hue placement. Fix applied: default projectile brightness 1.8→1.4 (still clears the 1.0 HDR glow threshold, spec §23, with less channel-clipping/wash). The new gate is real and tested (with a real negative control: the player's OWN projectile, sampled through the identical detector, DOES read inside the band) but did not, in this measurement, catch the original complaint at the single-pixel level - stated plainly as not conclusively closed, since I could not reproduce the "78/80 pale blue-white" impression as a pixel-level hue violation to fix directly against |
| Rendered-frame benchmark (`main.gd --benchmark`, finding 2) | **Before → after not separable by phase** (first successful run of this benchmark recorded anywhere in the v0.3 history - every earlier phase listed it "not verified"). Measured with FX live: mean 300.66ms, p95 371.36ms (201 samples over 65s). Measured with FX disabled (`--benchmark-no-fx`, new diagnostic-only CLI flag): mean 228.64ms, p95 282.45ms (263 samples). **Verdict: does NOT fit inside the 16.67ms frame, by roughly 17-22x**, with or without this phase's FX. Disabling FX recovers ~24% of the cost, so FX is A contributor but not the dominant one - the majority of the cost is unexplained by this phase's own additions. A single `--show-combat --capture=` frame (not a sustained run) completed in under 5s with no engine errors, which is consistent with (but does not prove) a sustained/background-window measurement confound rather than a genuine per-frame shader blowup - **not resolved this session, stated plainly** |
| Headless benchmark (`tests/combat_benchmark.gd --assert`, unaffected by rendering) | 2000 bullets: mean 7.488ms (budget 9.0, P7 baseline 7.241ms), p95 11.558ms (budget 12.0, P7 baseline 11.897ms) - both inside budget with the same headroom as before; the simulation side shows no regression from FX/trails |
| `tools\gates.ps1 -GPU` (no `-Exports` this pass, stated plainly) | 7/7 ok in 765.5s: harness self-test, suite 35/35 (29 headless + 6 GPU), benchmark budgets, acceptance bots (10 checks, 3 controls), NEGATIVE acceptance controls (3/3), NEGATIVE benchmark controls (4/4 timing, 2/2 fill) |
| Golden trace | Re-recorded (expected: `BulletPool.to_array` gained a `vr` key on every live bullet, moving the very first snapshot digest). Checked first per the standing rule: at `origin_flown` every field through `offers`/`profile` matched; only `snapshot` differed. New final digest not yet stamped into a commit (no commit made this session, per the task's own instruction) |
| Negative controls added (all confirmed caught) | A deliberately 0.1s non-exempt template fails `validate_templates`; a `floor_exempt` 0.1s template does NOT fail it; fragment count outside 5-7 fails; drag forced to 1.0 fails the decay-ratio check; the old 0.35s mine warn fails the ≥0.5s check; no `_flare()` call leaves ticks_alive at 0; a sim trace with FX suppressed (`world.fx.enabled=false`) matches one with FX live, byte-for-byte over 180 ticks; GPU: a frame captured BEFORE `emit()` shows no ring; the collar never emitted leaves the centre at the playfield value; the player's own (light-blue) projectile DOES read inside the hue band through the same detector |
| Captures looked at | `--show-combat` (node -3,2, ring 3, T4 lightning player): player beam firing straight down, rendered as a light-blue line with visible width (the "wide faint band under a bright core" - jitter/pulse not distinguishable in a single still frame); several enemy lightning hulls each with a thin red laser-telegraph line drawn toward the player; two small pale rings concentric around the player core (consistent with the dash/invulnerability ring, not conclusively a muzzle/impact ring since neither event necessarily lands on the exact captured tick); background circuit traces visible and dim, correctly below the ship/projectile brightness; minimap and HUD unaffected. **Not conclusively shown in this single still**: a muzzle ring, an impact's two rings, fragments, a visible rim flare, or a dark collar - these are transient (0.15-0.65s) events that this one non-scripted capture did not happen to land on. The GPU pixel tests (above) are the actual proof for those; the capture is a sanity check on overall scene composition, not a substitute |
| What I could not make work, plainly | The rendered-frame benchmark's dominant cost (roughly 76% of the ~230-300ms/frame figure, i.e. everything beyond what disabling FX recovers) is unidentified. I bisected FX (24% of the cost) and ruled out the ring-based background density change (the benchmark scene's `world.sector` is never set by `CombatWorld.benchmark()`, so `ring` reads its default 0 and the trace count/intensity is unchanged from before this phase). I did not get to bisect the shader edits (`ship_outline.gdshader` flare, `projectile_instances.gdshader` interiors) or rule out a background-window/OS-throttling measurement confound (a single `--capture=` frame completes in seconds with no errors, which is suggestive but not conclusive). This needs a supervised, focused-window rerun and/or a GPU profiler capture, not more blind bisection from this seat |
| Bug found and fixed, not part of the brief but blocking the flare mechanism entirely | `combat_world.gd` `_step_motion`: writing `pose.flare = flare` (the same `PackedFloat32Array` object actor.part_flare had just been assigned) let `ShipMotion.step`'s own `pose.flare[i] = 0.0` reach back and zero `actor.part_flare` on the very next tick - measured directly: flare intensity went 1.0 → 0.933 (tick 0, correct) → 0.0 (tick 1, wrong - should have taken ~15 ticks). Fixed by `.duplicate()`-ing at every hand-off (actor/pose/renderer each keep an independent buffer) |
| Bug found and fixed in my own GPU test harness | `root.size = Vector2i(900,700)` (aspect 1.286) does not match the project's base content-scale aspect ratio (1.6); `root.get_texture().get_image()` then returns a letterboxed/scaled image (measured 900x562, not 900x700) whose pixels no longer map 1:1 to world/canvas coordinates, so every sample silently read background. `arena_render_test.gd` avoids this by using 1280x800 (aspect 1.6) - `combat_fx_render_test.gd` now does the same, with a comment recording the trap for the next GPU test author |
| Not completed / stated plainly | `tools\gates.ps1 -GPU -Exports` (package export verification) was not run this session, for time. Background density-by-ring was not re-captured at a deep ring via GPU pixel test (only code-reviewed for staying inside the 10-15% ceiling at the clamp bounds). `damage_number`'s own text rendering was left on the old `ThemeDB.fallback_font`/immediate-draw path inside `fx.draw_above` rather than a new template beat with its own timing beyond the existing 0.6s (already well clear of the 0.25s floor, so not touched further). Human-feel questions (does a flared rim actually read as "this got hit" at a glance, does the collar read as more violent than a flash) remain unverified, consistent with every prior phase's standing waiver. |

## P9 — Narrative, demo, docs, exports
- [x] `scripts/ui/dialogue_director.gd` with immediate lane; boss and unlock lines; coverage test
- [x] Demo flavour (levels 1–2)
- [x] README, INTERFACES, VALIDATION (old → `VALIDATION_V02.md`), RELEASE_CHECKLIST, STORE_DRAFT, workshop doc, STEAM_SETUP
- [x] `tools/package.py` 0.3.0; presets; four exports verified; commit pending

### Review — P9 (narrative, demo, docs, exports)

| What | Measured |
|---|---|
| `DialogueDirector` | New `scripts/ui/dialogue_director.gd`, a pure `RefCounted`: `line_queue`, `seen_lines` (dedupe), the static line tables (`entry_line`/`defeat_line`/`RIVAL_NAMES`), and two lanes — `queue()` (normal, gated on the caller's `combat_clear`) and `queue_immediate()` (spec §25's one exception, pushes to the FRONT of the same queue and is exempt from the gate). `main.gd` keeps `seen_lines`/`line_queue` as computed properties forwarding to the director's own live containers, so `tests/golden_trace_test.gd`/`tests/support/make_v3_fixtures.gd` needed no changes; `facade_contract_test.gd` stayed at 77 checks, 0 failures |
| Boss encounter line | Was queued through the same gated lane as everything else, so it could never show before the fight it announces was already over (contradicting spec §25 "a line ... on encounter"). Fixed: `_queue_line(...,immediate=true)` at both `_enter_sector`/`_on_warp_committed`'s boss-intro call sites; `_process` now calls `_update_dialogue` every play tick (not only when `remaining_enemies()==0`), and `DialogueDirector.can_show_next` arbitrates the gate itself |
| `tests/dialogue_coverage_test.gd` | 44 checks, 0 failures, 6 negative controls caught. Static wiring scan (every required literal trigger id, the unlock/reboot/boss-keyed ids, the immediate-lane call); boss-per-level distinctness (5 campaign levels → 5 distinct boss elements; dev-mode control collapses to 1, proving the property is real); between-fights gate (queued line blocked/unblocked correctly, never dropped); immediate lane (jumps the queue, exempt from the gate, an identical line through the ordinary lane is NOT exempt — the control); never-shown-twice (dedupe survives a full drain; two bypass controls prove the dedupe is really in `_enqueue`/`seen_lines`, not incidental) |
| Boss-per-level remap | No trigger-id code changed: `CampaignState.element_of` already gives a level's boss cell the LAST element of that level's `_revealed_elements()` slice, and the five campaign/demo levels reveal `GameTuning.ELEMENTS` one at a time, so a boss's `element` already identifies exactly one level (dev mode is the one exception, always plasma — noted, not fixed, out of scope) |
| Demo ending trigger | Two structural holes fixed: (1) `CampaignState.campaign_complete()` compared against the FULL 5-level count regardless of mode; new `CampaignState.level_cap()` (`ModeConfig.from_id(mode).level_cap()`) makes it mode-aware, so a demo profile reports complete the instant its level-2 boss dies. (2) `travel_to_level()` now clamps to the same `level_cap()`, so a demo save cannot be walked to level 3 by ANY path (level-select was already filtered; this is the second, structural guard). `main.gd::_on_boss_defeated` calls `_show_ending(mode_config.id=="demo")` instead of the old hard-coded `_show_ending(false)` |
| Demo menu copy | Stale "FIRE / CORRUPTION / PLASMA · T1-T3" panel and 3-root T3 preview replaced with "LIGHTNING / FIRE · LEVELS 1-2 · NO TIER CAP" and a lightning/fire preview at `GameTuning.MAX_TIER` |
| `package_validation.gd` (runs INSIDE exported builds) | 5 new checks, demo package only: `level_cap()==2`, `max_tier()==GameTuning.MAX_TIER`, `enemy_elements()==[lightning,fire]`, `travel_to_level(3)` leaves `level==2`, `campaign_complete()` false before the level-2 boss. Measured: campaign package 187→187 checks (unchanged), demo package 187→192 (the 5 new checks), both 0 failures, both platforms |
| Captures (looked at) | `--show-dialogue --capture=`: companion box renders with ECHO's portrait, "Your first light" title/body, HUD/minimap visible behind it, `engine_errors=0`. `--show-demo-ending --capture=` (reached through the real `_on_boss_defeated` path: level 1 completed, travel to level 2, level 2's boss defeated): "A SMALL LIGHT, AN OPEN WORLD" / "Lightning and Fire have both yielded...", `sector_label` reads "DEMO · NODE 0,0 · RING 0", `engine_errors=0` |
| Docs | `README.md`, `docs/INTERFACES.md`, `docs/VALIDATION.md` (old archived to `docs/VALIDATION_V02.md` with an archived banner; `docs/LIGHTSHIP_GAME_SPEC.md`'s stale forward-reference to the now-repurposed `VALIDATION.md` redirected to the archive), `docs/RELEASE_CHECKLIST.md`, `docs/STORE_DRAFT.md` (checked against every §3 forbidden TRON term — none present), `docs/SHIP_WORKSHOP_V2.md`, `scripts/platform/STEAM_SETUP.md` all rewritten for v0.3. Every number in the new `VALIDATION.md` is either measured this session or cited directly from an existing `tasks/todo.md` review table; where a v0.2 number could not be re-derived this session (e.g. the rendered-frame tail, acceptance-bot medians), the doc says so explicitly rather than copying the old figure forward |
| `tools/package.py` / `export_presets.cfg` | Version `0.2.0`→`0.3.0` (manifest + both Windows presets' `file_version`/`product_version`; the demo preset was missing `product_version` entirely, now added). README.txt template regenerated: added the Dash control line, corrected the demo/campaign blurbs (no more "Fire core at distance eight" / "81 preset hulls") |
| Exports (this session) | All four (`tools\export.ps1 -Platform all`, `-Demo`) built; `tools\verify_exports.ps1 -LinuxContainer` (Docker available, used): **Windows campaign 187/0, Windows demo 192/0, Linux campaign 187/0, Linux demo 192/0**, all "runtime checks passed". `tools/package.py`: 4 archives, `builds/distributions/manifest.json` version `0.3.0`, integrity/hash checks passed (38.1 MiB Windows zips, 29.0 MiB Linux tarballs) |
| `tools\gates.ps1 -GPU -Exports` | **12/12 ok**, 895.2s: harness self-test, test suite (36/36, 0 failures), benchmark budgets, acceptance bots (10 checks/3 controls), NEGATIVE acceptance controls (3/3), NEGATIVE benchmark budgets (4/4 timing, 2/2 fill), rendered frame benchmark (2/2), NEGATIVE rendered frame (2/2), Windows campaign/demo export, exported packages verify (2/2) |
| `test.ps1 -GPU` (literal PASS lines) | 36/36: arena 21/0(4c), campaign_playthrough 54/0, combat_fx 24/0(6c), combat_tests 141/0, dev_console 22/0(3c), **dialogue_coverage 44/0(6c)**, enemy_ai 41/0(10c), enemy_parts 31/0(6c), facade_contract 77/0(1c), golden_trace 4/0(1c), handling 12/0(1c), hud_model 1356/0(2c), mode_isolation 26/0(7c), save_migration 24/0(2c), ships_compositor 0f, ships_editor 0f, ships_mesh_cache 0f, ships_mesh 6922/0, ships_reshape 15135/0 (125 routes), ships_validation 10982/0, ship_motion 19/0(5c), ship_roster 825/0(14c), sound_shutdown 0f, ui_flow 33/0, unlock_offers 34/0(4c), warp 19/0(1c), world_generation 17/0(4c), world_platform 31, world_rules 103, plus 6 GPU render tests all 0 failures |
| Golden trace | Re-recorded (expected: the queued-line dict gained an `"immediate"` key, moving the `lines` digest — `sha256([seen_lines,line_queue])`). Checked first per the standing rule: the failing run's own diff named `lines` as the FIRST differing field at the `new_game` step, meaning every field checked before it in insertion order matched exactly. New final digest `4089779872420184`, `engine_errors=0` |
| Bug found, noted for P10 (not fixed — out of this phase's brief) | `enemy_ai_test.gd`'s `turret_ring` census check, flagged failing in the P7 review and still listed as an unfixed carry-forward item above, passed clean (41/41) in every run this session. No file touched this phase explains why; left exactly as recorded above for P10 to confirm or correct, not removed on the strength of these green runs |
| Not completed / stated plainly | `tasks/todo.md`'s own P6 checklist (above) is still shown fully unchecked even though the code (momentum/dash/trails/warp) and its tests (`handling_test.gd`, `warp_test.gd`, `warp_render_test.gd`) demonstrably exist and pass — a stale checklist, noted in `docs/VALIDATION.md` and here, left for P10 to tidy since fixing checkboxes for work done in an earlier, already-committed phase is outside this phase's own brief. Linux DISPLAY/audio/controller qualification on real hardware was not performed (the container verification is headless runtime checks only, stated in `docs/RELEASE_CHECKLIST.md`). No human-feel review of the dialogue box's pacing, the demo's menu copy, or the ending screen — captures were looked at, but no second person. The rendered-frame tail and acceptance-bot numbers were not re-measured this phase (no sim/render code changed) and are cited, not re-derived, in `docs/VALIDATION.md`.

## P10 — Adversarial review
- [x] Review by three independent lenses (spec conformance; determinism, saves and blind
      instruments; sim/render agreement, performance and code health), each read-only and each
      asked to be adversarial. They converged, and between them they found real defects that the
      12/12 green gate could not see. The most valuable output was not the spec gaps but the
      **blind instruments**: several "negative controls" turned out to be arithmetic tautologies
      over literals, or to sabotage something the assertion did not read.
- [x] Fixed this pass, each with the instrument that would have caught it:
      - **Every T6 Heavy hull threw a script error every frame.** `GameTuning.slots(6,"heavy")`
        granted 4 secondaries (base 3 + Heavy's +1) while only three bindings exist anywhere
        (§26: Space/Shift/Q, LB/RB/X; `ShipCommand.secondaries` is 3 long). `_draw_slot_icons` and
        `_component_controls` indexed a 3-element literal with 3 and GDScript aborted the function,
        so `_refresh_hud` never reached its only `minimap.queue_redraw()` call and the corner
        minimap froze permanently. Capped at the single source of the slot count
        (`MAX_SECONDARY_SLOTS = 3`) rather than clamping at each reader, and T6 now gets the second
        passive §9 grants it. 5 of 101 hulls were erroring unnoticed because nothing built the HUD
        per hull.
      - **§16 "contact with an enemy body damages the core" was not implemented.** `_update_contact`
        tested only the enemy's core centre, so a 226 px, 29-circle elite was free to fly inside.
      - **The exploration save is written during the warp lock and restored into a phantom warp.**
      - **`tick` was a process-global counter**, never reset per life and never saved, while
        `elapsed` (which decides nothing geometric) was. It is the clock every orbit group reads, so
        limb and muzzle positions depended on how long the process had been running. The golden
        trace could not see it because its level-1 route met no hull with a motion group; the route
        now includes a corruption chain hull, which always carries a `whip` group.
      - **P8's FX batching composited the "above" pass under everything.** `_fx_canvas` and
        `_pickup_canvas` stayed parented under `world`, inside the background subviewport, so their
        internal z-order was correct relative to each other but never compared against the bullet
        canvas, trails or the player hull — an impact ring on the player drew beneath it.
      - **Light was silently destroyed at the pickup cap** (`_spend_energy` debited the budget before
        the cap check), and detachment debris dropped a single pickup of arbitrary size where §10
        defines exactly 1 / 5 / 20.
- [ ] **Not fixed — the review's own findings that remain open.** Recorded here rather than closed:
      - The pillar-5 instrument is blind: `combat_fx_render_test`'s hue gate samples a patch centred
        on the player's own ship, so it measures the white player core and returns the same result
        for all five elements. Pillar 5 ("light blue is the player; no other ship, pickup or enemy
        projectile uses it") therefore has no working automated guard, and the element actually at
        risk is **void** — `#9aa3b3` at emission renders a near-desaturated pale blue measured 0.056
        from the player hue, against a 1/24 threshold, and a hue-only metric is meaningless at that
        saturation.
      - Five counted negative controls are tautologies over literals and cannot fail
        (`combat_fx_test.gd` fragment-count / drag / telegraph-warn, `enemy_parts_test.gd`'s
        `not (plain > plain)`, `enemy_ai_test.gd`'s aim-error control); `hud_model_test.gd`'s
        HUD-overlap control is satisfied by an unrelated null guard; `acceptance_bot.gd`'s
        light-chasing control compares two indifferent walks that both sit at the 240 s cap, and its
        median folds failed runs in — the exact bias P7 fixed for the first-evolution bot two
        functions above it.
      - `hud_model_test`'s boss bearing asserts only the four cardinal labels, so reordering the
        diagonal names would leave all 1356 checks passing with the arrow wrong in every diagonal.
      - `pose.scale` (breathing) scales the drawn rim but not the collider radius; during a reshape
        the renderer ignores the pose entirely and draws from authored rest positions.
      - No inverted warp on death or level travel, though the approved preamble promises one.
      - Reach rings are missing on bosses (6 orbiting groups, 0 rings) and drones author no motion
        group at all, against §14's "small orbit, breathing".
      - Enemy respawn works only within one continuous visit: `_dead_enemy_records` is not in the
        encounter snapshot.
      - Dead code is wider than previously recorded (`combat_status`, `run_stats`,
        `_narrow_to_circle`, `ShipRig.bound_radius`, two unconnected signal handlers, and an Options
        "show elements" toggle that is written and never read), and several file headers describe
        designs that were replaced.
      - Stale numbers: the P8 review row cites benchmark budgets the code no longer has, the
        unsectioned-tick figure is now 0.18 ms rather than 1.4 ms, and `main.gd` is 1488 lines, not
        the 1298 recorded below.
- [x] Final `tools\gates.ps1 -GPU -Exports`; review + "what is NOT verified" below; commit

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
- [ ] **Profile the unsectioned ~1.4 ms of the tick.** At 2000 bullets the named sections sum to
  7.57 ms while `simulation_ms` measures 8.3–9.6. The already-measured parts got cheaper or held
  (bullets 5.17 → 4.09, ai 1.54 → 1.36, grid 0.58 → 0.67, upload 1.06 → 1.08), so the growth is in
  work that has no section: `_update_pace`, debris, the warp state machine. Add sections for those
  and see whether any of it is avoidable before accepting the restated budget as permanent.
- [ ] **The rendered frame's worst 5% still dips below 60 fps in the stress case** (p95 15.5–19.9 ms
  across runs, against 16.67). Mean is 8.2–10.8 ms, so this is a tail, and it occurs only with the
  bullet pool at 2000 AND the pickup pool at its 400 cap simultaneously. The frame is now
  simulation-bound, so the item above is the lever. No Steam Deck has been measured at any point.
- [ ] **Trails are not a MultiMesh.** §23 says "Trails are pooled segment buffers, not nodes" and
  names MultiMesh; P6 pooled the buffers but draws them with immediate `draw_line` on one canvas.
  The "not nodes" requirement and the 40-trail budget hold and the benchmark stays in budget, so
  this is fidelity to the letter of §23, not a functional gap.
- [ ] **Warp streak geometry.** §12 wants "radial streaks running from a vanishing point in the
  travel direction". The capture shows them fanning outward from the ship rather than converging on
  a point ahead, and only in a cone toward the exit rather than radially across the frame.
- [ ] `scripts/world/run_controller.gd` was never extracted (deferred at P1, P5b and P6). `main.gd`
  is now 1298 lines. Nothing depends on it — it is a maintainability item, and the facade contract
  test keeps the members it would move honest.
- [ ] The benchmark gate flaked once when run immediately after the GPU and export steps
  (contention), then measured inside budget on three standalone re-runs. If it recurs, either run
  the benchmark first in `gates.ps1` or take the best of N runs rather than widening the budget.

# Ship design spec — build plan

Spec: `docs/LIGHTSHIP_SHIP_DESIGN_SPEC.md` (spec **v2** verbatim, under the scope approved
2026-09-21; v2 replaced v1 the same day, before any v1 code existed, adding the motion numbers of §9,
the gallery of §12 and the generator of §13). It supersedes v0.3 §14, §17, §18, §21 and §22: all 141 hulls are discarded and every ship is
rebuilt on one grammar (core stack, rails at 52/96/140/184, slots, spokes, hub/pod clusters, weapon
set pieces, two colours that gate what may be mounted). Reference image:
`docs/ship-design-reference.png`. Same house rules and the same judge (`tools\gates.ps1 -GPU -Exports`).
Commits: `Lightship v0.3 S<n>: <clause>, and <finding>`, path-scoped to `Lightwings 1`.

**No mid-build stops** (user, 2026-09-21). Captures for each would-be review point are saved and
listed in the review tables. "Trace identical" means `golden_trace_test` passes without re-recording;
everything new is gated on `schema_version == 4`, so that holds until the S11 cutover.

Architecture in one paragraph: the grammar is the only stored truth and parts are compiled on load
(`ShipCompiler`), so `ShipMesh`, the outline shader, the rig, the broadphase, `_destroy_part` and saves
keep working. Motion becomes one forward-kinematics pass (`_step_fk`) beside the untouched legacy
evaluator, because nested groups do not compose today; its joints are v2 §9's layers (rail spin, pod
and node bob, arm pump of the rail RADIUS, aim slew, chains) with defaults in `ShipGrammar.MOTION`.
Nothing scales except the render-only core-dot pulse. Circles gain a `solid` flag (rail rings, inner
core rings, passive rings and set-piece circles carry no HP, collider, reward or TP). The hub is the
mount. `SetPieceCatalog.legal_for(chassis, accent)` is the single colour gate. One recipe engine
(`ship_recipe.gd`, §13) builds both the pinned roster and seeded ships. The new roster is built in
`content/ships_next/`, reviewed through the gallery's contact sheets, and swapped in by one commit.

## S0 — Spec, reference, baselines, honest instruments (trace identical)
- [x] This plan in `tasks/todo.md`; spec saved with the approved-scope header; V3 §14/17/18/21/22 marked superseded (v2)
- [x] `docs/ship-design-reference.png` + measured census `docs/ship-design-reference.json`
- [x] Bookkeeping: P6 ticked with a short review; open P10 items triaged (superseded / fixed here / open)
- [x] Pillar-5 instrument repaired for PROJECTILES, all five elements (void 0.433, plasma 0.407 from player blue); the SHIP-RIM half moves to S2, where the first silver-chassis rail hull is rendered; acceptance
      bot's light-chasing control and failure-folding median repaired
- [x] `motion` and `grid` benchmark sections, each line with its own negative control
- [x] Baselines ×3 recorded below: suite counts, bot medians and maxima over 20 seeds, both benchmarks,
      footprint and circle census of today's roster; gates; commit (renderer profile NOT run: it is taken in S1 beside the `_rig_to_mesh` change it judges)

## S1 — Behaviour-neutral seams (trace identical)
- [x] `scripts/data/elements.gd`; the three duplicated ELEMENTS/COLORS arrays become aliases; `"blue"` palette entries
- [x] Part joint/solid/style fields, rig packed arrays, `_step_fk` beside `_step_legacy`, `solid_indices`
      in the broadphase, `ShipRenderer.external_pose`, `_rig_to_mesh` index map
- [x] `ShipGrammar.MOTION` (§9 tables); new `ship_fk_test` (the legacy `ship_motion_test` is left
      alone): pod bob on a spinning rail, arm pump moves the hub and never its radius, aim joint; a
      control that re-parents the pod so it inherits nothing must fail; commit. **Node bob is the same
      joint as pod bob and is first exercised by the compiler in S2; the chain wave moved to S3 with
      the rest of the stateful motion**

## S2 — Grammar, compiler, validator, first set pieces, rail rendering (trace identical; `content/` diff empty)
- [x] Schema-4 resources, `ShipGrammar` (coded `RULES`), `ShipCompiler`, `SetPieceCatalog` with ALL 33
      pieces (S4 now only tests, gates and captures them); shader styles 4/5, line kind 2 and
      paint-order baking, shipped with a GPU test
- [x] Fixtures `tests/fixtures/ships_v4/{radial_elite, player_t3, drone, boss, irregular}.json`
- [x] `ship_grammar_test.gd` (one control per coded rule + every rule triggered by some control);
      `ship_compiler_test.gd` (compile twice byte-equal, ids unique, paint order, `budget()` = compiled, boss ≤ 128)
- [x] `tests/support/ring_probe.gd` + `ship_reference_render_test.gd` (structural signature vs the
      reference; controls: 4 arms, equal orders, third colour, no set piece, blank image, wrong scale); `rail_render_test.gd`
- [x] Pillar 5 for SHIP RIMS (carried from S0): all five chassis colours vs the player's rim (nearest is
      violet at 0.423, not silver), same metric and threshold as the projectile lines, two controls
- [x] Review capture 1: `artifacts/acceptance/reference_vs_render.png`; commit

## S3 — Rails in combat (gated on schema 4; trace identical)
- [x] Aim slew (≤ 3.0 rad/s, outward with nothing to aim at) stepped per sim tick; chain WAVE as a
      pure function (tip 6.50 / 15.13 px); rail-ring rule; mount-table muzzles and twin mounts;
      core-weapon firing for decision-driven AI; `archetype` dispatch; `part_hp <= 0` readers read
- [ ] **Open:** follow-the-leader chain trailing (§9.6's other half)
- [x] Shine period by ladder radius + the (part, cluster) phase rule, assigned by the compiler;
      core-dot pulse (render-only, from the tick); rail dash 2/5 at 28% (S2)
- [x] Destruction (§9.8): debris inherits rail velocity, spins 0.5–1.5 rad/s, drifts outward, fades
      over 1.0 s, drops light at 0.5 s
- [ ] **Open:** §9.8's 0.10 s collapse and 5–7 fragments along the incoming vector (existing FX kept)
- [x] Acceptance 3 and 4 as instruments (`ship_motion_law_test`; excursions in S1's `ship_fk_test`)
- [ ] **Open:** GPU two-tick check of visible bob; GPU check of the core pulse and of a set piece
      staying aim-aligned on screen (all three are covered headless only)
- [x] Reshape: a rail hull swaps meshes at once and never takes the CPU tween. **The planned GPU
      reshape with a ghost mesh was NOT built**; the CPU path stays for v0.3 hulls until S12
- [x] `rail_combat_test` on fixtures in a real `CombatWorld` (cluster detach, rail deletion, scenery
      carries no HP or reward with a "ring marked solid" control, slew, debris, core weapon, twins)
- [x] `ship_ladder_render_test.gd` (acceptance 2): hub span equal on elite, boss and player, core on
      drone and boss, at base and minimum zoom and at two ticks; four controls; commit.
      **`motion` cost for 17 boss-fixture actors NOT measured** — it moves to S10, with the roster

## S4 — The 33 set pieces and the colour gate (trace identical)
- [x] All 33 authored (2–5 ladder circles; lines end on circles or the hub); `implemented` = its ability exists
- [x] `set_piece_test.gd`: 18 mono + 15 duo, colours match §6.3, `legal_for` equals the §6.5 lists
      hard-coded from the spec, pairwise glyph distance with a piece-against-itself control
      (silver-vs-blue was measured on rims in S2 and not repeated on pieces)
- [x] Review capture 2: `artifacts/acceptance/set_pieces.png`, the 33-piece sheet at 1×; commit

## S5 — Editor on the grammar (trace identical)
- [x] Shell kept; tabs Core / Rails / Slots / Colours / Motion / Set-piece library in flat `tab_*.gd`
      files (Motion: per-rail speed and pump, per-cluster bob, chain mode, live preview; speed sign
      auto-alternates with a warning on override); one
      `edit()` choke point; free placement, drag, line tool, macros and mirror authoring deleted
- [x] `ship_canvas.gd` as a ring diagram with polar slot picking; illegal mounts ringed red
- [x] Colours tab never blocks a change; greys out illegal pieces and lists mounted-but-illegal ones
      through the validator's own `illegal_mounts()`
- [x] `ShipAuthoring` JSON on the §10 schema (strict, canonical, byte-stable)
- [x] `ships_editor_test.gd` and `docs/SHIP_WORKSHOP_V2.md` rewritten; package check that no editor script ships; commit
      — measured: `tools/test.ps1 -GPU` 48 passed / 0 failed / 98.9s total, `golden_trace_test`
      unchanged (4 checks, 1 control). `ships_editor_test.gd` has no separate printed check/control
      counts (it is a scenario-style test, not a counted one like `ship_grammar_test`); it covers
      the S5 brief's ten listed behaviours, each with its own negative control, 0 failures. NOT
      done from the original brief: no live-preview scrub through Motion beyond static overrides
      (no per-frame preview scrubbing was built — the base/min zoom previews already animate live
      via the production renderer, but there is no frame-by-frame scrub bar; that belongs to S6's
      detail view per §12.4); the Slots tab's "mirror twin sharing one mount" for an off-axis player
      weapon (spec §5) is NOT implemented — "apply to symmetric orbit" only guarantees rotational
      uniformity across a whole rail, which is sufficient for `SYM-ROT` but not a literal built
      mirror-twin/shared-mount mechanism for `SYM-MIRROR`; a player hull must still satisfy
      `SYM-MIRROR` by hand-placed slot symmetry today. `tests/ships_validation.gd` (pre-existing,
      out of S5's file list) needed a small fix: it exercised the now-retired v2/v3
      `ShipAuthoring.to_json`/`from_json`/`from_description` round trip and local-compiler
      generation; updated its three affected assertions to the stub/strict behaviour this phase
      requires, leaving its 141-hull schema-3 roster checks untouched (11003 checks, 0 failures).

## S6 — Gallery (§12; trace identical)
- [x] Pure `GalleryModel`: scans a catalog root INCLUDING invalid files; metadata (counts, footprint,
      set pieces, errors, mtime); §12.3 filters, sorts and search; roster coverage grid; the "≤ 24
      animating, nearest-to-centre, off-screen frozen" scheduler as a pure function
- [x] Views in flat editor-only files: contact sheet with live tiles and true-scale toggle; detail
      (part tree with HP, detach preview from the rig's `subtree_size`, weapon legality, motion panel
      with a tick scrub bar, silhouette); compare 2–4; coverage → editor pre-seed; PNG export (sheet,
      single ship, rails on/off); mtime-poll live reload. Replaces the editor's library window
- [x] `gallery_model_test.gd` (a control per filter, sort, coverage, invalid-still-listed and scheduler
      line); `gallery_render_test.gd` (a visible tile changes between ticks, a frozen one does not;
      detach highlight sits on the hub's subtree only — acceptance 7); commit
      — measured: `gallery_model_test` 54 checks / 0 failures / 17 controls caught (headless).
      `gallery_render_test` (GPU) 0 failures / 3 controls caught: moving-tile diff 0.19 vs frozen-tile
      diff 0.00003 over 90 real frames; `fixture_radial_elite` hub `r2s0` redness +0.053 vs `r2s1`
      +0.00 after `GalleryDetachOverlay.highlight`; every staged ship's tile reads 0.06-0.30 against
      an empty-tile baseline vs 0.006 for the same ship with its renderer forced invisible.
      `tools/test.ps1 -GPU` whole suite: 50/50 passed, `golden_trace_test` unchanged (4 checks, 1
      control). The subagent's export saved only the current 1280x800 viewport (8 tiles of 141);
      the review fixed it to page through the scroll and stitch (see Review — S6). NOT done, stated
      plainly: `tests/ships_render_smoke.gd` (an ad hoc, ungated capture
      script predating S6) still expects the old `_player`/`_populate` API and was not updated, since
      it is outside `tools/test.ps1`'s gated suite. See `docs/SHIP_WORKSHOP_V2.md`'s "Gallery"
      section for the full file list and verification detail.

## S7 — Weapons I: cheap and shared machinery (additive; trace identical)
- [x] Batch 0: `drone_hatch`, `slow_field`, `void_orb` lite
- [x] Batch A: `spiral_shot`, `pulse_ring`, `chain_infection`, `overcharge`, `drone_swarm`, `phase_shot`
- [x] Batch B (tethers on the virus list; fixes the never-expiring virus on the player): `arc_tether`,
      `siphon_tether`, `siphon_leech`, `ignition_lance`
- [x] `weapon_behaviour_test.gd`: fresh world per id, swapped-ability control, enemy damage ≥ 0.5 s after activation; commit

## S8 — Weapons II: telegraphs and the hot loop (built and committed WITH S7: see Review — S7 + S8)
- [x] Batch C: `discharge`, `collapse_charge`, `nova_pulse`, `refract_beam`, `blink_mine`
- [x] Batch D: `black_hole_shot`, `incendiary_spores`
- [ ] **Open:** `void_orb` FULL (a piercing orb that damages per tick of overlap); it ships as a slow heavy shot
- [x] Headless benchmark ×3 with and ×3 without the weapons, same session; budgets unchanged. The
      rendered-frame benchmark was taken once, by the gate, not ×3

## S9 — Generator (§13; trace identical)
- [x] `scripts/ships/ship_recipe.gd`: `generate(params)` (the 12 steps, own seeded RNG) and
      `style_check(ship)` = validator errors + circle count ±20% of the archetype target from
      `budget()`, reach ring and core dot present ("one set piece per hub" is structural: a slot
      has one `set_piece` field). ONE engine: a roster entry pins its structure, a generated ship
      leaves it to the seed
- [x] Editor "generate from description" resolves text into the §13.1 template (theme biases set-piece
      weights only; it does NOT bias speed jitter, which stays the seed's)
- [ ] **Open:** gallery coverage cells pre-seed the editor but do not call the recipe to fill the hull
- [x] `ship_recipe_test.gd`: 20 seeds × every archetype × a spread of pairs pass validate + style check
      unedited; same seed byte-identical; different seeds differ; a control per style rule; stub band 10–25%; commit

## S10 — The roster, in staging
- [ ] Roster manifest as pinned recipe inputs: 101 player hulls (four shapes and four loadouts per
      element/tier), 25 mono regulars, 15 elites (radial = next element on the reveal ring,
      irregular = previous, heavy = two ahead), 5 bosses
- [ ] `ship_library_test.gd` (our own gate: zero errors, zero warnings, manifest = disk, max circles ≤ 128);
      `colour_language_test.gd` (acceptance 5 proxies); distinct-shape roster test; slot chord ≥ measured cluster width
- [ ] Bots and both benchmarks on `--catalog-root=content/ships_next`, 20 seeds, per-ability event
      census and the marking-to-shot angle at fire events; far-end benchmark (boss + 2 heavy elites at 2000 bullets)
- [ ] Review capture 3: gallery contact sheets of the staging roster at uniform and true scale;
      acceptance 8 line-up sheet (generated among pinned, with an answer key); commit

## S11 — Cutover, one commit (trace re-recorded: name the first differing field first)
- [ ] `export_catalog.gd --rebuild` from staging; ability table remap with the `.tres` rebuild and a `.tres`-equals-table test
- [ ] Offers, campaign descriptors (heavy elites at node tier ≥ 3), `SchemaVersion` 5, HUD model ids
- [ ] Every migrated test restated; Retired assertions filled
- [ ] Bots before/after; both benchmarks ×3; budgets restated with the reason; `gates.ps1 -GPU -Exports`; commit

## S12 — Delete the legacy (content and tests byte-identical; trace identical)
- [ ] Growth builders, `add_pair`, `mount_component`, `ABILITIES`, v3 validate/warnings, `GroupDefinition`,
      `_step_legacy`, reach-ring synthesis, `symmetry`/`mirror_id`, v2/v3 JSON import, retired ability
      branches and body-feature sim code; commit

## S13 — HUD, docs, acceptance (no briefings: v2 dropped them)
- [ ] Evolution cards with colour chips and set-piece glyphs; HUD slots draw the 1× glyph
- [ ] README, `docs/INTERFACES.md`, `docs/VALIDATION.md`, store draft and art; `docs/ACCEPTANCE_HUMAN.md`
- [ ] Review capture 4: two-colour enemy cold-capture set; commit

## S14 — Tuning from measurement
- [ ] Re-tune only what the S11 numbers moved so the v0.3 M1/M5 bot gates hold; trace re-recorded; budgets restated with history; commit

## S15 — Adversarial review
- [ ] Three lenses, one dedicated to tautological controls and blind instruments; fix or list; final
      gates; project memory updated; honest open list; commit

---

# Improvements spec — build plan (phases I0–I4)

Spec: `LIGHTSHIP_IMPROVEMENTS_SPEC.md` (supplied 2026-09-21; saved to `docs/` in I0). It supersedes V3 §12,
the membrane rules in §11 and the laser-prong entries in §15/§16/appendix B. **Plan written 2026-09-21,
awaiting approval — nothing below is started.** Same house rules, same judge, same commit style
(`Lightship v0.3 I<n>: <clause>, and <finding>`, path-scoped).

**Decisions taken (user, 2026-09-21):** enemies that carried the prong get the Arc Tether if they move and
`explosives` if they are static sentries. Camera: the "camera and movement spec" the improvements spec
leans on is not in the repo, so the 1.30× zoom and focus lead are removed, the camera stays locked on
the ship, and camera behaviour is isolated in one function for that spec to replace.

**Assumptions to correct at approval, each a one-line change:** (a) an arc is open iff its direction is
in `exits_of(coord)` — the maze topology stays, so interior sealed arcs exist as well as the perimeter
(`EDGE_OPEN_PROBABILITY = 1.0` would open every interior edge); (b) the shader tail in I3 applies to
both factions' plain shots (one code path; the spec says "same as the player", and the player's plain
shots have no trail today either); (c) the tether line is drawn in the component's yellow, not player blue.

**What exploration found that changes the spec's premises**
- §3's "enemy projectiles appear and disappear" is only partly true here: the muzzle ring, impact rings
  and fragments and the player-core flare already fire for enemy shots (`_emit_shot`, the shared hit
  branch and `_damage_actor` do not branch on faction). What is missing: a trail on plain shots (the
  pool trail is gated on `HOMING|ROCKET` and budgeted at 40), every enemy-specific difference, the core
  clip, the HP-bar pulse, and a cap that drops the oldest (`CombatFX._slot` drops the NEWEST). I3
  starts by measuring this rather than trusting either account.
- §4 is already half-planned by the ship design spec: `laser_prong` retires there, `hook_node` = Arc
  Tether is one of the 33 set pieces, `arc_tether` is S7 batch B, and `ABILITIES` / `mount_component`
  are deleted at S12. So §4 is **folded into S7/S10/S11/S12** (I4 below), not built on the legacy roster
  only to be rebuilt two phases later.
- Spec items from V3 §12 that were never built and are now owed by I2: rim deformation, the light burst
  on arrival, running lights stretching, the new rim expanding into view, any transition audio
  (`warp_arrived` has no listener), and streaks that radiate from the ship (P10 open item).
- `tests/support/bot_pilot.gd` sets `ability_secondary` but never `secondaries`, so **no bot has ever
  fired a secondary**. Acceptance 7 cannot be approached until that is fixed (I4).

**Ordering.** I1 → I2 (I2 builds on I1's exit angle) ; I3 independent; I4 rides the S-phases. I1–I3 all
edit `combat_world.gd`, which has uncommitted S3 work in the tree — they start only from a clean tree
after S3's commit. Golden trace: I1 and I2 each re-record (name the first differing field first); I3 must
pass WITHOUT re-recording (FX never touches the sim).

## I0 — Spec in, baselines measured (trace identical)
- [ ] Save the spec as `docs/LIGHTSHIP_IMPROVEMENTS_SPEC.md` under an approved-scope header (the decisions
      and assumptions above); supersede notes on V3 §11 membranes, §12, §15/§16/appendix B prong rows
- [ ] Baselines before any change: warp locked time and arrival speed as a fraction of APPROACH speed
      (today's arrival speed is the speed at commit, i.e. already cut to ≤ 40% — measure it, 20 seeds);
      seconds a node-crossing bot spends within 60 px of the rim before committing (the "hunting for the
      door" number §1 exists to kill); rendered-frame benchmark ×3
- [ ] FX census by faction over the acceptance bots (muzzle / impact / flare emits, pool drops, peak
      simultaneous enemy impacts) with a firing-disabled control; GPU capture of enemy shots landing on
      the player, looked at; commit

## I1 — Exit from any point on the rim (trace re-recorded)
- [ ] `circular_arena.gd`: `arc_of(point) -> Vector2i` (quadrant by |dx| vs |dy|, deterministic on the
      diagonals), `is_open(dir)`, `exit_offset(point, dir) -> float` (u ∈ [−1,1] on the axis perpendicular
      to travel, normalised by R·sin 45°) and `entry_point(dir, u)`; `entry_position(dir)` stays as the
      u = 0 case for `_enter_sector`. Delete `membrane_at`, `membrane_half_angle`, `OPENING_HALF_WIDTH`,
      dead `in_opening`
- [ ] `combat_world.gd`: `_warp_engage_direction` uses `arc_of` + `is_open`; press state carries the
      contact angle and offset; `_warp_arrive` places at `entry_point(dir, u)` and keeps the velocity
      VECTOR (today it snaps to the cardinal direction and discards the offset). Sealed arc: reflect with
      `GameTuning.RIM_BOUNCE_RESTITUTION` + the existing `wall_flash` / `boundary_contact`
- [ ] `combat_persistence.gd`: new warp fields in the snapshot; the P10 mid-warp restore fix keeps working
- [ ] `arena_backdrop.gd`: the rim becomes ONE `draw_polyline_colors` ring — per-vertex colour for the
      local brightening (cosine falloff over 60° either side of the contact angle, open arcs only);
      sealed arcs get a second thin concentric stroke (two thin strokes, not one fat one: a thick bright
      ring blooms inward). `sector_edges.gd` labels sit at each open arc's centre
- [ ] Bots: `bot_pilot.gd` / `campaign_playthrough_test.gd` exit through the nearest point of an open arc
- [ ] Proof — acceptance 1: `arena_test.gd` round trip over 360 exit angles × 4 arcs returns within
      0.01 px and the same velocity (control: offset discarded, as today); a live two-warp round trip in
      `warp_test.gd`. Acceptance 2: `arena_render_test.gd` samples ON the rim at open-idle, open-pressed
      at the contact angle and at +90°, and sealed, each relative to the measured background (controls:
      brightening drawn on a sealed arc; second stroke removed). Rim-dwell time against I0's baseline,
      20 seeds, median and max. Retired: `membrane_at` checks, membrane pixel 0.8575, the literal
      `entry_position` geometry in `combat_tests.gd`. Gates; commit

## I2 — Node transition rework (trace re-recorded)
- [ ] Sim, one state machine reshaped: `PRESS 0.20 → BREAK 0.06 → WARP 0.30 → ARRIVAL 0.20` (+ `FADE 0.20`
      when reduced), integer ticks. Approach velocity = peak speed during the press along the direction
      at commit, so the 40% press slowdown never becomes the arrival speed. Ship flung at 3× top speed
      through BREAK/WARP, placed at ARRIVAL start at approach velocity; `warp_locked()` is false in
      ARRIVAL; invulnerable BREAK → end of ARRIVAL through the single `player_invulnerable` choke point;
      enemy projectiles discarded at BREAK; sector swap stays synchronous at commit
- [ ] Trail: the player's trail survives `_clear_encounter` and is translated by the teleport delta at
      arrival (one continuous ribbon); sample distance shortens during PRESS so the trail bunches
- [ ] Rim (view, driven by sim ticks only): bulge ≤ 40 px at the contact angle, brightness 60% → 140%
      with push depth; spring-back wobble on release; at BREAK a recoil that oscillates twice and a
      `breach_ring` FX template from the breach point; `arrival_burst` template at the ship; the new rim
      expands in from beyond the screen edge during ARRIVAL
- [ ] Streaks: origins on a small ring round the ship, radiating in every direction, 0 → 400 px over
      0.12 s then hold, stepped taper reusing `TrailPool.STEP_SCALES`, staggered contraction in ARRIVAL,
      per-channel offset < 2 px. World except the ship to 20% in one frame at BREAK (modulate on the
      compositor's background image and foreground canvases, player renderer excluded). Running lights
      stretched into lines: a `warp_stretch` uniform on `ship_outline.gdshader`, shipped with a GPU test
- [ ] Camera: `combat_compositor.gd::_warp_zoom` and the focus lead deleted; one `_camera_focus()` seam
- [ ] Audio: `soundscape.gd` cues `warp_strain` (rising, cut if the press is released), `warp_snap`,
      `warp_rush` (falling), `warp_bloom`; signals `warp_press_started` / `warp_press_released` (new),
      `warp_committed`, `warp_arrived` (exists, never connected)
- [ ] Accessibility: reduced = 0.20 s cross-fade, no streaks, no bulge, no dim
- [ ] Proof — acceptance 3: control returns ≤ 0.6 s after commit measured in ticks (0.56 s by design;
      control: the old 1.02 s constants), and arrival speed ≥ 95% of approach speed at slow / cruise /
      dash approaches over 20 seeds, median and worst (control: capture at commit, as today). Acceptance
      4: `warp_render_test.gd` — the ship's screen position is constant across WARP frames while streak
      endpoints move away from it on all four sides (controls: focus lead restored; the old
      vanishing-point streaks). Invulnerability window, projectile discard, press-release spring-back,
      save/restore in every phase, byte-identical determinism. Captures of all four phases, looked at.
      Retired: locked ≈ 1.02 s, reduced 0.25 s, rim width equal at 1.00× / 1.30×. Gates; commit

## I3 — Enemy projectile impact parity (trace identical)
- [ ] `combat_fx.gd`: `impact_enemy` template (rings to 20 and 32 px, 0.22 s, 3–5 fragments), chosen at
      the hit site by `bullets.factions[index]`. 0.22 s is under the 0.25 s floor: exempted by name with
      the spec reference, and recorded as an amended assertion
- [ ] Cap of 24 enemy impact EVENTS, dropping the oldest: a FIFO of events inside `CombatFX`, each the
      slots it spawned with a generation guard against slot reuse; `enemy_impacts_retired` counter
- [ ] Core clip with no new draw call: enemy-impact instances (rings and fragments) carry the player
      core's centre in instance-local space in the two unused custom floats, a sentinel meaning "no
      clip"; `fx_instances.gdshader` zeroes coverage inside the 14 px disc. Ships with a GPU test
- [ ] Shader tail on plain shots in `projectile_instances.gdshader`: the quad extends back along
      −velocity, 4–6 discrete steps of width and alpha (no gradient), length `min(L, speed·age)` so it
      never pokes out behind the muzzle; uses the unused kind-0 custom floats; no new instances
- [ ] `player_damaged(amount)` signal from `_damage_actor`'s player branch → `main.gd` pulses
      `energy_bar` for 0.2 s, outside the 10 Hz HUD throttle
- [ ] Interior structure above 7 px: confirm by GPU test that an ENEMY rocket and seeker render it
- [ ] Proof — acceptance 5: GPU test lands 40 enemy impacts on the player in one tick and samples the
      14 px core disc against a measured no-impact baseline, relative threshold (control: clip off).
      Cap: spawn 40, ≤ 24 live events and the survivors are the newest (control: cap off). Template
      numbers, tail length at age 0 and at full length, pulse fires once per hit, each with its own
      control — and none copied from the tautological `combat_fx_test` controls P10 flagged. FX-disabled
      trace byte-identical. Rendered-frame benchmark ×3 at 2000 bullets against I0 (tail overdraw is the
      risk); budgets restated only from measurement. I0's census re-run. Gates; commit

## I4 — Prong out, Arc Tether in: amendments to S7 / S10 / S11 / S12 (no phase of its own)
- [ ] **S7 batch B, `arc_tether`** takes the improvements spec's behaviour: anchor at 600 px/s, stops at
      400 px or on the first enemy circle (a static world point — "pin and burst" is the one that
      sticks); line live 3.0 s; 45 DPS×dt along it each tick with a fresh hit set, through
      `_damage_segment`; 20% slow via a `slow_amount` on the single `_slow_multiplier` choke point (max
      wins, still capped at 30%, poison keeps 0.30); breaks beyond 520 px; re-firing recalls; 4.0 s
      cooldown; integer-tick timers; state in `ACTOR_ALLOW`. The line is STRAIGHT in the sim and drawn
      straight (hitbox and pixels agree); "bends" is a render-only sag ≤ 3 px, measured
- [ ] **Before S11 deletes anything:** fix `bot_pilot.gd` to fire secondaries (census control: secondaries
      off); add `player_distance` to `CombatWorld`; measure the prong baseline — distance per minute and
      damage per activation for a standing bot and a circling bot, 20 seeds
- [ ] **S10 roster:** `hook_node` on mobile hulls that carried the prong (drones, chains, elites, the
      Lightning boss's turret hubs); sentries mount `explosives`, and enemy-fired explosives aim at the
      target's position within a max range instead of a fixed 260 px ahead, so
      `enemy_ai_test`'s sentry telegraph ≥ 0.5 s holds (measured: 1.2 s)
- [ ] **S11/S12:** `laser_prong` row, `.tres`, the `"laser"` telegraph kind (queue arm, damage branch,
      draw branch), dead `ELITE_WEAPON_ROTATION` and `_reward_for`, and the four laser checks in
      `combat_tests.gd` go; `_queue_attack`, `_update_telegraphs`, the ring draw branch, `_ray_end`,
      `_damage_segment` and `segment_circle_t` STAY (explosives, mines, beams)
- [ ] Proof — acceptance 6: `no_prong_test.gd` scans `scripts/ content/ shaders/ scenes/ tests/` and the
      live docs for `laser_prong`, `prong` and the `"laser"` kind; control: a planted fixture string.
      History rows in this file are history and stay — said plainly in the review. Acceptance 7 is a
      human criterion; the bot proxy is the incentive gradient — tether damage per activation circling ÷
      standing, against the same ratio for the prong baseline, 20 seeds, median and worst (control: DPS
      made independent of the line's sweep). The hands-on check goes in `docs/ACCEPTANCE_HUMAN.md` (S13)

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

## Review — S0 (ship design spec: spec, reference, baselines, honest instruments)
| What | Measured |
|---|---|
| Spec | v1 arrived first and v2 replaced it in full the same day, before any v1 code existed. `docs/LIGHTSHIP_SHIP_DESIGN_SPEC.md` is v2 byte-for-byte under the approved-scope header; V3 §14/17/18/21/22 carry supersede notes |
| Reference image | `tools/measure_reference.py` (numpy Hough + least-squares refit) → `docs/ship-design-reference.json`. 22 circles; hubs 15.00 / 15.02 / 15.02 units; pods 6.95–7.22; inner rail dashes at 51.5 (order 4), outer at 95.4 (order 3, hubs at 92.9); pods 29.4–30.3 from the hub at 0° and ±51–52°; inner core ring 17.0 and dot 2.6 (both off the ladder: the image predates it). The `v_rack` is a yellow V plus a red pin ending in an r 5.2 ring, not the "red V" of the prose |
| Census tool, how its thresholds were set | First run found NOTHING: I assumed a perfect rim scores ~1.0; measured, real circles peak 0.44–0.52 and clutter ≤ 0.31, so 0.40. Five false circles (V lines closing a loop with the hub rim; an arm and a node spoke 3 px apart) matched real occluded pods on every fit statistic, so they are rejected structurally ("centre inside a larger circle", "weak AND hollow"). The first "inside" rule asked for full containment and missed one by 0.1 px. Rails: real 0.39 / 0.43 lit, next strongest 0.15, threshold 0.25. Overlay looked at: every circle and both rails sit on the drawing |
| Pillar-5 instrument (P10: blind) | Was blind three ways: the player stood IN the sampled patch, only plasma was tested, and hue alone is meaningless for silver. Repairing it exposed a fourth: one rendered frame after a MultiMesh write is not enough, so readings were a blend of this bullet and the last, and which elements read wrong changed between runs. With two frames, identical over 3 runs: distance from the player's projectile fire 1.090, lightning 0.941, corruption 0.569, void 0.433, plasma 0.407; second player projectile 0.000. Threshold 0.20. Controls 6/6 (adds "empty patch is not 'not blue'") |
| Light-chasing bot (P10: tautological) | Old gate: medians with capped runs folded in, control on different seeds. New: paired per seed, a capped run is a failure. Chaser unlocks fire in 16/20 seeds, indifferent in 5/20; chaser sooner in 12, later in 0, tied 8. The old median would have read the wrong way: unlocked-only medians are 9.2 s (chaser) vs 3.1 s (the indifferent walk's few lucky seeds). Control (preference off on both sides): 0 vs 0 |
| Acceptance bot, other lines (baseline) | novice first evolution 20/20, median 20.7 s, max 47.7 s, deaths median 0 / max 1; perfect median 5.2 s, max 10.8 s; camper 6.4 vs pusher 60.05 light/min; death-to-flying median 558 ms, max 683 ms. 11 checks, 3 controls caught, 292.6 s |
| Benchmark sections | `motion` was never timed (it ran before the first `section_start`). Now timed, with `grid` split out; a gate line fails an absent or zero section; control `--require-section=not_a_section` fails exactly its own 2 lines and leaves the 4 real ones ok=1 |
| Headless benchmark ×3 (baseline) | 1000 bullets: mean 5.11–5.47, p95 8.13–8.71 ms. 2000 bullets: mean 7.45–7.81, p95 10.46–11.14 ms. Sections at 2000: bullets 4.00–4.20, ai 1.31–1.37, upload 1.09–1.14, grid 0.37–0.39, **motion 0.157–0.168**. Budgets unchanged |
| Roster census (baseline, `tests/roster_census.gd`) | 141 hulls. Footprint / circles: drone 49–95 / 4–10; sentry 48–63 / 5–8; chain 124–139 / 8–11; radial elite 210–396 / 16–22; irregular elite 204–390 / 25–38; boss 196–228 / **13**; player T1 53 / 4, T6 72–366 / 25–37 |
| P10 open items, triaged | **Fixed here:** pillar-5 instrument; light-chasing control and median. **Superseded by the rebuild:** breathing scale vs collider (v2 has no scale), reshape ignoring the pose (S3 GPU reshape), missing reach rings and motionless drones (every rail draws its ring and moves), `turret_ring` / thin enemy-only components / bosses without body features (all retire at S11), `standard_a` = `standard_b` geometry (S10 distinct-shape test). **Still open:** the other tautological controls (`combat_fx_test` ×3, `enemy_parts_test`, `enemy_ai_test`, `hud_model_test` overlap and diagonals), no inverted warp, respawn records outside the snapshot, dead code, trails not a MultiMesh, warp streak geometry, `run_controller.gd`, unprofiled tick remainder, p95 frame tail, no Steam Deck measurement |
| P6 bookkeeping | Ticked with its own review, from commit `382a40e`'s contents |
| `tools\gates.ps1 -GPU -Exports` | 13/13 ok in 766.5 s (12 before; +1 is the untimed-section control, caught 2/2 with the 4 real section lines still ok). Suite 38/38, golden trace NOT re-recorded (the two new timers only run under `profile_sections`). Rendered frame (30 s, 2000 bullets, 400 pickups, 17 actors): mean 8.14 ms, p95 15.72 ms against 14.0 / 26.0. Both Windows exports built and verified 2/2 |
| Not completed / stated plainly | The rendered-frame benchmark and renderer profile baselines are taken from the gate run, not three separate runs. The `hud_model_test` diagonal fix the design notes suggested for S0 was not done; it stays on the open list. The reference census trusts one image at one scale; its ±0.3-unit agreement with the ladder on hubs and pods is the evidence that the scale basis (core_1 = 34) is right |

## Review — S1 (behaviour-neutral seams)
| What | Measured |
|---|---|
| `Elements` | One source for the wire order and the six colours; `ShipCatalog`, `CombatWorld` and `combat_canvas` alias it; `"blue"` added to the palette. `elements_test`: 24 checks, 3 controls. It keeps one duplication on purpose (`RIM_BY_INDEX`, a plain array the canvases index by a bullet's element int) and tests it against `RIM` with a swapped-entry control |
| Forward-kinematics evaluator | `_step_fk` beside the untouched `_step_legacy`, chosen by `schema_version >= 4`. Confirmed by reading `_build_rig` first: v0.3 groups do NOT compose (innermost group owns a circle, posed from rest positions), so a bobbing pod on a moving hub was unrepresentable. One rule now: angle = parent's + spin·t + bob; offset from the LIVE parent, pumped. `ship_fk_test`: 19 checks, 6 controls — hub angle error ≤ 1e-4 rad and pumped-radius error ≤ 1e-3 px over 10 s; pod within 1e-3 px of "30 px from the live hub at hub angle + bob" (control: pod re-parented to the core); acceptance 4's excursions measured headless: bob ≥ 0.27 rad and pump ≥ 5.8 % peak-to-peak (controls: each amplitude zeroed); scale never leaves 1.0; aim joint holds a given aim and points outward without one (control: joint removed); pose is a pure function of the tick |
| `ShipGrammar` | Ladder, rails, §4.4 cluster layout and every §9 default as data (`MOTION`), frequencies in rad/s as the spec writes them. Writing the "five pods" control found a real bug: the fan clamped its loop but centred on the unclamped count |
| `solid` | Rig `solid` / `solid_indices`; the broadphase walks them (identical order for v0.3, where every circle is solid); `_configure_parts` gives a non-solid circle no HP (hence no reward share) and no gun. Exercised on the FK fixture only — no shipped hull has a non-solid circle until S11 |
| One pose per actor | `ShipRenderer.external_pose`, handed over by `_step_motion` every tick; the renderer reads it and skips its own evaluation. **The pixel test caught a bug in the seam itself:** `set_ship` uploads once from the renderer's own pose, and the upload's dirty check keyed on the tick alone, so a pose handed over at the same tick was skipped and the hull drew at rest. Fixed by adding the pose's identity to the check — the same class of bug as the P8 flare dependency. `ship_motion_render_test`: +2 checks, +1 control (a misfit pose is ignored), 2/2 caught |
| `_rig_to_mesh` | Per-frame id-string Dictionary lookup replaced by an index map built once per hull. `ships_renderer_profile` (20 T5 hulls, 2 runs each, same machine, minutes apart): `mean_process_ms` 1.18 / 1.24 before → 0.86 / 1.02 after |
| Behaviour-neutral proof | Suite 40/40 with GPU (38 + `elements_test` + `ship_fk_test`); golden trace passes WITHOUT re-recording; `content/` untouched |
| Lesson recorded | I edited three GDScript files with a Python read-replace-write. Byte-safe, and it still failed halfway: the third file did not match, after two were already rewritten. Edit refuses before touching anything. In `tasks/lessons.md` |
| `tools\gates.ps1 -GPU -Exports` | 13/13 ok in 771.0 s; suite 40/40. Headless 2000 bullets: mean 7.00, p95 9.80 ms (S0: 7.45–7.81 / 10.46–11.14). Rendered frame: mean 7.65, p95 14.89 ms (S0: 8.14 / 15.72). One run each, so "no regression", not "faster" |
| Not completed / stated plainly | The renderer profile has no sim, so it measures the index map and NOT the saved second evaluation; that saving shows up only in the rendered-frame gate, which is dominated by other work. Chains and the aim SLEW are not here: both are stateful and belong with the sim in S3; S1 only gives the aim joint its input array. The 2-run profile comparison is small-sample: it shows direction, not a budget |

## Review — S2 (grammar, compiler, validator, first set pieces, rail rendering)
| What | Measured |
|---|---|
| Schema 4 | `RailDefinition`, `SlotDefinition`, and the grammar fields on `ShipDefinition` (colours, `core_depth`, `core_weapon`, `archetype`, rails, chain links). `ShipCatalog.refresh` compiles a rail hull on load, `save_ship` strips the derived parts, `validate`/`warnings` dispatch on schema. No shipped hull is schema 4 yet: `content/` is untouched and the golden trace passes without re-recording |
| `ShipCompiler` | Grammar → parts in PAINT order (rings, spokes and links, core, passives, nodes and pods, hubs, set-piece lines, set-piece circles), because the mesh bakes a rail hull in part order. Positional ids; hub is the mount; rails 1–2 spoke to the core, 3–4 to the inner ring. `ship_compiler_test`: 54 checks, 3 controls over five fixtures — each validates with no warnings, compiles to the same bytes twice, has unique ids, a `budget()` equal to the compiled counts, and a rig that walks only the solid circles. It passed on its first run |
| Circle budget, measured (`tests/fixture_census.gd`) | circles / lines / solid / footprint: drone 9 / 6 / 4 / 112 px; player T3 24 / 14 / 13 / 263; radial elite 29 / 25 / 17 / 266; irregular 49 / 33 / 23 / 373; boss **101** / 71 / 48 / 438 of 128 (13 hub pieces + core weapon, 2 pods per hub). I first wrote this row from memory (14 / 40 / 52 / 104) and every number was wrong. Four pods on every boss hub is still legal, which I only learned when my over-budget control stopped failing; it now also mounts five-circle pieces. Against S0's census the rebuilt drone is 112 px where today's are 49–95, and the boss 438 where today's are 196–228 |
| Set pieces | All 33 authored now, not just the three S2 needs, because the format was the hard part: per-primitive intrinsic colours, lines that may start at the hub's centre. `v_rack` is traced from the census (red r5 ring at 22 on a red pin); its yellow V ends on two rim beads because the image's V runs to the PODS, which bob while a piece tracks the aim |
| Validator | 22 coded rules in `ShipGrammar.RULES`. `ship_grammar_test`: 52 checks, **44 controls**, one mutation each through the real validator, asserting THAT rule's code; a final assertion requires every rule to have been triggered. Behavioural control: the SYM-ROT mutation is legal on an irregular elite. `illegal_mounts()` is the one function behind both COLOUR-GATE and the editor's future Colours tab |
| Shader | Style 4 (thin passive ring), style 5 (rail: 1 px, 2 on / 5 off, 28 %, no running light), line kind 2 (starts at its hub's centre). `rail_render_test` (GPU): rail ring lit over 0.252 of its circumference with peak 1.08 against a core rim's 0.970 and 3.65; the `v_rack`'s red pin is visible INSIDE the hub; controls for each (ring drawn solid; lines clipped at the rim) |
| Pillar 5, ship rims (carried from S0) | Same metric and threshold as the projectile lines. Distance of each chassis rim from the player's: red 1.165, yellow 1.046, green 0.670, silver 0.561, **violet 0.423**. Second player hull 0.000. Threshold 0.20. Silver is NOT the nearest on ships, violet is |
| Acceptance 1, automated | `ship_reference_render_test` (GPU): the reference PNG and the rendered fixture give the IDENTICAL signature through one probe — core rim at 34 units, 4-fold inner rail, 3-fold outer rail, pods [3,3,3], 3 armed hubs, red core, two colour families, no third. 8/8 sabotage controls, each moving its own line |
| The probe, how it went wrong first | It counted BRIGHT lobes and read the reference as 0 inner / 1 outer: a circle here is a dark fill inside a thin rim, so a ring crossing it sees two 2° hits. It now asks "inside a shape?" (max channel > 0.12; background 0.08, fill 0.16), and only clusters answer widely |
| Review capture 1 (looked at) | `artifacts/acceptance/reference_vs_render.png`: reference, render, onion skin. Structure matches. Differences, all recorded decisions: our hubs sit on the 96 rail (image 92.9), pod fan 0.78 rad (image 0.90), inner core ring 22 (image 17), dot 5 (image 2.6), two yellow beads on each hub rim. First capture looked unfilled: the HDR viewport is linear and I had not converted; `Image.linear_to_srgb` only takes 8-bit data, so it is done per pixel |
| A rule read from the image | The first render drew the core weapon's set piece over the core, which the reference keeps clean. Rule adopted: a core of depth ≥ 3 has an accent inner ring and THAT marks the core weapon; only a depth-2 core (drone, sentry) draws the piece |
| `tools\gates.ps1 -GPU -Exports` | 13/13 ok in 774.9 s; suite 44/44 (S1's 40 + `ship_compiler_test`, `ship_grammar_test`, `rail_render_test`, `ship_reference_render_test`). Headless 2000 bullets mean 7.35 / p95 10.12 ms; rendered frame mean 9.37 / p95 17.19 ms (S1: 7.65 / 14.89, S0: 8.14 / 15.72 — single runs; no rail hull is in play yet, so this spread is run-to-run noise, and it is wide) |
| Not completed / stated plainly | Chain hulls compile (links trail the core) but have no fixture and no test until S3 gives them motion. The core-dot pulse is not here: the fragment shader assumes the quad's extent is `core_radius + 0.75`, so it needs a shader change and lands in S3. `compile_key` is set but no cache keys on it yet (the rig and mesh keys still serialise parts) |

## Review — S3 (rails in combat)
| What | Measured |
|---|---|
| Behaviour-neutral | Every change is behind `rig.legacy == false` or a declared `archetype`, and no shipped hull has either. Suite 47/47 with GPU; golden trace passes WITHOUT re-recording. v0.3 debris still makes its single RNG draw |
| Mounts and muzzles | `_muzzle` used to find a mount by treating its NAME as a circle id, which cannot work once ids are positional. Rail hulls resolve through a mount table; mirror twins share one mount and take turns. `rail_combat_test`: the muzzle is the hub's live position (it moves as the rail turns), twins alternate, an unknown mount falls back to the hull's centre |
| Scenery carries nothing | On the radial-elite fixture in a real `CombatWorld`: rings, the inner core ring and set-piece circles have 0 HP and 0 reward share; the limb reward sits on solid circles; a hub's authored 60 hp is its HP; guns are exactly the three armed hubs. Control: the 96 px ring marked solid |
| Detachment and the rail ring | Killing a hub detaches 7 circles (hub + 3 pods + 3 set-piece circles), hides its spoke and kills its weapon. The ring stays while two hubs live and goes with the LAST one; rail 1's ring is untouched. **Found by the test:** `_destroy_part` keeps its own hidden list and never reached the rule I had put in `_rebuild_part_views`, so the ring outlived its rail. The rule now runs in both. Recorded deviation: a ring also stays while the rail just outside it (3 or 4) still spokes from it |
| Aim slew (§9.7) | Stepped once per sim tick, state in the pose, firing direction unchanged. A piece told to aim dead behind swings at exactly the limit (worst step = 3.0/60 rad, never more) and takes > 20 ticks to arrive. Control: a 10 s tick lets it snap |
| Core weapon | Decision-driven actors with guns never called `_fire_primary`, so a rail elite's core weapon would NEVER have fired. With its hubs silenced the fixture still fires bolts from its core; control: its archetype blanked (as on a v0.3 hull) fires nothing |
| Destruction (§9.8) | Rail debris inherits the rail's tangential velocity (leaves with speed though the hull stood still), spins 0.5–1.5 rad/s, drifts outward, pays its light at 0.5 s exactly once and is gone at 1.0 s. Control: asking for the light at 0.483 s |
| Chains (§9.6) | A pure function of the tick: each link swings about the one before it, 0.85 rad behind. First version measured tip 10.7 px (sway) and 24.9 (whip) against the spec's 6 and 14: I had divided by rest × N, ignoring that each link's swing carries every link after it. Dividing by the weighted phasor sum gives **6.50 and 15.13**; rigid 0.00; head 1.55; link stretch 0.0000 |
| Acceptance 2 (`ship_ladder_render_test`, GPU) | Hub span 29.71 / 29.84 / 29.95 px on elite, boss and player; core 68.08 / 68.08 on drone and boss; at zoom 0.6561 hubs 19.52 / 19.61, ratio 0.6569; same hub at tick 137: 29.83 (nothing scales). Controls 4/4: a 16 px hub on one ship, a 16 px hub outright, the wrong zoom, a hub scaled 1.05 as v0.3's breathing did. **The ruler was wrong first:** scanning horizontally it read the boss's core as 71.7 px because a spoke lay along the scan; it now measures ACROSS the arm |
| Acceptance 3 (`ship_motion_law_test`) | Structural, as approved: over five fixtures no two shining circles share a (period, phase), no two rails share a speed, neighbours counter-rotate, every shine laps at §9.4's period for its radius. 24 checks, 3 controls |
| Acceptance 4 | The headless excursions were measured in S1 (`ship_fk_test`: bob ≥ 0.27 rad, pump ≥ 5.8 %) |
| Shine, pulse, reshape | The compiler assigns shine period by radius and the (part, cluster) phase rule. Core pulse: `core_pulse` / `core_quad` uniforms, quad baked for the 1.22× peak, render-only (the pose's core scale stays 1.0). A rail hull's shine and pulse run from the sim tick. A rail hull never takes the CPU reshape tween (one polyline per dash: ~190 draws a frame for a 184 px rail); it swaps meshes at once |
| `tools\gates.ps1 -GPU -Exports` | 13/13 ok in 893.1 s; suite 47/47 (S2's 44 + `rail_combat_test`, `ship_motion_law_test`, `ship_ladder_render_test`). Headless 2000 bullets mean 8.15 / p95 10.89 ms, `motion` 0.177 ms (S0 0.157–0.168: the legacy branch now pays one `rig.legacy` test per actor; within noise, and no rail hull is in play). Rendered frame mean 8.36 / p95 16.37 ms |
| Not completed / stated plainly | **No GPU reshape with a ghost mesh**: the plan promised one; rail hulls swap instantly instead, which is cheaper and avoids off-ladder radii mid-morph, but an evolution no longer morphs. **Follow-the-leader chains are not built**: the wave is a pure function, so a chain's tail does not trail the path its head flew; the spec's §9.6 has both. **§9.8's 0.10 s collapse and 5–7 fragments** use the existing destruction FX unchanged. **No GPU test of the core pulse or of a set piece staying aim-aligned on screen**: both are covered headless only. The marking-to-shot angle at fire events is not yet measured; that needs the roster (S10). The audit of `part_hp <= 0` readers: nine sites in `combat_world.gd` (beam 1132, guns 1242, `_damage_part` 1263/1272, radial blast 1496, bullets 1589, mounts 995/2167, rails 517), read one by one; every one SKIPS a circle at 0 HP, which is the right behaviour for scenery. Read, not tested |

## Review — S4 (the 33 set pieces and the colour gate)
| What | Measured |
|---|---|
| Catalogue | All 33 were authored in S2; this phase proves them. `set_piece_test`: 156 checks, 5 controls. Every expectation is written out from the spec IN the test (§6.3's colours and slots, §6.5's five pools of seven), never read back from the table under test: 33 ids, 18 mono + 15 two-colour, 33 different weapons, 2–5 circles each, every radius 7 / 5 / 4, every line between two of its circles or from the hub, every declared colour used and no other |
| The gate | `legal_for("blue", accent)` equals §6.5's list for all five accents; every mono ship has exactly three pieces; `v_rack` mounts on yellow + red either way round; ten hybrids carry no blue and are enemy-only. Controls: `v_rack` on yellow + green, on mono yellow, a blue piece on enemy colours, a piece that does not exist |
| 33 different shapes | Each piece rasterised with its hub on a 96 × 96 grid; pairwise differing cells. Closest pairs: `halo_node` / `iris_ring` 109, `halo_node` / `well_cup` 116, `bloom_pod` / `prism_stack` 135, `spore_rack` / `fin_trio` 141, `burst_ring` / `halo_node` 144. Threshold 55 (half the closest pair; one micro circle is ~25 cells). Control: a piece against itself |
| Unbuilt weapons | 20 of 33 pieces have no weapon behaviour yet, and the validator's SETPIECE-IMPL keeps them off every hull until S7/S8 build them: hook_node, spore_rack, spin_ring, halo_node, phase_pair, well_cup, iris_ring, pull_cage, storm_crown, coil_array, split_lance, web_node, node_pair, rift_pair, ember_rack, collapse_cage, flare_ring, leech_arm, mesh_node, prism_stack |
| Review capture 2 (looked at) | `artifacts/acceptance/set_pieces.png`, 33 pieces at 1× through the real compiler and renderer. All distinct, colours right, hub lines visible inside their hubs. **Seen in it:** on a ONE-pod hub the pod sits on the outward axis and forward-pointing pieces (twin_barrel, lens_stack, split_lance…) overlap it at rest. In play a piece swings to the aim so it is transient, but the roster (S10) should give armed hubs 2 or 4 pods, which straddle the axis, not 1 or 3 |
| Silver vs blue on pieces | Not re-measured here: S2 measured chassis rims (silver 0.561, violet 0.423 from player blue). A piece's circles draw through the same rim path in the same palette keys |
| `tools\gates.ps1 -GPU -Exports` | 13/13 ok in 871.5 s; suite 48/48 (+ `set_piece_test`). Golden trace not re-recorded; `content/` untouched |
| Not completed / stated plainly | The glyph distance is a CPU raster of outlines, not rendered pixels, so it does not see colour or fill; two pieces identical in outline but different in colour would read as the same. None are |

## Review — S5 (editor on the grammar)
| What | Measured |
|---|---|
| How it was built | By a subagent from a written brief, then reviewed by me: I read its test line by line, ran it, and ran the suite and the gates myself. Its own notes are inline in the S5 checklist above |
| The editor | `ship_editor.gd` 848 → 351 lines: a shell with ONE mutation choke point `edit(label, mutate)`, undo over whole-grammar snapshots, a compiled copy for the canvas and the two zoom previews. Six flat tab files (Core 117, Rails 128, Slots 121, Colours 94, Motion 91, Set pieces 20 lines). `ship_canvas.gd` is a ring diagram with a static, pure polar picker. `ship_authoring.gd` 397 → 98 lines: canonical §10 JSON, strict import through `ShipGrammar.from_dict`, the v2/v3 import paths deleted. `ship_object_card.gd` deleted |
| `ships_editor_test` | Rewritten, headless, against the real scene. One edit is one undo step; a new rail takes the next ladder radius and the opposite sign, and forcing the same sign raises both the tab's warning and the validator's RAIL-SIGN; an order change re-tiles slots; "apply to symmetric orbit" keeps a rail symmetric and turning it off produces SYM-ROT; a recolour is accepted, names the now-illegal `v_rack`, blocks the save on COLOUR-GATE, and Unmount all clears it; save refuses an invalid hull and a valid one is written with NO parts; JSON export → import → export is byte-identical for all five fixtures and a 0.001 rad nudge changes the bytes; the picker finds slots 0 and 2 and a click between rails selects nothing; a schema-3 `.tres` is refused; `export_presets.cfg` excludes `scripts/editor/*` |
| What my review changed | The palette check proved every legal, implemented piece was OFFERED but not that nothing else was — it would have passed a palette offering all 33. Added the converse; it passes |
| `tools\gates.ps1 -GPU -Exports` | 13/13 ok in 866.6 s; suite 48/48; golden trace not re-recorded; both Windows exports build and verify 2/2 with the six new `tab_*.gd` files present, so the `scripts/editor/*` exclusion covers them |
| Not completed / stated plainly | The test does not use the shared harness, so it prints no check or control count, and its "controls" are contrast checks inside one scenario rather than counted negative controls. No Motion scrub bar (that is the gallery's detail view, S6). No mirror-twin helper: a player's off-axis weapon must be placed symmetrically by hand. `from_description` is a stub until the generator (S9). The editor's library window is gone and Load Ship… is a plain file dialog until the gallery (S6). Nobody has LOOKED at the editor running: there is no capture of it yet |

## Review — S6 (gallery)
| What | Measured |
|---|---|
| How it was built | By a subagent from a written brief (this time requiring the shared harness and counted controls), then reviewed by me: I looked at its capture, fixed what the capture showed, and ran the suite and gates myself. Its measured notes are inline in the S6 checklist |
| The gallery | Pure `GalleryModel` (scan INCLUDING invalid files, metadata, §12.3 filters / sorts / search, roster coverage, the "≤ 24 animating, nearest-to-centre" scheduler as a pure function, a name+mtime signature polled each second for live reload) and flat views: contact sheet, tile, detail (part tree, detach preview from the rig's `subtree_size`, weapon legality, motion panel with a tick scrub bar, silhouette), compare, coverage → editor pre-seed. It lists schema-3 and rail hulls alike and works on any catalog root |
| Tests (the subagent's numbers, from its printed output) | `gallery_model_test`: 54 checks, 17 controls. `gallery_render_test` (GPU): 3 controls — an animating tile's pixels differ 0.19 between ticks against 0.00003 for a frozen one; the detach highlight reddens hub `r2s0`'s cluster by +0.053 and leaves `r2s1` at 0.00 (acceptance 7); every tile reads 0.06–0.30 against 0.006 with its renderer hidden |
| What my review changed | Looking at `gallery_roster.png` showed two faults the tests did not: a FOUR-column grid overflowed the 1280 px window and clipped the last column, and the export saved one screen — 8 tiles of 141 — which is useless as the review mechanism this gallery exists to be. Now three columns, and the export pages through the scroll and stitches: the shipped roster is one 1280 × 14848 PNG from 23 pages. A middle slice was looked at: clean seams, every tile drawn with its metadata |
| Review capture | `artifacts/acceptance/gallery_roster.png` (today's 141 schema-3 hulls). The staging roster's sheets come in S10 |
| `tools\gates.ps1 -GPU -Exports` | 13/13 ok in 857.8 s; suite 50/50 (+ `gallery_model_test`, `gallery_render_test`); golden trace not re-recorded; exports verify 2/2 |
| Not completed / stated plainly | **Acceptance 6's human half** ("a designer can find a specific model in under ten seconds") is not measured; search and nine filters exist and are tested, which is the proxy. The gallery's frame cost with many live tiles was NOT measured. The paged export has no automated test (it is a capture path; it was verified by looking). `tests/ships_render_smoke.gd`, an older ungated capture script, still calls the previous gallery's API and is now broken; it is superseded by `--gallery-export` and should be deleted in S12. Nobody has clicked through the detail view, compare mode or coverage grid by hand: they are covered by the model and pixel tests only |

## Review — S7 + S8 (the twenty new weapons, in one phase)
| What | Measured |
|---|---|
| Why one phase | The plan split them into "cheap" and "telegraphs and the hot loop". Built from existing machinery, only ONE of the twenty touches the per-bullet loop (one flag test for `phase_shot`), and the black-hole pull runs in its own pass that costs nothing while no black hole exists. So there was no second risk tier to stage |
| The weapons | 20 rows in `AbilityCatalog.DEFINITIONS` (26 → 46) and 20 cases in `_activate_component`, all from `_shoot`, the telegraph queue, clouds, drones and the virus list. New telegraph kinds `nova` and `spore`; tethers are virus entries with `kind`, a lifetime, a break range and a draw-in warning; bullet flag `PHASE`; `AbilityCatalog.is_continuous`. Additive: no shipped hull mounts one, and the golden trace passes WITHOUT re-recording |
| `weapon_behaviour_test` | 65 checks, 7 controls, a fresh world per weapon. Each of the 20 produces ITS effect and is counted once in the play census; the same cast with `radar` produces nothing. Specifics: overcharge's FOURTH shot, and only it, is triple and chains; 520 phase shots fanned across an elite cost its limbs nothing while the same fan as `pulse_cannon` does; an arc tether hurts while it holds, snaps out of reach, lets go after 3 s, and does not attach at 900 px; `siphon_tether` returns light; a black hole drags a hostile in reach and its counter recounts to 0; a nova releases 24 shots only after its warning; spores bloom into three clouds |
| v0.3 §16 (warn ≥ 0.5 s) | An ENEMY's `discharge`, `collapse_charge`, `nova_pulse`, `refract_beam`, `arc_tether` and `siphon_leech` never cost the player light before 0.5 s. Control: a tether with its draw-in zeroed hurts at once |
| A v0.3 bug fixed on the way | A plain virus latched onto the PLAYER never expired ("until it dies" — and the player does not). It lets go after 4 s now; on enemies it is unchanged. The trace did not move |
| Test mistakes of mine, both caught by running it | The siphon check started the player ABOVE the tier-1 bar's capacity, so no light could be returned (400 → 400); then it tethered to an enemy four seconds of arc tether had already killed (30 → 30). It now starts from a low bar with a fresh target |
| `set_piece_test` | All 33 pieces now report implemented. `ship_grammar_test`'s SETPIECE-IMPL control therefore has NO live subject any more (the ability table is a const and cannot be sabotaged from a test); the rule is exercised only by its own code path having run in S2–S6 |
| `tools\gates.ps1 -GPU -Exports` | 13/13 ok in 856.7 s; suite 51/51 (+ `weapon_behaviour_test`); golden trace not re-recorded |
| Benchmark: slower than S0, and NOT because of this phase | The gate read 2000-bullet mean 8.84 / p95 13.65 ms against S0's 7.45–7.81 / 10.46–11.14, with `bullets` 4.69 against 4.00–4.20. Every section had risen by the same ~12 %, INCLUDING `ai` and `grid`, which this phase does not touch. So I measured instead of theorising: three standalone runs WITH the weapons, mean 8.33 / 9.05 / 8.54; then the previous commit's code, shelved in and measured minutes later on the same machine, mean 9.50 / 8.97 / 9.02. The old code is no faster today. The machine is slower than it was at S0 (a second Claude session is building P11 in a worktree and may be running Godot); the `phase_shot` flag test and the black-hole pass cost nothing measurable. Budgets NOT changed. **S0's baselines are no longer comparable with today's machine: S10 must take a same-session before/after, as this row did** |
| Not completed / stated plainly | These are FIRST-DRAFT weapons, numbers untuned (S14). Simplified against the design notes: `void_orb` is a slow heavy shot, not a piercing damage-over-time orb; `pulse_ring` fires outward at once rather than orbiting first; `collapse_charge` does not pull during its warning; `ignition_lance` is a short beam with no burn; `blink_mine` does not relocate; `refract_beam` bends once toward the nearest hostile; enemy bullets do not yet take their firing piece's colour. None of the twenty has its own FX template or sound. No weapon has been SEEN in play: the census proves each fires from a unit cast, not from a hull in a fight (that is S10) |

## Review — S9 (generator)
| What | Measured |
|---|---|
| One engine | `ShipRecipe.generate(params)` builds a spec-§10 dictionary and hands it to `ShipGrammar.from_dict`. Anything in `params.pins` replaces the generated value key by key, so a roster entry (structure pinned) and a generated ship (structure from the seed) go through the SAME code path. Own `RandomNumberGenerator`, no clock, no unordered iteration. `style_check` = the validator's errors + circle count within ±20 % of the archetype's target + every rail has its reach ring + the core dot exists and pulses |
| `ship_recipe_test` | 31 checks, 7 controls. 20 seeds × 7 archetypes × a spread of 10 colour pairs: all 140 pass validate, the style check AND the archetype-table warnings with no edits. Same seed → same bytes; a different seed differs. Irregular elites turn 10–25 % of their slots to stubs. Pinned rails are used verbatim under any seed. One control per style rule (count, ring, colour gate, adjacent order, rail sign, off-ladder node), each naming ITS rule |
| Circle targets are measurements | First draft targets were my guesses (9 / 22 / 32 / 66 / 58 / 14 / 101) and four were wrong. Measured medians over 20 unpinned seeds: drone 8, sentry 19, radial elite 26, heavy elite 57, irregular elite 68, chain 16, boss 99; the test asserts the constant equals the measured median, so it cannot drift silently |
| The generator had to AIM | Set pieces run 2–5 circles, so a free draw missed the ±20 % band: sentry 17–24 about 19, radial 23–32 about 26, irregular 52–87 about 68. `generate` now re-draws from the same RNG stream (deterministic) until the count is in band, at most 24 draws. After: sentry 17–22, radial 23–29, irregular 55–81, boss 82–114 about 99 |
| The player roster | All 101 player hulls (5 elements × tiers 2–6 × 4 families + the seed) validate — mirror axis at rest, primary on the forward line on a rail that stands still, slots within `GameTuning.slots` — and every one mounts something in its accent (the player's dot is white, so only a set piece can show the element). **A tier's four offers are four different shapes AND four different loadouts**, which closes v0.3's open "standard_a and standard_b share geometry" item. The first run found THREE shapes at tiers 2–4 (heavy = standard_a below tier 5; standard_a = standard_b at tier 2): heavy hulls now carry four pods at every tier and standard_b's tier-2 rail is order 5 |
| Description → template (§13.1) | "yellow red radial elite t4, artillery platform, heavy rockets, slow" resolves to radial_elite / yellow / red / tier 4 / the given seed. First run resolved it to HEAVY elite: the theme word "heavy" overrode "radial". The first archetype named wins now; a theme never touches structure. Unknown words are reported ("platform"), and a "rockets" theme mounts more `v_rack`s over 40 seeds than no theme |
| Editor | Generate is wired to the recipe: the text resolves, the ship is built, and pressing Generate again draws the next seed |
| `tools\gates.ps1 -GPU -Exports` | 13/13 ok in 906.7 s; suite 52/52 (+ `ship_recipe_test`); golden trace not re-recorded; `content/` untouched |
| Not completed / stated plainly | **Acceptance 8's human half** (a designer cannot pick generated ships out of a line-up) needs the roster and the gallery's contact sheet; it is S10's capture. The gallery's coverage cells pre-seed the editor with element / tier / archetype, but do not yet call the recipe to fill the hull. Enemy hubs always carry 2 pods except on irregular elites: §13.9's "1–4 per hub" is narrowed on purpose (S4: a lone pod sits in a forward piece's way). Chains and sentries have fixed layouts; only their pieces, speeds and phases vary with the seed |

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
| S0 | `combat_fx_render_test.gd` "enemy plasma projectile's pixel hue sits outside the player's light-blue band" (hue distance > 1/24, plasma only) | Blind: the player's white core was in the sampled patch, so every element read alike; hue alone cannot judge void's near-grey silver | Five lines, one per element: max-normalised RGB distance from the player's own projectile > 0.20 (measured 0.407–1.090), sampled two rendered frames after the buffer write |
| S7 | `combat_tests.gd` "All 26 specified components have canonical metadata" | The ship design spec's catalogue adds twenty weapons | Restated as 46, exact |
| S7 | `ships_validation.gd` "Shipped roster exposes <component>" for EVERY non-enemy ability | The twenty new weapons are mounted by no v0.3 hull on purpose; they reach the game with the rail roster at the cutover | The line still holds the v0.3 roster to the v0.3 components, and now also asserts that no v0.3 hull mounts a new one; the rail roster's own coverage is `ship_library_test` (S10) |
| S0 | `acceptance_bot.gd` `light_chasing_faster_than_indifferent` (median chaser < median indifferent) | Medians folded capped runs in; its control compared two indifferent walks on different seeds | `light_chasing_unlocks_at_least_as_often` (16 vs 5 of 20) and `light_chasing_sooner_in_more_seeds` (12 / 0 / 8 ties), paired per seed; control pairs the indifferent walk with itself |
