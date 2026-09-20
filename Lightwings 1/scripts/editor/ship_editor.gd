extends Control
## Every authoring operation uses snapshots and the same validator as imports.
var working: ShipDefinition
var selected: int = -1
var undo: UndoRedo = UndoRedo.new()
var current_path: String = ""
var dirty: bool = false
var part_list: ItemList
var inspector: VBoxContainer
var canvas: ShipCanvas
var base_preview: EditorShipPreview
var min_preview: EditorShipPreview
var status: Label
var title_label: Label
var save_dialog: FileDialog
var load_dialog: FileDialog
var _drag_snapshot: ShipDefinition
var _updating: bool = false
var _forms: Array[ShipDefinition] = []
var symmetry: CheckButton
var stats: Label
var header: Label
var budget_bars: Dictionary = {}
var object_list: ItemList
var object_card: ShipObjectCard
var object_tab: String = "Body"
var description: LineEdit
var library_window: Window
var library_items: ItemList
var library_filters: Dictionary = {}
var library_search: LineEdit
var library_sort: OptionButton
var library_missing: CheckButton
var missing_label: Label
var _library_ids: Array[String] = []
var target_library: OptionButton
var _exit_after_save: bool = false
var _delete_confirmation: ConfirmationDialog
var _delete_id: String = ""
var _combat_window: Window

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_build_library()
	working = ShipCatalog.get_ship("player_seed")
	_apply_definition(working)
	dirty = false
	_refresh()

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
	background.color = Color("0b0d13")
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
	symmetry = CheckButton.new()
	symmetry.text = "Symmetric Mode"
	toolbar.add_child(symmetry)
	_button(toolbar, "Load Ship…", _show_library)
	_button(toolbar, "Save", _save)
	_button(toolbar, "Save and Exit", func() -> void: _exit_after_save = true; _save())
	_button(toolbar, "Exit", _request_exit)
	var toggle: CheckButton = CheckButton.new()
	toggle.text = "Stats"
	toggle.button_pressed = true
	toggle.toggled.connect(func(value: bool) -> void: stats.visible = value)
	toolbar.add_child(toggle)
	var columns: HSplitContainer = HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	header = _label(left, "Tier 1 | Max Tier: 5 | Complexity | TP", 16)
	var bars: HBoxContainer = HBoxContainer.new()
	left.add_child(bars)
	for name: String in ["tier", "complexity", "tp"]:
		var bar: ProgressBar = ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 8
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bars.add_child(bar)
		budget_bars[name] = bar
	canvas = ShipCanvas.new()
	canvas.custom_minimum_size = Vector2(450, 260)
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(canvas)
	canvas.part_selected.connect(_select_part)
	canvas.drag_started.connect(func() -> void: _drag_snapshot = working.duplicate(true))
	canvas.part_dragged.connect(_drag_part)
	canvas.drag_finished.connect(_finish_drag)
	canvas.object_dropped.connect(_place_object)
	var actions: HBoxContainer = HBoxContainer.new()
	left.add_child(actions)
	_button(actions, "Undo Last", func() -> void: if undo.has_undo(): undo.undo())
	_button(actions, "Redo", func() -> void: if undo.has_redo(): undo.redo())
	_button(actions, "Delete part", _delete_part)
	_button(actions, "Bullet preview", _preview_combat)
	_button(actions, "Duplicate", _duplicate_ship)
	var previews: HBoxContainer = HBoxContainer.new()
	left.add_child(previews)
	base_preview = _preview_column(previews, "BASE ZOOM · 1.00", 1)
	min_preview = _preview_column(previews, "MINIMUM ZOOM · 0.66", 0.6561)
	var morph: HBoxContainer = HBoxContainer.new()
	left.add_child(morph)
	target_library = OptionButton.new()
	target_library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	morph.add_child(target_library)
	_button(morph, "Preview reshape", _preview_reshape)
	var right: VBoxContainer = VBoxContainer.new()
	right.custom_minimum_size.x = 330
	columns.add_child(right)
	stats = _label(right, "", 14)
	var tabs: HBoxContainer = HBoxContainer.new()
	right.add_child(tabs)
	for kind: String in ["Body", "Primary", "Secondary", "Passive"]:
		_button(tabs, kind, func() -> void: object_tab = kind; _refresh_objects())
	object_card = ShipObjectCard.new()
	object_card.text = "Click and drag object"
	object_card.custom_minimum_size.y = 54
	right.add_child(object_card)
	object_card.pressed.connect(func() -> void: _place_object(object_card.object_id, object_card.object_kind, Vector2(20, 0)))
	object_list = ItemList.new()
	object_list.custom_minimum_size.y = 110
	right.add_child(object_list)
	object_list.item_selected.connect(func(index: int) -> void:
		object_card.object_id = object_list.get_item_metadata(index)
		object_card.object_kind = object_tab
		object_card.text = object_card.object_id.replace("_", " ").capitalize() + "\nClick and drag object")
	part_list = ItemList.new()
	part_list.custom_minimum_size.y = 85
	right.add_child(part_list)
	part_list.item_selected.connect(_select_part)
	var inspector_scroll: ScrollContainer = ScrollContainer.new()
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(inspector_scroll)
	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(inspector)
	var generator: HBoxContainer = HBoxContainer.new()
	layout.add_child(generator)
	description = LineEdit.new()
	description.placeholder_text = "Describe: compact fire tier 3 with ricochet and mine layer"
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	generator.add_child(description)
	_button(generator, "Generate locally", _generate)
	_button(generator, "Import file…", func() -> void: load_dialog.popup_centered_ratio(0.7))
	status = _label(layout, "", 13)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_dialog = FileDialog.new()
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.filters = PackedStringArray(["*.tres ; Ship resource", "*.json ; Portable ship JSON"])
	save_dialog.current_dir = ProjectSettings.globalize_path("res://content/ships")
	save_dialog.file_selected.connect(_save_to)
	add_child(save_dialog)
	load_dialog = FileDialog.new()
	load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	load_dialog.filters = save_dialog.filters
	load_dialog.current_dir = save_dialog.current_dir
	load_dialog.file_selected.connect(_load_from)
	add_child(load_dialog)

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

