class_name ShipAuthoring
extends RefCounted
## Offline description compiler: approved circle templates, no network or secrets.
static func from_description(text: String) -> Dictionary:
	var description: String = text.to_lower().strip_edges()
	if description.is_empty(): return {"errors": PackedStringArray(["Describe an element, tier and role; for example: compact fire tier 3 with ricochet and mines."])}
	var aliases: Dictionary = {"homing missiles": "seeker missiles", "missiles": "seeker missiles", "mines": "mine layer", "poison": "poison cloud", "rockets": "rocket launcher", "compact hull": "compact"}
	for alias: String in aliases:
		if not str(aliases[alias]) in description: description = description.replace(alias, aliases[alias])
	var element: String = "corruption"
	for candidate: String in ShipCatalog.ELEMENTS:
		if candidate in description: element = candidate
	var tier: int = 2
	var expression: RegEx = RegEx.new()
	expression.compile("(?:tier\\s*|t)([1-6])")
	var match_result: RegExMatch = expression.search(description)
	if match_result != null: tier = int(match_result.get_string(1))
	var family: String = "standard_a"
	for candidate: String in ShipCatalog.FAMILIES:
		if candidate.replace("_", " ") in description: family = candidate
	var faction: String = "player"
	for candidate: String in ["enemy", "elite", "boss"]:
		if candidate in description: faction = candidate
	var ship: ShipDefinition = ShipCatalog.build_ship(element, tier, faction == "player", [], family, faction)
	var explicit: Dictionary = {"primary": [], "secondary": [], "passive": []}
	var remainder: String = description
	var components: Array = AbilityCatalog.DEFINITIONS.keys()
	components.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for component: String in components:
		if component.replace("_", " ") in remainder:
			remainder = remainder.replace(component.replace("_", " "), " ")
			var definition: AbilityDefinition = AbilityCatalog.get_definition(component)
			if explicit.has(definition.slot_kind): explicit[definition.slot_kind].append(component)
	for kind: String in explicit:
		if explicit[kind].is_empty(): continue
		if kind == "primary" and explicit[kind].size() > 1: return {"errors": PackedStringArray(["Specify only one primary weapon."])}
		if kind == "primary": ship.primary = explicit[kind][0]
		elif kind == "secondary": ship.secondaries.assign(explicit[kind])
		else: ship.passives.assign(explicit[kind])
	if explicit.values().any(func(value: Array) -> bool: return not value.is_empty()): rebuild_loadout(ship)
	ship.id += "_draft"
	ship.display_name += " Draft"
	ship.description = text
	ShipCatalog.recalculate(ship)
	var warning: PackedStringArray = []
	var known: PackedStringArray = PackedStringArray(["a", "an", "the", "with", "and", "of", "ship", "hull", "tier", "t1", "t2", "t3", "t4", "t5", "t6", "1", "2", "3", "4", "5", "6", "player", "enemy", "elite", "boss", "compact", "standard", "heavy", "standard_a", "standard_b", "fire", "corruption", "plasma", "lightning", "void"])
	var words: RegEx = RegEx.new()
	words.compile("[a-z0-9_]+")
	var unsupported: PackedStringArray = []
	for word: RegExMatch in words.search_all(remainder):
		if not word.get_string() in known and not word.get_string() in unsupported: unsupported.append(word.get_string())
	if not unsupported.is_empty(): warning.append("Template generator did not interpret: " + ", ".join(unsupported))
	return {"ship": ship, "errors": ShipCatalog.validate(ship), "warnings": warning}

static func rebuild_loadout(ship: ShipDefinition) -> void:
	var remove: PackedStringArray = []
	for part: PartDefinition in ship.parts:
		if not part.mount_id.is_empty() and not part.mount_id.begins_with("elite_weapon_"): remove.append(part.id)
	for index: int in range(ship.parts.size() - 1, -1, -1):
		var part: PartDefinition = ship.parts[index]
		if part.id in remove or part.from_id in remove or part.to_id in remove: ship.parts.remove_at(index)
	ShipCatalog.mount_component(ship, ship.primary, "primary", Vector2(0, -9))
	for index: int in range(ship.secondaries.size()): ShipCatalog.mount_component(ship, ship.secondaries[index], "secondary_" + str(index), Vector2(0, 20 + index * 10))
	for index: int in range(ship.passives.size()): ShipCatalog.mount_component(ship, ship.passives[index], "passive_" + str(index), Vector2(0, -23 - index * 10))
	ShipCatalog.recalculate(ship)

