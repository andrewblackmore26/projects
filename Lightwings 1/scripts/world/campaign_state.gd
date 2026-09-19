class_name CampaignState
extends RefCounted

const Tuning = preload("res://scripts/data/game_tuning.gd")
const DEFAULT_CAMPAIGN = preload("res://content/campaign/default_campaign.tres")
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const ELEMENTS: Array[String] = Tuning.ELEMENTS
const GAMEPLAY_VERSION: int = 3
var demo: bool = false
var current_sector: Vector2i = Vector2i.ZERO
var unlocked: Array = []
var checkpoints: Dictionary = {}
var defeated_leaders: Array = []
var discovered: Array = []
var deaths: int = 0
var completed: bool = false
var demo_completed: bool = false
var cleared: Dictionary = {}
var territories: Dictionary = {}
var native_elements: Dictionary = {}
var story_flags: Dictionary = {}
var world_seed: int = DEFAULT_CAMPAIGN.campaign_seed
var border_changes: Array = []
var deepest_distance: int = 0
var legacy_history: Dictionary = {}

func _init() -> void:
	configure(false)

func configure(is_demo: bool) -> void:
	demo = is_demo
	current_sector = Vector2i.ZERO
	unlocked = Array(Tuning.START_ELEMENTS).duplicate()
	checkpoints.clear()
	defeated_leaders.clear()
	discovered = ["0,0"]
	deaths = 0
	completed = false
	demo_completed = false
	cleared = {"0,0": true}
	territories = {"0,0": "player"}
	native_elements.clear()
	story_flags.clear()
	border_changes.clear()
	deepest_distance = 0
	legacy_history.clear()

static func coord_key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]

static func valid_key(key: String) -> bool:
	var pieces: PackedStringArray = key.split(",")
	return pieces.size() == 2 and pieces[0].is_valid_int() and pieces[1].is_valid_int() and coord_key(Vector2i(int(pieces[0]), int(pieces[1]))) == key

static func key_coord(key: String) -> Vector2i:
	if not valid_key(key): return Vector2i.ZERO
	var pieces: PackedStringArray = key.split(",")
	return Vector2i(int(pieces[0]), int(pieces[1]))

static func distance_of(coord: Vector2i) -> float:
	return Vector2(coord).length()

static func layer_of(coord: Vector2i) -> int:
	return floori(distance_of(coord))

static func tier_at_distance(distance: float) -> int:
	return mini(Tuning.MAX_TIER, 1 + floori(distance / Tuning.WAYPOINT_INTERVAL))

func in_bounds(_coord: Vector2i) -> bool:
	return true

func _region_elements() -> Array:
	return Array(Tuning.START_ELEMENTS) if demo else Array(ELEMENTS)

func _initial_element(coord: Vector2i) -> String:
	var elements: Array = _region_elements()
	var angle: float = fposmod(Vector2(coord).angle() + PI / elements.size(), TAU)
	return str(elements[int(floor(angle / (TAU / elements.size()))) % elements.size()])

func core_coordinate(element: String) -> Vector2i:
	var elements: Array = _region_elements()
	var index: int = elements.find(element)
	if index < 0: return Vector2i.ZERO
	var angle: float = TAU * index / elements.size()
	var radius: int = Tuning.CORE_DISTANCES[ELEMENTS.find(element)]
	return Vector2i(roundi(cos(angle) * radius), roundi(sin(angle) * radius))

func known_cores() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for element: String in unlocked:
		if demo and element != "fire": continue
		var coord: Vector2i = core_coordinate(element)
		result.append({"id": element, "element": element, "coord": coord, "direction": Vector2(coord - current_sector).normalized(), "beaten": element in defeated_leaders})
	return result

func sector_at(coord: Vector2i) -> Dictionary:
	var distance: float = distance_of(coord)
	var key: String = coord_key(coord)
	var element: String = _initial_element(coord)
	var tier: int = mini(3 if demo else Tuning.MAX_TIER, tier_at_distance(distance))
	var core_id: String = ""
	var elite_ring: bool = false
	for candidate: String in _region_elements():
		if demo and candidate != "fire": continue
		var gap: float = Vector2(coord - core_coordinate(candidate)).length()
		if gap == 0.0: core_id = candidate
		elif gap <= 2.0: elite_ring = true
	var roll: int = absi(hash("%d:%s:%d" % [world_seed, key, deaths]))
	var elite_probability: float = 0.8 if elite_ring else clampf(0.04 + distance * 0.012, 0.04, 0.50)
	var kind: String = "origin" if coord == Vector2i.ZERO else "regular"
	if not core_id.is_empty(): kind = "demo_core" if demo else "core"
	var result: Dictionary = {"coord": coord, "id": key, "element": element, "distance": distance, "layer": floori(distance), "tier": tier, "owner": "player" if cleared.has(key) else element, "kind": kind, "core_id": core_id, "leader_id": core_id, "cleared": bool(cleared.get(key, false)), "in_bounds": true, "boss_tier": tier, "encounter_seed": roll, "exits": DIRECTIONS.duplicate(), "elite_heavy": elite_ring, "elite_probability": elite_probability, "elite": float(roll % 10000) / 10000.0 < elite_probability, "enemy_count": mini(48, 4 + floori(distance * 0.65)), "roaming_rival": false, "mirror": false, "rival_element": element, "rival_tier": tier, "mirror_buff": ""}
	result["elite_count"] = 2 if elite_ring else 1 if distance >= Tuning.WAYPOINT_INTERVAL and bool(result["elite"]) else 0
	result["core_defeated"] = not core_id.is_empty() and core_id in defeated_leaders
	result.merge(economy_profile(coord), true)
	return result