func _apply_definition(ship: ShipDefinition) -> void:
	working = ship.duplicate(true)
	ShipCatalog.recalculate(working)
	selected = clampi(selected, -1, working.parts.size() - 1)
	dirty = true
	_refresh()

func _refresh() -> void:
	_updating = true
	ShipCatalog.recalculate(working)
	symmetry.set_pressed_no_signal(working.is_player or symmetry.button_pressed)
	symmetry.disabled = working.is_player
	part_list.clear()
	for part: PartDefinition in working.parts: part_list.add_item(part.id + " · " + part.shape)
	if selected >= 0: part_list.select(selected)
	canvas.set_ship(working)
	canvas.select(selected)
	base_preview.set_ship(working)
	min_preview.set_ship(working)
	var limits: Dictionary = GameTuning.slots(working.tier, working.role)
	header.text = "Tier %d / Max Tier: %d     Complexity %d / 128     TP: %.2f / %.2f" % [working.tier, GameTuning.MAX_TIER, working.parts.size(), working.tp_used, working.tp_max]
	budget_bars.tier.max_value = GameTuning.MAX_TIER
	budget_bars.tier.value = working.tier
	budget_bars.complexity.max_value = 128
	budget_bars.complexity.value = working.parts.size()
	budget_bars.tp.max_value = working.tp_max
	budget_bars.tp.value = working.tp_used
	stats.text = "Speed %.0f · Turn %.1f · HP buffer ×%.2f\nFootprint %.0f px · %s · Magnet %.0f px\nPrimary: %s\nSecondary %d/%d: %s\nPassive %d/%d: %s\nTP %.2f / %.2f" % [working.speed, working.turn_rate, working.hp_buffer, working.footprint, working.role.capitalize(), working.magnet_radius, working.primary, working.secondaries.size(), limits.secondary, ", ".join(working.secondaries), working.passives.size(), limits.passive, ", ".join(working.passives), working.tp_used, working.tp_max]
	_refresh_inspector()
	_refresh_objects()
	var errors: PackedStringArray = ShipCatalog.validate(working)
	var warnings: PackedStringArray = ShipCatalog.warnings(working)
	status.text = "Ready · " + working.display_name if errors.is_empty() else "Save blocked: " + " | ".join(errors)
	if not warnings.is_empty(): status.text += " · Warning: " + " | ".join(warnings)
	status.modulate = Color("96d8b2") if errors.is_empty() else Color("ffb99f")
	title_label.text = "SHIP WORKSHOP" + (" •" if dirty else "")
	_updating = false

