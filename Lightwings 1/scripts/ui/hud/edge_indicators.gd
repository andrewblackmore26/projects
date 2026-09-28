class_name EdgeIndicators
extends RefCounted
## Edge-of-screen indicators of the floating HUD (modernization M11b): a chevron on the rim of the
## view, on the line from the ship toward something the camera does not show.
## - the node's living rival: ALWAYS, large, in its element's colour, with its distance;
## - every other living enemy: only with the `radar` passive (the pre-M11b rule);
## - every queued spawn (M13's rim spawns, CombatWorld.spawn_queue): a chevron and a converging
##   ring that brighten as the spawn comes due, so a telegraph the camera cannot see still reads.
## Positions come from the compositor's camera and the UI scale; the rim is this Control's rect
## (the safe rect) inset by RIM_INSET.

const RIM_INSET: float = 18.0
## World px per displayed metre of the boss distance.
const PX_PER_METRE: float = 10.0
## A queued spawn is shown from this many telegraph leads before it is due.
const SPAWN_LOOKAHEAD: float = 2.5

var app: Node
var root: Control
var _markers: Array[Dictionary] = []

func _init(owner: Node) -> void:
	app = owner

func build(parent: Control) -> void:
	root = Control.new()
	root.name = "EdgeIndicators"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)
	root.draw.connect(_draw)

func layout(safe: Rect2) -> void:
	root.position = safe.position
	root.size = safe.size

## Where the ray from `from` (inside `rim`) toward `to` leaves `rim`.
static func rim_point(rim: Rect2, from: Vector2, to: Vector2) -> Vector2:
	var direction: Vector2 = to - from
	var t: float = INF
	if direction.x > 0.0: t = minf(t, (rim.end.x - from.x) / direction.x)
	elif direction.x < 0.0: t = minf(t, (rim.position.x - from.x) / direction.x)
	if direction.y > 0.0: t = minf(t, (rim.end.y - from.y) / direction.y)
	elif direction.y < 0.0: t = minf(t, (rim.position.y - from.y) / direction.y)
	return from + direction * minf(t, 1.0) if t < INF else from

## World point -> this Control's local px.
func to_local(point: Vector2) -> Vector2:
	var combat: CombatWorld = app.combat
	var to_ui: float = 1.0 / maxf(0.0001, app.ui_layer.scale.x) if app.ui_layer != null else 1.0
	var screen: Vector2 = app.compositor.world_to_screen(point) if is_instance_valid(app.compositor) else point - combat.player_position + root.get_viewport().get_visible_rect().size * 0.5
	return screen * to_ui - root.position

