class_name ShipCatalog
extends RefCounted
## Canonical saved hulls; construction is exclusively an authoring operation.
static var catalog_root: String = "res://content/ships"
const MAX_PARTS: int = 128
const MAX_AUTHORED_PARTS: int = 128
const MAX_LINES: int = 512
const ELEMENTS: Array[String] = ["fire", "lightning", "void", "corruption", "plasma"]
const SHAPES: Array[String] = ["circle", "line"]
const FAMILIES: Array[String] = ["compact", "standard_a", "standard_b", "heavy"]
const PALETTE: Dictionary = {"player": Color("6fd3ff"), "player_blue": Color("6fd3ff"), "fire": Color("ff5436"), "lightning": Color("ffd23f"), "corruption": Color("45e06a"), "plasma": Color("a97dff"), "violet": Color("a97dff"), "void": Color("9aa3b3"), "silver": Color("9aa3b3"), "gold": Color("ffd23f"), "yellow": Color("ffd23f"), "red": Color("ff5436"), "white": Color.WHITE, "neutral": Color("9aa3b3"), "green": Color("45e06a"), "black": Color.BLACK}
const FILLS: Dictionary = {"player": Color("08233a"), "player_blue": Color("08233a"), "fire": Color("2a0b08"), "lightning": Color("2a2206"), "corruption": Color("062a12"), "plasma": Color("1d1233"), "violet": Color("1d1233"), "void": Color.BLACK, "silver": Color.BLACK, "gold": Color.BLACK, "yellow": Color("2a2206"), "red": Color("2a0b08"), "white": Color("191919"), "neutral": Color("101015"), "green": Color("062a12"), "black": Color.BLACK}
const LIGHTS: Dictionary = {"player": Color("dcf5ff"), "player_blue": Color("dcf5ff"), "fire": Color("ffc6b5"), "lightning": Color("fff3bd"), "corruption": Color("caffd5"), "plasma": Color("e4d6ff"), "violet": Color("e4d6ff"), "void": Color.WHITE, "silver": Color.WHITE, "gold": Color("fff3bd"), "yellow": Color("fff3bd"), "red": Color("ffc6b5"), "white": Color.WHITE, "neutral": Color.WHITE, "green": Color("caffd5"), "black": Color.BLACK}
# Retained for descriptive legacy consumers; gameplay uses mounted_components().
const NAMES: Dictionary = {"fire": ["Ember", "Flare", "Stoker", "Furnace", "Sunburst", "Cataclysm"], "lightning": ["Spark", "Arc", "Fork", "Surge", "Tempest", "Maelstrom"], "void": ["Null", "Eclipse", "Umbra", "Horizon", "Singularity", "Oblivion"], "corruption": ["Glitch", "Worm", "Trojan", "Rootkit", "Botnet", "Leviathan"], "plasma": ["Ion", "Orbit", "Corona", "Pulsar", "Quasar", "Supernova"]}
const ABILITIES: Dictionary = {"fire": ["flame_cone", "mine_layer", "explosives", "rocket_launcher", "forcefield"], "lightning": ["bolt", "laser_prong", "shield", "seeker_missiles", "thrusters"], "void": ["homing_beam", "orbital_blockers", "shield", "virus", "magnet"], "corruption": ["pulse_cannon", "virus", "poison_cloud", "seeker_missiles", "siphon"], "plasma": ["beam", "seeker_missiles", "laser_prong", "rocket_launcher", "orbital_seekers"]}

static func get_color(role: String) -> Color:
	return PALETTE.get(role, PALETTE["corruption"])

static var _templates: Dictionary = {}
static var _listings: Dictionary = {}

static func invalidate(_id: String = "") -> void:
	# Editor mutations explicitly invalidate, including multiple saves per second.
	_templates.clear()
	_listings.clear()