func _refresh_objects() -> void:
	object_list.clear()
	var objects: Array[String] = []
	if object_tab == "Body": objects.assign(ShipCatalog.SHAPES); objects.append("concentric_rings"); objects.append("crescent")
	else:
		for id: String in AbilityCatalog.DEFINITIONS:
			if AbilityCatalog.get_definition(id).slot_kind == object_tab.to_lower() or (object_tab == "Secondary" and not working.is_player and AbilityCatalog.get_definition(id).slot_kind == "enemy"): objects.append(id)
	for id: String in objects:
		var cost: float = 0.25 if object_tab == "Body" else AbilityCatalog.get_definition(id).tp_cost
		var index: int = object_list.add_item("[%.2f TP] %s" % [cost, id.replace("_", " ").capitalize()])
		object_list.set_item_metadata(index, id)
		var locked: bool = working.tp_used + cost > working.tp_max
		if object_tab != "Body":
			var definition: AbilityDefinition = AbilityCatalog.get_definition(id)
			locked = locked or (working.is_player and definition.minimum_tier > working.tier) or not working.faction in definition.allowed_factions
		object_list.set_item_disabled(index, locked)
	if objects.size() > 0:
		object_card.object_id = objects[0]
		object_card.object_kind = object_tab
		object_card.text = objects[0].replace("_", " ").capitalize() + "\nClick and drag object"

func _select_part(index: int) -> void:
	selected = clampi(index, -1, working.parts.size() - 1)
	canvas.select(selected)
	_refresh_inspector()

func _refresh_inspector() -> void:
	for child: Node in inspector.get_children(): inspector.remove_child(child); child.queue_free()
	_text_field("Name", working.display_name, func(value: String) -> void: _ship_property("display_name", value))
	_text_field("ID", working.id, func(value: String) -> void: _ship_property("id", value))
	_option_field("Element", ["neutral"] + ShipCatalog.ELEMENTS, working.element, func(value: String) -> void: _ship_property("element", value))
	_number_field("Tier", working.tier, 1, GameTuning.MAX_TIER, 1, func(value: float) -> void: _ship_property("tier", int(value)))
	_option_field("Faction", ["player", "enemy", "elite", "rival"], working.faction, func(value: String) -> void: _ship_property("faction", value))
	_option_field("Role", ["compact", "standard", "heavy"], working.role, func(value: String) -> void: _ship_property("role", value))
	if selected < 0: return
	var part: PartDefinition = working.parts[selected]
	_text_field("Part ID", part.id, _rename_part)
	_option_field("Primitive", ShipCatalog.SHAPES, part.shape, func(value: String) -> void: _part_property("shape", value))
	if part.mount_id.is_empty(): _option_field("Body stat", ["turn_rate", "speed", "magnet_radius", "structure"] + ([] if working.is_player else ["bullet_eater", "void_pull", "projectile_orbit"]), part.stat_id, func(value: String) -> void: _part_property("stat_id", value))
	else: _label(inspector, "Component: " + part.ability_id)
	if part.mount_id.is_empty(): _number_field("Stat contribution", part.stat_value, 0, 500, 0.25, func(value: float) -> void: _part_property("stat_value", value))
	if part.shape != "line":
		_number_field("Position X", part.position.x, -400, 400, 0.5, func(value: float) -> void: _part_vector("position", 0, value))
		_number_field("Position Y", part.position.y, -400, 400, 0.5, func(value: float) -> void: _part_vector("position", 1, value))
		_number_field("Radius", part.radius, 1, 400, 0.5, func(value: float) -> void: _part_property("radius", value))
		var filled_box: CheckButton = CheckButton.new()
		filled_box.text = "Filled"
		filled_box.button_pressed = part.filled
		inspector.add_child(filled_box)
		filled_box.toggled.connect(func(value: bool) -> void: _part_property("filled", value))
		var parent_options: Array[String] = []
		for candidate: PartDefinition in working.parts:
			if candidate.shape == "circle" and candidate.id != part.id and not _is_descendant(candidate.id, part.id): parent_options.append(candidate.id)
		if part.id != "core": _option_field("Parent", parent_options, part.parent_id, func(value: String) -> void: _part_property("parent_id", value))
	_number_field("Light period", part.light_period, 0.1, 10, 0.1, func(value: float) -> void: _part_property("light_period", value))
	_number_field("Light phase", part.light_phase, -10, 10, 0.1, func(value: float) -> void: _part_property("light_phase", value))
	if working.faction == "elite": _number_field("Weapon HP", part.hp, 0, 10000, 1, func(value: float) -> void: _part_property("hp", value))

