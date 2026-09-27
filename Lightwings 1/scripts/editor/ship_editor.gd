extends Control
## Ship design spec editor (S5): edits schema-4 rail hulls only. `working` holds the grammar; every
## change goes through the ONE mutation choke point, `edit()`, which duplicates `working`, mutates
## the copy, commits an undo step, and refreshes `compiled` (a `ShipCatalog.refresh`d duplicate) for
## the canvas and previews to draw. A schema-3 `.tres` is refused on load.

var working: ShipDefinition
var compiled: ShipDefinition
var undo: UndoRedo = UndoRedo.new()
var selection: Dictionary = {"rail": -1, "slot": -1}
var current_path: String = ""
var dirty: bool = false
var _updating: bool = false
var _exit_after_save: bool = false

var canvas: ShipCanvas
var base_preview: EditorShipPreview
var min_preview: EditorShipPreview
var status: Label
var header: Label
var mirror_label: Label
var elite_label: Label
var title_label: Label
var stats_toggle: CheckButton
var description: LineEdit
var save_dialog: FileDialog
var load_dialog: FileDialog
var tabs: Array[EditorTab] = []
var tab_container: TabContainer
var _combat_window: Window

func _ready() -> void:
	theme = UiKit.make_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	working = _seeded_ship()
	if working == null:
		var seed_errors: PackedStringArray = PackedStringArray()
		working = ShipGrammar.load_json("res://tests/fixtures/ships_v4/player_t3.json", seed_errors)
		if working == null or not seed_errors.is_empty(): working = _blank_ship()
	_refresh()
	dirty = false

## S6: the gallery hands off either a file path ("open in editor") or a coverage cell's suggested
## element/tier/family ("open the editor here"). Neither overrides the ordinary fixture default.
func _seeded_ship() -> ShipDefinition:
	var path: String = GalleryEditorSeed.take_path()
	if path != "":
		var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource is ShipDefinition and resource.is_rail_hull(): return resource.duplicate(true)
	var seed: Dictionary = GalleryEditorSeed.take_seed()
	if seed.is_empty(): return null
	var ship: ShipDefinition = _blank_ship()
	if seed.has("tier"): ship.tier = int(seed.tier)
	if str(seed.get("faction", "")) != "player":
		ship.faction = str(seed.get("faction", "enemy"))
		ship.archetype = str(seed.get("kind", ship.archetype))
	return ship

func _blank_ship() -> ShipDefinition:
	var ship: ShipDefinition = ShipDefinition.new()
	ship.schema_version = 4
	ship.id = "new_hull"
	ship.display_name = "New Hull"
	ship.faction = "player"
	ship.chassis_color = Elements.PLAYER_COLOR_KEY
	ship.core_depth = 2
	var rail: RailDefinition = RailDefinition.new()
	rail.radius = ShipGrammar.RAIL_RADII[0]
	rail.order = 3
	rail.speed = 0.0
	var slots: Array[SlotDefinition] = []
	for i: int in range(3):
		var slot: SlotDefinition = SlotDefinition.new()
		slot.type = "hub"
		slot.pods = 1
		if i == 0: slot.mount = "primary"
		slots.append(slot)
	rail.slots = slots
	ship.rails = [rail]
	return ship

# ------------------------------------------------------------- UI

