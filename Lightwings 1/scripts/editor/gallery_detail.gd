class_name GalleryDetail
extends Control
## Detail view (spec §12.4): a large animated render, a part tree with per-circle HP and detach
## preview, the weapon list with colour-legality flags, a motion panel with a tick scrub bar, and a
## minimum-zoom silhouette beside it.

signal open_in_editor(entry: Dictionary)

var entry: Dictionary = {}
var _renderer: ShipRenderer
var _overlay: GalleryDetachOverlay
var _silhouette: ShipRenderer
var _tree: Tree
var _weapon_label: Label
var _motion_label: Label
var _scrub: HSlider
var _rig: ShipMotion.ShipRig

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var columns: HBoxContainer = HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(columns)
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	var stage: Control = Control.new()
	stage.custom_minimum_size = Vector2(480, 360)
	left.add_child(stage)
	_renderer = ShipRenderer.new()
	_renderer.position = Vector2(240, 180)
	_renderer.visual_scale = 3.0
	stage.add_child(_renderer)
	_overlay = GalleryDetachOverlay.new()
	_overlay.target = _renderer
	_renderer.add_child(_overlay)
	var silhouette_row: HBoxContainer = HBoxContainer.new()
	left.add_child(silhouette_row)
	var silhouette_stage: Control = Control.new()
	silhouette_stage.custom_minimum_size = Vector2(160, 120)
	silhouette_row.add_child(silhouette_stage)
	_silhouette = ShipRenderer.new()
	_silhouette.position = Vector2(80, 60)
	_silhouette.visual_scale = 0.6561
	silhouette_stage.add_child(_silhouette)
	silhouette_row.add_child(_label("Silhouette check (minimum zoom 0.6561)"))
	var motion_box: VBoxContainer = VBoxContainer.new()
	left.add_child(motion_box)
	_motion_label = Label.new()
	_motion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	motion_box.add_child(_motion_label)
	_scrub = HSlider.new()
	_scrub.min_value = 0
	_scrub.max_value = 359
	_scrub.step = 1
	_scrub.value_changed.connect(func(v: float) -> void: _renderer.set_motion_tick(int(v)); _silhouette.set_motion_tick(int(v)))
	motion_box.add_child(_scrub)
	var editor_button: Button = Button.new()
	editor_button.text = "Open in editor"
	editor_button.pressed.connect(func() -> void: open_in_editor.emit(entry))
	left.add_child(editor_button)
	var export_row: HBoxContainer = HBoxContainer.new()
	left.add_child(export_row)
	var hide_rails: CheckButton = CheckButton.new()
	hide_rails.text = "Hide rails"
	hide_rails.toggled.connect(func(on: bool) -> void: _renderer.hidden_part_ids = _rail_ring_ids() if on else PackedStringArray())
	export_row.add_child(hide_rails)
	var export_button: Button = Button.new()
	export_button.text = "Export single-ship PNG"
	export_button.pressed.connect(func() -> void: _export_png("user://gallery_ship_export.png"))
	export_row.add_child(export_button)

	var right: VBoxContainer = VBoxContainer.new()
	right.custom_minimum_size.x = 320
	columns.add_child(right)
	right.add_child(_label("Part tree (hover to preview a detach)"))
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_mouse_selected.connect(func(_pos: Vector2, _button: int) -> void: _on_tree_select())
	_tree.item_selected.connect(_on_tree_select)
	right.add_child(_tree)
	right.add_child(_label("Weapons"))
	_weapon_label = Label.new()
	_weapon_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_weapon_label)

func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	return label

func set_entry(new_entry: Dictionary) -> void:
	entry = new_entry
	var ship: ShipDefinition = entry.get("ship")
	if ship == null: return
	_renderer.set_ship(ship)
	_silhouette.set_ship(ship)
	_overlay.clear()
	_rig = ShipMotion.get_rig(ship)
	_scrub.value = 0
	_renderer.set_motion_tick(0)
	_silhouette.set_motion_tick(0)
	_build_tree(ship)
	_build_weapons(ship)
	_motion_label.text = "Rail speeds: %s" % ", ".join(_rail_speed_strings(ship))

func _rail_speed_strings(ship: ShipDefinition) -> Array[String]:
	var result: Array[String] = []
	for i: int in range(ship.rails.size()):
		result.append("rail %d: %.2f rad/s @ r%d" % [i + 1, ship.rails[i].speed, ship.rails[i].radius])
	return result

func _build_tree(ship: ShipDefinition) -> void:
	_tree.clear()
	if _rig == null or _rig.ids.is_empty(): return
	var root_item: TreeItem = _tree.create_item()
	var items: Dictionary = {}
	for i: int in range(_rig.ids.size()):
		var id: String = _rig.ids[i]
		var parent_index: int = _rig.parent_index[i]
		var parent_item: TreeItem = items.get(parent_index, root_item) if parent_index >= 0 else root_item
		var item: TreeItem = _tree.create_item(parent_item)
		var hp: float = _rig.authored_hp[i]
		item.set_text(0, "%s (hp %.0f)" % [id, hp] if hp > 0 else id)
		item.set_metadata(0, i)
		items[i] = item

func _on_tree_select() -> void:
	var item: TreeItem = _tree.get_selected()
	if item == null: return
	var index: Variant = item.get_metadata(0)
	if index == null: return
	_overlay.highlight(int(index))

func _rail_ring_ids() -> PackedStringArray:
	var ship: ShipDefinition = entry.get("ship")
	var result: PackedStringArray = []
	if ship == null: return result
	for part: PartDefinition in ship.parts:
		if part.shape == "circle" and part.style == 5: result.append(part.id)
	return result

## §12.7 single-ship export: linear HDR converted PER PIXEL, not through `Image.linear_to_srgb()`
## (that call only accepts 8-bit data, by which point the darks are already crushed).
func _export_png(path: String) -> void:
	var viewport: Viewport = get_viewport()
	var image: Image = viewport.get_texture().get_image()
	if image.get_format() == Image.FORMAT_RGBAF or image.get_format() == Image.FORMAT_RGBH:
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				image.set_pixel(x, y, image.get_pixel(x, y).linear_to_srgb())
	image.convert(Image.FORMAT_RGB8)
	var result: Error = image.save_png(path)
	print("SHIP EXPORT ", path, " ", error_string(result))

func _build_weapons(ship: ShipDefinition) -> void:
	var illegal: Array[Dictionary] = ShipGrammar.illegal_mounts(ship)
	var illegal_where: Dictionary = {}
	for mount: Dictionary in illegal: illegal_where[str(mount.where)] = str(mount.needs)
	var lines: Array[String] = []
	if ship.core_weapon != "":
		var flag: String = " [ILLEGAL, needs %s]" % illegal_where["the core"] if illegal_where.has("the core") else ""
		lines.append("core: %s%s" % [ship.core_weapon, flag])
	for r: int in range(ship.rails.size()):
		for j: int in range(ship.rails[r].slots.size()):
			var slot: SlotDefinition = ship.rails[r].slots[j]
			if slot.set_piece == "": continue
			var where: String = "rail %d slot %d" % [r + 1, j]
			var flag: String = " [ILLEGAL, needs %s]" % illegal_where[where] if illegal_where.has(where) else ""
			lines.append("%s: %s%s" % [where, slot.set_piece, flag])
	_weapon_label.text = "\n".join(lines) if not lines.is_empty() else "No mounted weapons."