static func _ids() -> Array[String]:
	var now: int = Time.get_ticks_msec()
	if _listings.has(catalog_root) and now - int(_listings[catalog_root].checked) < 1000:
		return _listings[catalog_root].ids
	var result: Array[String] = ids_from_files(DirAccess.get_files_at(catalog_root))
	_listings[catalog_root] = {"checked": now, "ids": result}
	return result

static func ids_from_files(files: PackedStringArray) -> Array[String]:
	# Exported text resources may appear as .tres.remap entries in a PCK.
	# ResourceLoader still resolves the original .tres path; never load the remap.
	var unique: Dictionary = {}
	for file: String in files:
		var canonical: String = file.trim_suffix(".remap") if file.ends_with(".tres.remap") else file
		if canonical.ends_with(".tres") and canonical.get_file() == canonical:
			unique[canonical.trim_suffix(".tres")] = true
	var result: Array[String] = []
	result.assign(unique.keys())
	result.sort()
	return result

static func _template(id: String) -> ShipDefinition:
	if id.get_file() != id or id.contains("."): return null
	var path: String = catalog_root.path_join(id + ".tres")
	var now: int = Time.get_ticks_msec()
	if _templates.has(path) and now - int(_templates[path].checked) < 1000: return _templates[path].ship
	var physical_path: String = path if FileAccess.file_exists(path) else path + ".remap"
	var modified: int = FileAccess.get_modified_time(physical_path) if FileAccess.file_exists(physical_path) else 0
	if _templates.has(path) and int(_templates[path].modified) == modified:
		_templates[path].checked = now
		return _templates[path].ship
	if not ResourceLoader.exists(path): return null
	var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not resource is ShipDefinition or not validate(resource).is_empty(): return null
	recalculate(resource)
	_templates[path] = {"modified": modified, "checked": now, "ship": resource}
	return resource

static func get_ship(id: String) -> ShipDefinition:
	var template: ShipDefinition = _template(id)
	return template.duplicate(true) if template != null else null

static func all_forms() -> Array[ShipDefinition]:
	var result: Array[ShipDefinition] = []
	for id: String in _ids():
		var ship: ShipDefinition = get_ship(id)
		if ship != null: result.append(ship)
	return result

static func roster(element: String, tier: int) -> Array[ShipDefinition]:
	var result: Array[ShipDefinition] = []
	for id: String in _ids():
		var ship: ShipDefinition = _template(id)
		if ship != null and ship.faction == "player" and ship.tier == tier and (ship.element == element or tier == 1): result.append(ship.duplicate(true))
	return result
static func make_ship(element: String, tier: int, is_player: bool = false, _legacy: Array = []) -> ShipDefinition:
	tier = clampi(tier, 1, GameTuning.MAX_TIER)
	if is_player and tier == 1: return get_ship("player_seed")
	if not element in ELEMENTS: element = "corruption"
	if is_player: return get_ship("player_" + element + "_t" + str(tier) + "_standard_a")
	return get_ship(pick_enemy("enemy", element, tier))

## V02-ADAPTER: v0.2 built enemy/elite/rival hull ids by formula
## ("enemy_%s_t%d", "elite_%s_t%d", "rival_%s_t5"). Those exact ids no
## longer exist under the P2b-1 roster (archetype-first ids, banded tiers).
## This maps (faction, element, tier) onto the nearest roster hull for that
## archetype. It is a HARD ERROR (returns "", callers must treat a null
## `get_ship` result as a bug) when the element/faction combination has no
## roster entry at all - never a silent nearest-tier substitute that hides
## a genuinely missing hull. Removed with the rest of the shim in P5.
static func pick_enemy(faction: String, element: String, tier: int) -> String:
	return ShipGenerator.pick_enemy(faction, element, tier)

