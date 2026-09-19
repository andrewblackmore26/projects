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
	expression.compile("(?:tier\\s*|t)([1-5])")
	var match_result: RegExMatch = expression.search(description)
	if match_result != null: tier = int(match_result.get_string(1))
	var family: String = "standard_a"
	for candidate: String in ShipCatalog.FAMILIES:
		if candidate.replace("_", " ") in description: family = candidate
	var faction: String = "player"
	for candidate: String in ["enemy", "elite", "rival"]:
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
	var known: PackedStringArray = PackedStringArray(["a", "an", "the", "with", "and", "of", "ship", "hull", "tier", "t1", "t2", "t3", "t4", "t5", "1", "2", "3", "4", "5", "player", "enemy", "elite", "rival", "compact", "standard", "heavy", "standard_a", "standard_b", "fire", "corruption", "plasma", "lightning", "void"])
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

static func to_json(ship: ShipDefinition) -> String:
	var result: Dictionary = {}
	for property: Dictionary in ship.get_property_list():
		if not int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE: continue
		var key: String = property.name
		if key == "parts": continue
		result[key] = ship.get(key)
	result.parts = []
	for part: PartDefinition in ship.parts:
		var entry: Dictionary = {}
		for property: Dictionary in part.get_property_list():
			if not int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE: continue
			var value: Variant = part.get(property.name)
			entry[property.name] = [value.x, value.y] if value is Vector2 else value
		result.parts.append(entry)
	return JSON.stringify(result, "\t")

static func from_json(text: String) -> Dictionary:
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary or data.get("schema_version", 0) != 2 or not data.get("parts") is Array: return {"errors": PackedStringArray(["Expected a version 2 ship JSON object."])}
	var ship: ShipDefinition = ShipDefinition.new()
	for property: Dictionary in ship.get_property_list():
		if not int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE: continue
		var key: String = property.name
		if key == "parts" or not data.has(key): continue
		var current: Variant = ship.get(key)
		if current is Array:
			if not data[key] is Array: return {"errors": PackedStringArray([key + " must be an array."])}
			var values: Array[String] = []
			for entry: Variant in data[key]:
				if not entry is String: return {"errors": PackedStringArray([key + " entries must be strings."])}
				values.append(entry)
			ship.set(key, values)
		elif typeof(data[key]) == typeof(current) or (current is float and (data[key] is int or data[key] is float)) or (current is int and data[key] is float): ship.set(key, data[key])
		else: return {"errors": PackedStringArray(["Invalid type for " + key])}
	for entry: Variant in data.parts:
		if not entry is Dictionary: return {"errors": PackedStringArray(["Part must be an object."])}
		var part: PartDefinition = PartDefinition.new()
		for property: Dictionary in part.get_property_list():
			if not int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE: continue
			var key: String = property.name
			if not entry.has(key): continue
			var current: Variant = part.get(key)
			if current is Vector2:
				if not entry[key] is Array or entry[key].size() != 2 or not (entry[key][0] is float or entry[key][0] is int) or not (entry[key][1] is float or entry[key][1] is int): return {"errors": PackedStringArray(["Invalid vector for " + key])}
				part.set(key, Vector2(entry[key][0], entry[key][1]))
			elif typeof(entry[key]) == typeof(current) or (current is float and (entry[key] is int or entry[key] is float)) or (current is int and entry[key] is float): part.set(key, entry[key])
			else: return {"errors": PackedStringArray(["Invalid part type for " + key])}
		ship.parts.append(part)
	ShipCatalog.recalculate(ship)
	return {"ship": ship, "errors": ShipCatalog.validate(ship)}

static func thumbnail(ship: ShipDefinition) -> Texture2D:
	var scale: float = 48.0 / maxf(48.0, ship.footprint)
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="#050507"/>'
	for part: PartDefinition in ship.parts:
		if part.shape == "tether": continue
		var color: Color = ShipCatalog.get_color(("player" if ship.is_player else ship.element) if part.color_role == "chassis" else part.color_role)
		var point: Vector2 = Vector2(32, 32) + part.position * scale
		svg += '<ellipse cx="%f" cy="%f" rx="%f" ry="%f" fill="%s" stroke="#%s" stroke-width="1"/>' % [point.x, point.y, part.size.x * scale * 0.5, part.size.y * scale * 0.5, "none" if part.shape in ["ring", "arc"] else "#07111a", color.to_html(false)]
	svg += '</svg>'
	var image: Image = Image.new()
	image.load_svg_from_string(svg)
	return ImageTexture.create_from_image(image)



