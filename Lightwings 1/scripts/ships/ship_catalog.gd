class_name ShipCatalog
extends RefCounted
## Canonical saved hulls; construction is exclusively an authoring operation.
static var catalog_root: String = "res://content/ships"
const MAX_PARTS: int = 128
const MAX_AUTHORED_PARTS: int = 128
const ELEMENTS: Array[String] = ["fire", "lightning", "void", "corruption", "plasma"]
const SHAPES: Array[String] = ["circle", "line"]
const FAMILIES: Array[String] = ["compact", "standard_a", "standard_b", "heavy"]
const PALETTE: Dictionary = {"player": Color("6fd3ff"), "player_blue": Color("6fd3ff"), "fire": Color("ff5436"), "lightning": Color("ffd23f"), "corruption": Color("45e06a"), "plasma": Color("a97dff"), "violet": Color("a97dff"), "void": Color("9aa3b3"), "silver": Color("9aa3b3"), "gold": Color("ffd23f"), "yellow": Color("ffd23f"), "red": Color("ff5436"), "white": Color.WHITE, "neutral": Color("9aa3b3"), "green": Color("45e06a"), "black": Color.BLACK}
const FILLS: Dictionary = {"player": Color("08233a"), "player_blue": Color("08233a"), "fire": Color("2a0b08"), "lightning": Color("2a2206"), "corruption": Color("062a12"), "plasma": Color("1d1233"), "violet": Color("1d1233"), "void": Color.BLACK, "silver": Color.BLACK, "gold": Color.BLACK, "yellow": Color("2a2206"), "red": Color("2a0b08"), "white": Color("191919"), "neutral": Color("101015"), "green": Color("062a12"), "black": Color.BLACK}
const LIGHTS: Dictionary = {"player": Color("dcf5ff"), "player_blue": Color("dcf5ff"), "fire": Color("ffc6b5"), "lightning": Color("fff3bd"), "corruption": Color("caffd5"), "plasma": Color("e4d6ff"), "violet": Color("e4d6ff"), "void": Color.WHITE, "silver": Color.WHITE, "gold": Color("fff3bd"), "yellow": Color("fff3bd"), "red": Color("ffc6b5"), "white": Color.WHITE, "neutral": Color.WHITE, "green": Color("caffd5"), "black": Color.BLACK}
# Retained for descriptive legacy consumers; gameplay uses mounted_components().
const NAMES: Dictionary = {"fire": ["Ember", "Flare", "Stoker", "Furnace", "Sunburst"], "lightning": ["Spark", "Arc", "Fork", "Surge", "Tempest"], "void": ["Null", "Eclipse", "Umbra", "Horizon", "Singularity"], "corruption": ["Glitch", "Worm", "Trojan", "Rootkit", "Botnet"], "plasma": ["Ion", "Orbit", "Corona", "Pulsar", "Quasar"]}
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
	return get_ship(("player_" if is_player else "enemy_") + element + "_t" + str(tier) + ("_standard_a" if is_player else ""))

static func ability_description(element: String, tier: int) -> String:
	return str(NAMES.get(element, NAMES.corruption)[clampi(tier - 1, 0, 4)])

static func role_for_family(family: String) -> String:
	return family if family in ["compact", "heavy"] else "standard"