## --- Ships as data (spec §22) ----------------------------------------------
## Top level: id, name, faction, element, tier, symmetry, core, circles,
## lines, groups. "Mirrored parts on player hulls are authored once and
## generated on the other side": export keeps only the non-generated side of
## a mirrored pair (the side with position.x <= 0) and records the exact id
## its twin must have in a "mirror" field; import regenerates that twin
## rather than re-deriving a new id, so a round trip is lossless.

static func _circle_entry(part: PartDefinition) -> Dictionary:
	# The spec §22 example omits x/y (it is explicitly "abridged"); a circle's
	# placement is essential data our engine actually reads, so it travels as
	# "x"/"y" alongside the fields the example does show.
	var entry: Dictionary = {"id": part.id, "x": part.position.x, "y": part.position.y, "radius": part.radius, "parent": part.parent_id, "color": part.color_role, "hp": part.hp, "filled": part.filled, "light_period": part.light_period, "light_phase": part.light_phase, "layer": part.layer, "dashed": part.dashed, "stat_id": part.stat_id, "stat_value": part.stat_value}
	if not part.mount_id.is_empty():
		entry.component = part.ability_id
		entry.mount_id = part.mount_id
	if not part.mirror_id.is_empty(): entry.mirror = part.mirror_id
	return entry

static func _line_entry(part: PartDefinition) -> Dictionary:
	return {"id": part.id, "from": part.from_id, "to": part.to_id, "color": part.color_role}

static func to_json(ship: ShipDefinition) -> String:
	var core: PartDefinition = null
	for part: PartDefinition in ship.parts:
		if part.id == "core": core = part
	# The generated (positive-x) side of a mirrored pair is dropped from the
	# file; its exact id survives in the canonical circle's "mirror" field.
	var generated: Dictionary = {}
	var circle_mirror: Dictionary = {}
	for part: PartDefinition in ship.parts:
		if part.shape == "circle" and not part.mirror_id.is_empty(): circle_mirror[part.id] = part.mirror_id
	if ship.is_player:
		for part: PartDefinition in ship.parts:
			if part.shape == "circle" and part.id != "core" and not part.mirror_id.is_empty() and part.position.x > 0.01: generated[part.id] = true
	# Circles carry a real mirror_id (set by ShipCatalog.add_pair), but the
	# generator never sets one on the LINE that connects to a mirrored
	# circle. Its dropped twin's id is looked up here, from the actual
	# ship data, by matching the line's mirrored endpoints against every
	# other line's endpoints - not re-derived from an id naming convention,
	# which would break on a hand-authored file that doesn't follow it.
	var line_by_endpoints: Dictionary = {}
	for part: PartDefinition in ship.parts:
		if part.shape == "line": line_by_endpoints[part.from_id + "→" + part.to_id] = part.id
	var circles: Array = []
	var lines: Array = []
	for part: PartDefinition in ship.parts:
		if part.shape == "circle":
			if part.id == "core" or generated.has(part.id): continue
			circles.append(_circle_entry(part))
		elif part.shape == "line":
			if generated.has(part.from_id) or generated.has(part.to_id): continue
			var entry: Dictionary = _line_entry(part)
			var mirrored_from: String = str(circle_mirror.get(part.from_id, part.from_id))
			var mirrored_to: String = str(circle_mirror.get(part.to_id, part.to_id))
			if mirrored_from != part.from_id or mirrored_to != part.to_id:
				var key: String = mirrored_from + "→" + mirrored_to
				if line_by_endpoints.has(key): entry.mirror = line_by_endpoints[key]
			lines.append(entry)
	var groups: Array = []
	for group: GroupDefinition in ship.groups:
		groups.append({"root": group.root_id, "orbit_radius": group.orbit_radius, "orbit_speed": group.orbit_speed, "drift_amp": group.drift_amp, "drift_freq": group.drift_freq, "breathe_amp": group.breathe_amp, "chain_mode": group.chain_mode, "reach_ring": group.reach_ring})
	var result: Dictionary = {
		"schema_version": 3,
		"id": ship.id, "name": ship.display_name, "faction": ship.faction,
		"element": ship.element, "tier": ship.tier, "role": ship.role,
		"is_player": ship.is_player,
		"symmetry": ship.symmetry,
		# `ship.core_radius` is a distinct small glow-dot value the renderer
		# draws under the hull (see ship_renderer.gd); it is not the "core"
		# circle's own radius, which is `core.radius` below. Both must
		# survive the round trip.
		"core_glow_radius": ship.core_radius,
		"motion_signature": ship.motion_signature,
		"description": ship.description,
		"primary": ship.primary,
		"secondaries": ship.secondaries,
		"passives": ship.passives,
		"core": _circle_entry(core) if core != null else {},
		"circles": circles,
		"lines": lines,
		"groups": groups,
	}
	return JSON.stringify(result, "\t")