## V02-ADAPTER: each element is only authored across the tier band of the campaign level that
## introduces it, so a v0.2 wedge sector asking for a low-tier hull of a late element is handed a
## much higher-tier one. That hull carries the SLOT ALLOWANCE of its own tier, which made ring-1
## corruption and plasma enemies fight several tiers above their reward and HP (measured: a tier-1
## request fielded 2 mounts for corruption and 3 for plasma, against the 1 that GameTuning.slots
## grants tier 1). Slots are a hard cap in this game; apply that cap to the substitute so a tier-N
## enemy fights like tier N. Every dropped ability takes its mount circle and that circle's line
## with it, because a visible circle must always be an ability or a stat. Removed with the shim in P5.
static func trim_to_tier(ship: ShipDefinition, tier: int) -> ShipDefinition:
	if ship == null or ship.tier <= tier: return ship
	var limits: Dictionary = GameTuning.slots(tier, ship.role)
	if ship.secondaries.size() <= int(limits.secondary) and ship.passives.size() <= int(limits.passive): return ship
	var dropped: Dictionary = {}
	for index: int in range(int(limits.secondary), ship.secondaries.size()): dropped["secondary_" + str(index)] = true
	for index: int in range(int(limits.passive), ship.passives.size()): dropped["passive_" + str(index)] = true
	ship.secondaries = ship.secondaries.slice(0, int(limits.secondary))
	ship.passives = ship.passives.slice(0, int(limits.passive))
	var removed: Dictionary = {}
	var kept: Array[PartDefinition] = []
	for part: PartDefinition in ship.parts:
		if part.shape == "circle" and dropped.has(part.mount_id): removed[part.id] = true
		else: kept.append(part)
	var survivors: Array[PartDefinition] = []
	for part: PartDefinition in kept:
		if part.shape == "line" and (removed.has(part.from_id) or removed.has(part.to_id)): continue
		survivors.append(part)
	ship.parts = survivors
	recalculate(ship)
	return ship

static func ability_description(element: String, tier: int) -> String:
	return str(NAMES.get(element, NAMES.corruption)[clampi(tier - 1, 0, GameTuning.MAX_TIER - 1)])

static func role_for_family(family: String) -> String:
	return family if family in ["compact", "heavy"] else "standard"

## Generation itself (the ROSTER manifest and the five element growth
## builders) lives in ship_generator.gd (P2b-1); ShipCatalog keeps loading,
## caching, recalculate() and validate(). This is a thin forwarder kept for
## the editor/tests, which build one hull outside the manifest for authoring
## experiments (ShipAuthoring.from_description, the editor's tier/family
## pickers). `_legacy` is an unused parameter kept for call-site compatibility.
static func build_ship(element: String, tier: int, is_player: bool = false, _legacy: Array = [], family: String = "standard_a", faction: String = "") -> ShipDefinition:
	return ShipGenerator.build_ship(element, tier, is_player, family, faction)

static func add_part(ship: ShipDefinition, id: String, shape: String, position: Vector2, radius: float, color: String = "chassis", stat: String = "hp_buffer", layer: int = 3, filled: bool = true, parent_id: String = "") -> PartDefinition:
	var part: PartDefinition = PartDefinition.new()
	part.id = id
	part.shape = shape
	part.position = position
	part.radius = radius
	part.filled = filled
	part.parent_id = parent_id if shape == "circle" and id != "core" else ""
	part.color_role = color
	part.stat_id = "turn_rate" if stat == "hp_buffer" else stat
	part.stat_value = 40.0 if id == "core" else (4.0 if part.stat_id in ["speed", "magnet_radius"] else 0.25 if part.stat_id == "turn_rate" else 0.0)
	if id == "core": part.stat_id = "speed"
	part.layer = layer
	part.light_period = 1.6 if ship.parts.size() % 4 == 3 else 2.0
	part.light_phase = [0.0, -0.7, -1.3][ship.parts.size() % 3]
	# A "black" circle is a visual mask laid over another circle (the crescent
	# construction), not an extra structural piece; it carries no TP cost.
	part.tp_cost = 0.0 if color == "black" else snappedf(maxf(0.25, (0.25 if shape == "line" or not filled else radius * 2.0 / 50.0) + part.stat_value / 80.0), 0.25)
	ship.parts.append(part)
	return part

