extends Control
## S6 gallery (spec §12): a browser for every ship in the project. Replaces the old single-toggle
## library window. `_entries` is the current `GalleryModel.scan()`; `_filtered` is what is on screen.

const TILE_CAP: int = 24

var _entries: Array[Dictionary] = []
var _filtered: Array[Dictionary] = []
var _tiles: Array[GalleryTile] = []
var _pinned: Dictionary = {} # id -> entry
var _criteria: Dictionary = {}
var _sort_key: String = "name"
var _sort_desc: bool = false
var _true_scale: bool = false
var _signature: int = -1
var _grid: GridContainer
var _scroll: ScrollContainer
var _status: Label
var _search: LineEdit
var _faction: OptionButton
var _chassis: OptionButton
var _accent: OptionButton
var _tier: OptionButton
var _archetype: OptionButton
var _rail_count: OptionButton
var _piece: LineEdit
var _status_filter: OptionButton
var _true_scale_toggle: CheckButton
var _detail_window: Window
var _compare_window: Window
var _coverage_window: Window

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
	title.text = "LIGHTSHIP GALLERY — %s" % ShipCatalog.catalog_root
	title.add_theme_font_size_override("font_size", 22)
	layout.add_child(title)

	_build_toolbar(layout)

	_status = Label.new()
	layout.add_child(_status)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 3 # four overflowed a 1280 px window sideways and clipped the last column (seen in the first capture)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)

	var timer: Timer = Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_poll_reload)
	add_child(timer)
	timer.start()
	set_process(true)

	_apply_catalog_root_from_args()
	_rescan()
	_handle_export_args()

func _build_toolbar(layout: VBoxContainer) -> void:
	var row1: HBoxContainer = HBoxContainer.new()
	layout.add_child(row1)
	_search = LineEdit.new()
	_search.placeholder_text = "Search name or id"
	_search.text_changed.connect(func(_t: String) -> void: _apply())
	row1.add_child(_search)
	_faction = _option(row1, ["", "player", "enemy", "elite", "boss"])
	_chassis = _option(row1, [""] + Elements.COLOR_KEYS)
	_accent = _option(row1, ["", "none"] + Elements.COLOR_KEYS)
	_archetype = _option(row1, [""] + ShipGrammar.ARCHETYPES)
	_tier = _option(row1, ["0", "1", "2", "3", "4", "5", "6"])
	_rail_count = _option(row1, ["-1", "0", "1", "2", "3", "4"])
	_piece = LineEdit.new()
	_piece.placeholder_text = "Set piece id"
	_piece.text_changed.connect(func(_t: String) -> void: _apply())
	row1.add_child(_piece)
	_status_filter = _option(row1, ["", "valid", "invalid", "warnings"])

	var row2: HBoxContainer = HBoxContainer.new()
	layout.add_child(row2)
	var sort_picker: OptionButton = _option(row2, ["tier", "footprint", "circles", "name", "modified"])
	sort_picker.selected = 3
	sort_picker.item_selected.connect(func(index: int) -> void: _sort_key = sort_picker.get_item_text(index); _apply())
	var desc_toggle: CheckButton = CheckButton.new()
	desc_toggle.text = "Descending"
	desc_toggle.toggled.connect(func(v: bool) -> void: _sort_desc = v; _apply())
	row2.add_child(desc_toggle)
	_true_scale_toggle = CheckButton.new()
	_true_scale_toggle.text = "True scale"
	_true_scale_toggle.toggled.connect(func(v: bool) -> void: _true_scale = v; _rebuild_tiles())
	row2.add_child(_true_scale_toggle)
	var coverage_button: Button = Button.new()
	coverage_button.text = "Roster coverage"
	coverage_button.pressed.connect(_show_coverage)
	row2.add_child(coverage_button)
	var compare_button: Button = Button.new()
	compare_button.text = "Compare pinned"
	compare_button.pressed.connect(_show_compare)
	row2.add_child(compare_button)
	var export_sheet: Button = Button.new()
	export_sheet.text = "Export contact sheet PNG"
	export_sheet.pressed.connect(func() -> void: _export_contact_sheet("user://gallery_contact_sheet.png"))
	row2.add_child(export_sheet)
	var editor_button: Button = Button.new()
	editor_button.text = "Open ship workshop"
	editor_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/ship_editor.tscn"))
	row2.add_child(editor_button)

