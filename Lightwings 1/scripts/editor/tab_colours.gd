class_name TabColours
extends EditorTab
## Chassis / accent pickers and the read-only, colour-filtered set-piece list (spec §11 "Colours
## tab"). A colour change is NEVER blocked and never auto-unmounts anything mounted under the old
## pair; it shows what is now illegal and lets the designer unmount it explicitly.

var chassis_field: OptionButton
var accent_field: OptionButton
var piece_list: ItemList
var illegal_box: VBoxContainer
var illegal_label: Label

func build(parent: Control) -> void:
	chassis_field = _option(parent, "Chassis", func(v: String) -> void: edit("Set chassis", func(s: ShipDefinition) -> void: s.chassis_color = v))
	accent_field = _option(parent, "Accent (or none)", func(v: String) -> void: edit("Set accent", func(s: ShipDefinition) -> void: s.accent_color = "" if v == "(none)" else v))
	var piece_label: Label = Label.new()
	piece_label.text = "All set pieces (illegal pairs greyed out)"
	parent.add_child(piece_label)
	piece_list = ItemList.new()
	piece_list.custom_minimum_size.y = 160
	parent.add_child(piece_list)
	illegal_label = Label.new()
	illegal_label.text = "MOUNTED BUT ILLEGAL"
	illegal_label.modulate = Color("ff5436")
	illegal_label.visible = false
	parent.add_child(illegal_label)
	illegal_box = VBoxContainer.new()
	parent.add_child(illegal_box)
	var unmount_all: Button = Button.new()
	unmount_all.text = "Unmount all"
	unmount_all.pressed.connect(func() -> void: edit("Unmount all illegal", func(s: ShipDefinition) -> void:
		for mount: Dictionary in ShipGrammar.illegal_mounts(s): _unmount_at(s, str(mount.where))))
	parent.add_child(unmount_all)

func _option(parent: Control, caption: String, changed: Callable) -> OptionButton:
	var label: Label = Label.new()
	label.text = caption
	parent.add_child(label)
	var field: OptionButton = OptionButton.new()
	for colour: String in Elements.COLOR_KEYS: field.add_item(colour)
	if caption.begins_with("Accent"): field.add_item("(none)")
	parent.add_child(field)
	field.item_selected.connect(func(index: int) -> void: changed.call(field.get_item_text(index)))
	return field

## Parses the exact `where` strings `ShipGrammar.illegal_mounts` produces and clears that mount.
static func _unmount_at(ship: ShipDefinition, where: String) -> void:
	if where == "the core":
		ship.core_weapon = ""
		return
	if where.begins_with("rail "):
		var parts: PackedStringArray = where.split(" ")
		var rail_index: int = int(parts[1]) - 1
		var slot_index: int = int(parts[3])
		if rail_index >= 0 and rail_index < ship.rails.size() and slot_index >= 0 and slot_index < ship.rails[rail_index].slots.size():
			ship.rails[rail_index].slots[slot_index].set_piece = ""
			ship.rails[rail_index].slots[slot_index].mount = ""
		return
	if where.begins_with("chain link "):
		var link_index: int = int(where.split(" ")[2])
		if link_index >= 0 and link_index < ship.chain_links.size(): ship.chain_links[link_index].set_piece = ""

func refresh(working: ShipDefinition, _compiled: ShipDefinition, _selection: Dictionary) -> void:
	var player: bool = working.faction == "player"
	chassis_field.select(maxi(0, Elements.COLOR_KEYS.find(working.chassis_color)))
	chassis_field.disabled = player # blue is the only legal player chassis
	for i: int in range(Elements.COLOR_KEYS.size()): chassis_field.set_item_disabled(i, not player and Elements.COLOR_KEYS[i] == Elements.PLAYER_COLOR_KEY)
	accent_field.select(Elements.COLOR_KEYS.size() if working.accent_color == "" else maxi(0, Elements.COLOR_KEYS.find(working.accent_color)))
	for i: int in range(Elements.COLOR_KEYS.size()): accent_field.set_item_disabled(i, not player and Elements.COLOR_KEYS[i] == Elements.PLAYER_COLOR_KEY)
	piece_list.clear()
	for id: String in SetPieceCatalog.ids():
		var legal: bool = SetPieceCatalog.is_legal(id, working.chassis_color, working.accent_color)
		var index: int = piece_list.add_item("%s  [%s]" % [id, " + ".join(SetPieceCatalog.colours_of(id))])
		piece_list.set_item_disabled(index, not legal)
		if not legal:
			var missing: Array[String] = []
			for colour: String in SetPieceCatalog.colours_of(id):
				if colour != working.chassis_color and colour != working.accent_color: missing.append(colour)
			piece_list.set_item_tooltip(index, "Needs " + " + ".join(missing))
	for child: Node in illegal_box.get_children(): child.queue_free()
	var illegal: Array[Dictionary] = ShipGrammar.illegal_mounts(working)
	illegal_label.visible = not illegal.is_empty()
	for mount: Dictionary in illegal:
		var row: HBoxContainer = HBoxContainer.new()
		illegal_box.add_child(row)
		var label: Label = Label.new()
		label.text = "%s at %s (needs %s)" % [mount.piece, mount.where, mount.needs]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var where: String = str(mount.where)
		var button: Button = Button.new()
		button.text = "Unmount"
		button.pressed.connect(func() -> void: edit("Unmount " + str(mount.piece), func(s: ShipDefinition) -> void: _unmount_at(s, where)))
		row.add_child(button)
