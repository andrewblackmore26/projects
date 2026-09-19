# Validation record

Recorded 12 September 2026. The implementation includes the playable 81-sector campaign, separate 25-sector demo, four element roots, authored ships, workshop, combat, progression, saves and optional Steam adapters. Four local release exports pass their embedded runtime checks. Physical device testing, human balance and art review, and Steam partner configuration remain release gates.

## Automated evidence

The integrated suite completed successfully, including GPU tests (`artifacts/final-suite.log`). After the final audio shutdown fix, import, audio and UI checks were repeated successfully (`artifacts/final-import.log`, `final-audio-test.log`, `final-ui-test.log`). No relevant engine errors were reported.

| Area | Result | Coverage |
|---|---:|---|
| World and persistence | 307 assertions | Evolution thresholds and ranking, three stolen slots, gates, territory/drift, unlocks, demo import, recovery budgets, atomic saves and backup recovery. |
| Platform adapter | 22 assertions | Native input conversion, disconnect handling, achievement retries, cloud inspection and conflict handling using a deterministic API double. |
| Campaign traversal | 299 assertions | Legal progression through all campaign/demo sectors and both endings; natural combat fixtures are distinguished below. |
| Combat | 115 checks | Swept collisions, interception, core damage, abilities, shared-prong deduplication, source factions, hijack, infection, rewards, restoration and duplicate component upgrades. |
| UI flows | 34 checks | New game, evolution, map, save/resume and settings; map and evolution each held open for 10.1 seconds with gameplay unchanged and preview animation advancing. |
| Ship resources | 1,641 checks | Forty authored player/enemy forms, 26 ability resources, stable IDs, attachments, tethers and validation. |
| Ship meshes | 1,296 checks | Cached geometry, shape ranges and renderer invariants. |
| Reshapes | 5,120 checks on 64 routes | All supported cross-root transitions, retained IDs, attachment endpoints and preview/result consistency. |
| Editor and compositor | Zero failures | Shared renderer/editor behavior and composition lifecycle. |
| Audio shutdown | Zero failures | Late cues cannot restart playback; paused cleanup is safe and repeated shutdown is idempotent. |
| Final exported packages | 80 checks per package; all four passed | Correct campaign/demo feature flag, all authored forms and abilities, native Steam library, manifest/license, menus, advancing simulation, evolution, save/restore and native audio retirement. |

Tests are in `tests/`; the exported runtime probe is `scripts/platform/package_validation.gd`. It is invoked explicitly with `--verify-package` and uses an isolated save directory. Exported Godot release builds do not support the editor's external `--script` workflow, so these checks run from the embedded PCK.

## Natural simulation versus forced progression

| Scenario | Measured result | What it establishes |
|---|---|---|
| New instance, natural bot | First 100 energy at 7.98 simulated seconds; survived | Actual movement, firing, damage and collection without granted energy, HP overrides or forced deaths. |
| Recovery, natural bot | 717 energy at 19.23 simulated seconds; survived | Prior-life checkpoint/territory is a fixture. The new life starts at zero and earns light in actual combat. |
| Campaign, forced victories | 81 sectors, 116 legal transitions, six checkpoints, four leaders, finale and four mirrors | Starts with a T5/1,500-energy fixture and uses explicit debug victories. Verifies progression plumbing, not campaign difficulty. |
| Demo, forced victories | 25 sectors, 26 transitions, four gate/checkpoint records and demo ending | Uses a T3/1,500-energy fixture. The playable demo normally grows through T1–T3. |

The natural bot proves access to renewable energy and a timely first evolution. Its fast recovery does **not** establish the requested 3–5 minute human recovery pace. Reward tuning and observed human playtests remain necessary. A full campaign has not been completed by a human or an unassisted bot in this validation pass.

## Rendering and performance

The final Windows exported campaign passes the desktop frame-time target: **8.04 ms mean, 14.575 ms p95**, across 7,462 measured frames. Total run duration was 65.008 seconds: five seconds warm-up followed by 60 seconds of recording.

