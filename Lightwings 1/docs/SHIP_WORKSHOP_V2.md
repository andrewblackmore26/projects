# Ship workshop v2

Open **Ship workshop** from the game menu or run `scenes/ship_editor.tscn`. The runtime roster contains one neutral seed, four hull families per element in tiers 2–5 (81 player hulls), plus 25 regular enemies, 25 elites and five rivals.

## Authoring

- Use **Load Ship…** to browse thumbnail rows, search by name/ID, filter element/tier/role/faction, sort by any metadata field, or inspect missing roster slots. Duplicate a hull for the next tier, rename its display name, or explicitly confirm deletion.
- Drag the selected Body, Primary, Secondary or Passive object onto the canvas. Click the preview card to place at the default position. Enemy-only components appear under Secondary for non-player factions.
- Player symmetry stays enabled. Linked parts move, resize and delete together, including attached tethers; each mirrored component mount consumes one logical slot. Centerline parts stay on the centerline when dragged.
- Concentric rings place three independently editable ring parts. Ellipses are limited to Corruption. Guide spacing is 20 design pixels; right is forward in the authoring canvas, while stored/runtime coordinates retain forward-up.
- Every body part declares a statistic and contribution. Contributions add to speed 180, turn 10 and pickup radius 90 before role speed/turn modifiers. The hull's HP buffer remains exactly Compact 0.8, Standard 1.0 or Heavy 1.3. TP is recomputed from geometry, body contribution and unique component mounts; manually changing stored totals cannot bypass budgets.
- **Save** blocks invalid geometry, symmetry, component/faction/tier/slot or TP states. Footprint and disconnected-body findings are warnings. Resource filenames must match hull IDs. Save resources in `content/ships` to make them discoverable by the game and library; JSON is a portable import/export format.
- **Bullet preview** runs the authored draft in an isolated production `CombatWorld`, including unsaved drafts. Player loadouts fire against an immortal dummy. Enemy/elite previews attack an invulnerable player, with independent elite weapon HP and cooldown values displayed. Enable **Pilot ship** to test-flight the authored hull with WASD movement, mouse aim/LMB fire and Space/Shift/Q secondaries. Close the preview to continue editing. This does not change the campaign.

## Offline description generation

**Generate locally** compiles a bounded template description. It makes no network calls and needs no credentials. Supported terms: one of Fire/Lightning/Void/Corruption/Plasma, tier 1–5 (`tier 3` or `t3`), Compact/Standard A/Standard B/Heavy, optional player/enemy/elite/rival, and exact component names from the palette. Synonyms include `mines` → Mine layer, `missiles` → Seeker missiles, `rockets` → Rocket launcher and `poison` → Poison cloud. Longer names such as Homing beam are matched before Beam.

Examples: `compact fire tier 3 with ricochet and mines`; `void t3 with homing beam and shield`.

Unspecified fields use Corruption, tier 2, Standard A and player; unspecified slots retain the template loadout. Unrecognized words are reported after generation rather than silently claiming to interpret arbitrary geometry. Invalid requested loadouts are rejected. Every accepted draft remains fully editable and uses the same validator as saved resources and JSON imports.

## Verification and regeneration

`tools/test.ps1` covers resources, semantic budgets, portable round trips, generation, editor save/library/play preview and morph geometry. `tools/test.ps1 -GPU` additionally verifies HDR running lights, constant screen-space widths and Void occlusion. `scripts/ships/export_catalog.gd` preserves existing authored files by default; its `--rebuild` option deliberately regenerates the full template roster. `scripts/editor/author_roster.gd` is the explicit initial-roster rebuild utility and overwrites the canonical hull files.

