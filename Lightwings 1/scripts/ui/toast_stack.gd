class_name ToastStack
extends RefCounted
## Short event messages (moved from main.gd's `_toast` in modernization M2).
##
## M6: anchored top-centre, under the HUD's top clusters, so a toast never sits on the dialogue box
## or the dock at the bottom; it wraps rather than spilling past its box (`layout`).
##
## M15: a real stack. At most MAX_VISIBLE toasts, newest on top; the older ones slide down and the
## oldest leaves when a fourth arrives. Each slides in from above and fades out at the end of its
## time. A message already on screen is not shown twice: it is refreshed and counts up ("×2"). Each
## carries a kind icon - info (blue), reward (gold), warning (coral) - given by the caller or read
## from its words (`kind_for`).

const GOLD := VisualStyle.ACCENT
const DEFAULT_SECONDS: float = 4.0
const MAX_VISIBLE: int = 3
const WIDTH: float = 620.0
## Room kept on each side for the corner clusters (the minimap column: Minimap.SIZE.x + margins).
const SIDE_ROOM: float = 236.0
const ICON: float = 22.0
const PAD: float = 12.0
const GAP: float = 8.0
const KIND_INK: Dictionary = {"info": VisualStyle.BLUE, "reward": VisualStyle.ACCENT, "warning": VisualStyle.CORAL}

var parent: Control
## Newest first. Each: {root, panel, icon, text_label, count_label, text, kind, count, remaining}.
var toasts: Array[Dictionary] = []
## The newest toast's text (an empty, hidden label when none is up): tests and the M6 layout test
## judge the toast through this.
var label: Label:
	get: return toasts[0].text_label if not toasts.is_empty() else _idle
## Seconds the newest toast has left (0 when none).
var remaining: float:
	get: return float(toasts[0].remaining) if not toasts.is_empty() else 0.0
var _idle: Label

func _init(owner: Control) -> void:
	parent = owner
	_idle = Label.new()
	_idle.name = "Toast"
	_idle.visible = false
	_idle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_idle)

## The kind a message reads as when its caller does not say.
static func kind_for(text: String) -> String:
	var words: String = text.to_lower()
	for marker: String in ["fail", "could not", "cannot", "error", "reshaping", "not be"]:
		if words.contains(marker): return "warning"
	for marker: String in ["clear", "unlocked", "restored", "evolv", "yields", "reward", "achievement"]:
		if words.contains(marker): return "reward"
	return "info"

func show(text: String, seconds: float = DEFAULT_SECONDS, kind: String = "") -> void:
	var use_kind: String = kind if KIND_INK.has(kind) else kind_for(text)
	for toast: Dictionary in toasts:
		if str(toast.text) == text:
			toast.count = int(toast.count) + 1
			toast.remaining = seconds
			toast.count_label.text = "×%d" % int(toast.count)
			toast.count_label.visible = true
			UiMotion.pop(toast.root, 0.94, 1.0)
			layout(parent.size)
			return
	var toast: Dictionary = _make(text, use_kind)
	toast.remaining = seconds
	toasts.push_front(toast)
	while toasts.size() > MAX_VISIBLE: _retire(toasts.pop_back())
	layout(parent.size, true)
	# The newcomer slides down into its slot from just above it.
	var rest: Vector2 = toast.root.position
	toast.root.position = rest - Vector2(0, 16)
	toast.root.modulate.a = 0.0
	_move(toast, rest, UiTokens.BASE)
	UiMotion.tween(toast.root).tween_property(toast.root, "modulate:a", 1.0, UiMotion.duration(UiTokens.FAST, true))

## Slides a toast to `to`. One move per toast at a time: a newer slot replaces a move still running
## (an entrance and a restack in the same frames would otherwise fight over the position).
func _move(toast: Dictionary, to: Vector2, seconds: float) -> void:
	var running: Tween = toast.get("move")
	if running != null and running.is_valid(): running.kill()
	var root: Control = toast.root
	var move: Tween = UiMotion.tween(root)
	move.tween_property(root, "position", to, UiMotion.duration(seconds)).set_trans(UiTokens.EASE_IN_TRANS).set_ease(UiTokens.EASE_IN_EASE)
	toast.move = move

func tick(delta: float) -> void:
	var expired: Array[Dictionary] = []
	for toast: Dictionary in toasts:
		toast.remaining = maxf(0.0, float(toast.remaining) - delta)
		if float(toast.remaining) <= 0.0: expired.append(toast)
	if expired.is_empty(): return
	for toast: Dictionary in expired:
		toasts.erase(toast)
		_retire(toast)
	layout(parent.size, true)

func _retire(toast: Dictionary) -> void:
	var root: Control = toast.root
	if is_instance_valid(root): UiMotion.exit(root)

func _make(text: String, kind: String) -> Dictionary:
	var root := Control.new()
	root.name = "Toast"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)
	var ink: Color = KIND_INK[kind]
	var panel: Panel = UiKit.glass(root, Rect2(Vector2.ZERO, Vector2(WIDTH, 44)), Color(ink, 0.55))
	panel.name = "ToastPanel"
	var icon := MenuDraw.new(_paint_icon.bind(kind))
	icon.name = "Kind"
	icon.size = Vector2(ICON, ICON)
	root.add_child(icon)
	var text_label: Label = UiKit.label(root, text, Vector2.ZERO, Vector2(WIDTH - ICON - PAD * 3, 22), UiTokens.TEXT_M, VisualStyle.TEXT)
	text_label.name = "ToastText"
	var count_label: Label = UiKit.label(root, "", Vector2.ZERO, Vector2(40, 22), UiTokens.TEXT_S, ink)
	count_label.name = "Count"
	count_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.visible = false
	UiLayout.scale_text(root)
	return {"root": root, "panel": panel, "icon": icon, "text_label": text_label, "count_label": count_label, "text": text, "kind": kind, "count": 1, "remaining": DEFAULT_SECONDS}