func _is_descendant(candidate_id: String, ancestor_id: String) -> bool:
	var cursor: String = candidate_id
	var seen: Dictionary = {}
	while not cursor.is_empty() and not seen.has(cursor):
		if cursor == ancestor_id: return true
		seen[cursor] = true
		var found: bool = false
		for part: PartDefinition in working.parts:
			if part.id == cursor: cursor = part.parent_id; found = true; break
		if not found: break
	return false

func _text_field(caption: String, value: String, changed: Callable) -> void:
	_label(inspector, caption, 12)
	var edit: LineEdit = LineEdit.new()
	edit.text = value
	inspector.add_child(edit)
	edit.text_submitted.connect(changed)

func _option_field(caption: String, options: Array, value: String, changed: Callable) -> void:
	_label(inspector, caption, 12)
	var option: OptionButton = OptionButton.new()
	for index: int in range(options.size()):
		option.add_item(str(options[index]).replace("_", " ").capitalize())
		if options[index] == value: option.select(index)
	inspector.add_child(option)
	option.item_selected.connect(func(index: int) -> void: changed.call(str(options[index])))

func _number_field(caption: String, value: float, low: float, high: float, step_value: float, changed: Callable) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	inspector.add_child(row)
	_label(row, caption, 12).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var spin: SpinBox = SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step_value
	spin.value = value
	row.add_child(spin)
	spin.value_changed.connect(func(number: float) -> void: if not _updating: changed.call(number))

func _commit(before: ShipDefinition, after: ShipDefinition, label: String) -> void:
	undo.create_action(label)
	undo.add_do_method(_apply_definition.bind(after.duplicate(true)))
	undo.add_undo_method(_apply_definition.bind(before.duplicate(true)))
	undo.commit_action()

func _ship_property(property: String, value: Variant) -> void:
	var after: ShipDefinition = working.duplicate(true)
	after.set(property, value)
	if property == "faction": after.is_player = value == "player"
	if property == "id": current_path = ""
	if property == "element":
		# "inward"/"breathe" are retired: motion now comes from groups (see
		# ShipMotion). This still drives only the running-light behaviour.
		after.breathes = false
		after.motion_signature = {"fire": "flicker", "lightning": "snap", "plasma": "counter_rotate"}.get(value, "smooth")
	_commit(working, after, "Edit " + property)

