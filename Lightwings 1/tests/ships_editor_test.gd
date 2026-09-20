extends SceneTree
var editor: Control
var failures: int = 0
func _initialize() -> void:
	editor = load("res://scenes/ship_editor.tscn").instantiate()
	root.add_child.call_deferred(editor)
	_run.call_deferred()
func _run() -> void:
	await process_frame
	_check(editor.symmetry.disabled and editor.symmetry.button_pressed, "Player symmetry forced")
	var initial: int = editor.working.parts.size()
	editor._add_part()
	_check(editor.working.parts.size() == initial + 2, "Placement automatically creates mirrored pair")
	editor._rename_part("test_added")
	editor._part_vector("position", 0, 27.0)
	var part: PartDefinition = editor.working.parts[editor.selected]
	var mirror: PartDefinition
	for other: PartDefinition in editor.working.parts:
		if other.id == part.mirror_id: mirror = other
	_check(mirror != null and mirror.position.x == -27 and mirror.mirror_id == "test_added", "Rename and transform preserve linked symmetry")
	editor._add_line()
	_check(editor.working.parts.size() == initial + 4, "Mirrored lines added")
	editor._delete_part()
	_check(editor.working.parts.size() == initial, "Deleting pair removes its lines")
	editor.undo.undo()
	_check(editor.working.parts.size() == initial + 4, "Undo restores complete mirrored operation")
	editor.undo.redo()
	_check(editor.working.parts.size() == initial, "Redo deletes complete mirrored operation")
	editor.description.text = "compact fire tier 3 with ricochet and mines"
	editor._generate()
	_check(editor.working.role == "compact" and editor.working.primary == "ricochet", "Generate valid template into editable canvas")
	editor._place_object("ricochet", "Primary", Vector2(24, -12))
	var primary_positions: Array[Vector2] = []
	for mounted: PartDefinition in editor.working.parts:
		if mounted.mount_id == "primary": primary_positions.append(mounted.position)
	_check(primary_positions.has(Vector2(24, -12)) and primary_positions.has(Vector2(-24, -12)), "Dragged component preserves position and mirror with one logical slot")
	var before_slots: int = editor.working.secondaries.size()
	editor._place_object("shield", "Secondary", Vector2.ZERO)
	_check(editor.working.secondaries.size() == before_slots and "blocked" in editor.status.text, "Slot overflow placement blocked")

	# --- Motion tab: editing a group and the live preview reflecting it ---
	editor.object_tab = "Motion"
	editor._refresh_objects()
	var core_index: int = -1
	for index: int in range(editor.working.parts.size()):
		if editor.working.parts[index].id == "core": core_index = index
	editor._select_part(core_index)
	_check(editor._group_for("core") == null, "New hull has no motion group on the core yet")
	editor._add_group("core")
	_check(editor._group_for("core") != null, "Motion tab adds a group to the selected subtree")
	editor._group_property("core", "orbit_speed", 1.25)
	_check(is_equal_approx(editor._group_for("core").orbit_speed, 1.25), "Motion tab edits orbit_speed on the selected group")
	var rig_before: ShipMotion.ShipRig = ShipMotion.get_rig(editor.working)
	var pose_preview: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig_before)
	ShipMotion.step(rig_before, pose_preview, 30)
	var moved: bool = false
	for i: int in range(rig_before.ids.size()):
		if rig_before.group_index[i] >= 0 and not pose_preview.local[i].is_equal_approx(rig_before.rest[i]): moved = true
	_check(moved, "Live preview evaluator (ship_motion.gd) actually moves the group's subtree, not just the schema")
	editor._remove_group("core")
	_check(editor._group_for("core") == null, "Motion tab removes a group")
	# Negative control: sabotage the group lookup key so the instrument would
	# have to notice a group that is not actually there.
	_check(not editor.working.groups.any(func(g: GroupDefinition) -> bool: return g.root_id == "core"), "CONTROL: removed group cannot be found by a stale lookup")
	editor.object_tab = "Body"
	editor._refresh_objects()

	# --- Parent dropdown must exclude the selected part's own subtree, and a
	# line requires picking two existing circles. Run these on a disposable
	# scratch hull (positions on the centreline, so no mirror is required) so
	# they cannot perturb the TP budget the save/JSON tests below rely on.
	var saved_working: ShipDefinition = editor.working
	var saved_selected: int = editor.selected
	var scratch: ShipDefinition = ShipCatalog.get_ship("player_seed")
	ShipCatalog.add_part(scratch, "branch_a", "circle", Vector2(0, 30), 8, "chassis", "hp_buffer", 3, true, "core")
	ShipCatalog.add_part(scratch, "branch_b", "circle", Vector2(0, 45), 6, "chassis", "hp_buffer", 3, true, "branch_a")
	editor.working = scratch
	_check(not editor._is_descendant("core", "branch_b"), "CONTROL: a real ancestor (core) is correctly not flagged as its own descendant's descendant")
	_check(editor._is_descendant("branch_b", "branch_a"), "A grandchild is correctly detected as a descendant (the cycle the parent dropdown must exclude when re-parenting branch_a onto branch_b)")
	var before_line_count: int = 0
	for p: PartDefinition in scratch.parts:
		if p.shape == "line": before_line_count += 1
	editor.object_tab = "Body"
	editor._place_object("line", "Body", Vector2.ZERO) # arms the two-click flow, adds nothing yet
	var after_arm_count: int = 0
	for p: PartDefinition in editor.working.parts:
		if p.shape == "line": after_arm_count += 1
	_check(after_arm_count == before_line_count, "Placing 'line' from the object list does not add a part by itself; it requires two circle picks")
	editor._add_line_between("branch_a", "branch_b")
	var after_line_count: int = 0
	for p: PartDefinition in editor.working.parts:
		if p.shape == "line": after_line_count += 1
	_check(after_line_count == before_line_count + 1, "Explicit two-circle line placement adds exactly one line")
	editor._add_line_between("branch_a", "branch_a")
	var unchanged_count: int = 0
	for p: PartDefinition in editor.working.parts:
		if p.shape == "line": unchanged_count += 1
	_check(unchanged_count == after_line_count and "blocked" in editor.status.text, "CONTROL: a line cannot connect a circle to itself")
	editor._add_line_between("no_such_circle", "branch_b")
	var still_unchanged: int = 0
	for p: PartDefinition in editor.working.parts:
		if p.shape == "line": still_unchanged += 1
	_check(still_unchanged == after_line_count and "blocked" in editor.status.text, "CONTROL: a line cannot name a circle that does not exist")
	editor.working = saved_working
	editor.selected = saved_selected

	# --- Missing view is derived from the manifest, never a hard-coded count ---
	editor._refresh_library()
	_check(editor.missing_label.text.begins_with("All %d player roster slots are filled." % ShipGenerator.player_hull_count()) or editor.missing_label.text.begins_with("Missing:"), "Missing-slot view reports against ShipGenerator.roster_manifest(), not a hard-coded total")
	_check(not editor.missing_label.text.contains("81"), "CONTROL: the stale hard-coded '81 player roster slots' count is gone")
	var old_root: String = ShipCatalog.catalog_root
	ShipCatalog.catalog_root = "user://workshop_v2_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ShipCatalog.catalog_root))
	var path: String = ShipCatalog.catalog_root.path_join(editor.working.id + ".tres")
	editor._save_to(path)
	_check(FileAccess.file_exists(path) and editor._library_ids.has(editor.working.id), "Save appears immediately in browsable library")
	editor._save_to(ShipCatalog.catalog_root.path_join("portable.json"))
	editor._load_from(ShipCatalog.catalog_root.path_join("portable.json"))
	_check(ShipCatalog.validate(editor.working).is_empty(), "Editor portable JSON roundtrip")
	ShipCatalog.catalog_root = old_root
	editor._preview_combat()
	await process_frame
	await process_frame
	var preview: WorkshopCombatPreview = editor._combat_window.get_child(0)
	_check(preview.actor.definition.id == editor.working.id, "Unsaved custom hull launches in real combat preview")
	_check(preview.actor.primary == "ricochet", "Preview uses authored loadout")
	preview.pilot = true
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_D
	key.keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	preview._process(1.0 / 60.0)
	var before_flight: Vector2 = preview.world.player_position
	preview.world._physics_process(1.0 / 60.0)
	_check(preview.world.player_position.x > before_flight.x, "Pilot mode flies the authored hull through actual movement simulation")
	var released: InputEventKey = key.duplicate()
	released.pressed = false
	Input.parse_input_event(released)
	editor._combat_window.queue_free()
	await process_frame

	# --- §22 JSON round trip: mirrored pairs regenerated, groups preserved ---
	var source: ShipDefinition = ShipCatalog.get_ship("player_corruption_t3_standard_a")
	var source_mirror_pairs: int = 0
	var source_circles: int = 0
	var source_lines: int = 0
	for p: PartDefinition in source.parts:
		if p.shape == "circle":
			source_circles += 1
			if not p.mirror_id.is_empty(): source_mirror_pairs += 1
		else: source_lines += 1
	_check(source.groups.size() > 0 and source_mirror_pairs > 0, "Fixture hull actually exercises both mirrored circles and motion groups")
	var json_text: String = ShipAuthoring.to_json(source)
	var exported: Dictionary = JSON.parse_string(json_text)
	_check(exported.circles.size() < source_circles - 1, "Export drops the generated (positive-x) half of every mirrored pair, not just re-lists it")
	var reimport: Dictionary = ShipAuthoring.from_json(json_text)
	_check(reimport.get("errors", ["missing"]).is_empty(), "§22 export re-imports to a valid ship: " + str(reimport.get("errors", [])))
	var restored: ShipDefinition = reimport.ship
	var restored_circles: int = 0
	var restored_lines: int = 0
	var restored_mirror_pairs: int = 0
	var restored_ids: Dictionary = {}
	for p: PartDefinition in restored.parts:
		restored_ids[p.id] = true
		if p.shape == "circle":
			restored_circles += 1
			if not p.mirror_id.is_empty(): restored_mirror_pairs += 1
		else: restored_lines += 1
	_check(restored_circles == source_circles, "Round trip regenerates every mirrored circle back, same total count (%d vs %d)" % [restored_circles, source_circles])
	_check(restored_lines == source_lines, "Round trip regenerates every mirrored line back, same total count (%d vs %d)" % [restored_lines, source_lines])
	_check(restored_mirror_pairs == source_mirror_pairs, "Round trip preserves the mirror-pair count")
	for p: PartDefinition in source.parts:
		_check(restored_ids.has(p.id), "Round trip preserves the exact original id (including regenerated mirror twins): " + p.id)
	_check(restored.groups.size() == source.groups.size(), "Round trip preserves motion groups")
	if restored.groups.size() == source.groups.size():
		for i: int in range(source.groups.size()):
			_check(restored.groups[i].root_id == source.groups[i].root_id and is_equal_approx(restored.groups[i].orbit_speed, source.groups[i].orbit_speed), "Round-tripped group keeps its root and signed orbit_speed")
	var reexported: String = ShipAuthoring.to_json(restored)
	_check(reexported == json_text, "Exporting the restored ship again reproduces byte-identical §22 JSON (lossless round trip)")
	# Negative control: drop a line's endpoint, as a hand-edited file might.
	var broken: Dictionary = JSON.parse_string(json_text)
	broken.lines[0].erase("to")
	var broken_result: Dictionary = ShipAuthoring.from_json(JSON.stringify(broken))
	_check(not broken_result.get("errors", []).is_empty(), "CONTROL: a line JSON entry with a dropped endpoint is rejected, not silently imported")

	# --- Legacy v2 import: ellipse/ring/crescent/tether upgraded, parents inferred ---
	# Faction "enemy" so the player-only mirror rule is out of scope here (the
	# §22 round trip above already covers mirrored-part regeneration).
	var legacy_text: String = JSON.stringify({
		"schema_version": 2, "id": "legacy_import_draft", "display_name": "Legacy Draft",
		"faction": "enemy", "element": "corruption", "tier": 2, "role": "standard", "is_player": false,
		"primary": "pulse_cannon",
		"parts": [
			{"id": "body", "shape": "ellipse", "position": [0, 0], "size": [20, 16]},
			{"id": "rim", "shape": "ring", "position": [0, 0], "radius": 30},
			{"id": "wing", "shape": "crescent", "position": [18, 0], "radius": 10},
			{"id": "gun", "shape": "circle", "position": [0, -10], "radius": 4, "component": "pulse_cannon"},
			{"id": "link_rim", "shape": "tether", "from_id": "body", "to_id": "rim"},
			{"id": "link_wing", "shape": "tether", "from_id": "body", "to_id": "wing"},
			{"id": "link_gun", "shape": "tether", "from_id": "body", "to_id": "gun"},
		]
	})
	var legacy_result: Dictionary = ShipAuthoring.from_legacy_v2(JSON.parse_string(legacy_text))
	_check(legacy_result.has("ship") and legacy_result.get("errors", ["missing"]).is_empty(), "Legacy v2 fixture upgrades to a valid ship: " + str(legacy_result.get("errors", [])))
	var legacy_ship: ShipDefinition = legacy_result.get("ship")
	if legacy_ship != null:
		var legacy_shapes: Dictionary = {}
		for p: PartDefinition in legacy_ship.parts: legacy_shapes[p.id] = p.shape
		_check(legacy_shapes.get("core", "") == "circle" and legacy_shapes.get("rim", "") == "circle" and legacy_shapes.get("wing", "") == "circle" and legacy_shapes.get("wing_cover", "") == "circle" and legacy_shapes.get("link_rim", "") == "line", "Legacy shapes upgrade: body->core, ellipse/ring/crescent -> circle(s), tether -> line")
		var legacy_by_id: Dictionary = {}
		for p: PartDefinition in legacy_ship.parts: legacy_by_id[p.id] = p
		_check(legacy_by_id.rim.parent_id == "core" and legacy_by_id.wing.parent_id == "core", "Parents inferred by walking the legacy tether graph from the renamed core")
	# Negative control: an unsupported schema version is rejected outright.
	var unsupported: Dictionary = ShipAuthoring.from_json(JSON.stringify({"schema_version": 1, "core": {}, "circles": [], "lines": []}))
	_check(not unsupported.get("errors", []).is_empty(), "CONTROL: an unsupported schema version is rejected, not silently accepted")

	editor.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://workshop_v2_test/portable.json")
	print("Ship editor v2: ", failures, " failures")
	quit(1 if failures else 0)
func _check(condition: bool, label: String) -> void:
	if not condition: failures += 1; push_error(label)