static func build_ship(element: String, tier: int, is_player: bool = false, _legacy: Array = [], family: String = "standard_a", faction: String = "") -> ShipDefinition:
	var ship: ShipDefinition = ShipDefinition.new()
	ship.is_player = is_player
	ship.faction = "player" if is_player else ("enemy" if faction.is_empty() else faction)
	ship.tier = clampi(tier, 1, GameTuning.MAX_TIER)
	ship.element = "neutral" if is_player and tier == 1 else element
	ship.family = family
	ship.role = "standard" if tier == 1 else role_for_family(family)
	ship.id = "player_seed" if is_player and tier == 1 else ship.faction + "_" + element + "_t" + str(tier) + ("_" + family if is_player else "")
	ship.display_name = "Lumen" if ship.element == "neutral" else str(NAMES[element][tier - 1]) + " " + family.replace("_", " ").capitalize()
	ship.motion_signature = {"fire": "flicker", "lightning": "snap", "void": "inward", "corruption": "breathe", "plasma": "counter_rotate"}.get(ship.element, "smooth")
	ship.breathes = ship.element == "corruption"
	ship.speed = 220.0 * (1.25 if ship.role == "compact" else 0.85 if ship.role == "heavy" else 1.0)
	ship.turn_rate = 10.0 * (1.25 if ship.role == "compact" else 0.8 if ship.role == "heavy" else 1.0)
	ship.hp_buffer = 0.8 if ship.role == "compact" else 1.3 if ship.role == "heavy" else 1.0
	ship.damage_multiplier = 1.15 if ship.role == "heavy" else 1.0
	ship.primary = "pulse_cannon" if ship.element == "neutral" else str(ABILITIES[element][0])
	if family == "standard_b" and tier > 1: ship.primary = "ricochet"
	if ship.faction == "enemy" and element in ["void", "plasma"]: ship.primary = "pulse_cannon"
	var limits: Dictionary = GameTuning.slots(tier, ship.role)
	for index: int in range(int(limits.secondary)):
		ship.secondaries.append(str(ABILITIES[element][1 + index % 3]))
	if ship.faction == "elite": ship.secondaries.clear()
	if ship.faction == "enemy" and element == "corruption" and tier >= 2: ship.secondaries[0] = "droid_bay"
	if tier >= 4: ship.passives.append("radar" if is_player and family == "standard_b" else "health_readout" if is_player and family == "compact" else str(ABILITIES[element][4]))
	ship.abilities = ship.mounted_components()
	var body_radius: float = 11.0 if tier == 1 else (12.0 if ship.role == "compact" else 18.0 if ship.role == "heavy" else 15.0)
	if not is_player and ship.faction == "elite": body_radius *= 2.8
	# Corruption's old ellipse body had half-axes (body_radius, body_radius*0.9); a
	# circle keeps the mean radius so the eye and mounts stay in the same place.
	var core_radius: float = body_radius * 0.95 if element == "corruption" and tier > 1 else body_radius
	var core: PartDefinition = add_part(ship, "core", "circle", Vector2.ZERO, core_radius, "chassis", "hp_buffer", 3)
	if ship.element == "void":
		ship.hull_radius = body_radius + 5.0 * tier
		core.radius = ship.hull_radius
		var reach: PartDefinition = add_part(ship, "reach", "circle", Vector2.ZERO, ship.hull_radius + 9, "chassis", "magnet_radius", 0, false, "core")
		reach.dashed = true
		# The old crescent "maw" is a bright rimmed circle with a black disc laid
		# over part of it; the rimmed circle keeps the id, position and stat that
		# combat reads (scripts/combat/combat_broadphase.gd's bullet_eater mouth).
		var maw_half: float = body_radius * 1.4 * 0.5
		var maw_position: Vector2 = Vector2(0, -body_radius * 0.3)
		var maw: PartDefinition = add_part(ship, "maw", "circle", maw_position, maw_half, "chassis", "hp_buffer", 3, true, "core")
		var maw_inner_radius: float = maw_half * 0.84
		var maw_inner_position: Vector2 = maw_position + Vector2(0, -maw_half * 0.42)
		var maw_cover: PartDefinition = add_part(ship, "maw_cover", "circle", maw_inner_position, maw_inner_radius, "black", "structure", 4, true, "maw")
		maw_cover.tp_cost = 0.0
	if ship.element == "plasma":
		for index: int in range(1 + tier / 2):
			add_part(ship, "orbit_" + str(index), "circle", Vector2.ZERO, body_radius + 5 + index * 6, "chassis", "magnet_radius", 2, false, "core")
	if tier > 1:
		for index: int in range(tier - 1):
			var spread: float = (9.0 if ship.role == "compact" else 14.0 if ship.role == "heavy" else 11.0)
			var x: float = body_radius + spread + (index % 2) * 7.0
			var y: float = (float(index) - float(tier - 2) * 0.5) * 15.0
			var radius: float = maxf(4.0, 9.0 - index)
			if element == "lightning": x += 12 + index * 4; radius = 5
			if element == "fire": y -= 9; x -= 5
			if element == "void": x = body_radius * 0.55; y *= 0.6; radius = 5
			if family == "standard_b": y = -y - 10; x += 4
			# Corruption's old lobe ellipse had half-axes (radius, radius*0.75); a
			# circle keeps the mean of the two.
			var lobe_radius: float = radius * 0.875 if element == "corruption" else radius
			add_pair(ship, "lobe_" + str(index), "circle", Vector2(x, y), lobe_radius, "chassis", "speed" if index % 2 == 0 else "magnet_radius", 2)
			add_line(ship, "link_" + str(index) + "_l", "core", "lobe_" + str(index) + "_l")
			add_line(ship, "link_" + str(index) + "_r", "core", "lobe_" + str(index) + "_r")
			ship.parts[-2].mirror_id = ship.parts[-1].id
			ship.parts[-1].mirror_id = ship.parts[-2].id
	mount_component(ship, ship.primary, "primary", Vector2(0, -body_radius * 0.7), 11.0 if ship.faction == "elite" else 3.5)
	if ship.faction == "elite": ship.parts[-2].hp = 24 + tier * 15
	for index: int in range(ship.secondaries.size()): mount_component(ship, ship.secondaries[index], "secondary_" + str(index), Vector2(0, body_radius + 7 + index * 9))
	for index: int in range(ship.passives.size()): mount_component(ship, ship.passives[index], "passive_" + str(index), Vector2(0, -body_radius - 8 - index * 9))
	if ship.faction == "elite":
		var weapons: Array[String] = ["laser_prong", "egg", "droid_bay", "deployment_ramp", "turret_ring", "explosives", "rocket_launcher", "poison_cloud"]
		for index: int in range(clampi(tier + 1, 2, 7)):
			var angle: float = TAU * float(index) / float(tier + 2)
			mount_component(ship, weapons[index], "elite_weapon_" + str(index), Vector2.from_angle(angle) * body_radius * 1.6, 11.0)
			ship.parts[-2].hp = 24 + tier * 15
	if ship.faction == "enemy":
		for part: PartDefinition in ship.parts:
			if element == "void" and part.id == "maw": part.stat_id = "bullet_eater"; part.stat_value = 9.0
			if element == "void" and part.id == "reach": part.stat_id = "void_pull"; part.stat_value = 180.0
			if element == "plasma" and part.id == "orbit_0": part.stat_id = "projectile_orbit"; part.stat_value = 65.0
	ship.magnet_radius = 95 + (15 if ship.role == "heavy" else -10 if ship.role == "compact" else 0) + (8 if family == "standard_b" else 0)
	recalculate(ship)
	return ship

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

