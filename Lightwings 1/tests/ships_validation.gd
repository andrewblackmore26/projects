extends SceneTree
var failures: int = 0
var checks: int = 0
func _initialize() -> void:
	var exported_ids: Array[String] = ShipCatalog.ids_from_files(PackedStringArray(["player_seed.tres.remap", "player_fire_t2_compact.tres.remap", "player_seed.tres", "notes.txt", "ship.tres.remap.remap", "abilities/beam.tres"]))
	_check(exported_ids == ["player_fire_t2_compact", "player_seed"], "Source/PCK resource names normalize and deduplicate without traversing subdirectories")
	var source_names: PackedStringArray = DirAccess.get_files_at(ShipCatalog.catalog_root)
	var remapped_names: PackedStringArray = []
	for name: String in source_names: remapped_names.append(name + ".remap" if name.ends_with(".tres") else name)
	_check(ShipCatalog.ids_from_files(remapped_names) == ShipCatalog.ids_from_files(source_names), "Full136-hull listing survives exported remap filenames")
	var forms: Array[ShipDefinition] = ShipCatalog.all_forms()
	_check(forms.size() == 136, "81 player, 25 regular, 25 elite, 5 rivals")
	var counts: Dictionary = {}
	var shipped_components: Dictionary = {}
	var shape_census: Dictionary = {"circle_filled": 0, "circle_unfilled": 0, "line": 0}
	for ship: ShipDefinition in forms:
		_check(ShipCatalog.validate(ship).is_empty(), ship.id + " validates")
		counts[ship.faction] = int(counts.get(ship.faction, 0)) + 1
		if ship.is_player:
			for component: String in ship.mounted_components(): shipped_components[component] = true
		var guns: int = 0
		var cores: int = 0
		var circles: Dictionary = {}
		for part: PartDefinition in ship.parts:
			if part.shape == "circle": circles[part.id] = part
			if part.id == "core": cores += 1
		for part: PartDefinition in ship.parts:
			if part.hp > 0: guns += 1
			if ship.faction == "elite" and not part.mount_id.is_empty() and AbilityCatalog.get_definition(part.ability_id).slot_kind != "passive": _check(part.hp > 0, "Every elite weapon circle is an active destructible gun")
			_check(part.shape in ShipCatalog.SHAPES, "Only permitted primitives")
			_check(not part.stat_id.is_empty() or not part.mount_id.is_empty(), "Every part communicates a function")
			if part.shape == "circle": shape_census[("circle_filled" if part.filled else "circle_unfilled")] += 1
			elif part.shape == "line": shape_census.line += 1
			if part.shape == "circle" and part.id != "core":
				var seen: Dictionary = {part.id: true}
				var cursor: String = part.parent_id
				var reached: bool = false
				while not cursor.is_empty() and circles.has(cursor) and not seen.has(cursor):
					if cursor == "core": reached = true; break
					seen[cursor] = true
					cursor = str(circles[cursor].parent_id)
				_check(reached or cursor == "core", ship.id + ": " + part.id + " reaches the core")
		_check(cores == 1, ship.id + " has exactly one core")
		if ship.faction == "elite": _check(guns >= 3 and guns <= 8, "Elite carries 3–8 functional guns")
	_check(counts.get("player") == 81 and counts.get("enemy") == 25 and counts.get("elite") == 25 and counts.get("rival") == 5, "Faction census")
	_check(shape_census.line > 0 and (shape_census.circle_filled + shape_census.circle_unfilled) > 0, "Census contains circles and lines")
	print("Shape census: ", shape_census)
	for component: String in AbilityCatalog.DEFINITIONS:
		if AbilityCatalog.get_definition(component).slot_kind != "enemy": _check(shipped_components.has(component), "Shipped roster exposes " + component)
	var seed: ShipDefinition = ShipCatalog.get_ship("player_seed")
	_check(seed.element == "neutral" and seed.secondaries.is_empty(), "Shared neutral seed with no secondary")
	for element: String in ShipCatalog.ELEMENTS:
		for tier: int in range(2, 6):
			var roster: Array[ShipDefinition] = ShipCatalog.roster(element, tier)
			_check(roster.size() == 4, "%s T%d four hulls" % [element, tier])
			var roles: Dictionary = {}
			for ship: ShipDefinition in roster: roles[ship.role] = true
			_check(roles.size() >= 2, "Roles span meaningful choices")
	var ship: ShipDefinition = ShipCatalog.get_ship("player_fire_t3_standard_a")
	var stat_ship: ShipDefinition = ship.duplicate(true)
	var original_speed: float = stat_ship.speed
	stat_ship.parts[0].stat_value += 4
	ShipCatalog.recalculate(stat_ship)
	_check(stat_ship.speed == original_speed + 4 and stat_ship.hp_buffer == 1.0, "Body statistics affect movement while role HP buffer stays fixed")
	var untouched: ShipDefinition = ShipCatalog.get_ship(ship.id)
	_check(untouched.speed == ship.speed, "Returned definitions cannot mutate cached templates")
	var broken: ShipDefinition = ship.duplicate(true)
	broken.parts[0].shape = "triangle"
	_check(not ShipCatalog.validate(broken).is_empty(), "Polygon rejected")
	broken = ship.duplicate(true)
	broken.parts[0].shape = "ellipse"
	_check(not ShipCatalog.validate(broken).is_empty(), "Ellipse is never legal (was: restricted to corruption)")
	broken = ship.duplicate(true)
	broken.parts[0].shape = "ring"
	_check(not ShipCatalog.validate(broken).is_empty(), "Ring is no longer a primitive")
	broken = ship.duplicate(true)
	broken.parts[0].shape = "tether"
	_check(not ShipCatalog.validate(broken).is_empty(), "Tether renamed to line; the old name is rejected")
	broken = ship.duplicate(true)
	broken.parts[0].shape = "crescent"
	_check(not ShipCatalog.validate(broken).is_empty(), "Crescent is composed from two circles, not a primitive")
	broken = ship.duplicate(true)
	broken.parts[0].shape = "arc"
	_check(not ShipCatalog.validate(broken).is_empty(), "Arc rejected")
	broken = ship.duplicate(true)
	# Introduce a two-part parent cycle between two non-core circles.
	for part: PartDefinition in broken.parts:
		if part.id == "lobe_0_l": part.parent_id = "lobe_0_r"
		if part.id == "lobe_0_r": part.parent_id = "lobe_0_l"
	_check(not ShipCatalog.validate(broken).is_empty(), "Parent cycle rejected")
	broken = ship.duplicate(true)
	for part: PartDefinition in broken.parts:
		if part.id == "lobe_0_l": part.parent_id = "does_not_exist"
	_check(not ShipCatalog.validate(broken).is_empty(), "Parent chain that never reaches the core rejected")
	broken = ship.duplicate(true)
	for part: PartDefinition in broken.parts:
		if part.id == "link_0_l": part.to_id = "link_0_r"
	_check(not ShipCatalog.validate(broken).is_empty(), "A line ending on a line is rejected")
	broken = ship.duplicate(true)
	broken.parts[1].position.x += 5
	_check(not ShipCatalog.validate(broken).is_empty(), "Broken symmetry rejected")
	broken = ship.duplicate(true)
	broken.secondaries.append("shield")
	_check(not ShipCatalog.validate(broken).is_empty(), "Slot overflow / missing mount rejected")
	broken = ship.duplicate(true)
	broken.parts[0].radius = 10000
	broken.parts[0].tp_cost = -100
	_check(not ShipCatalog.validate(broken).is_empty(), "TP is derived, imported fake costs cannot bypass budgets")
	broken = ShipCatalog.get_ship("enemy_fire_t3")
	broken.parts[0].color_role = "player"
	_check(not ShipCatalog.validate(broken).is_empty(), "Enemy player-blue rejected")
	var portable: Dictionary = ShipAuthoring.from_json(ShipAuthoring.to_json(ship))
	_check(portable.errors.is_empty() and portable.ship.parts.size() == ship.parts.size() and portable.ship.id == ship.id, "Portable JSON roundtrip")
	_check(not ShipAuthoring.from_json('{"schema_version":99,"parts":[]}').errors.is_empty(), "Future schema rejected")
	var generated: Dictionary = ShipAuthoring.from_description("compact fire tier 3 with ricochet and mines")
	_check(generated.errors.is_empty() and generated.ship.primary == "ricochet" and generated.ship.secondaries == ["mine_layer"], "Local compiler honors role/tier/components and synonyms")
	generated = ShipAuthoring.from_description("void tier 3 with homing beam and shield")
	_check(generated.errors.is_empty() and generated.ship.primary == "homing_beam", "Longest component match avoids beam collision")
	generated = ShipAuthoring.from_description("fire tier 3 with enormous butterfly wings")
	_check(not generated.warnings.is_empty(), "Uninterpreted description terms reported")
	generated = ShipAuthoring.from_description("fire tier 1 with shield")
	_check(not generated.errors.is_empty(), "Generator cannot bypass tier/slots")
	var outline: PackedVector2Array = ShipGeometry.outline("circle", 10)
	var lengths: PackedFloat32Array = ShipGeometry.lengths(outline)
	var section: PackedVector2Array = ShipGeometry.section(outline, lengths, 0, lengths[-1] * 0.13)
	_check(absf(ShipGeometry.lengths(section)[-1] / lengths[-1] - 0.13) < 0.001, "Running-light fraction")
	var line: PackedVector2Array = ShipGeometry.clipped_line({"position": Vector2.ZERO, "radius": 10}, {"position": Vector2(40, 0), "radius": 5})
	_check(line == PackedVector2Array([Vector2(10, 0), Vector2(35, 0)]), "Line clips to both rims")
	_check(ShipCatalog.get_ship("missing_hull") == null, "No silent production fallback")
	print("Ships v3: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(label)
