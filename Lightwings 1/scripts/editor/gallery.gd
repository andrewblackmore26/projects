extends Control
var _grid: GridContainer
var _player: bool = true
var _minimum: bool = false
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background: ColorRect = ColorRect.new()
	background.color = Color("050507")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	var title: Label = Label.new()
	title.text = "LIGHTSHIP / FIVE ELEMENTS / 81 PLAYER HULLS"
	title.add_theme_font_size_override("font_size", 24)
	layout.add_child(title)
	var controls: HBoxContainer = HBoxContainer.new()
	layout.add_child(controls)
	var mode: CheckButton = CheckButton.new()
	mode.text = "Player hulls"
	mode.button_pressed = true
	mode.toggled.connect(func(value: bool) -> void: _player = value; _populate())
	controls.add_child(mode)
	var zoom: CheckButton = CheckButton.new()
	zoom.text = "Minimum zoom (0.66)"
	zoom.toggled.connect(func(value: bool) -> void: _minimum = value; _populate())
	controls.add_child(zoom)
	var editor: Button = Button.new()
	editor.text = "Open ship workshop"
	editor.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/ship_editor.tscn"))
	controls.add_child(editor)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	_populate()
func _populate() -> void:
	for child: Node in _grid.get_children(): _grid.remove_child(child); child.queue_free()
	for ship: ShipDefinition in ShipCatalog.all_forms():
		if ship.is_player != _player: continue
		var card: VBoxContainer = VBoxContainer.new()
		card.custom_minimum_size.x = 280
		_grid.add_child(card)
		var preview: EditorShipPreview = EditorShipPreview.new()
		preview.custom_minimum_size = Vector2(260, 110)
		card.add_child(preview)
		preview.set_zoom(0.6561 if _minimum else 1)
		preview.set_ship(ship)
		var label: Label = Label.new()
		label.text = "%s · T%d · %s\n%s · %s · %.0f px" % [ship.display_name, ship.tier, ship.role, ship.element, ship.faction, ship.footprint]
		label.modulate = ShipCatalog.get_color("player" if ship.is_player else ship.element)
		card.add_child(label)
