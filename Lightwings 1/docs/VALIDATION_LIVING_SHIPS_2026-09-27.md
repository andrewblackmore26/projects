# Living ships validation — 2026-09-27

This record covers the living-ships implementation against the supplied orbiting
elite, following-chain and projectile HTML references. It supersedes the earlier
presentation record for ship appearance and geometry. The existing menu layout
and quiet audio policy remain in place.

## Implementation

- Saturated reference colours, dark interiors, 1.5px rims, 2px connections,
  dotted guides and rounded travelling rim lights share production rendering.
  Revision-3 component roles use the reference rim speeds and staggered phases.
- All 146 shipped hull IDs now have revision-3 anatomy. Nested weapon assemblies,
  three-pod fans and nine-link tapered chains retain original weapons and budgets.
- Historical following operates at the simulation step and supplies rendering,
  connection endpoints, collision, muzzles and bounds. Detached branches stop
  participating immediately and release as recognisable outlined pieces.
- Weapon-coloured projectiles have independent pooled path histories, distinct
  interior details, continuous beam pulses and reference impact profiles.
- Saved revisions 1 and 2 resolve their archived anatomy. Loading preserves
  component state; new spawns and evolution use revision 3. Custom definitions
  and chain history round-trip through encounter persistence.

## Visual evidence

Captures use the production renderer and shared simulation poses. Native PNG
sequences and manifests are retained alongside encoded GIFs in
`artifacts/living-ships`. Each resolution has the following evidence:

| Evidence | Resolution | Sampling |
|---|---|---|
| Elite orbit, chain following and breakup | 1280×800 and 1920×1080 | 16s, 8fps |
| Five-weapon range | 1280×800 and 1920×1080 | 6s, 10fps |
| Menu and evolution | 1280×800 and 1920×1080 | 4s each, 8fps |
| Crowded combat | 1280×800 and 1920×1080 | 4s, 8fps |
| Four player families, irregular elite, all five bosses, following chain | 1280×800 and 1920×1080 | Six pages, 8s each, 8fps |
| Complete roster | 1280×800 and 1920×1080 | 13 contact pages, all 146 IDs |
| Options | 1280×800 and 1920×1080 | Still captures |

Review clips: [reference machines](../artifacts/living-ships/reference-1280x800.gif),
[weapon range](../artifacts/living-ships/projectiles-1280x800.gif),
[menu](../artifacts/living-ships/menu-1280x800.gif),
[evolution](../artifacts/living-ships/evolution-1280x800.gif),
[combat](../artifacts/living-ships/combat-1280x800.gif), and
[largest boss](../artifacts/living-ships/roster-1280x800/03-irregular-boss.gif).
The corresponding 1920×1080 files and every roster page sit beside these captures.

The moving roster harness checks bounds at every 60Hz simulation tick, including
frames between exported images. Its contact-sheet manifest lists every hull ID
and geometry revision. The reference and UI captures also check preview bounds.

Source values and multiple rendered animation frames were compared for orbit
direction, breathing, pod movement, independent rim phases, chain turns, breakup,
projectile identity and preview fit. The supplied HTML was inspected as source;
local browser playback was blocked. This record does not claim live playback of
the original HTML or an exact browser-to-Godot pixel comparison.

## Deterministic combat comparison

`tests/ship_geometry_combat_comparison.gd` records revisions 1, 2 and 3 over three
seeds in two scenarios, plus a repeated run. The repeat is deterministic. Evidence
is retained in `artifacts/geometry_combat_comparison.json`.

The 60-second skirmish uses a tier-3 player against two tier-1 drones and a tier-1
chain. Revision-2 kills `[1, 2, 1]` become `[2, 2, 4]` with revision 3. First-kill
ticks change from `[839, 2237, 62]` to `[786, 794, 62]`. Paid sector rewards remain
160 in every run. All players survive, but one revision-3 seed finishes with
164.025 light rather than 500. These are meaningful changes in collision outcomes,
despite equal health/reward budgets; no weapon or damage rebalance was applied.