The workload runs at 1280×800 with the Mobile Vulkan renderer, HDR 2D and glow. It contains 2,000 live bullets, 13 actors, high-tier ships, pickups, seven drones and Void fields. Vsync is disabled to measure capacity; frame intervals use a wall clock. Audio uses the Dummy driver during this GPU capacity measurement.

Hardware: AMD Ryzen 7 9800X3D, NVIDIA GeForce RTX 5070 Ti; Vulkan 1.4.325. The exact report is `artifacts/benchmark-final-windows.json`, with the engine log in `artifacts/exported-benchmark.log`. The package manifest records the shipped executable SHA-256 hashes.

This is desktop evidence, **not a Steam Deck result**. The physical Deck requirement remains 2,000 representative bullets at 60 fps with p95 at or below 16.67 ms and no recurring stalls. Native Linux GPU behavior, thermal behavior and suspend/resume remain untested here.

The earlier renderer failed this workload (133.359 ms mean, 144.413 ms p95). That report is retained in `artifacts/benchmark-before-optimization.json`. Ships now use cached batched meshes, bullets use two packed MultiMesh passes, and aura outlines use consolidated draws.

Actual GPU pixel tests passed after those changes:

- Void's background halo measured 0.5449 before masking and exactly 0.0 inside its restored black hull; foreground threat pixels remained visible.
- Player core diameter measured six pixels at normal and minimum preview scales; sampled outline width remained two pixels at both scales.
- Running-light movement, breathing, orbit/core separation and paused preview clocks passed.

Final gameplay, evolution and map captures are in `artifacts/combat-final.png`, `evolution-final.png` and `map-final.png`. Three original store capsule drafts at 920×430, 462×174 and 1232×706 were generated with the native renderer and visually inspected. HDR images were converted from linear values to sRGB before RGBA8 output. Player art and public screenshot selection still need owner review.

## Export and platform evidence

Godot 4.7.2 and GodotSteam GDExtension 4.22.1 are pinned. Windows campaign/demo executables were launched on Windows. Linux campaign/demo executables were launched headlessly in a Linux container (`python:3.12-slim`); these are actual Linux release binaries, not Windows simulation of their game logic. Each passed 80 embedded checks. Logs: `artifacts/package-win-campaign.log`, `package-win-demo.log`, `package-linux-campaign.log`, `package-linux-demo.log`.

The Windows campaign also completed the rendered benchmark. Linux container checks do not exercise a Linux display, audio device or controller. Normal final package logs contain no ObjectDB/audio leaks; a verbose Linux diagnostic still reports 48 orphan static StringNames, including engine and Steam class names, without live ObjectDB instances (`artifacts/linux-campaign-audio-recheck.log`).

All four archives have CRC/content-hash verification, and Linux archives preserve executable permissions. `builds/distributions/manifest.json` contains archive and executable SHA-256 hashes. Exports include native libraries and third-party notices.

Steam remains optional for local play. Native API signatures were inspected and adapters tested, but no real App ID, official input layout, account stats, overlay or cross-device Cloud round trip was available. Demo saves remain local; the campaign supports importing them. Graphics and bindings remain outside cloud progression.

## Repeatable checks

From this project directory on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File tools/test.ps1 -GPU
powershell -ExecutionPolicy Bypass -File tools/export.ps1
powershell -ExecutionPolicy Bypass -File tools/export.ps1 -Demo
powershell -ExecutionPolicy Bypass -File tools/verify_exports.ps1 -LinuxContainer
python tools/package.py
```

The Linux verification switch requires Docker and the named Linux image. Omit it for Windows-only verification. Run GPU checks and the rendered benchmark without competing workloads. From an exported campaign folder:

```powershell
.\Lightship.exe --audio-driver Dummy -- --benchmark
```

The report is written beside the executable, or to the path supplied with `--benchmark-output=PATH`. Packaging is local and does not publish anything. Remaining device, human and partner checks are recorded in [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md); unpublished copy and assets are in [STORE_DRAFT.md](STORE_DRAFT.md).