func _label(parent: Node, text: String, font_size: int = 14) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _build_ui() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = VisualStyle.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var layout: VBoxContainer = VBoxContainer.new()
	margin.add_child(layout)
	var toolbar: HBoxContainer = HBoxContainer.new()
	layout.add_child(toolbar)
	title_label = _label(toolbar, "SHIP WORKSHOP", 20)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(toolbar, "Load Ship…", func() -> void: load_dialog.popup_centered_ratio(0.7))
	_button(toolbar, "Save", _save)
	_button(toolbar, "Save and Exit", func() -> void: _exit_after_save = true; _save())
	_button(toolbar, "Exit", _request_exit)
	_button(toolbar, "Gallery", func() -> void: get_tree().change_scene_to_file("res://scenes/gallery.tscn"))
	stats_toggle = CheckButton.new()
	stats_toggle.text = "Stats"
	stats_toggle.button_pressed = true
	toolbar.add_child(stats_toggle)
	var columns: HSplitContainer = HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	header = _label(left, "", 16)
	mirror_label = _label(left, "", 13)
	stats_toggle.toggled.connect(func(value: bool) -> void: header.visible = value; mirror_label.visible = value)
	canvas = ShipCanvas.new()
	canvas.custom_minimum_size = Vector2(450, 300)
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(canvas)
	canvas.core_selected.connect(func() -> void: select_core())
	canvas.rail_selected.connect(func(rail: int) -> void: select_rail(rail))
	canvas.slot_selected.connect(func(rail: int, slot: int) -> void: select_slot(rail, slot))
	var actions: HBoxContainer = HBoxContainer.new()
	left.add_child(actions)
	_button(actions, "Undo", func() -> void: if undo.has_undo(): undo.undo())
	_button(actions, "Redo", func() -> void: if undo.has_redo(): undo.redo())
	_button(actions, "Bullet preview", _preview_combat)
	elite_label = _label(left, "", 12)
	elite_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var previews: HBoxContainer = HBoxContainer.new()
	left.add_child(previews)
	base_preview = _preview_column(previews, "BASE ZOOM · 1.00", 1.0)
	min_preview = _preview_column(previews, "MINIMUM ZOOM · 0.6561", 0.6561)
	var right: VBoxContainer = VBoxContainer.new()
	right.custom_minimum_size.x = 360
	columns.add_child(right)
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(tab_container)
	_add_tab("Core", TabCore.new(self))
	_add_tab("Rails", TabRails.new(self))
	_add_tab("Slots", TabSlots.new(self))
	_add_tab("Colours", TabColours.new(self))
	_add_tab("Motion", TabMotion.new(self))
	_add_tab("Set Pieces", TabSetPieces.new(self))
	var generator: HBoxContainer = HBoxContainer.new()
	layout.add_child(generator)
	description = LineEdit.new()
	description.placeholder_text = "Describe a hull (generation lands in a later phase)"
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	generator.add_child(description)
	_button(generator, "Generate", _generate)
	status = _label(layout, "", 13)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_dialog = FileDialog.new()
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.filters = PackedStringArray(["*.tres ; Ship resource", "*.json ; Portable ship JSON"])
	save_dialog.current_dir = ProjectSettings.globalize_path(ShipCatalog.catalog_root)
	save_dialog.file_selected.connect(_save_to)
	add_child(save_dialog)
	load_dialog = FileDialog.new()
	load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	load_dialog.filters = save_dialog.filters
	load_dialog.current_dir = save_dialog.current_dir
	load_dialog.file_selected.connect(_load_from)
	add_child(load_dialog)

func _add_tab(caption: String, tab: EditorTab) -> void:
	var panel: ScrollContainer = ScrollContainer.new()
	panel.name = caption
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_container.add_child(panel)
	var body: VBoxContainer = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(body)
	tab.build(body)
	tabs.append(tab)

func _preview_column(parent: Node, caption: String, scale_value: float) -> EditorShipPreview:
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	_label(column, caption, 12)
	var preview: EditorShipPreview = EditorShipPreview.new()
	preview.custom_minimum_size = Vector2(150, 110)
	column.add_child(preview)
	preview.set_zoom(scale_value)
	return preview

# ------------------------------------------------------------- the one mutation choke point

## Duplicates `working`, mutates the copy, commits ONE undo step, and refreshes. Every tab and every
## selection-independent action routes through this; nothing else is allowed to touch `working`.
func edit(label: String, mutate: Callable) -> void:
	var after: ShipDefinition = working.duplicate(true)
	mutate.call(after)
	undo.create_action(label)
	undo.add_do_method(_apply.bind(after))
	undo.add_undo_method(_apply.bind(working))
	undo.commit_action()