func _part_property(property: String, value: Variant) -> void:
	if selected < 0: return
	var after: ShipDefinition = working.duplicate(true)
	var part: PartDefinition = after.parts[selected]
	part.set(property, value)
	if symmetry.button_pressed:
		for other: PartDefinition in after.parts:
			if other.id == part.mirror_id:
				other.set(property, value)
				other.position = Vector2(-part.position.x, part.position.y)
				other.radius = part.radius
				other.filled = part.filled
	_commit(working, after, "Edit part " + property)

func _part_vector(property: String, axis: int, value: float) -> void:
	var vector: Vector2 = working.parts[selected].get(property)
	vector[axis] = value
	_part_property(property, vector)

func _rename_part(value: String) -> void:
	if selected < 0: return
	var after: ShipDefinition = working.duplicate(true)
	var previous: String = after.parts[selected].id
	after.parts[selected].id = value.strip_edges()
	for part: PartDefinition in after.parts:
		if part.from_id == previous: part.from_id = value
		if part.to_id == previous: part.to_id = value
		if part.mirror_id == previous: part.mirror_id = value
	_commit(working, after, "Rename part")

func _unique_id(stem: String) -> String:
	var index: int = 1
	var existing: Array[String] = []
	for part: PartDefinition in working.parts: existing.append(part.id)
	while stem + "_" + str(index) in existing: index += 1
	return stem + "_" + str(index)

func _place_object(id: String, kind: String, point: Vector2) -> void:
	var after: ShipDefinition = working.duplicate(true)
	var stem: String = _unique_id(id)
	if kind == "Body":
		if id == "line": _add_line(); return
		if id == "concentric_rings":
			for ring_index: int in range(3): ShipCatalog.add_part(after, stem + "_" + str(ring_index), "circle", Vector2.ZERO, 20 + ring_index * 10, "chassis", "magnet_radius", 2, false, "core")
		elif id == "crescent":
			var outer: PartDefinition = ShipCatalog.add_part(after, stem, "circle", point, 10, "chassis", "hp_buffer", 3, true, "core")
			ShipCatalog.add_part(after, stem + "_cover", "circle", point + Vector2(0, -3), 8, "black", "structure", 4, true, outer.id)
		elif symmetry.button_pressed and absf(point.x) > 0.01: ShipCatalog.add_pair(after, stem, id, point, 10, "chassis", "hp_buffer", 2)
		else: ShipCatalog.add_part(after, stem, id, point, 10, "chassis", "hp_buffer", 3, true, "core")
	else:
		var definition: AbilityDefinition = AbilityCatalog.get_definition(id)
		if definition.slot_kind == "primary":
			after.primary = id
			ShipAuthoring.rebuild_loadout(after)
		elif definition.slot_kind == "secondary": after.secondaries.append(id); ShipCatalog.mount_component(after, id, stem, point)
		elif definition.slot_kind == "passive": after.passives.append(id); ShipCatalog.mount_component(after, id, stem, point)
		else:
			ShipCatalog.mount_component(after, id, stem, point, 11)
			after.parts[-2].hp = 30 + working.tier * 15
		var placed: PartDefinition
		if definition.slot_kind == "primary":
			for part: PartDefinition in after.parts:
				if part.id == "primary": placed = part; placed.position = point
		else: placed = after.parts[-2]
		if placed != null and symmetry.button_pressed and absf(point.x) > 0.01:
			var mirror: PartDefinition = placed.duplicate(true)
			mirror.id = placed.id + "_mirror"
			mirror.position.x *= -1
			mirror.mirror_id = placed.id
			placed.mirror_id = mirror.id
			after.parts.append(mirror)
			ShipCatalog.add_line(after, mirror.id + "_link", "core", mirror.id)
	ShipCatalog.recalculate(after)
	var errors: PackedStringArray = ShipCatalog.validate(after)
	if not errors.is_empty(): status.text = "Placement blocked: " + " | ".join(errors); return
	selected = after.parts.size() - 1
	_commit(working, after, "Place " + id)

