class_name CampaignState
extends RefCounted
## v0.3 world model (spec §7, §8, §11). Replaces the v0.2 wedge/core world.
##
## Persistent across death: mode, world_seed, epoch, deaths, unlocked
## (absorb-earned elements), levels_completed, best_ring (per level), story
## flags.
## Reset on an epoch change (death OR travelling to a different level):
## current_sector, discovered, ring_reached, boss_down, and the per-life node
## light-pool bookkeeping. `level` itself is only changed by `travel_to_level`;
## dying does not change which level you are on.
##
## `epoch` increments on every epoch change, and `level_seed()` mixes
## (world_seed, epoch, level), so every life is a fresh, reproducible layout
## (spec §7 "a fresh seed every life"; §11 "deterministic hash of (level
## seed, x, y)").
##
## Hash helpers (`level_seed`, `boss_coord`) and the lattice seams
## (`neighbour_offsets`, `neighbours_of`) are ordinary INSTANCE methods, not
## static, precisely so a test can subclass CampaignState and override exactly
## one of them to build a deliberate mutant (see tests/world_generation_test.gd).

const Tuning = preload("res://scripts/data/game_tuning.gd")
const DEFAULT_CAMPAIGN = preload("res://content/campaign/default_campaign.tres")
## Modernization M3: the OPEN 8-neighbour lattice (the maze is gone). Bearing
## order E, SE, S, SW, W, NW, N, NE with y pointing down, i.e. clockwise on
## screen; `nearest_bearing` breaks an exact tie toward the LOWER index here.
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
const ELEMENTS: Array[String] = Tuning.ELEMENTS
const GAMEPLAY_VERSION: int = SchemaVersion.CURRENT

var mode: String = "campaign"
var demo: bool = false
var world_seed: int = DEFAULT_CAMPAIGN.campaign_seed
var epoch: int = 0
var deaths: int = 0
var unlocked: Array = []
var levels_completed: Array = []
var best_ring: Dictionary = {}
var story_flags: Dictionary = {}
## Discarded state from a migrated pre-v4 save, keyed "schema_<N>_unlocked"
## (spec preamble: "unlocks reset to Lightning" -- the old list survives here
## instead of vanishing, per tasks/todo.md P5b save-schema item).
var legacy_history: Dictionary = {}

var level: int = 1
var current_sector: Vector2i = Vector2i.ZERO
var discovered: Array = []
var ring_reached: int = 0
var boss_down: bool = false
## Per-life node light-pool bookkeeping, keyed by coord_key. Cleared whenever
## the epoch changes (a new layout has nothing to remember). Never touched by
## sector_at() itself, which stays a pure read.
var _node_state: Dictionary = {}

func _init() -> void:
	configure(false)

func configure(is_demo: bool) -> void:
	configure_mode("demo" if is_demo else "campaign")

## Mode-aware configure (campaign / dev / demo -- spec §4). `demo` is kept as
## a plain bool field for the many call sites that only ever asked the old
## binary question; `mode` is the source of truth ModeConfig.from_id reads.
func configure_mode(mode_id: String) -> void:
	mode = mode_id if mode_id in ["campaign", "dev", "demo"] else "campaign"
	demo = mode == "demo"
	epoch = 0
	deaths = 0
	## Dev mode: "every element unlocked from the start" (spec §4).
	unlocked = ELEMENTS.duplicate() if mode == "dev" else [ELEMENTS[0]]
	levels_completed = []
	best_ring = {}
	story_flags = {}
	legacy_history = {}
	level = 1
	_reset_life()

func _reset_life() -> void:
	current_sector = Vector2i.ZERO
	discovered = ["0,0"]
	ring_reached = 0
	boss_down = false
	_node_state.clear()

static func coord_key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]

static func valid_key(key: String) -> bool:
	var pieces: PackedStringArray = key.split(",")
	return pieces.size() == 2 and pieces[0].is_valid_int() and pieces[1].is_valid_int() and coord_key(Vector2i(int(pieces[0]), int(pieces[1]))) == key

