# Ship workshop v2 (v0.3)

Open **Ship workshop** from the game menu or run `scenes/ship_editor.tscn`. The runtime roster is **141 hulls**: one neutral seed plus four hull families per element across six tiers (101 player hulls), plus 25 regular enemies, 10 elites and 5 bosses (`ShipGenerator.roster_manifest()`/`player_hull_count()` are the source of truth — the gallery title derives from the manifest, it is never a hard-coded number).

## Geometry: two primitives, not five

A hull is built from exactly two primitive shapes, both on `PartDefinition`: **circle** (`radius`, `filled`) and **line**. There is no ellipse, ring, arc, crescent or tether any more — a `filled=false` circle IS what used to be a ring; a `line` IS what used to be a tether; corruption's old ellipse lobes are round; void's old crescent is a rimmed circle with a black covering circle over part of its rim. Every part (except the one literally named `core`) declares a `parent_id`, so the whole hull is a parent graph, not a flat list — detachment (a limb blowing off in combat) is a subtree walk of that graph.

## Authoring

- Use **Load Ship…** to browse thumbnail rows, search by name/ID, filter element/tier/role/faction, sort by any metadata field, or inspect missing roster slots. Duplicate a hull for the next tier, rename its display name, or explicitly confirm deletion.
- Drag the selected Body (circle or line), Primary, Secondary or Passive object onto the canvas. Click the preview card to place at the default position. Enemy-only components appear under Secondary for non-player factions.
- The **inspector** for a selected circle/line shows Parent, Filled (circles only), Radius, HP — the same fields `PartDefinition` stores, no derived size/rotation/weapon_hp fields exist any more.
- The **Motion tab** authors a `GroupDefinition` on a subtree: `root_id` (which circle's subtree moves), `orbit_radius`/`orbit_speed` (signed — a mirrored pair uses opposite signs), `drift_amp`/`drift_freq`, `breathe_amp`, `chain_mode` (e.g. `rigid`, `sway`, `whip`), `reach_ring` (synthesizes a dashed ring around the root at `hull_radius+9`, void's authored "reach" stat carrier). A subtree orbits the point where its ROOT attaches to its own PARENT, not around itself.
- Player symmetry stays enabled. Linked parts move, resize and delete together, including attached lines; each mirrored component mount consumes one logical slot. Centerline parts stay on the centerline when dragged.
- Every body part declares a statistic and contribution. Contributions add to speed 180, turn 10 and pickup radius 90 before role speed/turn modifiers. The hull's HP buffer remains exactly Compact 0.8, Standard 1.0 or Heavy 1.3. TP is recomputed from geometry, body contribution and unique component mounts, against the six-tier budget table (`GameTuning.TP_BUDGETS`, tier 6 cap 36); manually changing stored totals cannot bypass budgets.
- **Save** blocks invalid parent-graph geometry (cycles, a chain that never reaches `core`, a line ending on a line), symmetry, component/faction/tier/slot or TP states, and circle/line count caps (≤128 circles, ≤512 lines). Footprint and disconnected-body findings are warnings. Resource filenames must match hull IDs. Save resources in `content/ships` to make them discoverable by the game and library; JSON (§22 shape, below) is a portable import/export format, with a v2→v3 schema upgrade path for older authored files.
- **Bullet preview** runs the authored draft in an isolated production `CombatWorld`, including unsaved drafts. Player loadouts fire against an immortal dummy. Enemy/elite previews attack an invulnerable player, with independent per-circle HP and cooldown values displayed. Enable **Pilot ship** to test-flight the authored hull with WASD movement, mouse aim/LMB fire, Space/Shift/Q secondaries and right-mouse dash. Close the preview to continue editing. This does not change the campaign.

## JSON shape (spec §22)

```json
{
  "id": "elite_lightning_t4_triskel", "name": "Triskel", "faction": "elite",
  "element": "lightning", "tier": 4, "symmetry": "radial",
  "core": { "id": "core", "radius": 34, "color": "yellow", "component": "burst_cannon", "hp": 400 },
  "circles": [
    { "id": "hub_a", "radius": 15, "parent": "core", "color": "yellow", "hp": 60 },
    { "id": "gun_a", "radius": 5, "parent": "hub_a", "color": "red", "hp": 25, "component": "seeker_missiles" }
  ],
  "lines": [
    { "from": "core", "to": "hub_a", "color": "yellow" }
  ],
  "groups": [
    { "root": "hub_a", "orbit_radius": 96, "orbit_speed": 0.42, "drift_amp": 0.14, "drift_freq": 1.9, "breathe_amp": 0.03, "chain_mode": "rigid", "reach_ring": true }
  ]
}
```

Every circle names its `parent`, so the graph is implicit and detachment is a subtree walk. `groups` is optional and maps 1:1 to `GroupDefinition`. Mirrored parts on player hulls are authored once and generated on the other side.

## Offline description generation

**Generate locally** compiles a bounded template description. It makes no network calls and needs no credentials. Supported terms: one of Fire/Lightning/Void/Corruption/Plasma, tier 1-6 (`tier 3` or `t3`), Compact/Standard A/Standard B/Heavy, optional player/enemy/elite/boss, and exact component names from the palette. Synonyms include `mines` → Mine layer, `missiles` → Seeker missiles, `rockets` → Rocket launcher and `poison` → Poison cloud. Longer names such as Homing beam are matched before Beam.

Examples: `compact fire tier 3 with ricochet and mines`; `void t3 with homing beam and shield`.

Unspecified fields use Corruption, tier 2, Standard A and player; unspecified slots retain the template loadout. Unrecognized words are reported after generation rather than silently claiming to interpret arbitrary geometry. Invalid requested loadouts are rejected. Every accepted draft remains fully editable and uses the same validator as saved resources and JSON imports.

## Verification and regeneration

`tools/test.ps1` covers resources, semantic budgets, portable round trips, generation, editor save/library/play preview and morph geometry, plus `ship_motion_test.gd` (the Motion tab's own evaluator, 19 checks/5 controls) and `ship_roster_test.gd` (825 checks/14 controls). `tools/test.ps1 -GPU` additionally verifies HDR running lights, constant screen-space widths, Void occlusion and `ship_motion_render_test.gd` (a moving group's rim is found at its simulated, not rest, position). `scripts/ships/export_catalog.gd` preserves existing authored files by default; its `--rebuild` option deliberately regenerates the full template roster. `scripts/editor/author_roster.gd` is the explicit initial-roster rebuild utility and overwrites the canonical hull files.

Every export preset excludes `scripts/editor/*` and both `scenes/ship_editor.tscn`/`scenes/gallery.tscn` — the workshop is a development-only surface and is never present in a shipped build (unlike the dev console, which lives outside that folder specifically so Dev mode can start in an exported package; see `scripts/platform/package_validation.gd`).
