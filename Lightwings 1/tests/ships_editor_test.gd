extends SceneTree
## S5: the editor on the grammar. Headless; instantiates the real scene like the v0.3 test did.
var editor: Control
var failures: int = 0

func _initialize() -> void:
	editor = load("res://scenes/ship_editor.tscn").instantiate()
	root.add_child.call_deferred(editor)
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if not condition: failures += 1; push_error(label)

func _tab_of(script_class: Script) -> EditorTab:
	for tab: EditorTab in editor.tabs:
		if tab.get_script() == script_class: return tab
	return null

func _has(errors: PackedStringArray, code: String) -> bool:
	for e: String in errors:
		if e.begins_with(code): return true
	return false

func _use(ship: ShipDefinition) -> void:
	editor.working = ship
	editor.select_core()
	editor._refresh()

func _enemy_hull(order: int = 4, slot_type: String = "node") -> ShipDefinition:
	var ship: ShipDefinition = ShipDefinition.new()
	ship.schema_version = 4
	ship.id = "test_enemy"
	ship.display_name = "Test Enemy"
	ship.faction = "enemy"
	ship.archetype = "sentry"
	ship.chassis_color = "yellow"
	ship.accent_color = "red"
	ship.core_depth = 2
	ship.core_weapon = "coil_pair" # yellow-only, legal on this yellow/red pair; sentries need one
	var rail: RailDefinition = RailDefinition.new()
	rail.radius = ShipGrammar.RAIL_RADII[0]
	rail.order = order
	rail.speed = -0.95
	var slots: Array[SlotDefinition] = []
	for i: int in range(order):
		var slot: SlotDefinition = SlotDefinition.new()
		slot.type = slot_type
		slot.node_radius = 7
		slots.append(slot)
	rail.slots = slots
	ship.rails = [rail]
	return ship