func can_enter(from: Vector2i, to: Vector2i, _light: float = 0) -> Dictionary:
	var adjacent: bool = absi(from.x - to.x) + absi(from.y - to.y) == 1
	return {"allowed": adjacent, "reason": "" if adjacent else "Nodes must share an edge"}

func on_enter(coord: Vector2i) -> Dictionary:
	current_sector = coord
	discover(coord)
	var event: Dictionary = {"waypoint": false, "checkpoint": false, "unlocked": ""}
	var element: String = _initial_element(coord)
	if element not in unlocked:
		unlocked.append(element)
		event["unlocked"] = element
	var distance: int = layer_of(coord)
	var previous_band: int = floori(float(deepest_distance) / Tuning.WAYPOINT_INTERVAL)
	deepest_distance = maxi(deepest_distance, distance)
	if floori(float(distance) / Tuning.WAYPOINT_INTERVAL) > previous_band:
		_add_waypoint(coord, "distance")
		event["waypoint"] = true
		event["checkpoint"] = true
	return event

func _add_waypoint(coord: Vector2i, source: String) -> void:
	checkpoints[coord_key(coord)] = {"tier": mini(3 if demo else Tuning.MAX_TIER, tier_at_distance(distance_of(coord))), "distance": distance_of(coord), "source": source}

func clear_sector(coord: Vector2i) -> Dictionary:
	var event: Dictionary = {"checkpoint": false, "waypoint": false, "unlocked": "", "leader": "", "core": "", "completed": false, "demo_completed": false}
	var key: String = coord_key(coord)
	if bool(cleared.get(key, false)): return event
	var data: Dictionary = sector_at(coord)
	cleared[key] = true
	territories[key] = "player"
	discover(coord)
	var core_id: String = str(data["core_id"])
	if not core_id.is_empty(): event = defeat_core(core_id)
	return event

## Core death is an objective event, independent of surviving node opponents.
func defeat_core(core_id: String) -> Dictionary:
	var event: Dictionary = {"checkpoint": false, "waypoint": false, "unlocked": "", "leader": "", "core": "", "completed": false, "demo_completed": false}
	if core_id not in ELEMENTS or core_id in defeated_leaders or (demo and core_id != "fire"): return event
	var coord: Vector2i = core_coordinate(core_id)
	defeated_leaders.append(core_id)
	discover(coord)
	_add_waypoint(coord, "core")
	event.merge({"waypoint": true, "checkpoint": true, "leader": core_id, "core": core_id}, true)
	story_flags["core_" + core_id] = true
	if demo:
		demo_completed = true
		event["demo_completed"] = true
	elif defeated_leaders.size() == ELEMENTS.size():
		completed = true
		event["completed"] = true
	return event

func discover(coord: Vector2i) -> void:
	var key: String = coord_key(coord)
	if key not in discovered: discovered.append(key)

func can_teleport(coord: Vector2i, current_tier: int) -> bool:
	var waypoint: Dictionary = checkpoints.get(coord_key(coord), {})
	return current_sector == Vector2i.ZERO and not waypoint.is_empty() and current_tier >= int(waypoint.get("tier", Tuning.MAX_TIER))

func highest_checkpoint_threshold() -> int:
	var tier: int = 1
	for waypoint: Dictionary in checkpoints.values(): tier = maxi(tier, int(waypoint.get("tier", 1)))
	return int(Tuning.THRESHOLDS[tier - 2]) if tier > 1 else 0