static func _part_from_circle_entry(entry: Dictionary, id: String, parent: String) -> PartDefinition:
	var part: PartDefinition = PartDefinition.new()
	part.id = id
	part.shape = "circle"
	part.radius = float(entry.get("radius", 5.0))
	part.position = Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
	part.parent_id = parent
	part.color_role = str(entry.get("color", "chassis"))
	part.hp = float(entry.get("hp", 0.0))
	part.filled = bool(entry.get("filled", true))
	part.light_period = float(entry.get("light_period", 2.0))
	part.light_phase = float(entry.get("light_phase", 0.0))
	part.layer = int(entry.get("layer", 3))
	part.dashed = bool(entry.get("dashed", false))
	part.stat_id = str(entry.get("stat_id", ""))
	part.stat_value = float(entry.get("stat_value", 0.0))
	if entry.has("component"):
		part.ability_id = str(entry.component)
		part.mount_id = str(entry.get("mount_id", id))
	return part

static func to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry: Variant in value: result.append(str(entry))
	return result

static func from_json(text: String) -> Dictionary:
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary: return {"errors": PackedStringArray(["Invalid ship JSON."])}
	if int(data.get("schema_version", -1)) == 2: return from_legacy_v2(data)
	if int(data.get("schema_version", -1)) != 3 or not data.get("core") is Dictionary or not data.get("circles") is Array or not data.get("lines") is Array:
		return {"errors": PackedStringArray(["Expected a version 3 (§22) ship JSON object."])}
	var ship: ShipDefinition = ShipDefinition.new()
	ship.schema_version = 3
	ship.id = str(data.get("id", ""))
	ship.display_name = str(data.get("name", ship.id))
	ship.faction = str(data.get("faction", "player"))
	ship.element = str(data.get("element", "neutral"))
	ship.tier = int(data.get("tier", 1))
	ship.role = str(data.get("role", "standard"))
	ship.is_player = bool(data.get("is_player", ship.faction == "player"))
	ship.symmetry = str(data.get("symmetry", "bilateral" if ship.is_player else "none"))
	ship.core_radius = float(data.get("core_glow_radius", 3.0))
	ship.motion_signature = str(data.get("motion_signature", "smooth"))
	ship.description = str(data.get("description", ""))
	ship.primary = str(data.get("primary", ""))
	ship.secondaries = to_string_array(data.get("secondaries", []))
	ship.passives = to_string_array(data.get("passives", []))
	var by_id: Dictionary = {}
	var core_entry: Dictionary = data.core
	var core_part: PartDefinition = _part_from_circle_entry(core_entry, "core", "")
	ship.parts.append(core_part)
	by_id["core"] = core_part
	for raw: Variant in data.circles:
		if not raw is Dictionary: return {"errors": PackedStringArray(["A circle entry must be an object."])}
		var entry: Dictionary = raw
		var id: String = str(entry.get("id", ""))
		if id.is_empty(): return {"errors": PackedStringArray(["A circle is missing its id."])}
		var part: PartDefinition = _part_from_circle_entry(entry, id, str(entry.get("parent", "")))
		ship.parts.append(part)
		by_id[id] = part
		if entry.has("mirror"):
			# The twin regenerated here gets the EXACT id recorded at export
			# time - never a freshly invented one - so ids that lines,
			# mounts and groups reference elsewhere in the file still match.
			var mirror_id: String = str(entry.mirror)
			var parent_mirror: String = ""
			if by_id.has(part.parent_id): parent_mirror = str(by_id[part.parent_id].mirror_id)
			var mirror: PartDefinition = part.duplicate(true)
			mirror.id = mirror_id
			mirror.position = Vector2(-part.position.x, part.position.y)
			mirror.parent_id = parent_mirror if not parent_mirror.is_empty() else part.parent_id
			mirror.mirror_id = id
			part.mirror_id = mirror_id
			ship.parts.append(mirror)
			by_id[mirror_id] = mirror
	for raw: Variant in data.lines:
		if not raw is Dictionary: return {"errors": PackedStringArray(["A line entry must be an object."])}
		var entry: Dictionary = raw
		var from_id: String = str(entry.get("from", ""))
		var to_id: String = str(entry.get("to", ""))
		if from_id.is_empty() or to_id.is_empty(): return {"errors": PackedStringArray(["A line is missing an endpoint."])}
		var line: PartDefinition = PartDefinition.new()
		line.id = str(entry.get("id", from_id + "_" + to_id + "_line"))
		line.shape = "line"
		line.from_id = from_id
		line.to_id = to_id
		line.color_role = str(entry.get("color", "chassis"))
		# Matches ShipCatalog.add_line's own defaults; without a stat a line
		# fails "assign a component or body statistic" in validate().
		line.stat_id = "structure"
		ship.parts.append(line)
		if entry.has("mirror"):
			var mirror_from: String = str(by_id[from_id].mirror_id) if by_id.has(from_id) and not str(by_id[from_id].mirror_id).is_empty() else from_id
			var mirror_to: String = str(by_id[to_id].mirror_id) if by_id.has(to_id) and not str(by_id[to_id].mirror_id).is_empty() else to_id
			var mirror_line: PartDefinition = PartDefinition.new()
			mirror_line.id = str(entry.mirror)
			mirror_line.shape = "line"
			mirror_line.from_id = mirror_from
			mirror_line.to_id = mirror_to
			mirror_line.color_role = line.color_role
			mirror_line.stat_id = "structure"
			mirror_line.mirror_id = line.id
			line.mirror_id = mirror_line.id
			ship.parts.append(mirror_line)
	for raw: Variant in data.get("groups", []):
		if not raw is Dictionary: continue
		var group: GroupDefinition = GroupDefinition.new()
		group.root_id = str(raw.get("root", ""))
		group.orbit_radius = float(raw.get("orbit_radius", 0.0))
		group.orbit_speed = float(raw.get("orbit_speed", 0.0))
		group.drift_amp = float(raw.get("drift_amp", 0.0))
		group.drift_freq = float(raw.get("drift_freq", 0.0))
		group.breathe_amp = float(raw.get("breathe_amp", 0.0))
		group.chain_mode = str(raw.get("chain_mode", "rigid"))
		group.reach_ring = bool(raw.get("reach_ring", false))
		ship.groups.append(group)
	ShipCatalog.recalculate(ship)
	return {"ship": ship, "errors": ShipCatalog.validate(ship)}