func _run() -> void:
	await process_frame

	# --- edit() is the only mutation path; one edit == one undo step -------------------------
	_use(_enemy_hull())
	editor.edit("rename a", func(s: ShipDefinition) -> void: s.display_name = "A")
	editor.edit("rename b", func(s: ShipDefinition) -> void: s.display_name = "B")
	_check(editor.working.display_name == "B", "Two edits land in order")
	editor.undo.undo()
	_check(editor.working.display_name == "A", "One undo reverts exactly the last edit")
	editor.undo.undo()
	_check(editor.working.display_name == "Test Enemy", "A second undo reverts the first edit: two edits needed two undos")
	editor.undo.redo()
	editor.undo.redo()
	_check(editor.working.display_name == "B", "CONTROL: redoing both edits returns to the same state a single big edit could not distinguish from")

	# --- Adding a rail picks the next ladder radius and the opposite sign --------------------
	var rails_tab: TabRails = _tab_of(TabRails)
	_use(_enemy_hull())
	var before_speed: float = editor.working.rails[0].speed
	rails_tab._add_rail()
	_check(editor.working.rails.size() == 2, "Add rail appends a rail")
	_check(editor.working.rails[1].radius == ShipGrammar.RAIL_RADII[1], "New rail sits at the next ladder radius")
	_check(editor.working.rails[1].speed * before_speed < 0.0, "New rail's default speed opposes the rail before it")
	editor.select_rail(1)
	rails_tab.refresh(editor.working, editor.compiled, editor.selection)
	_check(rails_tab.sign_warning.text == "", "No sign warning while rails alternate")
	editor.edit("force same sign", func(s: ShipDefinition) -> void: s.rails[1].speed = s.rails[0].speed)
	rails_tab.refresh(editor.working, editor.compiled, editor.selection)
	_check(rails_tab.sign_warning.text != "", "CONTROL: forcing the same sign raises the tab's own warning")
	_check(_has(ShipGrammar.validate(editor.working), "RAIL-SIGN"), "CONTROL: forcing the same sign also raises the validator's RAIL-SIGN")

	# --- Changing a rail's order re-tiles slots to exactly that many -------------------------
	_use(_enemy_hull(4))
	editor.select_rail(0)
	rails_tab.refresh(editor.working, editor.compiled, editor.selection)
	rails_tab._retile_order(7)
	_check(editor.working.rails[0].slots.size() == 7 and editor.working.rails[0].order == 7, "Order change re-tiles the slot array to exactly the new order")
	rails_tab._retile_order(3)
	_check(editor.working.rails[0].slots.size() == 3, "Shrinking the order re-tiles down as well")

	# --- "Apply to symmetric orbit" keeps an enemy rail rotationally symmetric ----------------
	var slots_tab: TabSlots = _tab_of(TabSlots)
	_use(_enemy_hull(4, "node"))
	editor.select_slot(0, 1)
	slots_tab.symmetric_box.button_pressed = true
	slots_tab._apply(func(slot: SlotDefinition) -> void: slot.node_radius = 4)
	_check(not _has(ShipGrammar.validate(editor.working), "SYM-ROT"), "With the box on, editing one slot keeps the rail uniform, so it stays rotationally symmetric")
	_use(_enemy_hull(4, "node"))
	editor.select_slot(0, 1)
	slots_tab.symmetric_box.button_pressed = false
	slots_tab._apply(func(slot: SlotDefinition) -> void: slot.node_radius = 4)
	_check(_has(ShipGrammar.validate(editor.working), "SYM-ROT"), "CONTROL: with the box off, one edit breaks rotational symmetry (SYM-ROT)")

	# --- A colour change is never blocked; it flags mounted-but-illegal pieces and Unmount clears them
	var enemy_with_piece: ShipDefinition = _enemy_hull(4, "node")
	enemy_with_piece.core_weapon = "" # isolate the illegal-mount count to the one piece under test
	enemy_with_piece.rails[0].slots[0].type = "hub"
	enemy_with_piece.rails[0].slots[0].pods = 1
	enemy_with_piece.rails[0].slots[0].set_piece = "v_rack" # needs yellow + red, currently legal
	_use(enemy_with_piece)
	_check(ShipGrammar.illegal_mounts(editor.working).is_empty(), "v_rack starts legal on a yellow/red hull")
	editor.edit("recolour", func(s: ShipDefinition) -> void: s.chassis_color = "green")
	_check(editor.working.chassis_color == "green", "CONTROL: a colour change is never refused")
	var illegal: Array[Dictionary] = ShipGrammar.illegal_mounts(editor.working)
	_check(illegal.size() == 1 and str(illegal[0].piece) == "v_rack", "The now-illegal mount is flagged by name")
	_check(_has(ShipGrammar.validate(editor.working), "COLOUR-GATE"), "The save is blocked on COLOUR-GATE")
	editor.edit("unmount all", func(s: ShipDefinition) -> void:
		for mount: Dictionary in ShipGrammar.illegal_mounts(s): TabColours._unmount_at(s, str(mount.where)))
	_check(ShipGrammar.illegal_mounts(editor.working).is_empty(), "Unmount all clears the flagged mounts")

	# --- The Slots palette offers exactly legal_for INTERSECT implemented --------------------
	_use(_enemy_hull(4, "node"))
	editor.working.rails[0].slots[0].type = "hub"
	editor.working.rails[0].slots[0].pods = 1
	editor.select_slot(0, 0)
	slots_tab.refresh(editor.working, editor.compiled, editor.selection)
	var offered: Dictionary = {}
	for i: int in range(slots_tab.set_piece_field.item_count): offered[slots_tab.set_piece_field.get_item_text(i)] = true
	var expected: Array[String] = []
	for id: String in SetPieceCatalog.legal_for(editor.working.chassis_color, editor.working.accent_color):
		if SetPieceCatalog.is_implemented(id): expected.append(id)
	var matches: bool = true
	for id: String in expected:
		if not offered.has(id): matches = false
	_check(matches, "Every colour-legal, implemented piece is offered")
	# ...and nothing else. "Every legal piece is offered" alone would pass a palette that offered all 33.
	var strangers: Array[String] = []
	for text: String in offered:
		if SetPieceCatalog.has(text) and not expected.has(text): strangers.append(text)
	_check(strangers.is_empty(), "The palette offers EXACTLY the legal, implemented pieces (also offered: %s)" % str(strangers))
	var unimplemented: String = ""
	for id: String in SetPieceCatalog.legal_for(editor.working.chassis_color, editor.working.accent_color):
		if not SetPieceCatalog.is_implemented(id): unimplemented = id
	if unimplemented != "": _check(not offered.has(unimplemented), "CONTROL: a colour-legal piece with no implemented weapon is absent from the palette")

	# --- Save refuses an invalid ship, and writes no parts for a valid one --------------------
	var scratch_root: String = "user://ships_editor_v5_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_root))
	var old_root: String = ShipCatalog.catalog_root
	ShipCatalog.catalog_root = scratch_root
	var invalid_ship: ShipDefinition = _enemy_hull(4, "stub") # every slot unoccupied: RAIL-EMPTY
	_use(invalid_ship)
	var invalid_path: String = scratch_root.path_join(invalid_ship.id + ".tres")
	editor._save_to(invalid_path)
	_check(not FileAccess.file_exists(invalid_path), "Save refuses an invalid ship (no file written)")
	_check("Save blocked" in editor.status.text, "Status line reports the block")
	var valid_ship: ShipDefinition = _enemy_hull(4, "node")
	valid_ship.id = "test_valid_hull"
	_use(valid_ship)
	_check(ShipGrammar.validate(editor.working).is_empty(), "The valid fixture actually validates clean")
	var valid_path: String = scratch_root.path_join(valid_ship.id + ".tres")
	editor._save_to(valid_path)
	_check(FileAccess.file_exists(valid_path), "A valid ship is written")
	var reloaded: ShipDefinition = ResourceLoader.load(valid_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(reloaded != null and reloaded.parts.is_empty(), "A saved rail hull stores no compiled parts (positions are derived, never authored)")
	ShipCatalog.catalog_root = old_root

	# --- JSON round trip is byte-identical for every fixture ---------------------------------
	var fixture_paths: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open("res://tests/fixtures/ships_v4")
	if dir != null:
		for file: String in dir.get_files():
			if file.ends_with(".json"): fixture_paths.append("res://tests/fixtures/ships_v4/".path_join(file))
	_check(fixture_paths.size() == 5, "Found all five §10 fixtures (found %d)" % fixture_paths.size())
	for path: String in fixture_paths:
		var text: String = FileAccess.get_file_as_string(path)
		var imported: Dictionary = ShipAuthoring.from_json(text)
		_check(imported.has("ship"), "%s parses as a schema-4 ship: %s" % [path, str(imported.get("errors", []))])
		if not imported.has("ship"): continue
		var exported_once: String = ShipAuthoring.to_json(imported.ship)
		var reimported: Dictionary = ShipAuthoring.from_json(exported_once)
		var exported_twice: String = ShipAuthoring.to_json(reimported.ship)
		_check(exported_once == exported_twice, "%s: export -> import -> export is byte-identical" % path)
		# Negative control: nudging a phase must change the bytes.
		if not imported.ship.rails.is_empty():
			var nudged: ShipDefinition = imported.ship.duplicate(true)
			nudged.rails[0].phase += 0.001
			var nudged_json: String = ShipAuthoring.to_json(nudged)
			_check(nudged_json != exported_once, "CONTROL: a nudged phase changes the exported bytes (%s)" % path)

	# --- Polar picking: a known click lands on the right slot ---------------------------------
	var pick_ship: ShipDefinition = _enemy_hull(4, "node")
	pick_ship.rails[0].phase = 0.9146
	var step: float = TAU / 4.0
	var slot0_point: Vector2 = Vector2(sin(pick_ship.rails[0].phase), -cos(pick_ship.rails[0].phase)) * float(pick_ship.rails[0].radius)
	var hit: Dictionary = ShipCanvas.pick(slot0_point, pick_ship)
	_check(str(hit.kind) == "slot" and int(hit.rail) == 0 and int(hit.slot) == 0, "A click on slot 0's rest position picks slot 0")
	var slot2_angle: float = pick_ship.rails[0].phase + 2.0 * step
	var slot2_point: Vector2 = Vector2(sin(slot2_angle), -cos(slot2_angle)) * float(pick_ship.rails[0].radius)
	var hit2: Dictionary = ShipCanvas.pick(slot2_point, pick_ship)
	_check(str(hit2.kind) == "slot" and int(hit2.slot) == 2, "A click on slot 2's rest position picks slot 2")
	var miss_point: Vector2 = Vector2(0, -74) # between the 52 and 96 rails, and outside the 34 px core
	var miss: Dictionary = ShipCanvas.pick(miss_point, pick_ship)
	_check(str(miss.kind) == "none", "CONTROL: a click 40 px off any rail and outside the core selects nothing")

	# --- A schema-3 .tres is refused --------------------------------------------------------
	var legacy_path: String = ShipCatalog.catalog_root.path_join("player_seed.tres")
	if ResourceLoader.exists(legacy_path):
		var before_id: String = editor.working.id
		editor._load_from(legacy_path)
		_check(editor.working.id == before_id, "CONTROL: a schema-3 hull does not replace the working ship")
		_check("retired by the ship design spec" in editor.status.text, "A schema-3 .tres is refused with the retirement message")
	else:
		_check(false, "player_seed.tres (schema-3 fixture) not found at " + legacy_path)

	# --- Package check: the editor never ships in an export --------------------------------
	var export_cfg: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	_check(export_cfg.contains("scripts/editor/*"), "export_presets.cfg excludes scripts/editor/*")

	editor.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ships_editor_v5_test/test_enemy.tres"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ships_editor_v5_test/test_valid_hull.tres"))
	print("Ship editor S5: ", failures, " failures")
	quit(1 if failures else 0)
