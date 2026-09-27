# Lightship v0.3 validation record

The latest presentation and geometry work is recorded in [Living ships validation — 2026-09-27](VALIDATION_LIVING_SHIPS_2026-09-27.md). The earlier [presentation redesign record](VALIDATION_PRESENTATION_2026-09-27.md) and September 20 record below are historical and do not establish verification of the current presentation.

Recorded 2026-09-20 (P9, `lightship-v0.3`). This record describes the historical source after P0–P9 of `tasks/todo.md`'s rewrite (two primitives/motion evaluator, six tiers/141-hull roster, per-circle enemy HP, five bounded Chebyshev levels, campaign/dev/demo modes, save schema 4, momentum/dash/trails/warp, the pace system, attack/impact FX, and this phase's narrative/demo/docs/exports work). The v0.2 record is archived at [VALIDATION_V02.md](VALIDATION_V02.md) and does not establish v0.3 correctness.

**Every number below is either measured in this session or is a direct citation of a number already measured and recorded in `tasks/todo.md`'s per-phase "Review" tables** (P0 through P8, plus this phase). Where a v0.2 claim (in `VALIDATION_V02.md`) is no longer true of the v0.3 build and has not been re-measured, this record says so instead of copying the old number forward. P10 (adversarial review) has not run yet; nothing here should be read as that review's conclusion.

## What changed, and the review section that measured it

| Area | What it is now | Where it was measured |
|---|---|---|
| Ship model | Two primitives (circle, line), a parent graph, `ShipMotion` groups, six tiers, TP 36/tier-6 cap 2300, 141-hull roster (101 player) | `tasks/todo.md` "Review — P2a-1/P2a-2", `ship_roster_test.gd` (825 checks, 14 controls) |
| Node geometry | Circular arena, analytic `boundary_hit`, membrane arcs on open exits only | "Review — P3", `arena_test.gd` (21 checks, 4 controls), `arena_render_test.gd` |
| Enemies | Per-circle HP, detachment/debris, archetypes (drone/sentry/chain/radial/irregular/boss), 150-300 ms reaction lag, 2-5 deg aim error, shielded/multi-cored bosses | "Review — P4b", `enemy_ai_test.gd` (41 checks, 10 controls, all green in this session's run) |
| World | `CampaignState` v4, Chebyshev rings, bounded discs per level (radii 6/8/9/11/12), membrane construction, absorb-to-unlock | "Review — P5a", `world_generation_test.gd` (200 seeds x 5 levels) |
| Modes/saves | `ModeConfig` (campaign/dev/demo), save schema 4 + `.legacy-v3`, `MinimapModel`, dev console | "Review — P5b", `save_migration_test.gd`, `mode_isolation_test.gd`, `dev_console_test.gd` |
| Handling/warp | Momentum, dash (no i-frames), pooled trails, warp state machine, reduced-warp option | `handling_test.gd` (12 checks), `warp_test.gd` (19 checks), `warp_render_test.gd` — all green this session. **Note:** `tasks/todo.md`'s own P6 checklist is still shown unchecked even though this code and its tests exist and pass; that is a stale checklist, not a missing feature, and is left for P10 to tidy rather than fixed here (out of this phase's brief) |
| Pace/death loop | Decay, combo, sized pickups, node respawn, frictionless 1.2s death card | "Review — P7", `tests/acceptance_bot.gd` → `artifacts/acceptance_v03.json` |
| Attack/impact FX | Pooled `CombatFX`, target rim flare, dark collar, per-weapon projectiles/trails | "Review — P8", `combat_fx_test.gd` (24 checks), `combat_fx_render_test.gd` |
| Narrative | `scripts/ui/dialogue_director.gd` (queue, dedupe, immediate lane), boss-encounter/defeat/unlock/regression/reboot lines | This phase, below |
| Demo | Levels 1-2 (Lightning/Fire), no tier cap, ending on the level-2 boss, import into campaign | This phase, below |

## Narrative (this phase)

