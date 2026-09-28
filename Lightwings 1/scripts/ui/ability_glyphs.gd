class_name AbilityGlyphs
extends RefCounted
## Procedural HUD glyph per ability (modernization M11; also S13's glyph item). A glyph is drawn in
## the ships' own vocabulary: an ability that has a set piece is drawn AS that set piece (the
## authored circles and rails of SetPieceCatalog, full arrangement, its own colours), fitted into
## a circle. Abilities with no set piece (passives, enemy mounts, the dash) use the small table
## below, written in the same [x, y, radius, filled, colour_index] / [from, to, colour_index]
## format with the same ladder radii, so there is one drawing path for both.

const HUB: int = SetPieceCatalog.HUB
const FALLBACK: Dictionary = {
	"dash": {"colours": ["blue"], "circles": [[-11, 8, 4, true, 0], [0, -9, 5, true, 0], [11, 8, 4, true, 0]], "lines": [[0, 1, 0], [1, 2, 0]]},
	"homing_beam": {"colours": ["violet"], "circles": [[0, -8, 7, false, 0], [-8, -22, 4, true, 0], [0, -32, 4, false, 0]], "lines": [[0, 1, 0], [1, 2, 0]]},
	"laser_prong": {"colours": ["red"], "circles": [[-6, -10, 4, true, 0], [6, -10, 4, true, 0], [-6, -28, 4, false, 0], [6, -28, 4, false, 0]], "lines": [[HUB, 0, 0], [HUB, 1, 0], [0, 2, 0], [1, 3, 0]]},
	"orbital_seekers": {"colours": ["red"], "circles": [[0, 0, 5, false, 0], [0, -18, 4, true, 0], [15.6, 9, 4, true, 0], [-15.6, 9, 4, true, 0]], "lines": []},
	"radar": {"colours": ["yellow"], "circles": [[0, 0, 4, true, 0], [0, 0, 12, false, 0], [12, -12, 4, true, 0]], "lines": [[0, 2, 0]]},
	"health_readout": {"colours": ["yellow"], "circles": [[-13, 0, 4, true, 0], [0, 0, 4, true, 0], [13, 0, 4, false, 0]], "lines": [[0, 1, 0], [1, 2, 0]]},
	"magnet": {"colours": ["yellow"], "circles": [[-10, -12, 4, true, 0], [10, -12, 4, true, 0], [-10, 7, 5, false, 0], [10, 7, 5, false, 0]], "lines": [[0, 2, 0], [1, 3, 0], [2, 3, 0]]},
	"siphon": {"colours": ["green"], "circles": [[0, -14, 7, false, 0], [0, 4, 4, true, 0], [0, 16, 4, true, 0]], "lines": [[0, 1, 0], [1, 2, 0]]},
	"thrusters": {"colours": ["yellow"], "circles": [[0, -10, 7, false, 0], [-9, 12, 4, true, 0], [9, 12, 4, true, 0]], "lines": [[0, 1, 0], [0, 2, 0]]},
	"forcefield": {"colours": ["red"], "circles": [[0, 0, 4, true, 0], [0, 0, 14, false, 0]], "lines": []},
}
## Anything else (enemy mounts, unknown ids): a ring and a bead, in the ability's catalogue colour.
const GENERIC: Dictionary = {"colours": ["neutral"], "circles": [[0, 4, 7, false, 0], [0, -14, 4, true, 0]], "lines": [[0, 1, 0]]}

## The shape the glyph draws, in set-piece format. `source` says where it came from.
static func shape_for(id: String) -> Dictionary:
	var piece_id: String = SetPieceCatalog.for_ability(id)
	if not piece_id.is_empty():
		var piece: Dictionary = SetPieceCatalog.get_piece(piece_id, false).duplicate()
		piece.source = "set_piece:" + piece_id
		return piece
	if FALLBACK.has(id):
		var own: Dictionary = (FALLBACK[id] as Dictionary).duplicate()
		own.source = "fallback"
		return own
	var generic: Dictionary = GENERIC.duplicate()
	generic.colours = [str(AbilityCatalog.DEFINITIONS[id][6]) if AbilityCatalog.DEFINITIONS.has(id) else "neutral"]
	generic.source = "generic"
	return generic

## Draw `id`'s glyph fitted inside a circle of `radius` around `center`.
static func draw(canvas: CanvasItem, id: String, center: Vector2, radius: float, alpha: float = 1.0) -> void:
	var shape: Dictionary = shape_for(id)
	var circles: Array = shape.get("circles", [])
	var lines: Array = shape.get("lines", [])
	var colours: Array = shape.get("colours", ["neutral"])
	var uses_hub: bool = false
	for line: Array in lines:
		if int(line[0]) == HUB or int(line[1]) == HUB: uses_hub = true
	# Fit: the bounding box of every rim (and the hub's centre when a rail starts there).
	var low: Vector2 = Vector2.INF
	var high: Vector2 = -Vector2.INF
	for bead: Array in circles:
		var at: Vector2 = Vector2(float(bead[0]), float(bead[1]))
		low = low.min(at - Vector2.ONE * float(bead[2]))
		high = high.max(at + Vector2.ONE * float(bead[2]))
	if uses_hub:
		low = low.min(Vector2.ZERO)
		high = high.max(Vector2.ZERO)
	if circles.is_empty(): return
	var middle: Vector2 = (low + high) * 0.5
	var extent: float = 0.0
	for bead: Array in circles:
		extent = maxf(extent, (Vector2(float(bead[0]), float(bead[1])) - middle).length() + float(bead[2]))
	if uses_hub: extent = maxf(extent, middle.length())
	# A lone small ring should not balloon to fill the slot: cap the scale at a 12-unit radius.
	var scale: float = minf(radius * 0.86 / maxf(extent, 0.001), radius / 12.0)
	var width: float = clampf(radius * 0.11, 1.0, 2.0)
	var point := func(index: int) -> Vector2:
		if index == HUB: return center - middle * scale
		return center + (Vector2(float(circles[index][0]), float(circles[index][1])) - middle) * scale
	var reach := func(index: int) -> float:
		return 0.0 if index == HUB else float(circles[index][2]) * scale
	for line: Array in lines:
		var from: Vector2 = point.call(int(line[0]))
		var to: Vector2 = point.call(int(line[1]))
		var along: Vector2 = (to - from).normalized()
		var start: Vector2 = from + along * float(reach.call(int(line[0])))
		var finish: Vector2 = to - along * float(reach.call(int(line[1])))
		if (finish - start).dot(along) <= 0.0: continue
		canvas.draw_line(start, finish, _ink(colours, int(line[2]), alpha), width, true)
	if uses_hub: canvas.draw_circle(point.call(HUB), maxf(1.2, 2.5 * scale), _ink(colours, 0, alpha))
	for bead: Array in circles:
		var at: Vector2 = center + (Vector2(float(bead[0]), float(bead[1])) - middle) * scale
		var size: float = maxf(1.2, float(bead[2]) * scale)
		var ink: Color = _ink(colours, int(bead[4]), alpha)
		if bool(bead[3]): canvas.draw_circle(at, size, ink)
		else: canvas.draw_arc(at, size - width * 0.5, 0.0, TAU, 24, ink, width, true)

static func _ink(colours: Array, index: int, alpha: float) -> Color:
	var key: String = str(colours[clampi(index, 0, colours.size() - 1)]) if not colours.is_empty() else "neutral"
	return Color(ShipCatalog.get_color(key), alpha)
