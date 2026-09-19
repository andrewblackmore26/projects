# Lightship v0.2 validation record

Recorded 13 September 2026. The revised five-tier campaign, three-element demo, fixed-preset 81-player-hull roster, procedural world, save migration and workshop are implemented. This record describes the current source and fresh exports. The previous version's evidence is retained in [VALIDATION_V01.md](VALIDATION_V01.md) and does not establish v0.2 correctness.

## Implementation by milestone

| Milestone | Implemented and exercised | Acceptance still requiring people or hardware |
|---|---|---|
| M1 | Fractional light, absorption, three cached offers, historical regression, reshape/grace, fixed presets, rounded arena, camera-aligned compositor, parallax, running-light pickups and boundary collision. | Observe an uncoached new player reaching first evolution within two minutes and understanding pickups/exits. |
| M2 | 49 starting-element player hulls, resource contracts, primitive renderer, five motion signatures, symmetry, budgets, undo/redo, searchable thumbnail library, save/import/export, bounded local description generator and production-renderer test-flight preview. | Independent designer usability and silhouette review. |
| M3 | Seed/coordinate generation, five wedges, reciprocal exits, sparse explored map, tier-qualified waypoints, persistent encounter deltas with 32-entry decoded cache, version-3 migration and original-save archives. | Longer human exploration and recovery balance. |
| M4 | All 26 components through shared execution, bounded shields, destructible elite weapons, saved gun/reward state, telegraphs, positional cues, passive-gated readouts and preview dummies. | Players discover gun destruction through play; compare elite and rival pressure. |
| M5 | Remaining 32 Lightning/Void player hulls, 25 regular/25 elite/five rival assets, elemental attacks, five core encounters, Plasma portraits/dialogue and queued narrative/completion. | Deliberate element seeking and recognizable combat identity in human playtests. |
| M6 | T3/500-light, three-element demo and Fire-core ending, supported import, three secondary bindings and Steam actions, four local exports, package checks, archives and review artwork. | Physical controller/Deck, native Linux GPU, owned Steam App ID/account round trips and store approval. |

The automated sequence validates integration, not all human milestone exit conditions. No publication was performed.

## Automated evidence

The complete source suite, including both Vulkan pixel tests, passed after the final gameplay, resource and export-enumeration edits. Log: `artifacts/v2-final-suite.log`. There were no script errors or failed assertions.

| Area | Result | Representative coverage |
|---|---:|---|
| Campaign traversal | 157 assertions | Ordinary-command bot progression; all five campaign cores and demo ending; early core completion persists while other enemies survive. |
| Combat | 138 checks | Thresholds, fractional role mitigation, exact regression floors, multi-tier hits, death, capped/Siphon collection, preset/history restoration, grace snapshots, walls/ricochet, ability limits, authored NPC mounts/passives, elite exposure and gun attacks, reward/cache persistence. |
| World and saves | 164 assertions | Visit-order-independent/distant generation, open reciprocal exits, hidden-node privacy, waypoints, unlocks, offers, migration, recovery, corrupt/future saves and demo import. |
| Platform adapters | 31 assertions | Three indexed secondary actions, native input conversion/disconnect, achievement retry, cloud conflict choices and migration via API doubles. |
| Ship resources | 5,324 checks | 136 hulls: 81 player, 25 regular, 25 elite, five rivals; all 26 component resources; role/roster coverage, meaningful parts, symmetry, slot/TP constraints and exported filename normalization. |
| Meshes | 5,362 checks | Cached primitive geometry and renderer invariants. |
| Reshapes | 5,874 checks on 100 routes | Stable part IDs, attachment endpoints, additive families and cross-family transitions. |
| UI | 32 checks | Evolution cards, stable offers/menu/save/resume, demo cap, map, camera input transform and unrestricted exits. |
| Editor, compositor, mesh cache and audio | Zero failures | Save/library/round-trip/generator flow, unsaved draft combat/pilot preview, composition alignment and shutdown cleanup. |
| Vulkan pixels | Zero failures | Player core six pixels and outline two pixels at base/minimum scale; running lights, motion and Void masking. |
| Exported runtime | 178 checks in each of four packages | Embedded roster/abilities, native Steam extension, manifest/license, menus, simulation, preset evolution, snapshot round-trip and audio retirement. |

## Simulation and playtest limits

The controller-command bot reaches first evolution with 100 light at **6.77 simulated seconds**. A new life with prior waypoint progress as a fixture reaches T3/250 light at **13.82 seconds**. Both start with the normal 40 light and earn further light through actual combat; neither is a human pacing result.

Forced-clear fixtures traverse 124 transitions and defeat all five campaign cores, earning ten waypoints; the demo fixture takes eight transitions, one core and two waypoints. These deliberately force victories to verify state transitions and completion. They do not establish combat difficulty or full-campaign survivability.

Human tuning remains open, including the short automated recovery times. Starting thresholds, role multipliers, shield duration/cooldown and world progression are centralized in `scripts/data/game_tuning.gd`, `content/campaign/default_campaign.tres` and component resources. No unobserved human playtest is claimed.

