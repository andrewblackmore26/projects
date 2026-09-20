# Runtime interfaces

Godot 4.7.2, typed GDScript. GameTuning owns the approved five-tier thresholds, starter elements, slot budgets, arena dimensions and timing values. The campaign resource selects a persistent seed. The original v0.2 document is retained with approved overrides in LIGHTSHIP_GAME_SPEC.md.

## Ship catalog and evolution

`ShipCatalog.get_ship(id) -> ShipDefinition` returns a duplicate resource or null. `ShipCatalog.roster(element, tier) -> Array[ShipDefinition]` returns player hulls. Canonical IDs are `player_seed` and `player_{element}_t{2..5}_{compact|standard_a|standard_b|heavy}`. Hull parts have stable IDs for reshape matching, circle-family shapes, component identity, mirrored geometry and tier-point costs. The `primary` string and `secondaries` / `passives` arrays identify the complete fixed runtime loadout; no component inventory is implied by the editor's ability to author these slots.

`EvolutionRules.threshold(tier) -> int` returns 100/250/500/900 or -1 at terminal tier. `offers(current_element, tier, absorption, unlocked, previous_offers = [], seed_value = 0) -> Array[String]` returns hull IDs. First evolution ranks absorbed eligible elements with a stable element-order tie break. Later offers select three of the current element's four hulls, replacing one when a different unlocked element exceeds 40% of absorption since the last evolution. The previous set is avoided where alternatives exist. An old fifth-argument string is tolerated for call compatibility and confers no mirror reward.

The UI saves pending offers, previous offers and an offer serial. Combat saves absorption and the selected hull/history. Regrowth asks the rules for a new offer, rather than automatically restoring a lost build.

## Campaign state (v0.3, schema 4)

`CampaignState` is a **square Chebyshev lattice** (spec §11), not the v0.2 wedge/core world. Coordinates are `Vector2i`; serialized keys are canonical `"x,y"` strings via `coord_key`/`key_coord`/`valid_key`.

**Persistent fields** (survive death): `mode`, `world_seed`, `epoch`, `deaths`, `unlocked` (elements earned by absorbing their light, spec §8), `levels_completed`, `best_ring` (Dictionary level -> best ring reached), `story_flags`.

**Per-life fields** (reset whenever `epoch` changes - on death OR on `travel_to_level`): `level`, `current_sector`, `discovered`, `ring_reached`, `boss_down`, and the node light-pool bookkeeping (`_node_state`, private).

`level_seed()` mixes `(world_seed, epoch, level)`, so every life is a fresh, reproducible layout (spec §7 "a fresh seed every life"). `ring(coord)` is Chebyshev (`max(|x|,|y|)`); `tier_of(coord)` is `1 + ring/2` clamped to `GameTuning.MAX_TIER`; `in_bounds(coord)` is `ring(coord) <= level_radius()` (a bounded disc, `GameTuning.LEVEL_RADIUS` per level). `exits_of(coord)` and `boss_coord()` are pure functions of `level_seed()` and the coordinate (see the class doc comment in `campaign_state.gd` for the membrane construction and the boss-placement rule). `archetype_of(coord)` returns one of `transit`/`skirmish`/`dense`/`elite_lair`/`boss`; `element_of(coord)` returns one of the level's revealed elements, rolled per `ELEMENT_BLOCK_SIZE`x`ELEMENT_BLOCK_SIZE` block so territories read on a map.

### `sector_at(coord, now = 0.0) -> Dictionary` (the descriptor contract)

Pure and read-only — never mutates the profile, never populates a persistent map, and gives the same result regardless of call order. Keys:

| Key | Meaning |
|---|---|
| `coord`, `id` | The coordinate and its canonical string key |
| `in_bounds` | False beyond the level's perimeter (a sealed cell still gets a descriptor, with empty `exits`/`enemy_hulls`) |
| `ring`, `tier` | Chebyshev ring and the ring-derived difficulty tier |
| `element`, `archetype` | This node's rolled element and archetype |
| `kind` | `origin`, `boss`, or `regular` |
| `exits` | `Array[Vector2i]` of open cardinal directions (`Vector2i.UP/RIGHT/DOWN/LEFT`) |
| `encounter_seed`, `encounter_epoch` | Deterministic RNG seed for the node's own local rolls, and the profile's current epoch (combat clears its sector cache whenever this changes) |
| `pool_size`, `pool_remaining`, `resource_budget` | The node's light pool (spec §7): authored size, remaining after refill-since-last-visit, and the same remaining value combat reads as its economy budget |
| `respawn_cooldown` | `GameTuning.ENEMY_RESPAWN_COOLDOWN` - enemies respawn on this cooldown; the pool does not follow (spec §7) |
| `boss_down`, `cleared` | True only for the level's boss cell once its boss is beaten (a defeated boss never respawns; everything else always repopulates on return) |
| `enemy_hulls`, `elite_hulls` | `Array[String]` of EXACT roster hull ids to spawn, named directly by the descriptor (see `ShipGenerator.hull_id`) - combat never guesses a hull from `(element, tier)` at spawn time |
| `boss_hull` | The boss's exact roster hull id, only set when `kind == "boss"` |
| `starter_pickups` | `Array[String]` of elements to drop at the origin, only set when `kind == "origin"` - always drawn from the level's own revealed prefix, never a hard-coded list |