static func add_pair(ship: ShipDefinition, id: String, shape: String, position: Vector2, radius: float, color: String, stat: String, layer: int = 2, parent_id: String = "core") -> void:
	var left: PartDefinition = add_part(ship, id + "_l", shape, Vector2(-position.x, position.y), radius, color, stat, layer, true, parent_id)
	var right: PartDefinition = add_part(ship, id + "_r", shape, position, radius, color, stat, layer, true, parent_id)
	left.mirror_id = right.id
	right.mirror_id = left.id

static func add_line(ship: ShipDefinition, id: String, from: String, to: String) -> PartDefinition:
	var part: PartDefinition = add_part(ship, id, "line", Vector2.ZERO, 1.0, "chassis", "structure", 1)
	part.from_id = from
	part.to_id = to
	return part

static func mount_component(ship: ShipDefinition, ability: String, mount: String, position: Vector2, radius: float = 3.5) -> void:
	var definition: AbilityDefinition = AbilityCatalog.get_definition(ability)
	var part: PartDefinition = add_part(ship, mount, "circle", position, radius, definition.visual_color, "", 4, true, "core")
	part.ability_id = ability
	part.mount_id = mount
	part.tp_cost = 0
	add_line(ship, mount + "_link", "core", part.id)

static func recalculate(ship: ShipDefinition) -> void:
	ship.tp_max = GameTuning.TP_BUDGETS[clampi(ship.tier - 1, 0, GameTuning.MAX_TIER - 1)] * (2.5 if ship.faction == "elite" else 8.0 if ship.faction == "boss" else 1.0)
	ship.tp_used = 0
	var mounts: Dictionary = {}
	var radius: float = ship.hull_radius
	var totals: Dictionary = {"speed": 180.0, "turn_rate": 10.0, "magnet_radius": 90.0}
	for part: PartDefinition in ship.parts:
		if part == null: continue
		if part.mount_id.is_empty():
			if totals.has(part.stat_id): totals[part.stat_id] += part.stat_value
			part.tp_cost = 0.0 if part.color_role == "black" else snappedf(maxf(0.25, (0.25 if part.shape == "line" or not part.filled else part.radius * 2.0 / 50.0) + part.stat_value / 80.0), 0.25)
			ship.tp_used += part.tp_cost
		elif not mounts.has(part.mount_id):
			ship.tp_used += AbilityCatalog.get_definition(part.ability_id).tp_cost
			mounts[part.mount_id] = true
		if part.shape != "line" and not part.dashed: radius = maxf(radius, part.position.length() + part.radius)
	ship.footprint = radius * 2
	ship.speed = float(totals.speed) * (1.25 if ship.role == "compact" else 0.85 if ship.role == "heavy" else 1.0)
	ship.turn_rate = float(totals.turn_rate) * (1.25 if ship.role == "compact" else 0.8 if ship.role == "heavy" else 1.0)
	ship.magnet_radius = totals.magnet_radius
	ship.hp_buffer = 0.8 if ship.role == "compact" else 1.3 if ship.role == "heavy" else 1.0
	ship.damage_multiplier = 1.15 if ship.role == "heavy" else 1.0
	ship.abilities = ship.mounted_components()

