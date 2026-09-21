class_name TabSlots
extends EditorTab
## Click a slot (via the canvas or the pickers here), choose hub / node / stub, pods, node radius,
## hp, and a set piece from the colour-legal AND implemented pool. "Apply to symmetric orbit" is on
## by default: it copies the edit to every slot on the rail, so a non-irregular enemy rail's
## rotational symmetry holds by construction instead of by a validator catching it after the fact.

var rail_picker: OptionButton
var slot_picker: OptionButton
var type_field: OptionButton
var pods_field: SpinBox
var node_radius_field: OptionButton
var hp_field: SpinBox
var set_piece_field: OptionButton
var mount_field: OptionButton
var symmetric_box: CheckButton
var _rail: int = -1
var _slot: int = -1

const TYPES: Array[String] = ["stub", "node", "hub"]
const NODE_RADII: Array[int] = [4, 7]
const MOUNTS: Array[String] = ["", "primary", "secondary_0", "secondary_1", "secondary_2"]

func build(parent: Control) -> void:
	var pickers: HBoxContainer = HBoxContainer.new()
	parent.add_child(pickers)
	rail_picker = OptionButton.new()
	pickers.add_child(rail_picker)
	rail_picker.item_selected.connect(func(index: int) -> void: _rail = index; _slot = 0; editor.select_rail(index))
	slot_picker = OptionButton.new()
	pickers.add_child(slot_picker)
	slot_picker.item_selected.connect(func(index: int) -> void: _slot = index; editor.select_slot(_rail, index))
	symmetric_box = CheckButton.new()
	symmetric_box.text = "Apply to symmetric orbit"
	symmetric_box.button_pressed = true
	parent.add_child(symmetric_box)
	type_field = _option(parent, "Type", TYPES, func(v: String) -> void: _apply(func(slot: SlotDefinition) -> void: slot.type = v))
	pods_field = _spin(parent, "Pods", 1, ShipGrammar.MAX_PODS, 1, func(v: float) -> void: _apply(func(slot: SlotDefinition) -> void: slot.pods = int(v)))
	node_radius_field = _option(parent, "Node radius", ["4", "7"], func(v: String) -> void: _apply(func(slot: SlotDefinition) -> void: slot.node_radius = int(v)))
	hp_field = _spin(parent, "HP", 0, 500, 5, func(v: float) -> void: _apply(func(slot: SlotDefinition) -> void: slot.hp = v))
	set_piece_field = OptionButton.new()
	var piece_label: Label = Label.new()
	piece_label.text = "Set piece (colour-legal and implemented)"
	parent.add_child(piece_label)
	parent.add_child(set_piece_field)
	set_piece_field.item_selected.connect(func(index: int) -> void:
		var value: String = "" if index <= 0 else set_piece_field.get_item_text(index)
		_apply(func(slot: SlotDefinition) -> void: slot.set_piece = value))
	mount_field = _option(parent, "Mount (players only)", MOUNTS, func(v: String) -> void: _apply(func(slot: SlotDefinition) -> void: slot.mount = v))

func _option(parent: Control, caption: String, values: Array, changed: Callable) -> OptionButton:
	var label: Label = Label.new()
	label.text = caption
	parent.add_child(label)
	var field: OptionButton = OptionButton.new()
	for value: String in values: field.add_item(str(value) if str(value) != "" else "(none)")
	parent.add_child(field)
	field.item_selected.connect(func(index: int) -> void: changed.call(str(values[index])))
	return field

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

## Applies `mutate` to the selected slot, and (if the box is on) every other slot on the same rail.
func _apply(mutate: Callable) -> void:
	if _rail < 0 or _slot < 0: return
	var whole_rail: bool = symmetric_box.button_pressed
	var rail_index: int = _rail
	edit("Edit slot", func(s: ShipDefinition) -> void:
		if rail_index >= s.rails.size(): return
		var rail: RailDefinition = s.rails[rail_index]
		if _slot >= rail.slots.size(): return
		if whole_rail:
			for slot: SlotDefinition in rail.slots: mutate.call(slot)
		else:
			mutate.call(rail.slots[_slot]))

func refresh(working: ShipDefinition, _compiled: ShipDefinition, selection: Dictionary) -> void:
	if int(selection.get("rail", -2)) != -2: _rail = int(selection.rail)
	if int(selection.get("slot", -2)) != -2: _slot = int(selection.slot)
	_rail = clampi(_rail, -1, working.rails.size() - 1)
	rail_picker.clear()
	for i: int in range(working.rails.size()): rail_picker.add_item("Rail %d" % (i + 1))
	if _rail >= 0: rail_picker.select(_rail)
	slot_picker.clear()
	var rail: RailDefinition = working.rails[_rail] if _rail >= 0 and _rail < working.rails.size() else null
	if rail != null:
		for j: int in range(rail.slots.size()): slot_picker.add_item("Slot %d (%s)" % [j, rail.slots[j].type])
	_slot = clampi(_slot, -1, (rail.slots.size() - 1) if rail != null else -1)
	if _slot >= 0: slot_picker.select(_slot)
	var enabled: bool = rail != null and _slot >= 0
	for field: Control in [type_field, node_radius_field, set_piece_field, mount_field]: field.disabled = not enabled
	for field: SpinBox in [pods_field, hp_field]: field.editable = enabled
	if not enabled: return
	var slot: SlotDefinition = rail.slots[_slot]
	type_field.select(maxi(0, TYPES.find(slot.type)))
	pods_field.set_value_no_signal(maxi(1, slot.pods))
	node_radius_field.select(maxi(0, NODE_RADII.find(slot.node_radius)))
	hp_field.set_value_no_signal(slot.hp)
	set_piece_field.clear()
	set_piece_field.add_item("(none)")
	for id: String in SetPieceCatalog.legal_for(working.chassis_color, working.accent_color):
		if SetPieceCatalog.is_implemented(id): set_piece_field.add_item(id)
	var found: int = -1
	for i: int in range(set_piece_field.item_count):
		if set_piece_field.get_item_text(i) == slot.set_piece: found = i
	set_piece_field.select(maxi(0, found))
	mount_field.disabled = working.faction != "player"
	mount_field.select(maxi(0, MOUNTS.find(slot.mount)))