`can_enter(from, to, light = 0)` checks cardinal adjacency, `in_bounds(to)`, and that `to - from` is actually one of `exits_of(from)` - a sealed perimeter or a missing membrane both refuse entry. `on_enter(coord)` updates `current_sector`, `discovered` and `ring_reached`; it has no return value (no waypoint/unlock side effects - those are separate calls, below).

`unlock_element(element, amount) -> bool` is the single place spec §8's "first time you absorb a light type" unlock happens; it returns true only on the call that newly unlocks it (`amount <= 0`, an unknown element, or an already-unlocked element all return false with no side effect). `complete_level() -> {level_completed, revealed_element, next_level}` is idempotent: call it every time a boss dies; it only fires `level_completed` and reveals the next element the first time a given level is finished, and always updates `best_ring`. `is_level_complete(level = current)` and `campaign_complete()` read `levels_completed`. `travel_to_level(new_level)` is a level-select jump: it is also an epoch change (fresh layout, spec preamble "the short inverted warp plays on death and on level travel").

`node_pool_state(coord, now)` and `record_node_left(coord, now, remaining)` implement the light-pool refill (`GameTuning.NODE_POOL_REFILL_PER_MINUTE`), keyed by the campaign's own elapsed-seconds clock (never a wall clock, per lessons.md) so refill during time away from a node is deterministic and testable.

`on_death()` preserves everything in the persistent list, advances `epoch`, and resets the per-life fields via `_reset_life()`. `to_dict()` emits gameplay schema 4. `from_dict()` migrates any schema `< 4` profile (including genuine v0.2 schema-3 saves) by keeping `deaths` and whitelisted `reboot_*` story flags and resetting everything else to a fresh campaign, per the approved preamble ("unlocks reset to Lightning"). `import_demo(profile)` is a P5a stopgap (full demo/dev mode plumbing is P5b): it carries over compatible fields and always starts at level 1, origin, epoch 0.

## Combat and presentation

`CombatWorld` owns the player's light bar, hull history, actors, projectiles, effects, arena collision and encounter snapshots. `setup_player(element, tier, light, legacy_stolen, position)` remains a compatibility constructor; ordinary starts use neutral/T1/40. `evolve_hull(id) -> bool` validates a threshold and next-tier hull. `collect_light(amount, element)` returns the absorbed amount and updates the one bar and diet. `start_sector(descriptor)` loads an encounter. `set_command(ShipCommand)` supplies movement, aim, primary and three secondary actions. `snapshot()` / `restore(data)` preserve the current run.

The main controller owns menus, dialogue, map, evolution offers, node transitions and saving. Actors use world-space positions in the 1792×1120 arena; the camera follows the player. Projectiles use the arena boundary for lifetime and ricochet. Renderer animation may continue during paused menus but must not advance combat.

## Save and platform boundary

`SaveService.save_snapshot(profile, run, slot = "campaign") -> Error` and `load_snapshot(slot) -> {profile, run}` use envelope version 3, typed variant payloads and SHA-256 validation. Loads try the primary, backup and temporary candidates. Campaign gameplay schema and envelope schema are separate. Generic settings and Steam ledger snapshots are not interpreted as campaigns.

Legacy campaigns are copied byte-for-byte to `.legacy-v1` or `.legacy-v2` before a migrated profile is returned. The source is untouched until an ordinary save. Compatible unlocks/deaths and whitelisted narrative flags survive; removed progress is retained in `legacy_history`. The new run begins at origin with no old combat snapshot. A future schema or invalid archive is rejected safely.

`SaveService.import_demo(destination_slot)` refuses to overwrite an existing campaign, imports compatible demo state, and starts a fresh origin run while preserving the `seen_lines` dictionary. Device settings remain local.

`PlatformService` provides optional Steam Input, achievement queuing and cloud transport. Cloud inspection never replaces either save; loading a legacy local save may create its preservation archive. Conflict resolution requires a concrete local/cloud choice. Cloud comparisons use the pure `preview_migration(snapshot)` transform, so choosing a legacy remote save does not reopen the same conflict. `install_snapshot(reviewed_bytes, slot)` preserves the exact reviewed transport bytes and prior local backup, then archives and migrates through `load_snapshot` before gameplay resumes. Distinct legacy imports keep distinct hash-suffixed archives. Consult STEAM_SETUP.md for account configuration and current transport names; mocked tests do not certify a real Steam account or device.

