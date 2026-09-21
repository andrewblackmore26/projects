class_name TabMotion
extends EditorTab
## Per-rail speed and pump amplitude, per-cluster bob amplitude override, and chain mode for the
## chain archetype. Defaults come from `ShipGrammar.MOTION`; a ship file stores only overrides
## (spec §11 "Motion tab" / §9's "motion defaults are data, not file content").

var rail_picker: OptionButton
var speed_field: SpinBox
var pump_amp_field: SpinBox
var pump_default_box: CheckButton
var bob_amp_field: SpinBox
var bob_default_box: CheckButton
var chain_mode_field: OptionButton
var _rail: int = -1
var _slot: int = -1

func build(parent: Control) -> void:
	rail_picker = OptionButton.new()
	parent.add_child(rail_picker)
	rail_picker.item_selected.connect(func(index: int) -> void: _rail = index; editor.select_rail(index))
	speed_field = _spin(parent, "Rail speed (rad/s)", -3, 3, 0.01, func(v: float) -> void: _rail_prop("speed", v))
	pump_default_box = CheckButton.new()
	pump_default_box.text = "Pump amplitude: use archetype default (%.0f%%)" % (float(ShipGrammar.MOTION.pump_amp) * 100.0)
	pump_default_box.toggled.connect(func(on: bool) -> void: _rail_prop("pump_amp", -1.0 if on else maxf(0.0, pump_amp_field.value)))
	parent.add_child(pump_default_box)
	pump_amp_field = _spin(parent, "Pump amplitude (fraction of radius)", 0, 0.2, 0.005, func(v: float) -> void: _rail_prop("pump_amp", v))
	var slot_label: Label = Label.new()
	slot_label.text = "Selected slot's bob amplitude override"
	parent.add_child(slot_label)
	bob_default_box = CheckButton.new()
	bob_default_box.text = "Use archetype default"
	bob_default_box.toggled.connect(func(on: bool) -> void: _slot_prop("bob_amp", -1.0 if on else maxf(0.0, bob_amp_field.value)))
	parent.add_child(bob_default_box)
	bob_amp_field = _spin(parent, "Bob amplitude (rad)", 0, 0.5, 0.01, func(v: float) -> void: _slot_prop("bob_amp", v))
	var chain_label: Label = Label.new()
	chain_label.text = "Chain mode (chain archetype only)"
	parent.add_child(chain_label)
	chain_mode_field = OptionButton.new()
	for mode: String in ["rigid", "sway", "whip"]: chain_mode_field.add_item(mode)
	chain_mode_field.item_selected.connect(func(index: int) -> void:
		var value: String = chain_mode_field.get_item_text(index)
		edit("Set chain mode", func(s: ShipDefinition) -> void: s.chain_mode = value))
	parent.add_child(chain_mode_field)

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

func _rail_prop(property: String, value: float) -> void:
	if _rail < 0: return
	edit("Edit rail motion " + property, func(s: ShipDefinition) -> void:
		if _rail < s.rails.size(): s.rails[_rail].set(property, value))

func _slot_prop(property: String, value: float) -> void:
	if _rail < 0 or _slot < 0: return
	edit("Edit slot motion " + property, func(s: ShipDefinition) -> void:
		if _rail < s.rails.size() and _slot < s.rails[_rail].slots.size(): s.rails[_rail].slots[_slot].set(property, value))

func refresh(working: ShipDefinition, _compiled: ShipDefinition, selection: Dictionary) -> void:
	if int(selection.get("rail", -2)) != -2: _rail = int(selection.rail)
	if int(selection.get("slot", -2)) != -2: _slot = int(selection.slot)
	_rail = clampi(_rail, -1, working.rails.size() - 1)
	rail_picker.clear()
	for i: int in range(working.rails.size()): rail_picker.add_item("Rail %d" % (i + 1))
	if _rail >= 0: rail_picker.select(_rail)
	var rail: RailDefinition = working.rails[_rail] if _rail >= 0 else null
	speed_field.editable = rail != null
	pump_amp_field.editable = rail != null and not (rail != null and rail.pump_amp < 0.0)
	if rail != null:
		speed_field.set_value_no_signal(rail.speed)
		pump_default_box.set_pressed_no_signal(rail.pump_amp < 0.0)
		pump_amp_field.set_value_no_signal(rail.pump_amp if rail.pump_amp >= 0.0 else float(ShipGrammar.MOTION.pump_amp))
	_slot = clampi(_slot, -1, (rail.slots.size() - 1) if rail != null else -1)
	var slot: SlotDefinition = rail.slots[_slot] if rail != null and _slot >= 0 else null
	bob_amp_field.editable = slot != null and slot.bob_amp >= 0.0
	if slot != null:
		bob_default_box.set_pressed_no_signal(slot.bob_amp < 0.0)
		bob_amp_field.set_value_no_signal(slot.bob_amp if slot.bob_amp >= 0.0 else float(ShipGrammar.MOTION.node_bob_amp))
	chain_mode_field.disabled = working.archetype != "chain"
	chain_mode_field.select(maxi(0, ["rigid", "sway", "whip"].find(working.chain_mode)))