## Every indicator for the current frame: {kind: boss|enemy|spawn, at, direction, colour, urgency,
## distance}. `include_visible` (hud_model_test's control only) keeps targets the camera shows.
func markers(include_visible: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var combat: CombatWorld = app.combat
	if not is_instance_valid(combat) or root.size.x <= RIM_INSET * 2.0 + 2.0 or root.size.y <= RIM_INSET * 2.0 + 2.0: return result
	var view := Rect2(-root.position, root.get_parent().size if root.get_parent() is Control else root.size)
	var rim := Rect2(Vector2.ZERO, root.size).grow(-RIM_INSET)
	var ship: Vector2 = to_local(combat.player_position).clamp(rim.position + Vector2.ONE, rim.end - Vector2.ONE)
	var radar: bool = combat.has_passive("radar")
	for actor: Dictionary in combat.enemies:
		if bool(actor.get("dead", false)): continue
		var rival: bool = bool(actor.get("rival", false))
		if not rival and not radar: continue
		var marker: Dictionary = _place(view, rim, ship, Vector2(actor.pos), include_visible)
		if marker.is_empty(): continue
		marker.kind = "boss" if rival else "enemy"
		marker.colour = ShipCatalog.get_color(str(actor.element))
		marker.distance = Vector2(actor.pos).distance_to(combat.player_position) / PX_PER_METRE
		result.append(marker)
	var lead: float = GameTuning.SPAWN_TELEGRAPH_SECONDS * SPAWN_LOOKAHEAD * CombatWorld.SIM_Q_PER_SECOND
	for entry: Dictionary in combat.spawn_queue:
		var left: float = float(int(entry.get("due_q", 0)) - combat.encounter_q)
		if left > lead: continue
		var marker: Dictionary = _place(view, rim, ship, Vector2(entry.pos), include_visible)
		if marker.is_empty(): continue
		marker.kind = "spawn"
		marker.colour = VisualStyle.CORAL if not bool(entry.get("rival", false)) else ShipCatalog.get_color(str(entry.get("element", "")))
		marker.urgency = clampf(1.0 - left / maxf(1.0, lead), 0.0, 1.0)
		marker.elite = bool(entry.get("elite", false)) or bool(entry.get("rival", false))
		result.append(marker)
	return result

func _place(view: Rect2, rim: Rect2, ship: Vector2, world: Vector2, include_visible: bool) -> Dictionary:
	var at: Vector2 = to_local(world)
	if view.has_point(at) and not include_visible: return {}
	var direction: Vector2 = (at - ship).normalized()
	if direction.is_zero_approx(): direction = Vector2.UP
	return {"at": rim_point(rim, ship, at), "direction": direction, "urgency": 1.0, "distance": 0.0}

func update() -> void:
	_markers = markers()
	root.queue_redraw()

static func _chevron(canvas: CanvasItem, at: Vector2, direction: Vector2, size: float, ink: Color) -> void:
	var side: Vector2 = direction.orthogonal()
	var tip: Vector2 = at + direction * size
	canvas.draw_colored_polygon(PackedVector2Array([tip, at + side * size - direction * size * 0.45, at - direction * size * 0.05, at - side * size - direction * size * 0.45]), ink)

func _draw() -> void:
	var started: int = Time.get_ticks_usec()
	var elapsed: float = float(app.elapsed_ui)
	var font: Font = Hud.font(&"display")
	for marker: Dictionary in _markers:
		var at: Vector2 = marker.at
		var direction: Vector2 = marker.direction
		var ink: Color = marker.colour
		match str(marker.kind):
			"boss":
				var breath: float = 0.5 + 0.5 * sin(elapsed * 4.0)
				root.draw_circle(at - direction * 4.0, 20.0, Color(ink, 0.10 + 0.08 * breath))
				_chevron(root, at, direction, 13.0, Color(0.02, 0.02, 0.03, 0.8))
				_chevron(root, at - direction * 1.5, direction, 10.5, ink)
				_chevron(root, at - direction * 12.0, direction, 7.0, Color(ink, 0.55))
				var size: int = UiLayout.text_px(13)
				var text: String = "%d m" % roundi(float(marker.distance))
				var box: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
				var label_at: Vector2 = at - direction * 36.0
				label_at = label_at.clamp(Vector2(box.x * 0.5 + 2.0, size), root.size - Vector2(box.x * 0.5 + 2.0, 4.0))
				root.draw_string_outline(font, label_at + Vector2(-box.x * 0.5, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0.0, 0.0, 0.02, 0.85))
				root.draw_string(font, label_at + Vector2(-box.x * 0.5, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink.lerp(Color.WHITE, 0.35))
			"enemy":
				_chevron(root, at, direction, 6.0, Color(ink, 0.85))
			"spawn":
				var urgency: float = float(marker.urgency)
				var big: float = 1.35 if bool(marker.get("elite", false)) else 1.0
				# A ring converges on the chevron as the spawn comes due, and it all brightens.
				var ring: float = lerpf(22.0, 8.0, urgency) * big
				var alpha: float = lerpf(0.25, 1.0, urgency)
				var flicker: float = 0.75 + 0.25 * sin(elapsed * lerpf(6.0, 18.0, urgency))
				root.draw_arc(at, ring, 0.0, TAU, 32, Color(ink, alpha * 0.7 * flicker), 1.5, true)
				_chevron(root, at, direction, 8.0 * big, Color(ink, alpha * flicker))
	Hud.draw_usec += Time.get_ticks_usec() - started