`scripts/ui/dialogue_director.gd` is a pure `RefCounted` extracted from `scripts/main.gd`: it owns `line_queue`, `seen_lines` (per-id dedupe), the between-fights gate, and the two static line tables (`entry_line`, `defeat_line`, keyed by rival element). `main.gd` keeps `seen_lines`/`line_queue` as forwarding properties (`get`/`set` delegating to the director's own live containers) so `tests/golden_trace_test.gd` and `tests/support/make_v3_fixtures.gd` (which read/write `app.seen_lines`/`app.line_queue` directly) needed no changes; `tests/facade_contract_test.gd` (77 checks) confirms the facade still holds.

Two lanes: `queue()` (normal, gated on `combat.remaining_enemies() == 0`) and `queue_immediate()` (spec §25's one exception — a level boss's own ENCOUNTER line, which must be able to show on entry, not only after the fight it announces is already over; it jumps to the front of the same FIFO queue and is exempt from the gate, while every other queued line is unaffected). `tests/dialogue_coverage_test.gd`: **44 checks, 0 failures, 6 negative controls caught**, covering: every required literal trigger id is actually wired in `main.gd` (a source scan, the same technique `facade_contract_test.gd` uses); the absorb-unlock, per-death reboot (id includes the death count, so `seen_lines` cannot suppress the second death's line) and boss-encounter/defeat triggers; the between-fights gate (a normal line cannot leave the queue while `combat_clear` is false, and is not dropped, only delayed); the immediate lane (a `queue_immediate` line CAN leave with enemies alive, while an identical line queued through the ordinary lane cannot — the negative control); and "never shown twice" (dedupe survives across `pop_next`, and two separate negative controls prove the dedupe is really in `_enqueue`/`seen_lines` by bypassing each mechanism directly and confirming the bypass reproduces the bug).

The v0.2 wedge-world "five radial cores" triggers are remapped to the five level bosses by construction, not by touching the trigger IDs: `CampaignState.element_of` gives a level's boss coordinate the LAST element of that level's reveal slice, and the five campaign/demo levels reveal `GameTuning.ELEMENTS` (`lightning, fire, corruption, void, plasma`) one at a time, so a boss's own `element` already identifies exactly one level. Measured in `dialogue_coverage_test.gd::_test_boss_per_level`: walking campaign-mode levels 1-5 produces five distinct boss elements (one per level); a dev-mode control (which reveals every element from tick 0) collapses to exactly one boss element across all five levels, confirming the distinctness above is a real campaign/demo property.

Captured (`--show-dialogue --capture=`): the companion box renders with ECHO's portrait, title "Your first light" and the welcome body text, HUD/minimap visible behind it, `engine_errors=0`.

## Demo (this phase)

Approved preamble: campaign levels 1-2 (Lightning + Fire), no tier cap, demo progress imports into the full campaign. `ModeConfig`'s demo row already had `level_cap=2`, `max_tier=GameTuning.MAX_TIER` (no cap) and `enemy_elements=[lightning,fire]` from P5b. Two structural holes were found and fixed this phase:

1. `CampaignState.campaign_complete()` compared `levels_completed.size()` against the full `Tuning.LEVEL_RADIUS.size()` (5) regardless of mode, so a demo run could never trigger the ending after level 2 — pressing "CONTINUE TO LEVEL 3" would instead reveal a third element and offer level 3. Fixed by a new `CampaignState.level_cap()` (`mini(Tuning.LEVEL_RADIUS.size(), ModeConfig.from_id(mode).level_cap())`), used by both `campaign_complete()` and `travel_to_level()`'s clamp. `main.gd::_on_boss_defeated` now calls `_show_ending(mode_config.id == "demo")` instead of the old hard-coded `_show_ending(false)`.
2. Stale menu copy/geometry: the main menu's demo panel still listed "FIRE / CORRUPTION / PLASMA · T1-T3" and previewed those three roots at tier 3; fixed to "LIGHTNING / FIRE · LEVELS 1-2 · NO TIER CAP" and the lightning/fire roots at `GameTuning.MAX_TIER`.

**Measured, not asserted:** `scripts/platform/package_validation.gd` (which runs INSIDE an exported build, per `tools\verify_exports.ps1`) now checks, only in the demo package: `ModeConfig.from_id("demo").level_cap() == 2`; `max_tier() == GameTuning.MAX_TIER`; `enemy_elements() == ["lightning","fire"]`; calling `campaign.travel_to_level(3)` leaves `campaign.level == 2` (the clamp holds); and `campaign.campaign_complete()` is false before the level-2 boss dies. All five checks passed in the demo export run this session — see "Packages" below for the export itself.

Captured (`--show-demo-ending --capture=`, reached through the real `_on_boss_defeated` path — level 1 completed, travel to level 2, level 2's boss defeated, exactly as a real run would trigger it): title "A SMALL LIGHT, AN OPEN WORLD", body "Lightning and Fire have both yielded. The demo ends here...", `sector_label` reads "DEMO · NODE 0,0 · RING 0" confirming demo mode, `engine_errors=0`.

## Automated evidence (this session)

`tools\test.ps1 -GPU`: **36/36 tests pass, 0 failures**, 80.7s total (30 headless + 6 GPU). Full literal PASS lines:

```
PASS     0.19s  arena_test  ARENA: 21 checks, 0 failures (4 negative controls caught)
PASS     0.85s  campaign_playthrough_test  CAMPAIGN PLAYTHROUGH PASS: 54 assertions
PASS     0.47s  combat_fx_test  COMBAT_FX: 24 checks, 0 failures (6 negative controls caught)
PASS     0.59s  combat_tests  COMBAT V2: 141 checks, 0 failures
PASS     0.21s  dev_console_test  DEV CONSOLE: 22 checks, 0 failures (3 negative controls caught)
PASS     0.39s  dialogue_coverage_test  DIALOGUE COVERAGE: 44 checks, 0 failures (6 negative controls caught)
PASS     9.31s  enemy_ai_test  ENEMY AI: 41 checks, 0 failures (10 negative controls caught)
PASS     3.82s  enemy_parts_test  ENEMY PARTS: 31 checks, 0 failures (6 negative controls caught)
PASS     0.55s  facade_contract_test  FACADE CONTRACT: 77 checks, 0 failures (1 negative controls caught)
PASS     2.68s  golden_trace_test  GOLDEN TRACE: 4 checks, 0 failures (1 negative controls caught)
PASS     0.46s  handling_test  HANDLING: 12 checks, 0 failures (1 negative controls caught)
PASS     0.77s  hud_model_test  HUD MODEL: 1356 checks, 0 failures (2 negative controls caught)
PASS     1.11s  mode_isolation_test  MODE ISOLATION: 26 checks, 0 failures (7 negative controls caught)
PASS     0.29s  save_migration_test  SAVE MIGRATION: 24 checks, 0 failures (2 negative controls caught)
PASS     0.46s  ships_compositor_test  Ship compositor: 0 failures
PASS     1.22s  ships_editor_test  Ship editor v2: 0 failures
PASS     0.38s  ships_mesh_cache_test  Ship mesh cache: 0 failures
PASS     1.12s  ships_mesh_test  Ship meshes: 6922 checks, 0 failures
PASS     0.58s  ships_reshape_test  Ship reshapes: 125 routes, 15135 checks, 0 failures
PASS     0.75s  ships_validation  Ships v3: 10982 checks, 0 failures
PASS     0.29s  ship_motion_test  ship_motion: 19 checks, 0 failures (5 negative controls caught)
PASS     0.93s  ship_roster_test  ship_roster: 825 checks, 0 failures (14 negative controls caught)
PASS     0.74s  sound_shutdown_test  AUDIO SHUTDOWN: late cues and paused cleanup, 0 failures
PASS     2.41s  ui_flow_test  UI V2: 33 checks, 0 failures
PASS     0.38s  unlock_offers_test  unlock_offers: 34 checks, 0 failures (4 negative controls caught)
PASS     0.48s  warp_test  WARP: 19 checks, 0 failures (1 negative controls caught)
PASS    37.53s  world_generation_test  world_generation: 17 checks, 0 failures (4 negative controls caught)
PASS     0.37s  world_platform_test  PLATFORM TESTS PASS: 31 assertions
PASS     0.69s  world_rules_test  WORLD RULES PASS: 103 assertions
PASS     1.41s  arena_render_test  Arena rendering: background=0.0052 membrane=0.8575 sealed=0.1237 dead_zone=0.0052 (unclipped 0.0208), failures=0, controls 2/2
PASS     1.53s  combat_fx_render_test  Combat FX rendering: failures=0, controls 4/4
PASS     1.12s  ships_mesh_render_test  Ship mesh pixels: core widths=6/6 outline widths=2/2 failures=0
PASS     1.25s  ships_void_render_test  Void rendering: halo=(0.5449,0.5449,0.5449,1.0) masked=(0.0,0.0,0.0,1.0) failures=0
PASS     1.18s  ship_motion_render_test  Ship motion pixels: failures=0 controls_caught=1/1
PASS     1.26s  warp_render_test  Warp pixels: failures=0 controls_caught=2/2
```

Notable: `enemy_ai_test.gd` (the `turret_ring` census check flagged as pre-existing-broken in the P7 review, `tasks/todo.md` line ~195, and still listed there as an unfixed P10 carry-forward item) passed clean, 41/41, in this session's run. This is stated plainly, not claimed as a fix: I made no change to that file or to `combat_world.gd`'s `turret_ring` handling this phase, and did not investigate why it now passes (it may already have been fixed by P8 work between when that review paragraph was written and now). The `tasks/todo.md` carry-forward line is left as recorded for P10 to confirm, not removed on the strength of one green run.

Golden trace: re-recorded (expected — the queued-line dictionary gained an `"immediate"` key, moving the `lines` digest, which is `sha256([seen_lines, line_queue])`). Checked first per the standing rule: the failing run's own diff (`new_game.lines expected ... got ...`) named `lines` as the FIRST differing field, meaning every field checked before it in insertion order (`step, mode, overlay, paused, sector, hull, tier, light, enemies, bullets, offers, profile, snapshot`) matched exactly at the very first step. Re-recorded; new final digest `4089779872420184`, `engine_errors=0`.

## Rendered frame, benchmark, and the tail (carried from P7/P8, not re-measured this phase)

Not re-measured this session (no rendering/simulation code changed in P9): the P8 review's rendered-frame numbers (`main.gd --benchmark`) and the P7 acceptance-bot numbers stand as last measured — see `tasks/todo.md` "Review — P7"/"Review — P8" for the cited figures (novice first-evolution median 19.7s/max 55.2s with 20/20 seeds inside 2 minutes; pusher-vs-camper 8.2x; rendered frame mean ~10.8ms/p95 ~19.9ms in the stress case per the header comment in `scripts/main.gd`). `tasks/todo.md`'s P10 carry-forward list already states plainly: **the rendered frame's worst 5% still dips below 60 fps in the stress case** (p95 15.5-19.9ms against 16.67ms), and **no Steam Deck has been measured at any point**. Both remain true; this record does not claim otherwise.

## What is NOT verified

- **No human playtesting of feel** at any point in v0.3 (per the standing waiver at the top of `tasks/todo.md`: the P7 stop was waived by the user's own instruction to run the whole spec through without pausing for hands-on review).
- **No Steam Deck measurement** of any kind — frame rate, thermals, suspend/resume, or controller behaviour on the physical device.
- **No controller exercised with a real pad.** Steam Input bindings and the dash action exist in code and the manifest; nothing here proves a physical controller drives them correctly.
- **No real-account Steam round trip.** Achievements, Cloud conflict/merge and App ID configuration are exercised only through the platform adapter's API doubles (`scripts/platform/`), not an owned Steam account.
- **The rendered frame's worst 5% dips below 60 fps in the stress case** (2000 live bullets AND the 400-pickup cap simultaneously) — p95 15.5-19.9ms against the 16.67ms/60fps budget, per the P8/P10-carryforward record. Mean performance clears the budget with room; this is a tail, not a typical-play number.
- Linux export verification this session: see "Packages" below — plainly stated if Docker was or was not available.
- Whether the demo's menu copy/preview and the level-2 ending genuinely read as intended to a new player (no human reviewer beyond the captures in this record).

## Packages (this phase's export run)

See the "Release plumbing" section of this session's report for `tools\export.ps1`/`tools\verify_exports.ps1` results, run after the doc and version-string updates below.