func _apply(ship: ShipDefinition) -> void:
	working = ship.duplicate(true)
	dirty = true
	_refresh()

func select_rail(rail: int) -> void:
	selection = {"rail": rail, "slot": -1}
	canvas.select_rail(rail)
	_refresh_tabs()

func select_slot(rail: int, slot: int) -> void:
	selection = {"rail": rail, "slot": slot}
	canvas.select_slot(rail, slot)
	_refresh_tabs()

func select_core() -> void:
	selection = {"rail": -1, "slot": -1}
	canvas.select_core()
	_refresh_tabs()

# ------------------------------------------------------------- refresh

func _refresh() -> void:
	_updating = true
	compiled = working.duplicate(true)
	ShipCatalog.refresh(compiled)
	canvas.set_ship(working, compiled)
	base_preview.set_ship(compiled)
	min_preview.set_ship(compiled)
	var budget: Dictionary = ShipCompiler.budget(working)
	header.text = "Tier %d     Circles %d/%d     Set pieces %d" % [working.tier, int(budget.circles), ShipGrammar.MAX_CIRCLES, int(budget.set_pieces)]
	mirror_label.text = "Symmetry: " + _symmetry_label()
	_refresh_elite_preview()
	_refresh_tabs()
	var errors: PackedStringArray = ShipGrammar.validate(working)
	status.text = "Ready · " + working.display_name if errors.is_empty() else "Save blocked: " + " | ".join(errors)
	var warnings: PackedStringArray = ShipGrammar.warnings(working)
	if not warnings.is_empty(): status.text += " · Warning: " + " | ".join(warnings)
	status.modulate = Color("96d8b2") if errors.is_empty() else Color("ffb99f")
	title_label.text = "SHIP WORKSHOP" + (" •" if dirty else "")
	_updating = false

func _symmetry_label() -> String:
	if working.faction == "player": return "Mirror"
	if ShipGrammar.is_irregular(working): return "Irregular"
	return "Rotational"

func _refresh_elite_preview() -> void:
	elite_label.text = ""
	var rail_index: int = int(selection.get("rail", -1))
	var slot_index: int = int(selection.get("slot", -1))
	if rail_index < 0 or slot_index < 0 or rail_index >= working.rails.size(): return
	var rail: RailDefinition = working.rails[rail_index]
	if slot_index >= rail.slots.size() or rail.slots[slot_index].type != "hub": return
	var hub_id: String = "r%ds%d" % [rail_index + 1, slot_index]
	var rig: ShipMotion.ShipRig = ShipMotion.get_rig(compiled)
	var root: int = rig.index_of(hub_id)
	if root < 0: return
	var span: int = rig.subtree_size[root]
	var last: int = root + span
	var lines: int = 0
	for k: int in range(rig.line_from.size()):
		if rig.line_from[k] >= root and rig.line_from[k] < last and rig.line_to[k] >= root and rig.line_to[k] < last: lines += 1
	elite_label.text = "HP %.0f · subtree = %d circles, %d lines · rail %d goes when the last of its clusters dies" % [rail.slots[slot_index].hp, span, lines, rail_index + 1]

func _refresh_tabs() -> void:
	for tab: EditorTab in tabs: tab.refresh(working, compiled, selection)

# ------------------------------------------------------------- save / load

func _save() -> void:
	if current_path.is_empty(): _save_as()
	else: _save_to(current_path)
func _save_as() -> void:
	save_dialog.current_file = working.id + ".tres"
	save_dialog.popup_centered_ratio(0.7)
func _save_to(path: String) -> void:
	if path.ends_with(".tres") and path.get_file().get_basename() != working.id:
		status.text = "Save blocked: resource filename must match hull ID: " + working.id + ".tres"
		return
	var errors: PackedStringArray = ShipGrammar.validate(working)
	if not errors.is_empty(): status.text = "Save blocked: " + " | ".join(errors); _exit_after_save = false; return
	var result: Error = OK
	if path.ends_with(".json"):
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null: result = FileAccess.get_open_error()
		else: file.store_string(ShipAuthoring.to_json(working))
	else: result = ShipCatalog.save_ship(working, path)
	if result != OK: status.text = "Save failed: " + error_string(result); return
	current_path = path
	dirty = false
	_refresh()
	status.text = "Saved " + path
	if _exit_after_save: get_tree().change_scene_to_file("res://scenes/main.tscn")

