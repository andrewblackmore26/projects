class_name GalleryTile
extends PanelContainer
## One gallery contact-sheet tile (spec §12.1): a LIVE ShipRenderer (one draw call per ship) plus
## name/id, faction badge, two colour swatches, tier/archetype, circle/rail/footprint counts, set
## piece labels and a validation mark.

signal opened(entry: Dictionary)
signal pin_toggled(entry: Dictionary, pinned: bool)

const STAGE_SIZE: Vector2 = Vector2(220, 140)
const TRUE_SCALE_PX_PER_UNIT: float = 0.9

var entry: Dictionary = {}
var _stage: Control
var _renderer: ShipRenderer
var _pin_button: CheckButton
var _mark: Label
var _name_label: Label
var _meta_label: Label
var _swatches: HBoxContainer
var _pieces_label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(240, 220)
	var layout: VBoxContainer = VBoxContainer.new()
	add_child(layout)
	_stage = Control.new()
	_stage.custom_minimum_size = STAGE_SIZE
	_stage.clip_contents = true
	layout.add_child(_stage)
	_renderer = ShipRenderer.new()
	_stage.add_child(_renderer)
	var header: HBoxContainer = HBoxContainer.new()
	layout.add_child(header)
	_mark = Label.new()
	header.add_child(_mark)
	_name_label = Label.new()
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_name_label)
	_pin_button = CheckButton.new()
	_pin_button.text = "Pin"
	_pin_button.toggled.connect(func(on: bool) -> void: pin_toggled.emit(entry, on))
	header.add_child(_pin_button)
	_meta_label = Label.new()
	_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_meta_label)
	_swatches = HBoxContainer.new()
	layout.add_child(_swatches)
	_pieces_label = Label.new()
	_pieces_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_pieces_label)
	var open_button: Button = Button.new()
	open_button.text = "Open"
	open_button.pressed.connect(func() -> void: opened.emit(entry))
	layout.add_child(open_button)
	var stage_click: Button = Button.new()
	stage_click.flat = true
	stage_click.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage_click.pressed.connect(func() -> void: opened.emit(entry))
	_stage.add_child(stage_click)
	if not entry.is_empty(): set_entry(entry, false)

func set_entry(new_entry: Dictionary, true_scale: bool) -> void:
	entry = new_entry
	if _renderer == null: return # set before _ready
	_renderer.position = STAGE_SIZE * 0.5
	if entry.get("ship") == null:
		_renderer.definition = null
		_renderer.visible = false
	else:
		_renderer.visible = true
		_renderer.set_ship(entry.ship)
		_renderer.visual_scale = _scale_for(entry, true_scale)
	_apply_labels()

func _scale_for(current: Dictionary, true_scale: bool) -> float:
	var footprint: float = maxf(1.0, float(current.get("footprint", 48.0)))
	if true_scale: return TRUE_SCALE_PX_PER_UNIT
	# Off: uniform tile size, each ship scaled to fit the stage.
	return clampf((minf(STAGE_SIZE.x, STAGE_SIZE.y) * 0.85) / footprint, 0.05, 4.0)

func set_animating(on: bool) -> void:
	if _renderer != null: _renderer.set_process(on)

func _apply_labels() -> void:
	_name_label.text = "%s\n%s" % [str(entry.get("name", "?")), str(entry.get("id", "?"))]
	_mark.text = "[OK]" if entry.get("status", "invalid") == "valid" else ("[warn]" if entry.get("status") == "warnings" else "[X %s]" % _first_error_code())
	_mark.modulate = Color("96d8b2") if entry.get("status") == "valid" else (Color("ffd27a") if entry.get("status") == "warnings" else Color("ff8f7a"))
	_meta_label.text = "%s · T%d · %s\ncircles %d · rails %d · footprint %.0fpx" % [
		str(entry.get("faction", "?")), int(entry.get("tier", 0)), str(entry.get("archetype", "-")),
		int(entry.get("circles", 0)), int(entry.get("rails", 0)), float(entry.get("footprint", 0.0))]
	for child: Node in _swatches.get_children(): child.queue_free()
	for role: String in [str(entry.get("chassis", "")), str(entry.get("accent", ""))]:
		if role == "": continue
		var swatch: ColorRect = ColorRect.new()
		swatch.custom_minimum_size = Vector2(18, 18)
		swatch.color = ShipCatalog.get_color(role)
		_swatches.add_child(swatch)
	var names: Array = entry.get("set_pieces", [])
	_pieces_label.text = "pieces: " + (", ".join(names) if not names.is_empty() else "none")

func _first_error_code() -> String:
	var errors: PackedStringArray = entry.get("errors", PackedStringArray())
	if errors.is_empty(): return "?"
	return String(errors[0]).split(":")[0]

func set_pinned(on: bool) -> void:
	_pin_button.set_pressed_no_signal(on)