static func validate(ship: ShipDefinition) -> PackedStringArray:
	var errors: PackedStringArray = []
	if ship == null: return PackedStringArray(["No ship definition."])
	if ship.id.strip_edges().is_empty() or not ship.id.is_valid_filename() or ship.id.contains("."): errors.append("Ship needs a valid filename-safe ID without dots.")
	if ship.schema_version != 3: errors.append("Unsupported ship schema version.")
	if not ship.element in ELEMENTS and not (ship.tier == 1 and ship.element == "neutral" and ship.is_player): errors.append("Unknown element.")
	if ship.tier < 1 or ship.tier > GameTuning.MAX_TIER: errors.append("Tier outside supported range."); return errors
	if not ship.faction in ["player", "enemy", "elite", "boss"]: errors.append("Unknown faction.")
	if ship.is_player != (ship.faction == "player"): errors.append("Faction and player flag disagree.")
	if not ship.role in ["compact", "standard", "heavy"]: errors.append("Unknown role.")
	var circle_count: int = 0
	var line_count: int = 0
	var reach_ring_count: int = 0
	for counted: PartDefinition in ship.parts:
		if counted == null: continue
		if counted.shape == "circle": circle_count += 1
		elif counted.shape == "line": line_count += 1
	for counted_group: GroupDefinition in ship.groups:
		if counted_group.reach_ring: reach_ring_count += 1
	if circle_count + reach_ring_count > MAX_PARTS: errors.append("At most 128 circles (including synthesized reach rings) supported.")
	if line_count > MAX_LINES: errors.append("At most 512 lines supported.")
	if ship.core_radius <= 0 or not is_finite(ship.core_radius): errors.append("Invalid core radius.")
	var ids: Dictionary = {}
	var mounts: Dictionary = {}
	for part: PartDefinition in ship.parts:
		if part == null: errors.append("Null part."); continue
		if part.id.is_empty() or ids.has(part.id): errors.append("Missing or duplicate part ID: " + part.id)
		ids[part.id] = part
		if not part.shape in SHAPES: errors.append(part.id + ": forbidden primitive.")
		if part.shape == "circle" and (part.radius <= 0 or not is_finite(part.radius)): errors.append(part.id + ": invalid geometry.")
		if not part.position.is_finite(): errors.append(part.id + ": invalid geometry.")
		if part.light_period <= 0 or not is_finite(part.light_period) or not is_finite(part.light_phase): errors.append(part.id + ": invalid light timing.")
		if part.color_role != "chassis" and not PALETTE.has(part.color_role): errors.append(part.id + ": unknown color.")
		if not ship.is_player and part.color_role in ["player", "player_blue"]: errors.append(part.id + ": player blue is reserved.")
		if part.mount_id.is_empty() and not part.stat_id in ["speed", "turn_rate", "magnet_radius", "structure", "bullet_eater", "void_pull", "projectile_orbit", "sub_core", "shield_generator"]: errors.append(part.id + ": assign a component or body statistic.")
		if ship.is_player and part.stat_id in ["bullet_eater", "void_pull", "projectile_orbit"]: errors.append(part.id + ": enemy-only body feature.")
		if not is_finite(part.stat_value) or part.stat_value < 0: errors.append(part.id + ": invalid body contribution.")
		if not part.mount_id.is_empty():
			var ability: AbilityDefinition = AbilityCatalog.get_definition(part.ability_id)
			if not AbilityCatalog.DEFINITIONS.has(part.ability_id): errors.append(part.id + ": unknown component.")
			if ship.is_player and ship.tier < ability.minimum_tier: errors.append(part.id + ": component is tier locked.")
			if not ship.faction in ability.allowed_factions: errors.append(part.id + ": component is faction locked.")
			if part.color_role != ability.visual_color: errors.append(part.id + ": component color must match its definition.")
			if mounts.has(part.mount_id) and mounts[part.mount_id] != part.ability_id: errors.append(part.id + ": mount component mismatch.")
			mounts[part.mount_id] = part.ability_id
	# Parent graph: every circle other than the core names an existing circle as
	# its parent, with no cycles, and the chain must reach the core.
	var circle_ids: Dictionary = {}
	for part: PartDefinition in ship.parts:
		if part != null and part.shape == "circle": circle_ids[part.id] = part
	for part: PartDefinition in ship.parts:
		if part == null or part.shape != "circle": continue
		if part.id == "core":
			if not part.parent_id.is_empty(): errors.append("core must have no parent.")
			continue
		if part.parent_id.is_empty() or not circle_ids.has(part.parent_id): errors.append(part.id + ": parent must name an existing circle."); continue
		var seen: Dictionary = {part.id: true}
		var cursor: String = part.parent_id
		var reached_core: bool = false
		var broken: bool = false
		while true:
			if cursor == "core": reached_core = true; break
			if seen.has(cursor) or not circle_ids.has(cursor): broken = true; break
			seen[cursor] = true
			cursor = str(circle_ids[cursor].parent_id)
			if cursor.is_empty(): broken = true; break
		if broken or not reached_core: errors.append(part.id + ": parent chain must reach the core without cycles.")
	for part: PartDefinition in ship.parts:
		if part == null: continue
		if part.shape == "line":
			if not ids.has(part.from_id) or not ids.has(part.to_id) or part.from_id == part.to_id: errors.append(part.id + ": invalid line endpoints.")
			elif ids[part.from_id].shape != "circle" or ids[part.to_id].shape != "circle": errors.append(part.id + ": a line must end on circles.")
		elif ship.is_player:
			if absf(part.position.x) > 0.01:
				var other: PartDefinition = ids.get(part.mirror_id)
				if other == null or other.mirror_id != part.id or not other.position.is_equal_approx(Vector2(-part.position.x, part.position.y)) or not is_equal_approx(other.radius, part.radius) or other.filled != part.filled or other.shape != part.shape or other.color_role != part.color_role or other.stat_id != part.stat_id or not is_equal_approx(other.stat_value, part.stat_value) or other.ability_id != part.ability_id: errors.append(part.id + ": player parts must be mirrored.")
	var limits: Dictionary = GameTuning.slots(ship.tier, ship.role)
	if ship.primary.is_empty(): errors.append("One primary is required.")
	if ship.is_player:
		var counts: Dictionary = {"primary": 0, "secondary": 0, "passive": 0}
		for mount: String in mounts:
			var kind: String = AbilityCatalog.get_definition(mounts[mount]).slot_kind
			if counts.has(kind): counts[kind] += 1
		if counts.primary != 1 or counts.secondary != ship.secondaries.size() or counts.passive != ship.passives.size(): errors.append("Visible mount counts must match loadout slots.")
	if ship.secondaries.size() > limits.secondary or ship.passives.size() > limits.passive: errors.append("Slot budget exceeded.")
	for kind: String in ["primary", "secondary", "passive"]:
		var values: Array = [ship.primary] if kind == "primary" else ship.secondaries if kind == "secondary" else ship.passives
		for component: String in values:
			if not component in mounts.values(): errors.append("Loadout component has no visible mount: " + component)
			if AbilityCatalog.get_definition(component).slot_kind != kind and not (not ship.is_player and kind == "secondary" and AbilityCatalog.get_definition(component).slot_kind == "enemy"): errors.append("Component in wrong slot: " + component)
	if not ids.has("core") or not ids.core.position.is_zero_approx(): errors.append("Body must remain at the core origin.")
	# Groups: root must be a real circle, at most one group per root, tuning
	# stays inside the amplitudes spec §18 asks for, a sway/whip subtree is a
	# simple chain, and mirrored roots counter-rotate (spec §18: "or the hull
	# visibly stops being symmetric").
	var group_roots: Dictionary = {}
	var mount_bearing: Dictionary = {}
	for part: PartDefinition in ship.parts:
		if not part.mount_id.is_empty():
			var cursor: String = part.id
			var guard: int = 0
			while circle_ids.has(cursor) and guard < MAX_PARTS:
				mount_bearing[cursor] = true
				cursor = str(circle_ids[cursor].parent_id)
				guard += 1
	for group: GroupDefinition in ship.groups:
		if not circle_ids.has(group.root_id): errors.append("Group root must name an existing circle: " + group.root_id); continue
		if group_roots.has(group.root_id): errors.append("At most one group per root: " + group.root_id)
		group_roots[group.root_id] = true
		if absf(group.orbit_speed) > 3.0: errors.append(group.root_id + ": orbit_speed outside +/-3 rad/s.")
		if group.breathe_amp > 0.08: errors.append(group.root_id + ": breathe_amp above 0.08.")
		var drift_limit: float = 2.0 if mount_bearing.has(group.root_id) else 6.0
		if group.drift_amp > drift_limit: errors.append(group.root_id + ": drift_amp above the amplitude allowed for its subtree.")
		if not group.chain_mode in ["rigid", "sway", "whip"]: errors.append(group.root_id + ": unknown chain_mode.")
		if group.chain_mode in ["sway", "whip"]:
			var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
			var root_index: int = rig.index_of(group.root_id)
			if root_index >= 0:
				var last: int = root_index + rig.subtree_size[root_index]
				for i: int in range(root_index, last):
					var children_of_i: int = 0
					for j: int in range(root_index, last):
						if rig.parent_index[j] == i: children_of_i += 1
					if children_of_i > 1: errors.append(group.root_id + ": a sway/whip subtree must be a simple chain, not a tree.")
	for part: PartDefinition in ship.parts:
		if part.shape == "circle" and not part.mirror_id.is_empty() and group_roots.has(part.id) and group_roots.has(part.mirror_id):
			var mine: GroupDefinition = null
			var theirs: GroupDefinition = null
			for group: GroupDefinition in ship.groups:
				if group.root_id == part.id: mine = group
				if group.root_id == part.mirror_id: theirs = group
			if mine != null and theirs != null and not is_equal_approx(mine.orbit_speed, -theirs.orbit_speed): errors.append(part.id + ": mirrored group roots must counter-rotate.")
	if not errors.is_empty(): return errors
	if ship.is_player:
		# Spec §17: player hulls are majority light blue (chassis); the element
		# shows through arrangement and component colours, not a wholesale recolor.
		var chassis_circles: int = 0
		var colored_circles: int = 0
		for part: PartDefinition in ship.parts:
			if part.shape == "circle":
				colored_circles += 1
				if part.color_role == "chassis": chassis_circles += 1
		if colored_circles > 0 and chassis_circles * 2 < colored_circles: errors.append("Player hull must be majority light blue (chassis circles).")
	var copy: ShipDefinition = ship.duplicate(true)
	recalculate(copy)
	if copy.tp_used > copy.tp_max + 0.001: errors.append("TP budget exceeded: %.2f / %.2f" % [copy.tp_used, copy.tp_max])
	return errors