func _add_part() -> void: _place_object("circle", "Body", Vector2(20, 0))
func _can_add_part() -> bool: return working.parts.size() < ShipCatalog.MAX_PARTS
func _mirror_part() -> void:
	if selected < 0 or not working.parts[selected].mirror_id.is_empty(): return
	var after: ShipDefinition = working.duplicate(true)
	var part: PartDefinition = after.parts[selected]
	var other: PartDefinition = part.duplicate(true)
	other.id = _unique_id(part.id + "_mirror")
	other.position.x *= -1
	other.mirror_id = part.id
	part.mirror_id = other.id
	after.parts.append(other)
	_commit(working, after, "Mirror part")

func _add_line() -> void:
	if selected < 0 or working.parts[selected].shape == "line" or working.parts[selected].id == "core": return
	var after: ShipDefinition = working.duplicate(true)
	var target: PartDefinition = after.parts[selected]
	var stem: String = _unique_id("line")
	ShipCatalog.add_line(after, stem, "core", target.id)
	if symmetry.button_pressed and not target.mirror_id.is_empty():
		ShipCatalog.add_line(after, stem + "_mirror", "core", target.mirror_id)
		after.parts[-2].mirror_id = after.parts[-1].id
		after.parts[-1].mirror_id = after.parts[-2].id
	_commit(working, after, "Add line")

func _delete_part() -> void:
	if selected < 0 or working.parts[selected].id == "core": return
	var after: ShipDefinition = working.duplicate(true)
	var target: PartDefinition = after.parts[selected]
	var ids: Array[String] = [target.id]
	if symmetry.button_pressed: ids.append(target.mirror_id)
	if not target.mount_id.is_empty():
		if target.ability_id == after.primary: status.text = "Replace the primary from the Primary tab."; return
		var index: int = after.secondaries.find(target.ability_id)
		if index >= 0: after.secondaries.remove_at(index)
		else:
			index = after.passives.find(target.ability_id)
			if index >= 0: after.passives.remove_at(index)
	for index: int in range(after.parts.size() - 1, -1, -1):
		var part: PartDefinition = after.parts[index]
		if part.id in ids or part.from_id in ids or part.to_id in ids: after.parts.remove_at(index)
	selected = -1
	_commit(working, after, "Delete parts and tethers")

func _drag_part(index: int, point: Vector2) -> void:
	var part: PartDefinition = working.parts[index]
	if part.id == "core": return
	part.position = point
	if symmetry.button_pressed:
		if part.mirror_id.is_empty(): part.position.x = 0
		else:
			for other: PartDefinition in working.parts:
				if other.id == part.mirror_id: other.position = Vector2(-point.x, point.y)
	canvas.set_ship(working)
	base_preview.set_ship(working)
	min_preview.set_ship(working)

func _finish_drag() -> void:
	if _drag_snapshot == null: return
	_commit(_drag_snapshot, working, "Move symmetric parts")
	_drag_snapshot = null

func _duplicate_ship() -> void:
	var after: ShipDefinition = working.duplicate(true)
	after.id += "_copy"
	after.display_name += " Copy"
	current_path = ""
	_commit(working, after, "Duplicate ship")

func _generate() -> void:
	var result: Dictionary = ShipAuthoring.from_description(description.text)
	if not result.get("errors", []).is_empty(): status.text = "Generate: " + " | ".join(result.errors); return
	current_path = ""
	selected = -1
	_commit(working, result.ship, "Generate ship")
	if not result.get("warnings", []).is_empty(): status.text = " | ".join(result.warnings)

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
	ShipCatalog.recalculate(working)
	var errors: PackedStringArray = ShipCatalog.validate(working)
	if not errors.is_empty(): status.text = "Save blocked: " + " | ".join(errors); _exit_after_save = false; return
	var result: Error = OK
	if path.ends_with(".json"):
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null: result = FileAccess.get_open_error()
		else: file.store_string(ShipAuthoring.to_json(working))
	else: result = ResourceSaver.save(working, path)
	if result != OK: status.text = "Save failed: " + error_string(result); return
	current_path = path
	ShipCatalog.invalidate(working.id)
	dirty = false
	_refresh_library()
	_refresh()
	status.text = "Saved " + path
	if _exit_after_save: get_tree().change_scene_to_file("res://scenes/main.tscn")
