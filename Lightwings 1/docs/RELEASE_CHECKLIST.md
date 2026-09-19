# Release qualification checklist

This checklist concerns the revised five-tier implementation. Earlier build archives, screenshots and measurements do not establish verification of the rewrite. Consult [VALIDATION.md](VALIDATION.md) for dated, reproducible evidence. No human balance review, physical Steam Deck qualification or real-account Steam test is implied by local automated checks.

Checked items below record automated implementation verification; human acceptance has its own section.

## Rules, content and authoring

- [x] Verify the one-bar loop: seed starts at 40, thresholds 100/250/500/900, T5 capacity 1500, no passive regeneration, 85% regression threshold, reshape protection and fresh regrowth offers.
- [x] Validate all 81 player hulls and 55 enemy/elite/rival definitions against allowed geometry, symmetry where required, tier-point budgets, slots, role and palette rules.
- [x] Confirm each fixed hull preset provides exactly the weapons shown on its evolution card; three secondary bindings dispatch independently.
- [x] Automated author/save/library/play flow, filters, missing-roster view, validation, description generation and preview checks pass.
- [ ] A human designer completes the M2 authoring acceptance flow without editing code.
- [x] Verify elites expose independently destructible attack points and core protection; check every included component's runtime behavior and safety limits.
- [x] Verify all five procedural wedges, open exits, five cores, no unknown-node spoilers, distance waypoints and discovery-triggered Lightning/Void unlocks.
- [x] Verify death refreshes regular encounters while preserving discoveries, waypoints, beaten cores, unlocks and compatible story progress.
- [x] Verify three-element/T3 demo completion at Fire core and import into a previously empty campaign.

## Automated and package verification

- [x] Run the source test suite and required GPU render checks after the last relevant edit; record assertions, failures and limitations in VALIDATION.md.
- [x] Exercise ordinary-command first-evolution timing, seeded core routes, regression/regrowth, save/resume and bounded encounter/resource accounting. A forced-clear route validates progression plumbing, not difficulty.
- [x] Check legacy save migration, exact original archive retention, corruption recovery, future-schema rejection and local/cloud conflict choices.
- [x] Export fresh Windows and Linux campaign/demo packages; run embedded package validation against current roster, evolution and snapshot contracts.
- [x] Run both Linux release binaries under the available Linux container.
- [ ] Qualify Linux rendering, audio and controls on a native GPU desktop.
- [x] Measure 2000 live projectiles in a representative rendered scene after warm-up, including independent elite weapons, HDR/glow and the moving camera. Record hardware and frame-time distribution.
- [x] Produce fresh distributable hashes after final exports. Do not reuse old archive hashes or benchmark results.

## Human and hardware acceptance

- [ ] Observe new players without coaching: first evolution within two minutes, hollow pickups versus solid bullets understood, regression feels recoverable, and free escape through openings is discoverable.
- [ ] Observe testers discovering elite weapon destruction without instruction and deliberately steering toward an element's light.
- [ ] Assess all roles and evolution alternatives for meaningful differences; confirm silhouettes remain readable at minimum supported display scale.
- [ ] Evaluate color and motion identity, reserved player blue, core visibility, Void occlusion, background brightness and absence of default off-screen enemy blips.
- [ ] Test complete keyboard/mouse and physical-controller flows, rebinding, three secondary controls, hot-plug and menu focus.
- [ ] Test a physical Steam Deck: sustained frame rate, text readability, suspend/resume, focus loss, offline play and save recovery. Do not claim Deck Verified or a measured Deck frame rate beforehand.
- [ ] Establish measured minimum hardware, OS/driver and storage requirements from the final packages.

## Steam account and publication

- [ ] Supply owned campaign/demo App IDs and partner configuration. No sample App ID substitutes for ownership.
- [ ] Confirm achievement API IDs, real-account callback/retry behavior, version-3 payloads at the configured cloud paths and both conflict choices across two installations.
- [ ] Export and package official Xbox/Steam Deck Steam Input layouts and test both Gameplay and Menu contexts with the owned App ID.
- [ ] Verify extension loading, overlay and binding panel in packaged Windows/Linux builds.
- [ ] Approve title, price, release date, language list and platform feature claims in STORE_DRAFT.md.
- [ ] Replace old capsules/screenshots with approved captures from the revised renderer and UI; recheck current Steam asset requirements at publication time.
- [ ] Obtain authorization for any external upload, store publication or release action. Local preparation is not publication.

The supplied M1–M6 milestones are the product's acceptance sequence. Automated checks support those decisions; they do not replace designer usability review, human combat playtests or real hardware/account qualification.