The 30-second stress scenario produces 180 player shots and zero kills in every
revision-3 seed. Enemy shots change from `[130, 137, 143]` in revision 2 to
`[129, 132, 137]` in revision 3. This comparison exposes consequences of changed
anatomy; it does not assert identical combat outcomes or establish final balance.

## Automated verification

The final integrated suite passed 58 tests plus project import: 59 passing
entries, zero failures and no skipped GPU tests, in 133.4 seconds. This includes
all 12 GPU rendering suites. The complete `tools/gates.ps1 -GPU` run passed all
10 gates, including the acceptance bots and every negative control. It completed
at 05:48:23 local time. Logs are retained in
`artifacts/test-logs/20260927-053159-264-98bf6a-gates`; the machine-readable result
is `artifacts/gates-summary.json`. Every gate stderr log is empty.

| Focused coverage included in the full suite | Result |
|---|---|
| Revision-3 roster identity, weapons and tier-dependent budgets | 4,069 checks passed |
| Revision-1/2 actors, compressed cached encounters and custom definitions | 1,764 checks passed |
| Exact reference geometry, rim cadence and phases | 61 checks passed |
| Following, pose consistency, persistence and detachment | 33 checks passed |
| Projectile histories, emitter bindings, beam paths and slot reuse | 53 headless and 23 GPU checks passed |
| UI layout, preview envelopes and shared presentation | 195 checks passed |
| Quiet audio policy | 53 checks passed; shutdown suite also passed |

The thumbnail fill probe now samples the pixel containing an empty pod centre.
Its earlier location overlapped the restored rim highlight. It requires the exact
shared fill colour rather than loosening the old brightness bound.

The initial 2,000-projectile CPU run exposed a 12.094ms mean against the existing
12ms budget. Static ribbon instance records removed redundant per-frame packing;
all 21 position-history samples and the live appearance remain. In the isolated
verification, upload preparation fell from 3.33ms to 1.439ms and total simulation
mean fell to 9.359ms. Performance budgets were not changed.

### Final performance and acceptance results

| Measurement | Mean / budget | p95 / budget |
|---|---|---|
| Headless simulation and buffer preparation, 1,000 projectiles | 5.996 / 7.500ms | 7.764 / 12.000ms |
| Headless simulation and buffer preparation, 2,000 projectiles | 9.390 / 12.000ms | 12.547 / 17.500ms |
| Rendered gameplay, 2,000 projectiles | 6.931 / 14.000ms | 16.897 / 26.000ms |

The rendered sample used Godot 4.7.2, Vulkan Mobile, an NVIDIA RTX 5070 Ti and
AMD Ryzen 7 9800X3D on Windows, at 1280×800 with vsync disabled. It covered
30 seconds, 3,609 frames, 17 actors and 400 pickups. The headless and rendered
measurements use separate harnesses and are not directly comparable. These are
desktop measurements, not Steam Deck qualification.

All 11 acceptance checks passed, including three negative controls. All 20 novice
seeds evolved within two minutes; the median was 17.8 seconds and the maximum
68.15 seconds. Median exploration income exceeded camping income (24.4 versus
6.4 light per minute), and camping returns declined in all 20 seeds. Recovery
from death took at most 683.3ms. Targeting acceptance also passed.

All 18 capture groups report zero bounds failures. Each resolution's contact
sheet covers 146 unique hull IDs, and moving captures cover all five bosses.
Exported Windows packages were not rebuilt in this run.

### Recorded trace audit

The old golden trace was audited before rebaselining. Archived revision-2 anatomy
reproduces every old recorded hash after removing only the newly saved hull and
chain metadata and restoring the old projectile visual radius. Its public trace
fields are unchanged. `artifacts/geometry_trace_audit.json` retains the raw states
and comparison evidence.

Revision 3 changes one public trace value: the corruption motion sample retains
99.0 light instead of 89.5707. The moved following-chain emitter selects a different
target; exactly 9.429333 damage moves to the drone (52 to 42.570667 HP), with the
same 35.36 damage rate over 0.2666667 seconds. Position, aim, offers, profile and
counts otherwise match. The updated trace retains repeatability and the reversed
command-order negative control.
