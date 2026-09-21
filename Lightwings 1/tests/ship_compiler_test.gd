extends SceneTree
## ShipCompiler: grammar -> parts. Deterministic, positional ids, paint order, and a `budget()` that
## agrees with what is actually compiled. Every fixture must also pass the validator and its
## compiled-output guards with nothing to say.
const Harness = preload("res://tests/support/harness.gd")
const FIXTURES: Array[String] = ["radial_elite", "player_t3", "drone", "boss", "irregular"]

func _initialize() -> void: _run.call_deferred()

func _load(name: String) -> ShipDefinition:
	var errors: PackedStringArray = PackedStringArray()
	var ship: ShipDefinition = ShipGrammar.load_json("res://tests/fixtures/ships_v4/%s.json" % name, errors)
	if not errors.is_empty(): push_error("%s: %s" % [name, ", ".join(errors)])
	return ship

func _bytes(ship: ShipDefinition) -> PackedByteArray:
	var rows: Array = []
	for part: PartDefinition in ship.parts:
		rows.append([part.id, part.shape, part.position, part.radius, part.filled, part.parent_id, part.color_role, part.from_id, part.to_id, part.light_period, part.light_phase, part.spin_speed, part.bob_amp, part.bob_phase, part.pump_amp, part.pump_phase, part.aim_joint, part.solid, part.style, part.ability_id, part.mount_id, part.hp])
	return var_to_bytes(rows)

func _counts(ship: ShipDefinition) -> Dictionary:
	var circles: int = 0
	var lines: int = 0
	var solid: int = 0
	for part: PartDefinition in ship.parts:
		if part.shape == "line": lines += 1
		else:
			circles += 1
			if part.solid: solid += 1
	return {"circles": circles, "lines": lines, "solid": solid}

func _run() -> void:
	var h := Harness.new("SHIP COMPILER")
	for name: String in FIXTURES:
		var ship: ShipDefinition = _load(name)
		var errors: PackedStringArray = ShipCatalog.validate(ship)
		h.check(errors.is_empty(), "%s validates (%s)" % [name, ", ".join(errors)])
		h.check(ShipCatalog.warnings(ship).is_empty(), "%s has no warnings (%s)" % [name, ", ".join(ShipCatalog.warnings(ship))])
		h.check(ship.parts.is_empty(), "%s: validating did not compile the subject behind its back" % name)
		ShipCatalog.refresh(ship)
		var again: ShipDefinition = _load(name)
		ShipCatalog.refresh(again)
		h.check(_bytes(ship) == _bytes(again) and not ship.parts.is_empty(), "%s compiles to the same bytes twice" % name)
		var ids: Dictionary = {}
		for part: PartDefinition in ship.parts: ids[part.id] = true
		h.check(ids.size() == ship.parts.size(), "%s: every part id is unique" % name)
		var counts: Dictionary = _counts(ship)
		var budget: Dictionary = ShipCompiler.budget(ship)
		h.check(int(budget.circles) == int(counts.circles) and int(budget.lines) == int(counts.lines) and int(budget.solid) == int(counts.solid), "%s: budget() %s equals the compiled counts %s" % [name, str(budget), str(counts)])
		h.check(int(counts.circles) <= ShipGrammar.MAX_CIRCLES, "%s fits the shader: %d circles" % [name, counts.circles])
		var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
		h.check(rig.ids.size() == int(counts.circles) and not rig.legacy and rig.solid_indices.size() == int(counts.solid) - 1, "%s: the rig holds every circle and walks only the solid ones (%d of %d)" % [name, rig.solid_indices.size(), rig.ids.size()])
		# Paint order: no ring after a line, no line after a solid cluster circle except set-piece lines.
		var stage: int = 0
		var ordered: bool = true
		for part: PartDefinition in ship.parts:
			var rank: int = 2
			if part.style == 5: rank = 0
			elif part.shape == "line" and (part.id.ends_with("_spoke") or part.id.ends_with("_link")): rank = 1
			else: rank = 2
			if rank < stage: ordered = false
			stage = maxi(stage, rank)
		h.check(ordered, "%s: rings, then spokes and links, then everything else" % name)
	# The reference: 22 circles in the image. Ours adds what the image does not draw as circles.
	var elite: ShipDefinition = _load("radial_elite")
	ShipCatalog.refresh(elite)
	var visible: int = 0
	for part: PartDefinition in elite.parts:
		if part.shape == "circle" and part.style != 5 and not part.id.begins_with("core_w") and not (part.id.contains("w") and part.radius == 4.0): visible += 1
	h.check(visible == 21, "The radial elite compiles the reference's circles: core 2 + 4 nodes + 3 hubs + 9 pods + 3 red rings = 21, plus the dot (got %d)" % visible)
	h.check(is_equal_approx(elite.footprint, 2.0 * (96.0 + 30.0 + 7.0)), "Its footprint is the outer pods' reach (%.1f)" % elite.footprint)
	var hub: PartDefinition = null
	for part: PartDefinition in elite.parts:
		if part.id == "r2s0": hub = part
	h.check(hub != null and hub.ability_id == "rocket_launcher" and hub.mount_id == "r2s0" and is_equal_approx(hub.hp, 60.0) and is_equal_approx(hub.spin_speed, 0.42), "The hub IS the mount: ability, mount id, hp and the rail's spin live on it")
	h.check(elite.primary == "bolt" and elite.abilities.has("rocket_launcher"), "The loadout is read back from what is mounted (%s / %s)" % [elite.primary, str(elite.abilities)])
	# Saving strips the derived parts.
	var path: String = "user://compiler_test_%d.tres" % Time.get_ticks_usec()
	h.check(ShipCatalog.save_ship(elite, path) == OK, "A rail hull saves")
	var stored: ShipDefinition = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	h.check(stored != null and stored.parts.is_empty() and stored.rails.size() == 2 and not elite.parts.is_empty(), "The file holds the grammar and no parts; the live ship keeps its own")
	ResourceSaver.save(elite, path)
	var raw: ShipDefinition = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	h.control("saved with ResourceSaver directly, bypassing save_ship", not raw.parts.is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# Controls for the lines above.
	var moved: ShipDefinition = _load("radial_elite")
	moved.rails[1].phase += 0.01
	ShipCatalog.refresh(moved)
	h.control("a rail phase nudged by 0.01 rad", _bytes(moved) != _bytes(elite))
	var fat: ShipDefinition = _load("boss")
	for rail: RailDefinition in fat.rails:
		for slot: SlotDefinition in rail.slots:
			if slot.type == "hub":
				slot.pods = 4
				slot.set_piece = "burst_ring"
	h.control("a boss with four pods and a five-circle piece on every hub (%d circles)" % int(ShipCompiler.budget(fat).circles), not ShipCatalog.validate(fat).is_empty())
	h.finish(self)