func _load_from(path: String) -> void:
	var result: Dictionary
	if path.ends_with(".json"): result = ShipAuthoring.from_json(FileAccess.get_file_as_string(path))
	else:
		var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource is ShipDefinition and not resource.is_rail_hull(): result = {"errors": PackedStringArray(["retired by the ship design spec"])}
		elif resource is ShipDefinition: result = {"ship": resource, "errors": ShipGrammar.validate(resource)}
		else: result = {"errors": PackedStringArray(["Not a ship definition."])}
	if not result.has("ship"): status.text = "Load blocked: " + " | ".join(result.get("errors", [])); return
	current_path = path
	select_core()
	edit("Load ship", func(s: ShipDefinition) -> void:
		var loaded: ShipDefinition = result.ship
		for property: String in ["id", "display_name", "description", "faction", "archetype", "tier", "role", "family", "chassis_color", "accent_color", "core_depth", "core_weapon", "rails", "chain_links", "chain_mode", "passives"]:
			s.set(property, loaded.get(property)))
	dirty = false
	if not result.get("errors", []).is_empty(): status.text = "Loaded with warnings: " + " | ".join(result.errors)

## Spec §13.1: the description resolves into the recipe's template and the recipe builds the ship.
## Pressing Generate again on the same text draws the next seed, so a designer can roll.
var _generate_seed: int = 0
func _generate() -> void:
	_generate_seed += 1
	var result: Dictionary = ShipAuthoring.from_description(description.text, _generate_seed)
	var generated: ShipDefinition = result.ship
	select_core()
	edit("Generate from description", func(s: ShipDefinition) -> void:
		for property: String in ["id", "display_name", "description", "faction", "archetype", "tier", "role", "family", "element", "chassis_color", "accent_color", "core_depth", "core_weapon", "rails", "chain_links", "chain_mode", "passives"]:
			s.set(property, generated.get(property)))
	var notes: PackedStringArray = PackedStringArray(["seed %d" % _generate_seed])
	notes.append_array(result.warnings)
	notes.append_array(result.errors)
	status.text = "Generated: " + " | ".join(notes)

func _request_exit() -> void:
	if not dirty: get_tree().change_scene_to_file("res://scenes/main.tscn"); return
	var confirmation: ConfirmationDialog = ConfirmationDialog.new()
	confirmation.dialog_text = "Discard unsaved changes and exit the workshop?"
	confirmation.confirmed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main.tscn"))
	add_child(confirmation)
	confirmation.popup_centered()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.ctrl_pressed and event.keycode == KEY_S: _save()
	elif event.ctrl_pressed and event.keycode == KEY_Z:
		if event.shift_pressed:
			if undo.has_redo(): undo.redo()
		elif undo.has_undo(): undo.undo()

func _preview_combat() -> void:
	var errors: PackedStringArray = ShipGrammar.validate(working)
	if not errors.is_empty(): status.text = "Preview blocked: " + " | ".join(errors); return
	if is_instance_valid(_combat_window): _combat_window.queue_free()
	_combat_window = Window.new()
	_combat_window.title = "Live combat preview · mounted components against a dummy"
	_combat_window.size = Vector2i(960, 640)
	_combat_window.close_requested.connect(func() -> void: _combat_window.queue_free())
	add_child(_combat_window)
	var preview: WorkshopCombatPreview = WorkshopCombatPreview.new()
	preview.ship = compiled.duplicate(true)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_combat_window.add_child(preview)
	_combat_window.popup_centered()

func _exit_tree() -> void:
	undo.clear_history()
	undo.free()