static func key_coord(key: String) -> Vector2i:
	if not valid_key(key): return Vector2i.ZERO
	var pieces: PackedStringArray = key.split(",")
	return Vector2i(int(pieces[0]), int(pieces[1]))

## --- Pure geometry (Chebyshev world, spec §11) --------------------------

static func ring(coord: Vector2i) -> int:
	return maxi(absi(coord.x), absi(coord.y))

func level_radius() -> int:
	return int(Tuning.LEVEL_RADIUS[clampi(level - 1, 0, Tuning.LEVEL_RADIUS.size() - 1)])

func in_bounds(coord: Vector2i) -> bool:
	return ring(coord) <= level_radius()

func tier_of(coord: Vector2i) -> int:
	return clampi(1 + ring(coord) / Tuning.RING_TIER_DIVISOR, 1, GameTuning.MAX_TIER)

## `level_seed` is the seam a mutant control overrides to prove the
## fresh-seed-every-life check can fail (see tests/world_generation_test.gd).
func level_seed() -> int:
	return hash("%d:%d:%d" % [world_seed, epoch, level])

func _hash_cell(x: int, y: int, salt: String) -> int:
	return absi(hash("%d:%d:%d:%s" % [level_seed(), x, y, salt]))

## --- The open lattice (modernization M3; replaces the v0.3 maze) --------
## Every in-bounds cell connects to every in-bounds cell around it, diagonals
## included: 8 inside, 5 on an edge, 3 at a corner. The whole rim of a node is
## an exit, and a rim angle leads to the neighbour whose bearing is nearest
## (`nearest_bearing`, the one choke point), so the arcs of out-of-bounds
## bearings fold into their in-bounds neighbours and every rim point exits.

## Overridable seam: the candidate offsets before the bounds filter. A mutant
## that drops the diagonals is expected to fail the 3/5/8 neighbour census.
func neighbour_offsets() -> Array[Vector2i]:
	return NEIGHBOURS

