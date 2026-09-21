class_name ShipCanvas
extends Control
## A ring diagram over the production renderer (ship design spec §11). No drag handles: rail hulls
## are edited through the tabs, never by moving a circle. Clicking picks the core, a rail or a slot;
## the picking maths is a static pure function so it is testable without a scene tree.

signal slot_selected(rail: int, slot: int)
signal rail_selected(rail: int)
signal core_selected

var definition: ShipDefinition # the grammar (`working`): what the overlay draws and picks against
var compiled: ShipDefinition   # the compiled hull (`compiled`): what the production renderer draws
var zoom: float = 1.0
var preview: EditorShipPreview
var _overlay: Control
var selection: Dictionary = {"rail": -1, "slot": -1}

func _ready() -> void:
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	preview = EditorShipPreview.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview)
	if preview.renderer != null: preview.renderer.rotation = 0.0
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	resized.connect(func() -> void: _fit_zoom(); _overlay.queue_redraw())

func set_ship(ship: ShipDefinition, compiled_ship: ShipDefinition) -> void:
	definition = ship
	compiled = compiled_ship
	if preview != null: preview.set_ship(compiled_ship, true)
	_fit_zoom()
	if _overlay != null: _overlay.queue_redraw()

func select_rail(rail: int) -> void:
	selection = {"rail": rail, "slot": -1}
	if _overlay != null: _overlay.queue_redraw()

func select_slot(rail: int, slot: int) -> void:
	selection = {"rail": rail, "slot": slot}
	if _overlay != null: _overlay.queue_redraw()

func select_core() -> void:
	selection = {"rail": -1, "slot": -1}
	if _overlay != null: _overlay.queue_redraw()

## Fits the outermost used (or, with none used, the innermost addable) rail radius to the canvas.
func _fit_zoom() -> void:
	if definition == null or size.x <= 0 or size.y <= 0: return
	var outer: float = float(ShipGrammar.RAIL_RADII[0])
	for rail: RailDefinition in definition.rails: outer = maxf(outer, float(rail.radius))
	var half: float = minf(size.x, size.y) * 0.5 - 12.0
	zoom = clampf(half / outer, 0.4, 6.0)
	if preview != null: preview.set_zoom(zoom)

# ------------------------------------------------------------- picking (static, pure, testable)

## r < 34 selects the core; else the nearest rail within +-10 px; within it, the slot nearest the
## click's angle if the click lands within 12 px of that slot's rest-pose centre, else the rail.
static func pick(point: Vector2, ship: ShipDefinition) -> Dictionary:
	if point.length() < 34.0: return {"kind": "core", "rail": -1, "slot": -1}
	var best_rail: int = -1
	var best_distance: float = INF
	for r: int in range(ship.rails.size()):
		var local: Vector2 = point - ship.rails[r].offset
		var distance: float = absf(local.length() - float(ship.rails[r].radius))
		if distance <= 10.0 and distance < best_distance:
			best_distance = distance
			best_rail = r
	if best_rail == -1: return {"kind": "none", "rail": -1, "slot": -1}
	var rail: RailDefinition = ship.rails[best_rail]
	var local: Vector2 = point - rail.offset
	var angle: float = atan2(local.x, -local.y)
	var order: int = maxi(1, rail.order)
	var step: float = TAU / float(order)
	var slot_index: int = posmod(int(round((angle - rail.phase) / step)), order)
	var slot_angle: float = rail.phase + float(slot_index) * step
	var slot_pos: Vector2 = rail.offset + Vector2(sin(slot_angle), -cos(slot_angle)) * float(rail.radius)
	if point.distance_to(slot_pos) <= 12.0: return {"kind": "slot", "rail": best_rail, "slot": slot_index}
	return {"kind": "rail", "rail": best_rail, "slot": -1}

func _gui_input(event: InputEvent) -> void:
	if definition == null: return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = (event.position - size * 0.5) / zoom
		var hit: Dictionary = pick(local, definition)
		match str(hit.kind):
			"core": select_core(); core_selected.emit()
			"rail": select_rail(int(hit.rail)); rail_selected.emit(int(hit.rail))
			"slot": select_slot(int(hit.rail), int(hit.slot)); slot_selected.emit(int(hit.rail), int(hit.slot))
		accept_event()

# ------------------------------------------------------------- drawing

func _draw_overlay() -> void:
	if definition == null: return
	var center: Vector2 = size * 0.5
	var chassis: Color = ShipCatalog.get_color(definition.chassis_color if definition.chassis_color != "" else "neutral")
	var used_radii: Dictionary = {}
	for rail: RailDefinition in definition.rails: used_radii[rail.radius] = true
	for radius: int in ShipGrammar.RAIL_RADII:
		var used: bool = used_radii.has(radius)
		var colour: Color = chassis if used else Color(chassis, 0.15)
		_overlay.draw_arc(center, float(radius) * zoom, 0, TAU, 96, colour, 1.0, true)
	# Forward arrow, and the mirror axis for players.
	_overlay.draw_line(center, center + Vector2(0, -float(ShipGrammar.RAIL_RADII[0]) * 0.6 * zoom), Color(chassis, 0.6), 1.5)
	if definition.faction == "player": _overlay.draw_line(center, center + Vector2(0, -float(ShipGrammar.RAIL_RADII[-1] if definition.rails.is_empty() else definition.rails[-1].radius) * zoom), Color(1, 1, 1, 0.2), 1.0)
	var illegal_where: Dictionary = {}
	for mount: Dictionary in ShipGrammar.illegal_mounts(definition): illegal_where[str(mount.where)] = true
	for r: int in range(definition.rails.size()):
		var rail: RailDefinition = definition.rails[r]
		var rail_centre: Vector2 = center + rail.offset * zoom
		var order: int = maxi(1, rail.order)
		var step: float = TAU / float(order)
		var selected_rail: bool = int(selection.get("rail", -1)) == r
		if selected_rail and int(selection.get("slot", -1)) < 0: _overlay.draw_arc(rail_centre, float(rail.radius) * zoom, 0, TAU, 96, Color("dcf5ff"), 2.0, true)
		for j: int in range(rail.slots.size()):
			var slot: SlotDefinition = rail.slots[j]
			var angle: float = rail.phase + float(j) * step
			var pos: Vector2 = rail_centre + Vector2(sin(angle), -cos(angle)) * float(rail.radius) * zoom
			var illegal: bool = illegal_where.has("rail %d slot %d" % [r + 1, j])
			var mark_colour: Color = Color("ff5436") if illegal else chassis
			match slot.type:
				"hub":
					_overlay.draw_arc(pos, 6.0 * zoom, 0, TAU, 24, mark_colour, 2.0, true)
					for tick: int in range(maxi(1, slot.pods)): _overlay.draw_arc(pos, 9.0 * zoom, 0, TAU, 8, Color(mark_colour, 0.5), 1.0, true)
				"node": _overlay.draw_circle(pos, 3.0 * zoom, mark_colour)
				_: _overlay.draw_arc(pos, 3.0 * zoom, 0, TAU, 12, Color(mark_colour, 0.35), 1.0, true)
			if int(selection.get("rail", -1)) == r and int(selection.get("slot", -1)) == j: _overlay.draw_arc(pos, 8.0 * zoom, 0, TAU, 16, Color("dcf5ff"), 2.0, true)
	if illegal_where.has("the core"): _overlay.draw_arc(center, float(ShipGrammar.CORE_RADII[0]) * zoom, 0, TAU, 64, Color("ff5436", 0.6), 2.0, true)