static func warnings(ship: ShipDefinition) -> PackedStringArray:
	var result: PackedStringArray = []
	# Widened for P2b-1's six-tier growth. Lightning's long straight spokes
	# (spec §17: "few circles on long straight spokes") are the true worst
	# case, not the compact/dense elements this band was tuned against in
	# v0.2 - measured max per role across the whole roster: compact 259,
	# standard 313, heavy 367.
	var bands: Dictionary = {"compact": Vector2(20, 270), "standard": Vector2(35, 325), "heavy": Vector2(60, 380)}
	var band: Vector2 = bands.get(ship.role, Vector2(0, 200))
	# The role footprint band is a player-legibility guide (§17 role bands);
	# enemy archetypes (a chain's shrinking tail can run long), elites (2-4x
	# a player hull by spec) and bosses (3-4x scale by spec) are exempt by
	# design, not by oversight.
	if ship.is_player and ship.tier > 1 and (ship.footprint < band.x or ship.footprint > band.y): result.append("Footprint lies outside the role's suggested band.")
	var connected: Dictionary = {"core": true}
	for pass_index: int in range(ship.parts.size()):
		for part: PartDefinition in ship.parts:
			if part.shape == "line":
				if connected.has(part.from_id): connected[part.to_id] = true
				if connected.has(part.to_id): connected[part.from_id] = true
			elif not connected.has(part.id):
				for other: PartDefinition in ship.parts:
					if connected.has(other.id) and other.shape != "line" and part.position.distance_to(other.position) <= part.radius + other.radius: connected[part.id] = true; break
	for part: PartDefinition in ship.parts:
		if part.shape != "line" and not connected.has(part.id): result.append(part.id + ": disconnected from body.")
	return result