## Overridable seam: a mutant that skips the in-bounds filter is expected to
## fail the "every rim angle maps to an in-bounds neighbour" check.
func neighbours_of(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not in_bounds(coord): return result
	for dir: Vector2i in neighbour_offsets():
		if in_bounds(coord + dir): result.append(dir)
	return result

## The ONE rule that turns a rim angle into a bearing: the direction in `dirs`
## with the smallest absolute angular difference to `angle` (radians, y down).
## An exact tie goes to the lower index in NEIGHBOURS, whatever order `dirs`
## arrives in. Returns ZERO only when `dirs` is empty.
static func nearest_bearing(dirs: Array, angle: float) -> Vector2i:
	var best: Vector2i = Vector2i.ZERO
	var best_diff: float = INF
	var best_rank: int = 1 << 30
	for entry: Variant in dirs:
		var dir: Vector2i = entry
		if dir == Vector2i.ZERO: continue
		var diff: float = absf(angle_difference(bearing_angle(dir), angle))
		var rank: int = NEIGHBOURS.find(dir)
		if rank < 0: rank = NEIGHBOURS.size()
		if diff < best_diff or (diff == best_diff and rank < best_rank):
			best = dir
			best_diff = diff
			best_rank = rank
	return best

## A bearing's angle in double precision (Vector2.angle() is float32, ~6e-6 deg off at 45 deg).
static func bearing_angle(dir: Vector2i) -> float:
	return atan2(float(dir.y), float(dir.x))

func neighbour_for_angle(coord: Vector2i, angle: float) -> Vector2i:
	return nearest_bearing(neighbours_of(coord), angle)

## --- The boss cell (spec §11: "sits on the perimeter... never a corner or
## adjacent to an axis"). The rule predates the open lattice, where it no
## longer guards against single-exit highways; it is kept unchanged so boss
## placement stays stable per seed across the maze -> lattice change. -----

func _boss_candidates() -> Array[Vector2i]:
	var r: int = level_radius()
	var result: Array[Vector2i] = []
	for x: int in range(-r, r + 1):
		for y: int in range(-r, r + 1):
			var coord: Vector2i = Vector2i(x, y)
			if ring(coord) != r: continue
			var ax: int = absi(x)
			var ay: int = absi(y)
			if ax == r and ay == r: continue # corner
			var free: int = ay if ax == r else ax
			if free <= 1: continue # on/adjacent to an axis
			result.append(coord)
	return result

## Overridable seam: a mutant that biases this to ring R-1 is expected to
## fail the boss-on-the-perimeter check.
func boss_coord() -> Vector2i:
	var candidates: Array[Vector2i] = _boss_candidates()
	if candidates.is_empty(): return Vector2i(level_radius(), 0)
	var choice: int = _hash_cell(0, 0, "boss") % candidates.size()
	return candidates[choice]

## --- Archetypes, elements, enemy population (spec §7, §11) --------------

func archetype_of(coord: Vector2i) -> String:
	if coord == boss_coord(): return "boss"
	var band: int = clampi(ring(coord) / Tuning.RING_BAND_WIDTH, 0, Tuning.ARCHETYPE_TABLE.size() - 1)
	var table: Dictionary = Tuning.ARCHETYPE_TABLE[band]
	var roll: float = float(_hash_cell(coord.x, coord.y, "archetype") % 100000) / 100000.0
	var cumulative: float = 0.0
	for key: String in ["transit", "skirmish", "dense", "elite_lair"]:
		cumulative += float(table.get(key, 0.0))
		if roll < cumulative: return key
	return "dense"

static func _floor_div(value: int, divisor: int) -> int:
	return int(floori(float(value) / float(divisor)))

func _element_block(coord: Vector2i) -> Vector2i:
	var size: int = Tuning.ELEMENT_BLOCK_SIZE
	return Vector2i(_floor_div(coord.x, size), _floor_div(coord.y, size))

## Dev mode reveals every element regardless of level ("every enemy element
## in the node pool", spec §4); campaign/demo reveal one level at a time.
func _revealed_elements() -> Array:
	if mode == "dev": return Array(ELEMENTS).duplicate()
	return Array(ELEMENTS).slice(0, clampi(level, 1, ELEMENTS.size()))

func element_of(coord: Vector2i) -> String:
	if coord == boss_coord(): return str(_revealed_elements()[-1])
	var pool: Array = _revealed_elements()
	if pool.size() <= 1: return str(pool[0])
	var block: Vector2i = _element_block(coord)
	var roll: float = float(_hash_cell(block.x, block.y, "element") % 100000) / 100000.0
	if roll < Tuning.NEW_ELEMENT_WEIGHT: return str(pool[-1])
	var pick: int = _hash_cell(block.x, block.y, "element2") % pool.size()
	return str(pool[pick])

func enemy_count_for(coord: Vector2i) -> int:
	var archetype: String = archetype_of(coord)
	var base: int = int(Tuning.ARCHETYPE_ENEMY_BASE.get(archetype, 2))
	return maxi(0, base + ring(coord) / 3)

func elite_chance_for(coord: Vector2i) -> float:
	var archetype: String = archetype_of(coord)
	var base: float = float(Tuning.ARCHETYPE_ELITE_BASE.get(archetype, 0.0))
	return clampf(base + ring(coord) * 0.01, 0.0, 0.95)

func pool_size_for(coord: Vector2i) -> int:
	var archetype: String = archetype_of(coord)
	var base: float = float(Tuning.ARCHETYPE_POOL_BASE.get(archetype, 100.0))
	return int(roundi(base * (1.0 + ring(coord) * 0.06)))

func _kinds_for(archetype: String) -> Array[String]:
	match archetype:
		"transit": return ["drone"]
		"skirmish": return ["drone", "sentry"]
		"dense": return ["drone", "sentry", "chain"]
		_: return []

func _enemy_hulls_for(coord: Vector2i, archetype: String, element: String, tier: int) -> Array[String]:
	var kinds: Array[String] = _kinds_for(archetype)
	if kinds.is_empty(): return []
	var result: Array[String] = []
	for i: int in range(enemy_count_for(coord)):
		result.append(ShipGenerator.hull_id("enemy", kinds[i % kinds.size()], element, tier))
	return result

func _elite_hulls_for(coord: Vector2i, archetype: String, element: String, tier: int, roll: int) -> Array[String]:
	if archetype == "elite_lair":
		# Ship design spec §8: the heavy elite, a lair's third kind from node tier 3 up. Wandering
		# elites (below) stay radial or irregular, so their rolls mean what they meant before.
		var kinds: Array[String] = ["radial", "irregular"]
		if tier >= 3: kinds.append("heavy") # (a ternary of two array literals is untyped and will not assign to Array[String])
		return [ShipGenerator.hull_id("elite", kinds[roll % kinds.size()], element, tier)]
	if float(roll % 100000) / 100000.0 < elite_chance_for(coord):
		return [ShipGenerator.hull_id("elite", "radial" if roll % 2 == 0 else "irregular", element, tier)]
	return []

## --- Node pool / respawn bookkeeping (spec §7) ---------------------------
## `now` is the campaign's own elapsed-seconds clock (caller-supplied, so this
## stays deterministic and testable rather than reading a wall clock). Time
## spent away from a node still refills its pool (spec: "refills slowly...
## including time spent away" per the P5a brief); enemies themselves respawn
## on a flat cooldown that does NOT wait on the pool (spec §7).

func node_pool_state(coord: Vector2i, now: float) -> Dictionary:
	var size: float = float(pool_size_for(coord))
	var key: String = coord_key(coord)
	var stored: Dictionary = _node_state.get(key, {})
	var remaining: float = float(stored.get("remaining", size))
	var left_at: float = float(stored.get("left_at", now))
	var elapsed: float = maxf(0.0, now - left_at)
	var refilled: float = minf(size, remaining + size * (Tuning.NODE_POOL_REFILL_PER_MINUTE / 60.0) * elapsed)
	return {"size": size, "remaining": refilled}

func record_node_left(coord: Vector2i, now: float, remaining: float) -> void:
	_node_state[coord_key(coord)] = {"remaining": maxf(0.0, remaining), "left_at": now}

## --- The descriptor (spec §11 "generation is a deterministic hash of
## (level seed, x, y)"; read-only, never mutates the profile) -------------

func sector_at(coord: Vector2i, now: float = 0.0) -> Dictionary:
	var key: String = coord_key(coord)
	var bounded: bool = in_bounds(coord)
	var archetype: String = archetype_of(coord) if bounded else ""
	var element: String = element_of(coord) if bounded else ""
	var tier: int = tier_of(coord) if bounded else 1
	var kind: String = "origin" if coord == Vector2i.ZERO else ("boss" if archetype == "boss" else "regular")
	var roll: int = _hash_cell(coord.x, coord.y, "encounter") % 1000000000
	var pool: Dictionary = node_pool_state(coord, now)
	var result: Dictionary = {
		"coord": coord, "id": key, "in_bounds": bounded, "ring": ring(coord), "tier": tier,
		"element": element, "archetype": archetype, "kind": kind,
		"exits": neighbours_of(coord),
		"encounter_seed": roll, "encounter_epoch": epoch,
		"pool_size": int(pool.size), "pool_remaining": pool.remaining,
		"resource_budget": int(roundi(pool.remaining)),
		"respawn_cooldown": Tuning.ENEMY_RESPAWN_COOLDOWN,
		"boss_down": boss_down if kind == "boss" else false,
		"cleared": boss_down if kind == "boss" else false,
		"enemy_hulls": [], "elite_hulls": [], "boss_hull": "",
		"starter_pickups": [],
	}
	if not bounded: return result
	if kind == "origin":
		var starter_element: String = str(_revealed_elements()[-1])
		result["starter_pickups"] = [starter_element, starter_element, starter_element]
		return result
	result["enemy_hulls"] = _enemy_hulls_for(coord, archetype, element, tier)
	result["elite_hulls"] = _elite_hulls_for(coord, archetype, element, tier, roll)
	if kind == "boss":
		result["boss_hull"] = ShipGenerator.hull_id("boss", "boss", element, tier)
	return result

## --- Mutating world/travel API -------------------------------------------

func can_enter(from: Vector2i, to: Vector2i, _light: float = 0) -> Dictionary:
	if ring(to - from) != 1: return {"allowed": false, "reason": "Nodes must be neighbours"}
	if not in_bounds(from) or not in_bounds(to): return {"allowed": false, "reason": "The perimeter is sealed"}
	return {"allowed": true, "reason": ""}

func discover(coord: Vector2i) -> void:
	var key: String = coord_key(coord)
	if key not in discovered: discovered.append(key)

func on_enter(coord: Vector2i) -> void:
	current_sector = coord
	discover(coord)
	ring_reached = maxi(ring_reached, ring(coord))

## First absorption of a light type unlocks its branch permanently (spec §8).
## Returns true only when this call is the one that newly unlocks it.
func unlock_element(element: String, amount: float = 1.0) -> bool:
	if amount <= 0.0: return false
	if element not in ELEMENTS: return false
	if element in unlocked: return false
	unlocked.append(element)
	return true

## Beating the level's boss completes the level (spec §11) and reveals the
## next level's element into the pool. Idempotent: calling this again after
## the level is already recorded complete changes nothing but boss_down.
func complete_level() -> Dictionary:
	var event: Dictionary = {"level_completed": false, "revealed_element": "", "next_level": level}
	boss_down = true
	best_ring[level] = maxi(int(best_ring.get(level, 0)), ring_reached)
	if level not in levels_completed:
		levels_completed.append(level)
		event.level_completed = true
		if level < Tuning.LEVEL_RADIUS.size():
			event.revealed_element = str(ELEMENTS[level])
			event.next_level = level + 1
	return event

func is_level_complete(target_level: int = -1) -> bool:
	return (level if target_level < 0 else target_level) in levels_completed

## Highest level number THIS mode ever reveals (`ModeConfig`, spec §4/preamble:
## demo is "campaign levels 1-2"). Campaign/dev both cap at the full 5, so this
## only changes behaviour for demo -- a demo save can no longer be walked to
## level 3 by any path (level select is already filtered by
## `ModeConfig.selectable_levels`; this is the second, structural guard so a
## stale "CONTINUE TO LEVEL 3" button binding or a future call site cannot
## reopen the hole `travel_to_level` used to leave, per tasks/todo.md P9).
func level_cap() -> int:
	return mini(Tuning.LEVEL_RADIUS.size(), ModeConfig.from_id(mode).level_cap())

func campaign_complete() -> bool:
	return levels_completed.size() >= level_cap()

## Travelling to a different level is an epoch change (spec: "a fresh seed
## every life" applies on level travel too, per the P5a brief).
func travel_to_level(new_level: int) -> void:
	level = clampi(new_level, 1, level_cap())
	epoch += 1
	_reset_life()

func on_death() -> void:
	deaths += 1
	epoch += 1
	# Spec §7.6: "Ring reached: 14 - best 19" is a per-life speed goal, so
	# best_ring must track the best a life ever reached even when the run
	# ends in death, not only on complete_level()'s "beat the boss" event.
	best_ring[level] = maxi(int(best_ring.get(level, 0)), ring_reached)
	story_flags["reboot_%d" % deaths] = true
	_reset_life()

## Demo -> campaign import (spec preamble: "the demo build flavour is
## campaign levels 1-2... Demo progress imports into the full campaign").
## Carries unlocked (restricted to the demo's own {lightning, fire} pool),
## levels_completed, best_ring, deaths and story flags; the run itself
## (current combat state, discovered map) is always discarded, since a demo
## life has nothing a bounded-disc full campaign can safely resume into.
func import_demo(data: Dictionary) -> void:
	from_dict(data)
	demo = false
	mode = "campaign"
	var demo_pool: Array = ["lightning", "fire"]
	for element: Variant in unlocked.duplicate():
		if element not in demo_pool: unlocked.erase(element)
	if unlocked.is_empty(): unlocked = [ELEMENTS[0]]
	level = 1
	for entry: Variant in levels_completed:
		level = maxi(level, int(entry) + 1)
	level = clampi(level, 1, Tuning.LEVEL_RADIUS.size())
	epoch = 0
	_reset_life()

func to_dict() -> Dictionary:
	return {
		"schema_version": GAMEPLAY_VERSION, "mode": mode, "demo": demo, "world_seed": world_seed,
		"epoch": epoch, "deaths": deaths, "unlocked": unlocked.duplicate(),
		"levels_completed": levels_completed.duplicate(), "best_ring": best_ring.duplicate(true),
		"story_flags": story_flags.duplicate(true), "level": level,
		"current_sector": coord_key(current_sector), "discovered": discovered.duplicate(),
		"ring_reached": ring_reached, "boss_down": boss_down,
		"legacy_history": legacy_history.duplicate(true),
	}

## Migrates any schema < GAMEPLAY_VERSION profile, including genuine v0.2
## (schema 3) saves. SaveService._migrate_gameplay/preview_migration already
## archived the original bytes byte-for-byte as `<slot>.json.legacy-v<N>`
## before this runs, so nothing here needs to touch disk.
func from_dict(data: Dictionary) -> void:
	configure_mode(str(data.get("mode", "demo" if bool(data.get("demo", false)) else "campaign")))
	var incoming_schema: int = int(data.get("schema_version", 1))
	if incoming_schema < GAMEPLAY_VERSION:
		# Pre-v4 (wedge/core) saves have no equivalent world state. Here we
		# only carry forward what still means something: deaths, whitelisted
		# story flags, and any legacy_history the profile already carried.
		# Unlocks reset to the starting element (approved preamble: "v0.2
		# (schema 3) saves: unlocks reset to Lightning") -- the discarded
		# list is kept, not lost, under legacy_history so it is inspectable.
		deaths = maxi(0, int(data.get("deaths", 0)))
		var old_story: Dictionary = _dictionary_field(data, "story_flags")
		for flag: String in old_story:
			if flag.begins_with("reboot_"): story_flags[flag] = bool(old_story[flag])
		legacy_history = _dictionary_field(data, "legacy_history").duplicate(true)
		var old_unlocked: Array = _array_field(data, "unlocked")
		if not old_unlocked.is_empty():
			legacy_history["schema_%d_unlocked" % incoming_schema] = old_unlocked.duplicate()
		return
	legacy_history = _dictionary_field(data, "legacy_history").duplicate(true)
	world_seed = int(data.get("world_seed", DEFAULT_CAMPAIGN.campaign_seed))
	epoch = maxi(0, int(data.get("epoch", 0)))
	deaths = maxi(0, int(data.get("deaths", 0)))
	for element: Variant in _array_field(data, "unlocked"):
		if element in ELEMENTS and element not in unlocked: unlocked.append(element)
	for entry: Variant in _array_field(data, "levels_completed"):
		if entry is int or (entry is float): levels_completed.append(int(entry))
	best_ring = _dictionary_field(data, "best_ring").duplicate(true)
	story_flags = _dictionary_field(data, "story_flags").duplicate(true)
	level = clampi(int(data.get("level", 1)), 1, Tuning.LEVEL_RADIUS.size())
	current_sector = key_coord(str(data.get("current_sector", "0,0")))
	for key: Variant in _array_field(data, "discovered"):
		if key is String and valid_key(key) and key not in discovered: discovered.append(key)
	ring_reached = maxi(0, int(data.get("ring_reached", 0)))
	boss_down = bool(data.get("boss_down", false))

static func _array_field(data: Dictionary, key: String) -> Array:
	return data[key] if data.get(key) is Array else []

static func _dictionary_field(data: Dictionary, key: String) -> Dictionary:
	return data[key] if data.get(key) is Dictionary else {}
