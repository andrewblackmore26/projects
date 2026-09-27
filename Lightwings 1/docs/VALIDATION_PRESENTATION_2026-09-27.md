# Presentation redesign validation — 2026-09-27

This record covers the circle-and-line presentation revision on the existing working tree. The older validation record describes earlier builds. The implementation follows [VISUAL_REDESIGN.md](VISUAL_REDESIGN.md); pre-existing edits and deleted files were retained. No unrelated custom hull files were replaced.

## Geometry and compatibility

The 146 shipped hulls were captured before simplification in `content/ship_geometry_v1.json`. Rebuilding writes candidates to `artifacts/ships_geometry_v2` and copies only manifest entries into `content/ships`. The fleet went from **5,544 to 4,440 circles (19.9% fewer)**; the largest hull has 82. Generation no longer rerolls to satisfy minimum circle counts.

`ship_geometry_revision_test.gd` passes **4,066 checks**, including weapon/host/mount identities, firing multiplicity, base stats, total limb HP at every actual spawn tier from 1 to 6, geometry JSON round trips, current and compressed cached-encounter migration, and repeated save/load. Fixed HP and radius-derived armour are preserved separately. Detached sources contribute no paid reward share or remaining HP. Destroyed hosts cannot regrow decorations. Existing custom revision-1 hulls retain their authored bead layouts, with missing structural links repaired.

Four negative controls reject a removed spoke, a spoke ending on a guide, an external solid circle claiming to be an integrated marking, and disconnected weapon ornament. Motion, combat and GPU tests check offset rails, chains, aiming, bobbing, detachment and shared render/collision poses.

Heavy player pod fans were widened after visual review found tier-3 and tier-4 standard/heavy silhouettes too similar. These changes use the same simulation pose for connectors, visible circles and collision.

## Behaviour comparison and golden trace

`tests/ship_geometry_combat_comparison.gd` compares the captured old geometry with the revised roster over paired fixed-seed encounters and repeats one revised run to check determinism. It uses the same current simulation on both sides. Consolidation deliberately changes where damage lands, so equal total health does not imply identical combat outcomes or time to kill.

The comparison exposed an unintended dependency: allocating every decorative circle consumed encounter RNG and shifted firing cadence. Each actor now has a saved part seed, with stable per-part cooldown and aiming streams. Changing decorative circle counts no longer advances encounter RNG.

Final-geometry results, rerun after widening heavy pod fans:

| Seed | Player activations, old → new | Enemy activations | Remaining enemy core HP |
|---|---:|---:|---:|
| 101 | 180 → 180 | 138 → 130 | 1448.680 → 1463.247 |
| 202 | 180 → 180 | 133 → 137 | 1319.573 → 1321.107 |
| 303 | 180 → 180 | 128 → 129 | 1515.687 → 1483.947 |

All encounters ran for 30 simulated seconds. The repeated revised run matched exactly. Remaining core HP differs by approximately 0.1–2.1%; no ships died in these runs, so this is **not evidence of time-to-kill parity**. The report is `artifacts/geometry_combat_comparison.json`.

The golden trace was inspected before being re-recorded. The first difference was `new_game.snapshot`, consistent with geometry metadata, part identities and the saved part seed. The final fixture differs in snapshot hashes plus one combat light value (92.5173 → 89.5707 after the corruption-motion encounter); other recorded fields match. The new final digest is `7be208fb716b5466`. The deterministic repeat and reversed-movement negative control pass.

## Rendering and interface

Shared tokens define charcoal `#131315`, subdued elements, pale-blue player identity, dark tinted fills, 1.5-pixel outlines/structure, and 0.8-pixel dotted guides at 14% opacity. Idle travelling highlights are removed. Projectiles and significant feedback retain the bright palette.

The GPU style probe measured outline/connector/minimum-zoom widths of 2/2/2 raster pixels with antialiasing. Summed linear RGB peaks were 1.309 for structure, 0.205 for a guide, 0.061 for fill and 0.021 for background. Negative controls catch a bright guide and an oversized stroke. Reference, motion, ladder, void-mask, projectile-colour, arena, gallery and warp pixel tests pass.

The menu uses one gameplay-rendered hero at 35% animation speed. Menu, options and atlas previews fit conservative animated bounds. Atlas true-scale/detail/comparison views allocate scrollable space for their full geometry. Closing Options restores menu focus or returns to Pause. Options have Audio, Display, Gameplay and Controls tabs. UI presentation tests sample every hull's real motion over 30 seconds; thumbnail tests also exercise the SVG fallback's explicit connectors.

## Audio

