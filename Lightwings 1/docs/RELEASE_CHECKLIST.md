# Release qualification checklist

This checklist concerns the v0.3 implementation (two primitives, six tiers, five bounded Chebyshev levels, campaign/dev/demo modes, save schema 4). Earlier build archives, screenshots and measurements (`docs/VALIDATION_V02.md`) do not establish verification of the rewrite. Consult [VALIDATION.md](VALIDATION.md) for dated, reproducible evidence. No human balance review, physical Steam Deck qualification or real-account Steam test is implied by local automated checks.

Checked items below record automated implementation verification; human acceptance has its own section.

## Rules, content and authoring

- [x] Verify the one-bar loop: seed starts at 40 light, thresholds 100/250/500/900/1500 across six tiers, terminal (T6) capacity 2300, no passive regeneration (only decay, which floors and cannot kill), regression floor, reshape protection and fresh regrowth offers.
- [x] Validate the 101-player-hull roster (141 authored total: 101 player + 25 enemy + 10 elite + 5 boss) against the two-primitive parent-graph geometry, motion group rules, tier-point budgets (cap 36 at T6), slots, role and palette rules (`ship_roster_test.gd`, 825 checks/14 controls; `ships_validation.gd`, 10982 checks).
- [x] Confirm each fixed hull preset provides exactly the weapons shown on its evolution card; three secondary bindings plus dash dispatch independently.
- [x] Automated author/save/library/play flow, filters, missing-roster view, validation, description generation and preview checks pass (`ships_editor_test.gd`, `ships_compositor_test.gd`, `ships_mesh_cache_test.gd`).
- [ ] A human designer completes the authoring acceptance flow without editing code.
- [x] Verify enemies expose per-circle HP, detachable limbs/debris, and elite/boss archetype behaviour (reaction lag, aim error, retreat, shielded/multi-cored bosses) — `enemy_ai_test.gd` (41 checks/10 controls), `enemy_parts_test.gd` (31 checks/6 controls).
- [x] Verify all five bounded Chebyshev-lattice levels, membrane construction (open/sealed exits), one boss per level always on the sealed perimeter, no unknown-node spoilers on the map, and absorb-to-unlock element reveal — `world_generation_test.gd` (200 seeds x 5 levels), `world_rules_test.gd`.
- [x] Verify death is frictionless (no confirmation, 1.2s non-pausing card, fresh-press or auto-close dismissal) and refreshes regular encounters on a fresh per-life seed while preserving discoveries, unlocks, best-ring and compatible story progress — `acceptance_v03.json`, `world_rules_test.gd`.
- [x] Verify the demo (campaign levels 1-2, Lightning/Fire, no tier cap) ends on the level-2 boss and imports into a previously empty campaign; verify a demo save CANNOT reach level 3 by any path — `dialogue_coverage_test.gd`'s boss-per-level check, `package_validation.gd`'s demo-only checks (run inside the exported package), `docs/VALIDATION.md`'s demo section.
- [x] Verify the companion narrative fires on every required trigger (welcome, first evolution/regression/threshold, each new element, each elite, each level boss's encounter AND defeat, each death) at most once, and that the between-fights gate (with its one immediate-lane exception, a boss's encounter line) holds — `dialogue_coverage_test.gd` (44 checks/6 controls).

## Automated and package verification

- [x] Run the source test suite and required GPU render checks after the last relevant edit; record assertions, failures and limitations in VALIDATION.md. This session: `tools\test.ps1 -GPU` 36/36, 0 failures.
- [x] Exercise ordinary-command first-evolution timing, seeded boss routes, regression/regrowth, save/resume and bounded encounter/resource accounting. A forced-clear route validates progression plumbing, not difficulty.
- [x] Check legacy (schema < 4) save migration, exact original `.legacy-v3` archive retention, corruption recovery, future-schema rejection and local/cloud conflict choices — `save_migration_test.gd` (24 checks/2 controls).
- [x] Export fresh Windows and Linux campaign/demo packages; run embedded package validation against current roster, evolution, snapshot and demo-limit contracts. This session: campaign 187/187, demo 192/192 (Windows and Linux each).
- [x] Run both Linux release binaries under the available Linux container (`tools\verify_exports.ps1 -LinuxContainer`, Docker available this session).
- [ ] Qualify Linux rendering, audio and controls on a native GPU desktop (the container verification is headless runtime checks only, not a display/audio/input qualification).
- [x] Measure 2000 live projectiles in a representative rendered scene after warm-up. Per `tasks/todo.md`'s P8/P10-carryforward record: mean well inside the 16.67ms/60fps budget, but the worst 5% (p95) still dips to roughly 50-60fps in the absolute stress case (bullet AND pickup pools both at their caps) — not re-measured this phase (no rendering code changed in P9).
- [x] Produce fresh distributable hashes after final exports this session (`tools\package.py` → `builds/distributions/manifest.json`, version 0.3.0). Do not reuse old archive hashes or benchmark results.

