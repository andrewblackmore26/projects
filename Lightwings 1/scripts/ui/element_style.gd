class_name ElementStyle
extends RefCounted
## How the INTERFACE shows an element (modernization M15): its colour and its glyph. The one place
## the colourblind-safe palette lives. UI-side only: the ships, bullets and arena keep
## VisualStyle's palette whatever this says (recolouring the sim's art is out of scope; a
## colourblind player reads an enemy's element from the glyphs on menus, cards and the dialogue
## box, not from the ship).
##
## - `colorblind` (setting `colorblind`, main.gd's apply_settings sets it): swaps the element
##   colours for an Okabe-Ito set, lifted for a dark background, whose five hues stay apart under
##   protan, deutan and tritan simulation.
## - Every element also has a GLYPH (`draw_glyph`), drawn wherever the UI names an element, so the
##   colour is never the only carrier of the information.

static var colorblind: bool = false

## Okabe & Ito (2008) "Color Universal Design", lightened where the original is too dark on
## #050507: yellow, vermillion, bluish green, grey and reddish purple.
const SAFE: Dictionary = {
	"lightning": Color("f0e442"), "fire": Color("e8702a"), "corruption": Color("2fc29b"),
	"void": Color("c4c4c4"), "plasma": Color("e08fc4"),
}
const NAMES: Dictionary = {"lightning": "Lightning", "fire": "Fire", "corruption": "Corruption", "void": "Void", "plasma": "Plasma"}

## The UI colour of `element` ("companion", "neutral" and unknown ids are the neutral silver).
static func color(element: String) -> Color:
	if colorblind and SAFE.has(element): return SAFE[element]
	if element in ["companion", "neutral", ""]: return VisualStyle.SILVER
	return ShipCatalog.get_color(element)

static func display_name(element: String) -> String:
	return str(NAMES.get(element, element.capitalize() if not element.is_empty() else "Neutral"))

## The element's glyph, fitted in a circle of `radius` around `center`. Shapes, not letters, so they
## read at 10 px: lightning a bolt, fire a flame, corruption a three-node network, void an eclipse,
## plasma a diamond in its orbit; anything else a single bead.
static func draw_glyph(canvas: CanvasItem, element: String, center: Vector2, radius: float, ink: Color, width: float = 2.0) -> void:
	var r: float = radius
	match element:
		"lightning":
			var bolt := PackedVector2Array([Vector2(0.18, -1.0), Vector2(-0.42, 0.08), Vector2(0.02, 0.08), Vector2(-0.2, 1.0), Vector2(0.46, -0.16), Vector2(0.02, -0.16), Vector2(0.18, -1.0)])
			canvas.draw_colored_polygon(_scaled(bolt, center, r * 0.92), ink)
		"fire":
			# A teardrop: round below, drawn to a point above, with a filled inner drop.
			var flame := PackedVector2Array([Vector2(0, -1.0), Vector2(0.3, -0.48), Vector2(0.58, 0.02), Vector2(0.6, 0.4), Vector2(0.38, 0.76), Vector2(0, 0.9), Vector2(-0.38, 0.76), Vector2(-0.6, 0.4), Vector2(-0.58, 0.02), Vector2(-0.3, -0.48), Vector2(0, -1.0)])
			canvas.draw_polyline(_scaled(flame, center, r * 0.95), ink, width, true)
			var core := PackedVector2Array([Vector2(0, -0.2), Vector2(0.26, 0.3), Vector2(0.2, 0.58), Vector2(0, 0.68), Vector2(-0.2, 0.58), Vector2(-0.26, 0.3)])
			canvas.draw_colored_polygon(_scaled(core, center, r * 0.95), ink)
		"corruption":
			var nodes: Array[Vector2] = [Vector2(0, -0.72), Vector2(-0.66, 0.5), Vector2(0.66, 0.5)]
			for node: Vector2 in nodes: canvas.draw_line(center, center + node * r * 0.78, ink, width, true)
			for node: Vector2 in nodes: canvas.draw_circle(center + node * r * 0.8, r * 0.22, ink)
			canvas.draw_circle(center, r * 0.14, ink)
		"void":
			canvas.draw_arc(center, r * 0.8, 0.0, TAU, 40, ink, width, true)
			canvas.draw_circle(center + Vector2(r * 0.22, -r * 0.1), r * 0.5, ink)
		"plasma":
			var diamond := PackedVector2Array([Vector2(0, -0.62), Vector2(0.42, 0), Vector2(0, 0.62), Vector2(-0.42, 0)])
			canvas.draw_colored_polygon(_scaled(diamond, center, r), ink)
			var orbit := PackedVector2Array()
			for step: int in range(41):
				var t: float = TAU * step / 40.0
				orbit.append(Vector2(cos(t) * 0.95, sin(t) * 0.36).rotated(-0.5))
			canvas.draw_polyline(_scaled(orbit, center, r), ink, maxf(1.0, width * 0.75), true)
		_:
			canvas.draw_arc(center, r * 0.62, 0.0, TAU, 32, ink, width, true)
			canvas.draw_circle(center, r * 0.22, ink)

## A padlock of height `size` centred on `center`.
static func draw_lock(canvas: CanvasItem, center: Vector2, size: float, ink: Color) -> void:
	var body := Rect2(center + Vector2(-size * 0.36, -size * 0.06), Vector2(size * 0.72, size * 0.56))
	canvas.draw_arc(center + Vector2(0, -size * 0.06), size * 0.24, PI, TAU, 16, ink, maxf(1.5, size * 0.1), true)
	canvas.draw_rect(body, ink)
	canvas.draw_circle(body.get_center(), size * 0.07, Color(0, 0, 0, 0.8))

static func _scaled(points: PackedVector2Array, center: Vector2, scale: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points: result.append(center + point * scale)
	return result