func _option(parent: Node, values: Array) -> OptionButton:
	var picker: OptionButton = OptionButton.new()
	for value: Variant in values: picker.add_item(str(value) if str(value) != "" else "(any)")
	picker.item_selected.connect(func(_i: int) -> void: _apply())
	parent.add_child(picker)
	return picker

func _apply_catalog_root_from_args() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--catalog-root="): ShipCatalog.catalog_root = argument.trim_prefix("--catalog-root=")
		if argument == "--true-scale": _true_scale = true

func _selected(picker: OptionButton) -> String:
	var text: String = picker.get_item_text(picker.selected)
	return "" if text == "(any)" else text

func _apply() -> void:
	_criteria = {}
	if _search.text.strip_edges() != "": _criteria.search = _search.text
	if _selected(_faction) != "": _criteria.faction = _selected(_faction)
	if _selected(_chassis) != "": _criteria.chassis = _selected(_chassis)
	if _selected(_accent) != "": _criteria.accent = _selected(_accent)
	if _selected(_archetype) != "": _criteria.archetype = _selected(_archetype)
	var tier_value: int = int(_selected(_tier)) if _selected(_tier) != "" else 0
	if tier_value > 0: _criteria.tier = tier_value
	var rail_value: int = int(_selected(_rail_count)) if _selected(_rail_count) != "" else -1
	if rail_value >= 0: _criteria.rail_count = rail_value
	if _piece.text.strip_edges() != "": _criteria.set_piece = _piece.text
	if _selected(_status_filter) != "": _criteria.status = _selected(_status_filter)
	_filtered = GalleryModel.sort(GalleryModel.filter(_entries, _criteria), _sort_key, _sort_desc)
	_status.text = "%d / %d ships shown" % [_filtered.size(), _entries.size()]
	_rebuild_tiles()

func _rescan() -> void:
	_entries = GalleryModel.scan(ShipCatalog.catalog_root)
	_signature = GalleryModel.signature(ShipCatalog.catalog_root)
	_apply()

func _poll_reload() -> void:
	var current: int = GalleryModel.signature(ShipCatalog.catalog_root)
	if current != _signature: _rescan()

func _rebuild_tiles() -> void:
	for tile: GalleryTile in _tiles: tile.queue_free()
	_tiles.clear()
	for entry: Dictionary in _filtered:
		var tile: GalleryTile = GalleryTile.new()
		_grid.add_child(tile)
		tile.set_entry(entry, _true_scale)
		tile.set_pinned(_pinned.has(entry.id))
		tile.opened.connect(_open_detail)
		tile.pin_toggled.connect(_on_pin_toggled)
		_tiles.append(tile)
	call_deferred("_update_animating")

func _process(_delta: float) -> void:
	_update_animating()

func _update_animating() -> void:
	if _tiles.is_empty(): return
	var visible_rect: Rect2 = Rect2(_scroll.scroll_horizontal, _scroll.scroll_vertical, _scroll.size.x, _scroll.size.y)
	var rects: Array[Rect2] = []
	for tile: GalleryTile in _tiles: rects.append(Rect2(tile.position, tile.size))
	var scheduled: PackedInt32Array = GalleryModel.animating(visible_rect, rects, TILE_CAP)
	var on: Dictionary = {}
	for index: int in scheduled: on[index] = true
	for i: int in range(_tiles.size()): _tiles[i].set_animating(on.has(i))

func _on_pin_toggled(entry: Dictionary, pinned: bool) -> void:
	if pinned: _pinned[entry.id] = entry
	else: _pinned.erase(entry.id)

func _open_detail(entry: Dictionary) -> void:
	if is_instance_valid(_detail_window): _detail_window.queue_free()
	_detail_window = Window.new()
	_detail_window.title = "Ship detail — %s" % str(entry.get("name", entry.get("id", "")))
	_detail_window.size = Vector2i(900, 620)
	_detail_window.close_requested.connect(func() -> void: _detail_window.queue_free())
	add_child(_detail_window)
	var detail: GalleryDetail = GalleryDetail.new()
	detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_window.add_child(detail)
	detail.set_entry(entry)
	detail.open_in_editor.connect(_open_editor_with)
	_detail_window.popup_centered()

func _show_compare() -> void:
	if is_instance_valid(_compare_window): _compare_window.queue_free()
	_compare_window = Window.new()
	_compare_window.title = "Compare pinned ships"
	_compare_window.size = Vector2i(960, 420)
	_compare_window.close_requested.connect(func() -> void: _compare_window.queue_free())
	add_child(_compare_window)
	var compare: GalleryCompare = GalleryCompare.new()
	compare.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_compare_window.add_child(compare)
	var chosen: Array[Dictionary] = []
	for id: String in _pinned: chosen.append(_pinned[id])
	compare.set_entries(chosen.slice(0, 4))
	_compare_window.popup_centered()