static func add_pair(ship: ShipDefinition, id: String, shape: String, position: Vector2, radius: float, color: String, stat: String, layer: int = 2) -> void:
	var left: PartDefinition = add_part(ship, id + "_l", shape, Vector2(-position.x, position.y), radius, color, stat, layer, true, "core")
	var right: PartDefinition = add_part(ship, id + "_r", shape, position, radius, color, stat, layer, true, "core")
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
	ship.tp_max = GameTuning.TP_BUDGETS[clampi(ship.tier - 1, 0, GameTuning.MAX_TIER - 1)] * (2.5 if ship.faction == "elite" else 1.0)
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
	if not ship.faction in ["player", "enemy", "elite", "rival"]: errors.append("Unknown faction.")
	if ship.is_player != (ship.faction == "player"): errors.append("Faction and player flag disagree.")
	if not ship.role in ["compact", "standard", "heavy"]: errors.append("Unknown role.")
	if ship.parts.size() > MAX_PARTS: errors.append("At most 128 expanded parts supported.")
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
		if part.mount_id.is_empty() and not part.stat_id in ["speed", "turn_rate", "magnet_radius", "structure", "bullet_eater", "void_pull", "projectile_orbit"]: errors.append(part.id + ": assign a component or body statistic.")
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
	if not errors.is_empty(): return errors
	var copy: ShipDefinition = ship.duplicate(true)
	recalculate(copy)
	if copy.tp_used > copy.tp_max + 0.001: errors.append("TP budget exceeded: %.2f / %.2f" % [copy.tp_used, copy.tp_max])
	return errors

static func warnings(ship: ShipDefinition) -> PackedStringArray:
	var result: PackedStringArray = []
	var bands: Dictionary = {"compact": Vector2(20, 90), "standard": Vector2(35, 135), "heavy": Vector2(60, 180)}
	var band: Vector2 = bands.get(ship.role, Vector2(0, 200))
	if ship.tier > 1 and ship.faction != "elite" and (ship.footprint < band.x or ship.footprint > band.y): result.append("Footprint lies outside the role's suggested band.")
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