**53 audio policy checks** and shutdown tests pass: eight effect voices, at most four enemy voices, priority preemption, cue cooldowns, silent default pickups, optional pickup aggregation, immediate volume changes, saved startup settings, exact mute and safe shutdown. Startup and context transitions fade ambience; changing its volume applies immediately.

Six reproducible PCM audition files live in `artifacts/audio-review`, generated by `tools/render_audio_audition.gd`. They cover isolated firing, interface/damage/evolution feedback, a dense firefight, optional pickups, menu ambience and default pickup silence. At default gains the dense scene peaks at 0.1013 (approximately −19.9 dBFS); 203 of 643 requests are admitted. Optional pickups admit 10 of 100 requests; default pickups admit none and produce an all-zero waveform. The synthesis checks found no clipping or endpoint discontinuity.

**Perceptual listening remains unverified.** The execution environment does not support audio input. These waveform/policy results cannot establish that a human finds the sound pleasant; the audition files are provided for that review.

## Suite and final evidence

`tools/gates.ps1 -GPU`: **10/10 gates passed**. The suite passed 54 entries (import, 42 headless tests and all 11 GPU tests), with no failures or skipped GPU tests. The runner's own negative tests, sabotaged simulation timing/fill/section checks, and sabotaged rendered timing were all caught. Reports: `artifacts/gates-summary.json`, `artifacts/test-summary.json`; gate logs: `artifacts/test-logs/20260927-030339-567-a5fb51-gates`.

| Measurement | Result |
|---|---:|
| 1,000-projectile simulation mean / p95 | 3.866 / 4.522 ms |
| 2,000-projectile simulation mean / p95 | 6.623 / 9.273 ms |
| Rendered stress mean / p95 | 4.373 / 12.271 ms |
| Novice first evolution median / maximum | 14.665 / 83.07 s; 20/20 within two minutes |
| Exploration / camping median light per minute | 24.4 / 6.4 |
| Respawn median / maximum | 558.3 / 683.3 ms |

Rendered measurement: Godot 4.7.2, Windows, RTX 5070 Ti, Ryzen 7 9800X3D, 1280×800, Mobile Vulkan renderer, HDR/glow enabled, moving camera, 2,000 bullets and 400 pickups, 30 seconds, vsync disabled. These are desktop capacity measurements.

The UI capture review additionally caught and fixed atlas centring, clipped evolution labels, options return focus and true-scale atlas cropping. A final full `tools/test.ps1 -GPU` run after source freeze passed **54/54 entries**, with all 11 GPU tests included, in 111.45 seconds. This includes 195 UI presentation checks, 33 flow checks and seven thumbnail checks. Final suite logs: `artifacts/test-logs/20260927-031950-243-24d00b-suite`. Exports were not rebuilt during this presentation task.

## Captures inspected

All paths below are relative to the project root. PNGs use the production gameplay renderer. The main UI preserves its existing 16:10 aspect ratio: a 1920×1080 window has a 1728×1080 active viewport, which its capture command exports. The separate motion captures use native 1280×800 and 1920×1080 render targets.

| Evidence | Files |
|---|---|
| Supplied reference, rendered fixture and overlay | `artifacts/acceptance/reference_vs_render.png` |
| Menu, Audio options and evolution, both window sizes | `artifacts/acceptance/{menu,options,evolution}_refresh.png` and `_refresh_1080.png` |
| Display, Gameplay, Controls and Pause | `artifacts/acceptance/options_{display,gameplay,controls}_refresh.png`, `pause_refresh.png` |
| All 146 hulls, both window sizes | `artifacts/acceptance/roster_refresh.png`, `roster_refresh_1080.png` |
| Fitted and true-scale atlas review pages | `artifacts/acceptance/atlas_{fitted,true_scale}_page_{1,2,3}.png` |
| Four families at each tier, equal scale | `artifacts/acceptance/family_lightning_t{2,3,4,5,6}.png` |
| Combat, both window sizes | `artifacts/acceptance/combat_{1280x800,1920x1080}_refresh.png` |
| Eight seconds of actual offset-rail, chain and aiming motion | `artifacts/redesign-motion/motion-1280x800.gif`, `motion-1920x1080.gif` |
| Motion frame sequences and manifests | `artifacts/redesign-motion/1280x800/`, `1920x1080/`, `playback-summary.json` |
| Fixed sound scenes and measured levels | `artifacts/audio-review/*.wav`, `manifest.json` |

Both motion captures contain 65 native-resolution PNGs including the eight-second endpoint; each GIF has 64 frames and an exact eight-second duration. Bounds checks reported zero failures. Representative 0/2/4/8-second poses were visually inspected: structural lines stay attached, guides remain subordinate, and the full ships fit their cells. The original three-pod reference fixture remains intact.