func _load_from(path: String) -> void:
	var result: Dictionary
	if path.ends_with(".json"): result = ShipAuthoring.from_json(FileAccess.get_file_as_string(path))
	else:
		var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		result = {"ship": resource, "errors": ShipCatalog.validate(resource) if resource is ShipDefinition else PackedStringArray(["Not a ship definition."])}
	if not result.errors.is_empty(): status.text = "Load blocked: " + " | ".join(result.errors); return
	current_path = path
	selected = -1
	_commit(working, result.ship, "Load ship")
	dirty = false
	_refresh()
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

func _build_library() -> void:
	library_window = Window.new()
	library_window.title = "Ship Library"
	library_window.visible = false
	library_window.size = Vector2i(1040, 680)
	library_window.close_requested.connect(library_window.hide)
	add_child(library_window)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	library_window.add_child(layout)
	var filters: HBoxContainer = HBoxContainer.new()
	layout.add_child(filters)
	library_search = LineEdit.new()
	library_search.placeholder_text = "Search name or ID"
	library_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_search.text_changed.connect(func(_value: String) -> void: _refresh_library())
	filters.add_child(library_search)
	var values: Dictionary = {"element": ["all", "neutral"] + ShipCatalog.ELEMENTS, "tier": ["all", "1", "2", "3", "4", "5"], "role": ["all", "compact", "standard", "heavy"], "faction": ["all", "player", "enemy", "elite", "rival"]}
	for key: String in values:
		var option: OptionButton = OptionButton.new()
		for value: String in values[key]: option.add_item(value)
		option.item_selected.connect(func(_index: int) -> void: _refresh_library())
		filters.add_child(option)
		library_filters[key] = option
	library_sort = OptionButton.new()
	for key: String in ["display_name", "element", "tier", "role", "faction"]: library_sort.add_item(key)
	library_sort.item_selected.connect(func(_index: int) -> void: _refresh_library())
	filters.add_child(library_sort)
	library_missing = CheckButton.new()
	library_missing.text = "Missing roster slots"
	library_missing.toggled.connect(func(_value: bool) -> void: _refresh_library())
	layout.add_child(library_missing)
	missing_label = _label(layout, "")
	missing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	library_items = ItemList.new()
	library_items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library_items.fixed_icon_size = Vector2i(56, 56)
	library_items.item_activated.connect(func(_index: int) -> void: _open_catalog())
	layout.add_child(library_items)
	var actions: HBoxContainer = HBoxContainer.new()
	layout.add_child(actions)
	_button(actions, "Open", _open_catalog)
	_button(actions, "Duplicate for next tier", func() -> void:
		_open_catalog()
		_duplicate_ship()
		_ship_property("tier", mini(GameTuning.MAX_TIER, working.tier + 1)))
	_button(actions, "Rename", func() -> void: _open_catalog(); status.text = "Edit the name in the inspector, then Save.")
	_button(actions, "Delete…", _delete_library_ship)
	_delete_confirmation = ConfirmationDialog.new()
	_delete_confirmation.confirmed.connect(func() -> void:
		var path: String = ShipCatalog.catalog_root.path_join(_delete_id + ".tres")
		var result: Error = DirAccess.remove_absolute(path)
		ShipCatalog.invalidate(_delete_id)
		status.text = "Deleted " + _delete_id if result == OK else "Delete failed: " + error_string(result)
		_refresh_library())
	add_child(_delete_confirmation)
	_refresh_library()

func _show_library() -> void:
	ShipCatalog.invalidate()
	_refresh_library()
	library_window.popup_centered()