func economy_profile(coord: Vector2i) -> Dictionary:
	var distance: float = distance_of(coord)
	var recovery: float = clampf(float(highest_checkpoint_threshold()) / 150.0, 1.0, 5.0) if deaths > 0 and distance <= Tuning.WAYPOINT_INTERVAL else 1.0
	var budget: int = 30 if coord == Vector2i.ZERO else roundi((100.0 + minf(distance, 40.0) * 40.0) * recovery)
	return {"energy_budget": budget, "resource_budget": budget, "recovery_multiplier": recovery, "encounter_epoch": deaths, "ambient_budget": 30 if coord == Vector2i.ZERO else mini(20, roundi(budget * 0.1)), "renewable": true}

func on_death() -> void:
	deaths += 1
	current_sector = Vector2i.ZERO
	story_flags["reboot_%d" % deaths] = true
	_reset_encounter_clears()

func _reset_encounter_clears() -> void:
	cleared = {"0,0": true}
	territories = {"0,0": "player"}

func radiation_icons(_center: Vector2i, _player_tier: int) -> Array[Dictionary]:
	return []

func import_demo(data: Dictionary) -> void:
	from_dict(data)
	demo = false
	current_sector = Vector2i.ZERO
	_reset_encounter_clears()
	# Coordinates remain valid in the full grid. Recompute their tier requirement
	# against the full curve while preserving earned discoveries and waypoints.
	for key: String in checkpoints.keys():
		_add_waypoint(key_coord(key), str(checkpoints[key]["source"]))
	if "fire" in defeated_leaders:
		var coord: Vector2i = core_coordinate("fire")
		discover(coord)
		_add_waypoint(coord, "core")

func to_dict() -> Dictionary:
	return {"schema_version": GAMEPLAY_VERSION, "demo": demo, "current_sector": coord_key(current_sector), "unlocked": unlocked.duplicate(), "checkpoints": checkpoints.duplicate(true), "defeated_leaders": defeated_leaders.duplicate(), "discovered": discovered.duplicate(), "deaths": deaths, "completed": completed, "demo_completed": demo_completed, "cleared": cleared.duplicate(true), "story_flags": story_flags.duplicate(true), "world_seed": world_seed, "deepest_distance": deepest_distance, "legacy_history": legacy_history.duplicate(true)}

func from_dict(data: Dictionary) -> void:
	configure(bool(data.get("demo", false)))
	world_seed = int(data.get("world_seed", DEFAULT_CAMPAIGN.campaign_seed))
	deaths = maxi(0, int(data.get("deaths", 0)))
	for element: Variant in _array_field(data, "unlocked"):
		if element in _region_elements() and element not in unlocked: unlocked.append(element)
	if int(data.get("schema_version", 1)) < GAMEPLAY_VERSION:
		var old_story: Dictionary = _dictionary_field(data, "story_flags")
		for flag: String in old_story:
			if flag.begins_with("reboot_") or flag in ["first_evolution", "first_regression", "first_elite"]:
				story_flags[flag] = bool(old_story[flag])
		legacy_history = {"defeated_leaders": _array_field(data, "defeated_leaders").duplicate(), "completed": bool(data.get("completed", false)), "story_flags": old_story.duplicate(true)}
		return
	story_flags = _dictionary_field(data, "story_flags").duplicate(true)
	current_sector = key_coord(str(data.get("current_sector", "0,0")))
	deepest_distance = maxi(0, int(data.get("deepest_distance", 0)))
	for key: Variant in _array_field(data, "discovered"):
		if key is String and valid_key(key) and key not in discovered: discovered.append(key)
	for key: String in _dictionary_field(data, "cleared"):
		if valid_key(key) and data["cleared"][key] == true:
			cleared[key] = true
			territories[key] = "player"
	for key: String in _dictionary_field(data, "checkpoints"):
		var value: Variant = data["checkpoints"][key]
		if valid_key(key) and value is Dictionary and str(value.get("source", "")) in ["distance", "core"]:
			_add_waypoint(key_coord(key), str(value["source"]))
	for element: Variant in _array_field(data, "defeated_leaders"):
		if element in _region_elements() and element not in defeated_leaders: defeated_leaders.append(element)
	for element: String in _region_elements():
		var key: String = coord_key(core_coordinate(element))
		if element not in defeated_leaders and str(sector_at(key_coord(key))["kind"]) in ["core", "demo_core"]:
			cleared.erase(key)
			territories.erase(key)
	completed = not demo and defeated_leaders.size() == ELEMENTS.size()
	demo_completed = "fire" in defeated_leaders if demo else bool(data.get("demo_completed", false))
	legacy_history = _dictionary_field(data, "legacy_history").duplicate(true)

static func _array_field(data: Dictionary, key: String) -> Array:
	return data[key] if data.get(key) is Array else []

static func _dictionary_field(data: Dictionary, key: String) -> Dictionary:
	return data[key] if data.get(key) is Dictionary else {}
