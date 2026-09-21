class_name TabRails
extends EditorTab
## Add/remove a rail (always the next/outermost ladder radius), order, signed speed, phase, pump
## phase, and (irregular elites only) the rail centre offset. Spec §11 "Rails tab".

var rail_picker: OptionButton
var order_field: SpinBox
var speed_field: SpinBox
var phase_field: SpinBox
var pump_phase_field: SpinBox
var offset_x_field: SpinBox
var offset_y_field: SpinBox
var sign_warning: Label
var _current_rail: int = -1

func build(parent: Control) -> void:
	var top: HBoxContainer = HBoxContainer.new()
	parent.add_child(top)
	var add_button: Button = Button.new()
	add_button.text = "Add rail"
	add_button.pressed.connect(_add_rail)
	top.add_child(add_button)
	var remove_button: Button = Button.new()
	remove_button.text = "Remove outer rail"
	remove_button.pressed.connect(func() -> void: edit("Remove outer rail", func(s: ShipDefinition) -> void:
		if not s.rails.is_empty(): s.rails.remove_at(s.rails.size() - 1)))
	top.add_child(remove_button)
	var picker_label: Label = Label.new()
	picker_label.text = "Editing rail"
	parent.add_child(picker_label)
	rail_picker = OptionButton.new()
	parent.add_child(rail_picker)
	rail_picker.item_selected.connect(func(index: int) -> void: _current_rail = index; editor.select_rail(index))
	order_field = _spin(parent, "Order", 3, 8, 1, func(v: float) -> void: _retile_order(int(v)))
	speed_field = _spin(parent, "Speed (signed, rad/s)", -3, 3, 0.01, func(v: float) -> void: _set_rail("speed", v))
	var flip: Button = Button.new()
	flip.text = "Flip sign"
	flip.pressed.connect(func() -> void: _set_rail("speed", -speed_field.value))
	parent.add_child(flip)
	phase_field = _spin(parent, "Phase (rad)", -TAU, TAU, 0.01, func(v: float) -> void: _set_rail("phase", v))
	pump_phase_field = _spin(parent, "Pump phase (rad)", -TAU, TAU, 0.01, func(v: float) -> void: _set_rail("pump_phase", v))
	offset_x_field = _spin(parent, "Offset X (irregular elites only)", -ShipGrammar.MAX_RAIL_OFFSET, ShipGrammar.MAX_RAIL_OFFSET, 0.1, func(v: float) -> void: _set_offset(0, v))
	offset_y_field = _spin(parent, "Offset Y (irregular elites only)", -ShipGrammar.MAX_RAIL_OFFSET, ShipGrammar.MAX_RAIL_OFFSET, 0.1, func(v: float) -> void: _set_offset(1, v))
	sign_warning = Label.new()
	sign_warning.modulate = Color("ffb99f")
	sign_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(sign_warning)

func _spin(parent: Control, caption: String, low: float, high: float, step_value: float, changed: Callable) -> SpinBox:
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	var label: Label = Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var field: SpinBox = SpinBox.new()
	field.min_value = low
	field.max_value = high
	field.step = step_value
	row.add_child(field)
	field.value_changed.connect(changed)
	return field

func _add_rail() -> void:
	edit("Add rail", func(s: ShipDefinition) -> void:
		var index: int = s.rails.size()
		if index >= ShipGrammar.RAIL_RADII.size(): return
		var rail: RailDefinition = RailDefinition.new()
		rail.radius = ShipGrammar.RAIL_RADII[index]
		rail.order = 4
		rail.speed = ShipGrammar.rail_speed(index)
		rail.slots = _tiled([], rail.order)
		s.rails.append(rail))

func _retile_order(order: int) -> void:
	if _current_rail < 0: return
	edit("Set rail order", func(s: ShipDefinition) -> void:
		if _current_rail >= s.rails.size(): return
		var rail: RailDefinition = s.rails[_current_rail]
		rail.slots = _tiled(rail.slots, order)
		rail.order = order)

## Keeps as many existing slots as fit; new slots are unoccupied stubs.
static func _tiled(existing: Array[SlotDefinition], order: int) -> Array[SlotDefinition]:
	var result: Array[SlotDefinition] = []
	for i: int in range(order):
		if i < existing.size(): result.append(existing[i])
		else:
			var slot: SlotDefinition = SlotDefinition.new()
			slot.type = "stub"
			result.append(slot)
	return result

func _set_rail(property: String, value: Variant) -> void:
	if _current_rail < 0: return
	edit("Edit rail " + property, func(s: ShipDefinition) -> void:
		if _current_rail < s.rails.size(): s.rails[_current_rail].set(property, value))

func _set_offset(axis: int, value: float) -> void:
	if _current_rail < 0: return
	edit("Edit rail offset", func(s: ShipDefinition) -> void:
		if _current_rail >= s.rails.size(): return
		var offset: Vector2 = s.rails[_current_rail].offset
		offset[axis] = value
		s.rails[_current_rail].offset = offset)

func refresh(working: ShipDefinition, _compiled: ShipDefinition, selection: Dictionary) -> void:
	if int(selection.get("rail", -2)) != -2: _current_rail = int(selection.rail)
	_current_rail = clampi(_current_rail, -1, working.rails.size() - 1)
	rail_picker.clear()
	for i: int in range(working.rails.size()): rail_picker.add_item("Rail %d (r %d)" % [i + 1, working.rails[i].radius])
	if _current_rail >= 0: rail_picker.select(_current_rail)
	var enabled: bool = _current_rail >= 0
	for field: SpinBox in [order_field, speed_field, phase_field, pump_phase_field]: field.editable = enabled
	if not enabled: sign_warning.text = ""; return
	var rail: RailDefinition = working.rails[_current_rail]
	order_field.set_value_no_signal(rail.order)
	speed_field.set_value_no_signal(rail.speed)
	phase_field.set_value_no_signal(rail.phase)
	pump_phase_field.set_value_no_signal(rail.pump_phase)
	var irregular: bool = ShipGrammar.is_irregular(working)
	offset_x_field.editable = irregular
	offset_y_field.editable = irregular
	offset_x_field.set_value_no_signal(rail.offset.x)
	offset_y_field.set_value_no_signal(rail.offset.y)
	var warning: String = ""
	if _current_rail > 0 and rail.speed * working.rails[_current_rail - 1].speed > 0.0: warning = "Sign does not alternate against rail %d (RAIL-SIGN)." % _current_rail
	sign_warning.text = warning