func _refresh_library() -> void:
	if library_items == null: return
	_forms = ShipCatalog.all_forms()
	var sort_key: String = library_sort.get_item_text(library_sort.selected)
	_forms.sort_custom(func(a: ShipDefinition, b: ShipDefinition) -> bool: return str(a.get(sort_key)) + a.id < str(b.get(sort_key)) + b.id)
	library_items.clear()
	_library_ids.clear()
	target_library.clear()
	var counts: Dictionary = {}
	for ship: ShipDefinition in _forms:
		target_library.add_item(ship.display_name + " / T" + str(ship.tier))
		if ship.faction == "player": counts[ship.element + " T" + str(ship.tier)] = int(counts.get(ship.element + " T" + str(ship.tier), 0)) + 1
		var include: bool = true
		for key: String in library_filters:
			var option: OptionButton = library_filters[key]
			var value: String = option.get_item_text(option.selected)
			if value != "all" and str(ship.get(key)) != value: include = false
		if not library_search.text.is_empty() and not library_search.text.to_lower() in (ship.id + " " + ship.display_name).to_lower(): include = false
		if not include: continue
		library_items.add_item("%s · %s · T%d · %s · %s" % [ship.display_name, ship.element, ship.tier, ship.role, ship.faction], ShipAuthoring.thumbnail(ship))
		_library_ids.append(ship.id)
	var missing: PackedStringArray = []
	for element: String in ShipCatalog.ELEMENTS:
		for tier: int in range(2, GameTuning.MAX_TIER + 1):
			var key: String = element + " T" + str(tier)
			if int(counts.get(key, 0)) < 4: missing.append(key + ": " + str(counts.get(key, 0)) + " / 4")
	missing_label.text = "All 81 player roster slots are filled." if missing.is_empty() else "Missing: " + " · ".join(missing)
	missing_label.visible = library_missing.button_pressed
	library_items.visible = not library_missing.button_pressed

func _open_catalog() -> void:
	var selected_items: PackedInt32Array = library_items.get_selected_items()
	if selected_items.is_empty(): return
	var id: String = _library_ids[selected_items[0]]
	_load_from(ShipCatalog.catalog_root.path_join(id + ".tres"))
	library_window.hide()

func _delete_library_ship() -> void:
	var selected_items: PackedInt32Array = library_items.get_selected_items()
	if selected_items.is_empty(): return
	_delete_id = _library_ids[selected_items[0]]
	_delete_confirmation.dialog_text = "Delete " + _delete_id + " from the ship library? Roster gaps will appear in the missing view."
	_delete_confirmation.popup_centered()

func _preview_reshape() -> void:
	if target_library.selected < 0 or target_library.selected >= _forms.size(): return
	var target: ShipDefinition = _forms[target_library.selected]
	canvas.set_ship(working)
	base_preview.set_ship(working)
	min_preview.set_ship(working)
	canvas.set_ship(target, true)
	base_preview.set_ship(target, true)
	min_preview.set_ship(target, true)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.text = "Reshaping to " + target.display_name
	await get_tree().create_timer(1.6, true).timeout
	if not is_inside_tree(): return
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh()

func _preview_combat() -> void:
	var errors: PackedStringArray = ShipCatalog.validate(working)
	if not errors.is_empty(): status.text = "Preview blocked: " + " | ".join(errors); return
	if is_instance_valid(_combat_window): _combat_window.queue_free()
	_combat_window = Window.new()
	_combat_window.title = "Live combat preview · mounted components against a dummy"
	_combat_window.size = Vector2i(960, 640)
	_combat_window.close_requested.connect(func() -> void: _combat_window.queue_free())
	add_child(_combat_window)
	var preview: WorkshopCombatPreview = WorkshopCombatPreview.new()
	preview.ship = working.duplicate(true)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_combat_window.add_child(preview)
	_combat_window.popup_centered()


func _exit_tree() -> void:
	undo.clear_history()
	undo.free()
	_forms.clear()