## Human and hardware acceptance

- [ ] Observe new players without coaching: first evolution within two minutes, hollow pickups versus solid bullets understood, regression feels recoverable, and free node-to-node warp travel is discoverable.
- [ ] Observe testers discovering per-circle limb destruction without instruction and deliberately steering toward an element's light.
- [ ] Assess all roles and evolution alternatives for meaningful differences; confirm silhouettes remain readable at minimum supported display scale. Note: `standard_a`/`standard_b` player hulls share geometry and differ only by primary weapon (`tasks/todo.md` carry-forward item) — a tier's four offers currently read as three distinct shapes, not four.
- [ ] Evaluate color and motion identity, reserved player light-blue, core visibility, Void occlusion, background brightness and absence of default off-screen enemy blips.
- **Known limit (M19): the colourblind setting recolours the interface only.** `ElementStyle.colorblind` swaps the element colours on menus, cards, the map and the dialogue box (Okabe-Ito), and every element also carries a glyph there. Ships, bullets, pickups and the arena keep `VisualStyle`/`Elements` colours. There is no single colour choke point on the world side: the colours are baked into `const` tables (`Elements.RIM_BY_INDEX`, `CombatWorld.COLORS`), bullet pools indexed by element, authored part colours in ship definitions and shader palettes. Recolouring the world means a runtime palette read at every one of those sites, and it has to be re-checked for the reserved player light-blue. Treat it as a design task, not a toggle. Until then, in combat a colourblind player reads an element from silhouette, motion and the UI glyphs.
- [ ] Test complete keyboard/mouse and physical-controller flows, rebinding, three secondary controls plus dash, hot-plug and menu focus. **No physical controller has been exercised at any point in v0.3** — only the input-mapping code and API doubles.
- [ ] Test a physical Steam Deck: sustained frame rate, text readability, suspend/resume, focus loss, offline play and save recovery. Do not claim Deck Verified or a measured Deck frame rate beforehand. **No physical Steam Deck evidence exists for v0.3.**
- [ ] Establish measured minimum hardware, OS/driver and storage requirements from the final packages.

## Steam account and publication

- [ ] Supply owned campaign/demo App IDs and partner configuration. No sample App ID substitutes for ownership.
- [ ] Confirm achievement API IDs, real-account callback/retry behavior, schema-4 payloads at the configured cloud paths, both conflict choices across two installations, and that the `dev` save slot is confirmed excluded from a real account's cloud sync (code-level guard exists and is tested — `mode_isolation_test.gd` — but not exercised against a real account).
- [ ] Export and package official Xbox/Steam Deck Steam Input layouts and test both Gameplay and Menu contexts, including the `dash` action, with the owned App ID.
- [ ] Verify extension loading, overlay and binding panel in packaged Windows/Linux builds.
- [ ] Approve title, price, release date, language list and platform feature claims in STORE_DRAFT.md.
- [ ] Replace old capsules/screenshots with approved captures from the current renderer and UI; recheck current Steam asset requirements at publication time.
- [ ] Obtain authorization for any external upload, store publication or release action. Local preparation is not publication.

The spec's M1-M6 milestones (`docs/LIGHTSHIP_GAME_SPEC_V3.md`) are the product's acceptance sequence. Automated checks support those decisions; they do not replace designer usability review, human combat playtests or real hardware/account qualification. Per the standing waiver recorded at the top of `tasks/todo.md` (P7's hands-on review stop was waived by explicit user instruction to run the whole spec through without pausing), **no human-feel review has happened at any point in v0.3** — every item in "Human and hardware acceptance" above is open, not merely unchecked.