func _show_coverage() -> void:
	if is_instance_valid(_coverage_window): _coverage_window.queue_free()
	_coverage_window = Window.new()
	_coverage_window.title = "Roster coverage"
	_coverage_window.size = Vector2i(700, 500)
	_coverage_window.close_requested.connect(func() -> void: _coverage_window.queue_free())
	add_child(_coverage_window)
	var manifest: Array[Dictionary] = ShipGenerator.roster_manifest()
	var coverage: Dictionary = GalleryModel.coverage(_entries, manifest)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_coverage_window.add_child(scroll)
	var grid: GridContainer = GridContainer.new()
	grid.columns = int(coverage.max_tier) + 1
	scroll.add_child(grid)
	grid.add_child(Label.new())
	for tier: int in range(1, int(coverage.max_tier) + 1):
		var tier_label: Label = Label.new()
		tier_label.text = "T%d" % tier
		grid.add_child(tier_label)
	for element: String in coverage.elements:
		var element_label: Label = Label.new()
		element_label.text = element
		grid.add_child(element_label)
		for tier: int in range(1, int(coverage.max_tier) + 1):
			var cell: Dictionary = {}
			for candidate: Dictionary in coverage.cells:
				if str(candidate.element) == element and int(candidate.tier) == tier: cell = candidate
			var button: Button = Button.new()
			button.text = str(cell.get("count", 0))
			if not bool(cell.get("filled", false)):
				button.modulate = Color("ff8f7a")
				var suggestion: Dictionary = cell.get("suggestion", {})
				button.pressed.connect(func() -> void: _open_editor_seeded(suggestion))
			else:
				button.disabled = true
			grid.add_child(button)
	_coverage_window.popup_centered()

func _open_editor_with(entry: Dictionary) -> void:
	GalleryEditorSeed.pending_path = str(entry.get("path", ""))
	get_tree().change_scene_to_file("res://scenes/ship_editor.tscn")

func _open_editor_seeded(suggestion: Dictionary) -> void:
	GalleryEditorSeed.pending_seed = suggestion
	get_tree().change_scene_to_file("res://scenes/ship_editor.tscn")

# ------------------------------------------------------------- export (§12.7)

func _handle_export_args() -> void:
	var export_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--gallery-export="): export_path = argument.trim_prefix("--gallery-export=")
	if export_path == "": return
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await _export_contact_sheet(export_path)
	get_tree().quit(0)

## The WHOLE filtered set, not one screen: the scroll area is captured page by page and the pages
## are stitched. (The first version saved the viewport as it stood - 8 tiles of 141 - which is no
## use as a review sheet.) Tiles are scheduled to animate only while visible, so each page is given
## three rendered frames to wake and draw before it is read.
func _export_contact_sheet(path: String) -> void:
	var area: Rect2i = Rect2i(_scroll.get_global_rect())
	var content: int = int(_grid.size.y)
	var page: int = maxi(1, area.size.y)
	var sheet: Image = Image.create(area.size.x, maxi(page, content), false, Image.FORMAT_RGB8)
	var offset: int = 0
	while offset < content:
		_scroll.scroll_vertical = offset
		for i: int in range(3):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		# The container clamps the last page, so read back where it really scrolled to.
		var actual: int = _scroll.scroll_vertical
		var frame: Image = get_viewport().get_texture().get_image().get_region(area)
		_linear_to_srgb_per_pixel(frame)
		frame.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(frame, Rect2i(0, 0, area.size.x, mini(page, content - actual)), Vector2i(0, actual))
		offset += page
	_scroll.scroll_vertical = 0
	var result: Error = sheet.save_png(path)
	print("GALLERY EXPORT ", path, " ", error_string(result), " ", sheet.get_width(), "x", sheet.get_height(), " pages=", int(ceil(float(content) / float(page))))

## `Image.linear_to_srgb()` only accepts 8-bit data, by which point the darks are already crushed:
## walk the HDR floats and convert per pixel through `Color.linear_to_srgb()` instead.
func _linear_to_srgb_per_pixel(image: Image) -> void:
	if image.get_format() != Image.FORMAT_RGBAF and image.get_format() != Image.FORMAT_RGBH: return
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			image.set_pixel(x, y, image.get_pixel(x, y).linear_to_srgb())
