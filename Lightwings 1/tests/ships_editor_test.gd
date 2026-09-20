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
	editor.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://workshop_v2_test/portable.json")
	print("Ship editor v2: ", failures, " failures")
	quit(1 if failures else 0)
func _check(condition: bool, label: String) -> void:
	if not condition: failures += 1; push_error(label)






