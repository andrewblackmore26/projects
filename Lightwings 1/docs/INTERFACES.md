# Runtime interfaces

Godot 4.7.2, typed GDScript. GameTuning owns the approved five-tier thresholds, starter elements, slot budgets, arena dimensions and timing values. The campaign resource selects a persistent seed. The original v0.2 document is retained with approved overrides in LIGHTSHIP_GAME_SPEC.md.

## Ship catalog and evolution

`ShipCatalog.get_ship(id) -> ShipDefinition` returns a duplicate resource or null. `ShipCatalog.roster(element, tier) -> Array[ShipDefinition]` returns player hulls. Canonical IDs are `player_seed` and `player_{element}_t{2..5}_{compact|standard_a|standard_b|heavy}`. Hull parts have stable IDs for reshape matching, circle-family shapes, component identity, mirrored geometry and tier-point costs. The `primary` string and `secondaries` / `passives` arrays identify the complete fixed runtime loadout; no component inventory is implied by the editor's ability to author these slots.

`EvolutionRules.threshold(tier) -> int` returns 100/250/500/900 or -1 at terminal tier. `offers(current_element, tier, absorption, unlocked, previous_offers = [], seed_value = 0) -> Array[String]` returns hull IDs. First evolution ranks absorbed eligible elements with a stable element-order tie break. Later offers select three of the current element's four hulls, replacing one when a different unlocked element exceeds 40% of absorption since the last evolution. The previous set is avoided where alternatives exist. An old fifth-argument string is tolerated for call compatibility and confers no mirror reward.

The UI saves pending offers, previous offers and an offer serial. Combat saves absorption and the selected hull/history. Regrowth asks the rules for a new offer, rather than automatically restoring a lost build.

## Campaign state

`CampaignState.configure(is_demo)` starts fresh progression. Coordinates are `Vector2i`; serialized keys are canonical `"x,y"` strings. `sector_at(coord)` is read-only and generates a descriptor without populating the persistent map. Its fields include `id`, `coord`, `element`, Euclidean `distance`, `tier`, `kind`, `core_id`, `cleared`, `exits`, `encounter_seed`, `encounter_epoch`, `enemy_count`, `elite_count`, `resource_budget` and `ambient_budget`. Kinds are `origin`, `regular`, `core` and `demo_core`. `layer` and `leader_id` are compatibility aliases for floored distance and core identity.

`can_enter(from, to, light = 0)` returns `{allowed, reason}`. Only cardinal adjacency matters; it never checks a gate, tier, energy requirement or remaining opponent. `on_enter(coord)` updates the current node, discovery, region unlock and distance waypoint; it returns `{waypoint, checkpoint, unlocked}`. The UI must call it on actual entry, not when previewing map tiles.

`defeat_core(core_id)` records the objective as soon as its rival dies, even while regular opponents survive; `core_defeated` remains distinct from whole-node `cleared`. `clear_sector(coord)` records encounter completion and returns `{waypoint, checkpoint, core, leader, completed, demo_completed, unlocked}`. Core rewards are idempotent. `defeated_leaders` is retained as the persisted collection name but now stores the five element core IDs. No separate finale exists.

`checkpoints[coordinate_key]` stores `{tier, distance, source}` with source `distance` or `core`. `can_teleport(coord, current_tier)` allows jumps only from origin to an earned waypoint whose tier requirement is met. `known_cores()` returns `{id, element, coord, direction, beaten}` entries for eligible known elements; demo exposes only its Fire objective. `core_coordinate(element)` supplies its deterministic node.

`on_death()` preserves seed, discoveries, waypoints, cores, unlocks and story progress, advances the encounter epoch and resets regular clear flags. `to_dict()` emits gameplay schema 3 and sparse progress, not a generated infinite map. `from_dict()` validates canonical coordinates and collection fields. `import_demo(profile)` preserves earned coordinates and compatible progression, recalculates full-map waypoint requirements and resets to origin.

## Combat and presentation

`CombatWorld` owns the player's light bar, hull history, actors, projectiles, effects, arena collision and encounter snapshots. `setup_player(element, tier, light, legacy_stolen, position)` remains a compatibility constructor; ordinary starts use neutral/T1/40. `evolve_hull(id) -> bool` validates a threshold and next-tier hull. `collect_light(amount, element)` returns the absorbed amount and updates the one bar and diet. `start_sector(descriptor)` loads an encounter. `set_command(ShipCommand)` supplies movement, aim, primary and three secondary actions. `snapshot()` / `restore(data)` preserve the current run.

The main controller owns menus, dialogue, map, evolution offers, node transitions and saving. Actors use world-space positions in the 1792×1120 arena; the camera follows the player. Projectiles use the arena boundary for lifetime and ricochet. Renderer animation may continue during paused menus but must not advance combat.

## Save and platform boundary

`SaveService.save_snapshot(profile, run, slot = "campaign") -> Error` and `load_snapshot(slot) -> {profile, run}` use envelope version 3, typed variant payloads and SHA-256 validation. Loads try the primary, backup and temporary candidates. Campaign gameplay schema and envelope schema are separate. Generic settings and Steam ledger snapshots are not interpreted as campaigns.

Legacy campaigns are copied byte-for-byte to `.legacy-v1` or `.legacy-v2` before a migrated profile is returned. The source is untouched until an ordinary save. Compatible unlocks/deaths and whitelisted narrative flags survive; removed progress is retained in `legacy_history`. The new run begins at origin with no old combat snapshot. A future schema or invalid archive is rejected safely.

`SaveService.import_demo(destination_slot)` refuses to overwrite an existing campaign, imports compatible demo state, and starts a fresh origin run while preserving the `seen_lines` dictionary. Device settings remain local.

`PlatformService` provides optional Steam Input, achievement queuing and cloud transport. Cloud inspection never replaces either save; loading a legacy local save may create its preservation archive. Conflict resolution requires a concrete local/cloud choice. Cloud comparisons use the pure `preview_migration(snapshot)` transform, so choosing a legacy remote save does not reopen the same conflict. `install_snapshot(reviewed_bytes, slot)` preserves the exact reviewed transport bytes and prior local backup, then archives and migrates through `load_snapshot` before gameplay resumes. Distinct legacy imports keep distinct hash-suffixed archives. Consult STEAM_SETUP.md for account configuration and current transport names; mocked tests do not certify a real Steam account or device.