## Rendering and performance

The fresh exported Windows campaign measures **10.662 ms mean / 16.527 ms p95** over 5,628 recorded frames with **2,000 projectiles**. Total run duration is 65.003 seconds: five seconds warm-up and 60 seconds recording. This meets the desktop 16.67 ms p95 target, with little margin; it does not establish performance on minimum hardware.

The workload uses a T5 Plasma Heavy player running its actual primary, all three cooldown-driven secondaries and passive, steering around an ellipse with sweeping aim. Four T5 elites retain 28 independently firing gun points for the duration. The scene ends with 23 actors, two drones and 109 unconsumed pickups. Projectile replacement sustains 2,000 live shots; benchmark-only large health budgets keep the workload alive. Rendering uses 1280×800 Mobile Vulkan, HDR 2D/glow, a moving camera and disabled vsync; audio uses the Dummy driver. Hardware: AMD Ryzen 7 9800X3D and NVIDIA GeForce RTX 5070 Ti, Vulkan 1.4.325. Report/log: `artifacts/v2-benchmark-2000.json` and `.log`.

The same rendered fixture at **1,000 projectiles** measures **8.521 ms mean / 14.286 ms p95**, with 7,043 frames recorded after warm-up. It ends with 23 actors, four drones and 120 pickups. Report/log: `artifacts/v2-benchmark-1000.json` and `.log`.

An earlier equivalent full-load run failed at 21.761 ms mean / 54.957 ms p95 (`artifacts/v2-benchmark-before-combat-optimization.json`). Per-tick pickup collector caching, single-cell collision query acceleration, square-root-free containment and shared immutable mesh caching reduced redundant work. The same long headless fixture retained its actor/pickup/drone trajectories and reduced mean simulation from 8.90 to 6.68 ms; this is supporting CPU evidence, not a GPU result. The geometry cache is bounded to 96 entries and an estimated 32 MiB; edits use exact geometry keys, and actor materials/hidden-part offsets remain independent.

**No physical Steam Deck evidence is available.** Sustained Deck frame rate, thermal behavior and suspend/resume remain unqualified; desktop and headless numbers cannot substitute.

GPU tests measured the Void background halo at 0.5449 before masking and 0.0 inside the black hull while foreground threats remained visible. Core diameters were 6/6 pixels and outline widths 2/2 at the tested scales. The camera applies one transform to HDR and foreground passes, including projectiles and Void masks.

Visually reviewed captures include `artifacts/v2-combat.png`, `artifacts/v2-evolution.png` and `artifacts/v2-workshop.png`. Three native-renderer capsule drafts are under `artifacts/store/`; their manifest records v0.2 provenance. These are review drafts, not approved public store assets.

## Packages and platform limits

Godot 4.7.2 and GodotSteam GDExtension 4.22.1 are pinned. Fresh Windows campaign/demo binaries ran on Windows. Fresh Linux campaign/demo binaries ran headlessly inside a `python:3.12-slim` Linux container. All four passed 178 embedded runtime checks, including resource enumeration inside the exported pack. Logs: `artifacts/v2-export-campaign.log`, `v2-export-demo.log`, `v2-package-validation.log` and `package-{win,linux}-{campaign,demo}.log`.

All four local distributable archives passed integrity checks and archived-executable SHA-256 comparison. Windows ZIPs are about 37.9 MiB each; Linux tarballs are about 28.9 MiB each and preserve executable permissions. `builds/distributions/manifest.json` records version 0.2.0 and fresh archive/executable hashes. Native Steam libraries, licenses and launch/control instructions are included. Nothing was uploaded or published.

The Linux container does not qualify native Linux display, audio or controller behavior. Steam adapters were exercised with deterministic API doubles and the native extension loads in each package. Owned App IDs, official input layouts, overlay/account stats and two-device Cloud round trips remain unverified. Saves remain usable offline; demo import and migration preserve supported progress, and replaced/migrated originals are archived.

## Repeatable checks

```powershell
powershell -ExecutionPolicy Bypass -File tools/test.ps1 -GPU
powershell -ExecutionPolicy Bypass -File tools/export.ps1
powershell -ExecutionPolicy Bypass -File tools/export.ps1 -Demo
powershell -ExecutionPolicy Bypass -File tools/verify_exports.ps1 -LinuxContainer
python tools/package.py
```

Run GPU performance checks without competing workloads. From the exported campaign directory:

```powershell
.\Lightship.exe --audio-driver Dummy -- --benchmark --benchmark-bullets=2000 --benchmark-output=benchmark-2000.json
.\Lightship.exe --audio-driver Dummy -- --benchmark --benchmark-bullets=1000 --benchmark-output=benchmark-1000.json
```

Each benchmark uses five seconds of warm-up followed by 60 seconds of wall-clock frame intervals. Docker is required for the Linux verification switch. Remaining human, device and account checks are tracked in [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).