## Info: a ring with an "i". Reward: a four-point star. Warning: a triangle with a "!".
static func _paint_icon(canvas: MenuDraw, kind: String) -> void:
	var centre: Vector2 = canvas.size * 0.5
	var r: float = canvas.size.x * 0.5 - 1.0
	var ink: Color = KIND_INK[kind]
	match kind:
		"reward":
			var star := PackedVector2Array()
			for step: int in range(8):
				var reach: float = r if step % 2 == 0 else r * 0.38
				star.append(centre + Vector2.from_angle(-PI * 0.5 + TAU * step / 8.0) * reach)
			canvas.draw_colored_polygon(star, ink)
		"warning":
			var tri := PackedVector2Array([centre + Vector2(0, -r), centre + Vector2(r * 0.95, r * 0.8), centre + Vector2(-r * 0.95, r * 0.8)])
			canvas.draw_colored_polygon(tri, ink)
			canvas.draw_line(centre + Vector2(0, -r * 0.35), centre + Vector2(0, r * 0.25), UiTokens.CANVAS, 2.0, true)
			canvas.draw_circle(centre + Vector2(0, r * 0.52), 1.3, UiTokens.CANVAS)
		_:
			canvas.draw_arc(centre, r - 0.75, 0.0, TAU, 32, ink, 1.5, true)
			canvas.draw_line(centre + Vector2(0, -r * 0.05), centre + Vector2(0, r * 0.5), ink, 2.0, true)
			canvas.draw_circle(centre + Vector2(0, -r * 0.42), 1.4, ink)

## Places the stack for a UI of `size`: a centred column under any HUD cluster that overlaps it,
## newest on top. Each toast is as wide as its text needs (up to WIDTH, and never into the corner
## columns) and as tall as its wrapped text. `animate` slides toasts that changed slot.
func layout(size: Vector2, animate: bool = false) -> void:
	var safe: Rect2 = UiLayout.safe_rect(size)
	var column: float = clampf(size.x - SIDE_ROOM * 2.0, minf(320.0, safe.size.x), WIDTH)
	var top: float = _top(size, column, safe)
	for toast: Dictionary in toasts:
		var text_label: Label = toast.text_label
		var count_label: Label = toast.count_label
		var font: Font = text_label.get_theme_font(&"font")
		var font_size: int = text_label.get_theme_font_size(&"font_size")
		var count_width: float = count_label.get_minimum_size().x + 6.0 if count_label.visible else 0.0
		var room: float = column - ICON - PAD * 3.0 - count_width
		var natural: float = font.get_string_size(text_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if font != null else room
		var text_width: float = minf(room, ceilf(natural) + 2.0)
		var text_height: float = font.get_multiline_string_size(text_label.text, HORIZONTAL_ALIGNMENT_LEFT, text_width, font_size, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y if font != null else font_size * 1.4
		var height: float = maxf(ICON, ceilf(text_height)) + PAD * 1.4
		var width: float = ICON + PAD * 3.0 + text_width + count_width
		var root: Control = toast.root
		root.size = Vector2(width, height)
		(toast.panel as Panel).size = root.size
		(toast.icon as Control).position = Vector2(PAD, height * 0.5 - ICON * 0.5)
		text_label.position = Vector2(PAD * 2.0 + ICON, height * 0.5 - ceilf(text_height) * 0.5 - 1.0)
		text_label.size = Vector2(text_width, ceilf(text_height) + 2.0)
		count_label.size = count_label.get_minimum_size()
		count_label.position = Vector2(width - PAD - count_label.size.x, height * 0.5 - count_label.size.y * 0.5)
		# Centred, and never outside the safe rect whatever the window or the stack's depth.
		var slot := Vector2(clampf(roundf(size.x * 0.5 - width * 0.5), safe.position.x, maxf(safe.position.x, safe.end.x - width)), clampf(top, safe.position.y, maxf(safe.position.y, safe.end.y - height)))
		# Only a toast that already has a slot slides to a new one; a newcomer is placed.
		if animate and bool(toast.get("placed", false)):
			_move(toast, slot, UiTokens.FAST)
		else:
			var running: Tween = toast.get("move")
			if running != null and running.is_valid(): running.kill()
			root.position = slot
		toast.placed = true
		top += height + GAP

## The stack's top edge: just under every visible HUD cluster that overlaps the centre column (the
## light bar, and in a boss node the boss bar, which may sit on the row under it). Clusters are
## compared in the toast parent's own coordinates.
func _top(size: Vector2, column: float, safe: Rect2) -> float:
	var top: float = safe.position.y + 64.0
	var app: Node = parent.get_parent().get_parent() if parent.get_parent() != null else null
	var hud: Variant = app.get("hud_view") if app != null else null
	if hud == null or not hud.has_method("clusters"): return top
	var band := Rect2(size.x * 0.5 - column * 0.5, safe.position.y, column, size.y * 0.3)
	var origin: Vector2 = parent.get_global_rect().position
	for cluster: Variant in hud.clusters():
		if not cluster is Control or not (cluster as Control).is_visible_in_tree(): continue
		var rect: Rect2 = (cluster as Control).get_global_rect()
		rect.position -= origin
		if rect.size.x > 0.0 and rect.size.y > 0.0 and rect.intersects(band): top = maxf(top, rect.end.y + 12.0)
	return top
