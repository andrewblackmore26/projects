class_name GalleryCompare
extends Control
## Compare mode (spec §12.5): 2-4 pinned ships side by side at ONE matched scale, all driven by the
## same tick (checking a tier's hulls read distinguishable, or an element's family reads as one).

const MATCH_PX_PER_UNIT: float = 0.9
var _row: HBoxContainer
var _renderers: Array[ShipRenderer] = []
var _tick: int = 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row = HBoxContainer.new()
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_row)
	set_process(true)

func _process(_delta: float) -> void:
	_tick += 1
	for renderer: ShipRenderer in _renderers: renderer.set_motion_tick(_tick)

func set_entries(entries: Array[Dictionary]) -> void:
	for child: Node in _row.get_children(): child.queue_free()
	_renderers.clear()
	for entry: Dictionary in entries:
		var ship: ShipDefinition = entry.get("ship")
		if ship == null: continue
		var column: VBoxContainer = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_row.add_child(column)
		var caption: Label = Label.new()
		caption.text = "%s\nT%d %s" % [str(entry.get("name", "?")), int(entry.get("tier", 0)), str(entry.get("archetype", ""))]
		column.add_child(caption)
		var stage: Control = Control.new()
		stage.custom_minimum_size = Vector2(220, 220)
		column.add_child(stage)
		var renderer: ShipRenderer = ShipRenderer.new()
		renderer.position = Vector2(110, 110)
		renderer.visual_scale = MATCH_PX_PER_UNIT
		stage.add_child(renderer)
		renderer.set_ship(ship)
		_renderers.append(renderer)