## Legacy v2 (pre-P2a-1) importer: ellipse -> circle of mean radius,
## ring -> unfilled circle, crescent -> two circles (outer + a "black" cover
## disc, matching the P2a-1 adaptation), tether/arc -> line. v2 circles carry
## no parent_id; parents are inferred by walking the tether/line graph
## breadth-first from "body" (renamed "core"). Reached only when
## schema_version == 2 - an explicit "import legacy" path, never the default.
static func from_legacy_v2(data: Dictionary) -> Dictionary:
	if not data.get("parts") is Array: return {"errors": PackedStringArray(["Expected a version 2 (legacy) ship JSON object with a parts array."])}
	var ship: ShipDefinition = ShipDefinition.new()
	ship.schema_version = 3
	for key: String in ["id", "faction", "element", "role", "description"]:
		if data.has(key): ship.set(key, str(data[key]))
	if data.has("display_name"): ship.display_name = str(data.display_name)
	if data.has("tier"): ship.tier = int(data.tier)
	if data.has("is_player"): ship.is_player = bool(data.is_player)
	if data.has("primary"): ship.primary = str(data.primary)
	ship.secondaries = to_string_array(data.get("secondaries", []))
	ship.passives = to_string_array(data.get("passives", []))
	var built: Array[PartDefinition] = []
	var edge_pairs: Array = []
	var remap_body: Callable = func(value: String) -> String: return "core" if value == "body" else value
	for raw: Variant in data.parts:
		if not raw is Dictionary: continue
		var entry: Dictionary = raw
		var old_id: String = str(entry.get("id", ""))
		var id: String = remap_body.call(old_id)
		var shape: String = str(entry.get("shape", "circle"))
		var position: Vector2 = _legacy_vector(entry.get("position", [0, 0]))
		match shape:
			"ellipse":
				var size_value: Array = entry.get("size", [10, 10])
				var mean_radius: float = (float(size_value[0]) + float(size_value[1])) / 4.0
				var part: PartDefinition = PartDefinition.new()
				part.id = id; part.shape = "circle"; part.radius = maxf(1.0, mean_radius); part.position = position; part.filled = true
				built.append(part)
			"ring":
				var part: PartDefinition = PartDefinition.new()
				part.id = id; part.shape = "circle"; part.radius = maxf(1.0, float(entry.get("radius", 10.0))); part.position = position; part.filled = false
				built.append(part)
			"crescent":
				var outer_radius: float = maxf(1.0, float(entry.get("radius", 10.0)))
				var outer: PartDefinition = PartDefinition.new()
				outer.id = id; outer.shape = "circle"; outer.radius = outer_radius; outer.position = position; outer.filled = true
				built.append(outer)
				var cover: PartDefinition = PartDefinition.new()
				cover.id = id + "_cover"; cover.shape = "circle"; cover.radius = outer_radius * 0.8
				cover.position = position + Vector2(0, -outer_radius * 0.3)
				cover.filled = true
				cover.color_role = "black"
				built.append(cover)
				edge_pairs.append([cover.id, outer.id])
			"tether", "arc":
				var part: PartDefinition = PartDefinition.new()
				part.id = id; part.shape = "line"; part.stat_id = "structure"
				part.from_id = remap_body.call(str(entry.get("from_id", entry.get("from", ""))))
				part.to_id = remap_body.call(str(entry.get("to_id", entry.get("to", ""))))
				built.append(part)
			_:
				var part: PartDefinition = PartDefinition.new()
				part.id = id; part.shape = shape
				part.radius = maxf(1.0, float(entry.get("radius", 10.0)))
				part.position = position
				part.filled = bool(entry.get("filled", true))
				if entry.has("component"):
					# A mount circle, same shape as ShipCatalog.mount_component's own.
					part.ability_id = str(entry.component)
					part.mount_id = str(entry.get("mount_id", id))
					part.color_role = AbilityCatalog.get_definition(part.ability_id).visual_color
				built.append(part)
	for part: PartDefinition in built:
		if part.shape == "line": edge_pairs.append([part.from_id, part.to_id])
	# Every non-mount circle other than the core needs a body statistic
	# (validate()'s "assign a component or body statistic"); the legacy
	# schema had no such concept, so a generic fallback is assigned here.
	# The core keeps the generator's own default ("speed").
	for part: PartDefinition in built:
		if part.shape != "circle" or not part.mount_id.is_empty(): continue
		if part.id == "core": part.stat_id = "speed"
		elif part.stat_id.is_empty(): part.stat_id = "structure"
	var adjacency: Dictionary = {}
	for pair: Array in edge_pairs:
		var a: String = str(pair[0])
		var b: String = str(pair[1])
		if a.is_empty() or b.is_empty(): continue
		if not adjacency.has(a): adjacency[a] = []
		if not adjacency.has(b): adjacency[b] = []
		adjacency[a].append(b)
		adjacency[b].append(a)
	var parent_of: Dictionary = {}
	var visited: Dictionary = {"core": true}
	var queue: Array[String] = ["core"]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor: Variant in adjacency.get(current, []):
			var neighbor_id: String = str(neighbor)
			if visited.has(neighbor_id): continue
			visited[neighbor_id] = true
			parent_of[neighbor_id] = current
			queue.append(neighbor_id)
	for part: PartDefinition in built:
		if part.shape == "circle" and part.id != "core": part.parent_id = str(parent_of.get(part.id, "core"))
	ship.parts.assign(built)
	ShipCatalog.recalculate(ship)
	return {"ship": ship, "errors": ShipCatalog.validate(ship), "warnings": PackedStringArray(["Imported from legacy v0.2 schema; review parent inference and TP before saving."])}

static func _legacy_vector(value: Variant) -> Vector2:
	if value is Array and value.size() == 2: return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO

static func thumbnail(ship: ShipDefinition) -> Texture2D:
	var scale: float = 48.0 / maxf(48.0, ship.footprint)
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="#050507"/>'
	for part: PartDefinition in ship.parts:
		if part.shape == "line": continue
		var color: Color = ShipCatalog.get_color(("player" if ship.is_player else ship.element) if part.color_role == "chassis" else part.color_role)
		var point: Vector2 = Vector2(32, 32) + part.position * scale
		svg += '<circle cx="%f" cy="%f" r="%f" fill="%s" stroke="#%s" stroke-width="1"/>' % [point.x, point.y, part.radius * scale, "none" if not part.filled else "#07111a", color.to_html(false)]
		# Fill omitted for unfilled (ring) circles; stroke is always the rim color.
	svg += '</svg>'
	var image: Image = Image.new()
	image.load_svg_from_string(svg)
	return ImageTexture.create_from_image(image)



