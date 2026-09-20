class_name ShipCanvas
extends Control

signal object_dropped(id: String, kind: String, point: Vector2)
signal part_selected(index: int)
signal drag_started
signal part_dragged(index: int, point: Vector2)
signal drag_finished

var definition: ShipDefinition
var selected: int = -1
var zoom: float = 3.5
var preview: EditorShipPreview
var _dragging: bool = false
var _offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	preview = EditorShipPreview.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(preview)
	preview.set_zoom(zoom)
	if preview.renderer != null: preview.renderer.rotation = PI * 0.5
	var overlay: Control = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	# Control draw runs before children; use a transparent child for selection handles.
	overlay.draw.connect(func() -> void: _draw_handles(overlay))
	resized.connect(func() -> void: overlay.queue_redraw())
	set_meta("overlay", overlay)

func set_ship(ship: ShipDefinition, animate: bool = false) -> void:
	definition = ship
	if preview != null:
		preview.set_ship(ship, animate)
	_redraw_handles()

func select(index: int) -> void:
	selected = index
	_redraw_handles()

func set_zoom(value: float) -> void:
	zoom = value
	preview.set_zoom(value)
	_redraw_handles()

func _redraw_handles() -> void:
	if has_meta("overlay"):
		var overlay: Control = get_meta("overlay")
		overlay.queue_redraw()

func _draw_handles(overlay: Control) -> void:
	var center: Vector2 = size * 0.5
	for radius: int in range(20, 181, 20): overlay.draw_arc(center, radius * zoom, 0, TAU, 96, Color(0.4, 0.6, 0.7, 0.12), 1, true)
	overlay.draw_line(Vector2(0, center.y), Vector2(size.x, center.y), Color(0.4, 0.6, 0.7, 0.25), 1)
	overlay.draw_line(Vector2(size.x - 20, center.y - 6), Vector2(size.x - 8, center.y), Color(0.5, 0.8, 0.9, 0.6), 1)
	overlay.draw_line(Vector2(size.x - 20, center.y + 6), Vector2(size.x - 8, center.y), Color(0.5, 0.8, 0.9, 0.6), 1)
	overlay.draw_line(center + Vector2(-9, 0), center + Vector2(9, 0), Color(0.55, 0.7, 0.8, 0.2), 1)
	overlay.draw_line(center + Vector2(0, -9), center + Vector2(0, 9), Color(0.55, 0.7, 0.8, 0.2), 1)
	if definition == null or selected < 0 or selected >= definition.parts.size():
		return
	var part: PartDefinition = definition.parts[selected]
	if part.shape == "line": return
	var p: Vector2 = center + part.position.rotated(PI * 0.5) * zoom
	var extent: Vector2 = Vector2.ONE * part.radius * 2.0
	var bounds: Rect2 = Rect2(p - extent * zoom * 0.5 - Vector2(5, 5), extent * zoom + Vector2(10, 10))
	overlay.draw_rect(bounds, Color(0.5, 0.83, 1, 0.45), false, 1)
	for point: Vector2 in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		overlay.draw_rect(Rect2(point - Vector2(2, 2), Vector2(4, 4)), Color("dcf5ff"))

func _gui_input(event: InputEvent) -> void:
	if definition == null: return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			set_zoom(minf(8, zoom + 0.25))
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			set_zoom(maxf(1, zoom - 0.25))
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				var local: Vector2 = ((button.position - size * 0.5) / zoom).rotated(-PI * 0.5)
				var index: int = _pick(local)
				selected = index
				part_selected.emit(index)
				if index >= 0:
					_offset = definition.parts[index].position - local
					_dragging = definition.parts[index].shape != "line"
					if _dragging: drag_started.emit()
				_redraw_handles()
			elif _dragging:
				_dragging = false
				drag_finished.emit()
			accept_event()
	elif event is InputEventMouseMotion and _dragging and selected >= 0:
		var motion: InputEventMouseMotion = event
		var point: Vector2 = ((motion.position - size * 0.5) / zoom).rotated(-PI * 0.5) + _offset
		if not motion.shift_pressed: point = point.snapped(Vector2.ONE)
		part_dragged.emit(selected, point)
		_redraw_handles()
		accept_event()

func _pick(point: Vector2) -> int:
	var best: int = -1
	var best_layer: int = -999
	for index: int in range(definition.parts.size()):
		var part: PartDefinition = definition.parts[index]
		if part.shape == "line": continue
		var local: Vector2 = point - part.position
		var hit: bool = false
		if not part.filled:
			hit = absf(local.length() - part.radius) < 3.0
		else:
			var polygon: PackedVector2Array = ShipGeometry.outline(part.shape, part.radius)
			hit = Geometry2D.is_point_in_polygon(local, polygon) if polygon.size() >= 3 else false
		if hit and part.layer >= best_layer:
			best = index
			best_layer = part.layer
	return best

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("ship_object") and data.has("kind")
func _drop_data(position: Vector2, data: Variant) -> void:
	object_dropped.emit(str(data.ship_object), str(data.kind), ((position - size * 0.5) / zoom).rotated(-PI * 0.5))
