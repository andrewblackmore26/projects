class_name TabCore
extends EditorTab
## Header fields (name, id, faction, archetype, tier, role), core depth and the core weapon /
## passives (spec §11 "Core tab").

var name_field: LineEdit
var id_field: LineEdit
var faction_field: OptionButton
var archetype_field: OptionButton
var tier_field: SpinBox
var role_field: OptionButton
var depth_field: SpinBox
var core_weapon_field: OptionButton
var passive_list: ItemList
var passive_hint: Label

func build(parent: Control) -> void:
	name_field = _text(parent, "Name", func(v: String) -> void: edit("Rename", func(s: ShipDefinition) -> void: s.display_name = v))
	id_field = _text(parent, "ID", func(v: String) -> void: edit("Re-id", func(s: ShipDefinition) -> void: s.id = v))
	faction_field = _option(parent, "Faction", ShipGrammar.FACTIONS, func(v: String) -> void: edit("Set faction", func(s: ShipDefinition) -> void: s.faction = v))
	archetype_field = _option(parent, "Archetype", ShipGrammar.ARCHETYPES, func(v: String) -> void: edit("Set archetype", func(s: ShipDefinition) -> void: s.archetype = v))
	var tier_row: HBoxContainer = HBoxContainer.new()
	parent.add_child(tier_row)
	var tier_label: Label = Label.new()
	tier_label.text = "Tier"
	tier_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tier_row.add_child(tier_label)
	tier_field = SpinBox.new()
	tier_field.min_value = 1
	tier_field.max_value = GameTuning.MAX_TIER
	tier_field.step = 1
	tier_row.add_child(tier_field)
	tier_field.value_changed.connect(func(v: float) -> void: edit("Set tier", func(s: ShipDefinition) -> void: s.tier = int(v)))
	role_field = _option(parent, "Role", ["compact", "standard", "heavy"], func(v: String) -> void: edit("Set role", func(s: ShipDefinition) -> void: s.role = v))
	var depth_row: HBoxContainer = HBoxContainer.new()
	parent.add_child(depth_row)
	var depth_label: Label = Label.new()
	depth_label.text = "Core depth"
	depth_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	depth_row.add_child(depth_label)
	depth_field = SpinBox.new()
	depth_field.min_value = 2
	depth_field.max_value = 4
	depth_field.step = 1
	depth_row.add_child(depth_field)
	depth_field.value_changed.connect(func(v: float) -> void: edit("Set core depth", func(s: ShipDefinition) -> void: s.core_depth = int(v)))
	var weapon_label: Label = Label.new()
	weapon_label.text = "Core weapon (non-players only)"
	parent.add_child(weapon_label)
	core_weapon_field = OptionButton.new()
	parent.add_child(core_weapon_field)
	core_weapon_field.item_selected.connect(func(index: int) -> void:
		var value: String = "" if index <= 0 else core_weapon_field.get_item_text(index)
		edit("Set core weapon", func(s: ShipDefinition) -> void: s.core_weapon = value))
	var passive_label: Label = Label.new()
	passive_label.text = "Passives"
	parent.add_child(passive_label)
	passive_list = ItemList.new()
	passive_list.custom_minimum_size.y = 70
	parent.add_child(passive_list)
	passive_hint = Label.new()
	passive_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(passive_hint)
	var passive_buttons: HBoxContainer = HBoxContainer.new()
	parent.add_child(passive_buttons)
	var add_button: Button = Button.new()
	add_button.text = "Add radar"
	add_button.pressed.connect(func() -> void: edit("Add passive", func(s: ShipDefinition) -> void: s.passives.append("radar")))
	passive_buttons.add_child(add_button)
	var remove_button: Button = Button.new()
	remove_button.text = "Remove last"
	remove_button.pressed.connect(func() -> void: edit("Remove passive", func(s: ShipDefinition) -> void:
		if not s.passives.is_empty(): s.passives.remove_at(s.passives.size() - 1)))
	passive_buttons.add_child(remove_button)

func _text(parent: Control, caption: String, changed: Callable) -> LineEdit:
	var label: Label = Label.new()
	label.text = caption
	parent.add_child(label)
	var field: LineEdit = LineEdit.new()
	parent.add_child(field)
	field.text_submitted.connect(changed)
	return field

func _option(parent: Control, caption: String, values: Array, changed: Callable) -> OptionButton:
	var label: Label = Label.new()
	label.text = caption
	parent.add_child(label)
	var field: OptionButton = OptionButton.new()
	for value: String in values: field.add_item(value)
	parent.add_child(field)
	field.item_selected.connect(func(index: int) -> void: changed.call(field.get_item_text(index)))
	return field

func refresh(working: ShipDefinition, _compiled: ShipDefinition, _selection: Dictionary) -> void:
	name_field.text = working.display_name
	id_field.text = working.id
	faction_field.select(maxi(0, ShipGrammar.FACTIONS.find(working.faction)))
	archetype_field.select(maxi(0, ShipGrammar.ARCHETYPES.find(working.archetype)))
	tier_field.set_value_no_signal(working.tier)
	role_field.select(maxi(0, ["compact", "standard", "heavy"].find(working.role)))
	depth_field.set_value_no_signal(working.core_depth)
	var is_player: bool = working.faction == "player"
	core_weapon_field.disabled = is_player
	core_weapon_field.clear()
	core_weapon_field.add_item("(none)")
	var legal: Array[String] = SetPieceCatalog.legal_for(working.chassis_color, working.accent_color)
	for id: String in legal:
		if SetPieceCatalog.is_implemented(id): core_weapon_field.add_item(id)
	var found: int = -1
	for i: int in range(core_weapon_field.item_count):
		if core_weapon_field.get_item_text(i) == working.core_weapon: found = i
	core_weapon_field.select(maxi(0, found))
	passive_list.clear()
	for passive: String in working.passives: passive_list.add_item(passive)
	var cap: int = int(GameTuning.slots(working.tier, working.role).passive)
	passive_hint.text = "%d / %d passive slots (GameTuning.slots)" % [working.passives.size(), cap]
