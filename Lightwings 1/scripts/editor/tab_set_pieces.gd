class_name TabSetPieces
extends EditorTab
## Read-only list of every set piece: id, colours, weapon, slot kind, implemented yes/no. Set pieces
## are authored once by hand and never edited per ship (spec §11 "Set piece library").

var piece_list: ItemList

func build(parent: Control) -> void:
	var label: Label = Label.new()
	label.text = "All %d set pieces (read-only)" % SetPieceCatalog.ids().size()
	parent.add_child(label)
	piece_list = ItemList.new()
	piece_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(piece_list)

func refresh(_working: ShipDefinition, _compiled: ShipDefinition, _selection: Dictionary) -> void:
	piece_list.clear()
	for id: String in SetPieceCatalog.ids():
		var implemented: bool = SetPieceCatalog.is_implemented(id)
		piece_list.add_item("%s · %s · %s · %s · %s" % [id, " + ".join(SetPieceCatalog.colours_of(id)), SetPieceCatalog.ability_of(id), SetPieceCatalog.slot_of(id), "implemented" if implemented else "NOT IMPLEMENTED"])
