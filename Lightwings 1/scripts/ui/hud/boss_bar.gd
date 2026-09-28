class_name BossBar
extends RefCounted
## The boss bar (modernization M11b): in a node with a living rival the top-centre slot holds this
## instead of the combo meter. The rival's name over one segment per PHASE of the fight, read
## from the boss actor itself: each shield generator (while one lives the core takes no damage,
## CombatWorld._boss_shield_active), each sub-core (while one lives the core cannot die,
## _boss_can_die), then the core. Each segment is a GhostMeter, so a hit leaves the same coral
## ghost as the light bar. The segment the player can hurt now is lit; the ones it guards are dim.

const WIDTH: float = 560.0
const WIDTH_MIN: float = 200.0
const BAR_HEIGHT: float = 12.0
const SEGMENT_GAP: float = 4.0
## The core's segment is this many times a part's width.
const CORE_WEIGHT: float = 2.0

var app: Node
var root: Control
var name_label: Label
var phase_label: Label
var width: float = WIDTH
var actor_id: int = -1
var segments: Array[Dictionary] = []
var meters: Array[GhostMeter] = []
var _ink: Color = VisualStyle.CORAL
var _bar_y: float = 22.0

func _init(owner: Node) -> void:
	app = owner

func build(parent: Control) -> void:
	root = Hud.cluster(parent, "Boss")
	root.draw.connect(_draw)
	name_label = UiKit.label(root, "RIVAL", Vector2.ZERO, Vector2(200, 20), 15, VisualStyle.TEXT)
	name_label.add_theme_font_override("font", Hud.font(&"display_wide"))
	phase_label = UiKit.label(root, "", Vector2.ZERO, Vector2(120, 16), 11, VisualStyle.MUTED)
	phase_label.add_theme_font_override("font", Hud.font(&"body"))
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for label: Label in [name_label, phase_label]: label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.visible = false

## The phases of `actor`'s fight, in the order the player has to break them: shield generators,
## sub-cores, the core. Each is {kind, index, hp, max}; a detached part reads 0 hp.
static func phases(actor: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var hp: PackedFloat32Array = actor.get("part_hp", PackedFloat32Array())
	var top: PackedFloat32Array = actor.get("part_max_hp", PackedFloat32Array())
	var attached: PackedByteArray = actor.get("part_attached", PackedByteArray())
	for kind: String in ["shield_generator", "sub_core"]:
		for index: int in actor.get(kind + "_indices", PackedInt32Array()):
			var alive: bool = index >= attached.size() or bool(attached[index])
			result.append({"kind": kind, "index": index, "hp": hp[index] if alive and index < hp.size() else 0.0, "max": top[index] if index < top.size() else 1.0})
	result.append({"kind": "core", "index": 0, "hp": maxf(0.0, float(actor.get("hp", 0.0))), "max": maxf(0.001, float(actor.get("max_hp", 1.0)))})
	return result

## The living rival of the current node, or {}.
static func boss_of(combat: CombatWorld) -> Dictionary:
	for actor: Dictionary in combat.enemies:
		if bool(actor.get("rival", false)) and not bool(actor.get("dead", false)): return actor
	return {}

## Rest layout for a slot `room` wide; returns the bar's size.
func layout(room: float) -> Vector2:
	width = clampf(room, minf(WIDTH_MIN, room), WIDTH)
	var line: float = maxf(name_label.get_minimum_size().y, phase_label.get_minimum_size().y)
	var phase_width: float = UiLayout.text_width(phase_label, "PHASE 8 / 8") + 4.0
	phase_label.size = Vector2(phase_width, line)
	phase_label.position = Vector2(width - phase_width, 0)
	name_label.position = Vector2.ZERO
	name_label.size = Vector2(maxf(0.0, width - phase_width - 12.0), line)
	_bar_y = line + 5.0
	root.size = Vector2(width, _bar_y + BAR_HEIGHT + 2.0)
	return root.size

## One frame with the living boss `actor` ({} when none). Returns whether the bar is up.
func update(dt: float, actor: Dictionary) -> bool:
	if actor.is_empty():
		root.visible = false
		actor_id = -1
		return false
	segments = phases(actor)
	if int(actor.id) != actor_id or meters.size() != segments.size():
		actor_id = int(actor.id)
		meters.clear()
		for segment: Dictionary in segments:
			var meter := GhostMeter.new()
			meter.reset(float(segment.hp) / float(segment.max))
			meters.append(meter)
		_ink = VisualStyle.PALETTE.get(str(actor.get("element", "")), VisualStyle.CORAL)
		name_label.add_theme_color_override("font_color", _ink.lerp(Color.WHITE, 0.35))
		LightBar._set_text(name_label, str(DialogueDirector.RIVAL_NAMES.get(str(actor.get("element", "")), "RIVAL")))
	for index: int in range(segments.size()):
		meters[index].step(float(segments[index].hp) / float(segments[index].max), dt)
	LightBar._set_text(phase_label, "PHASE %d / %d" % [current_phase() + 1, segments.size()])
	root.visible = true
	root.queue_redraw()
	return true

## The first segment still standing: the one the player can break now.
func current_phase() -> int:
	for index: int in range(segments.size()):
		if float(segments[index].hp) > 0.0: return index
	return maxi(0, segments.size() - 1)

## Each segment's [x, width] on a bar `bar_width` wide.
static func segment_spans(segment_list: Array[Dictionary], bar_width: float) -> Array[Vector2]:
	var weights: float = 0.0
	for segment: Dictionary in segment_list: weights += CORE_WEIGHT if str(segment.kind) == "core" else 1.0
	var room: float = bar_width - SEGMENT_GAP * float(maxi(0, segment_list.size() - 1))
	var result: Array[Vector2] = []
	var x: float = 0.0
	for segment: Dictionary in segment_list:
		var span: float = room * (CORE_WEIGHT if str(segment.kind) == "core" else 1.0) / maxf(0.001, weights)
		result.append(Vector2(x, span))
		x += span + SEGMENT_GAP
	return result

func _draw() -> void:
	var started: int = Time.get_ticks_usec()
	var spans: Array[Vector2] = segment_spans(segments, width)
	var active: int = current_phase()
	for index: int in range(mini(spans.size(), meters.size())):
		var span: Vector2 = spans[index]
		var meter: GhostMeter = meters[index]
		var rect := Rect2(span.x, _bar_y, span.y, BAR_HEIGHT)
		var lit: bool = index == active
		Hud.draw_pill(root, rect.grow(1.0), UiTokens.STROKE if not lit else Color(_ink, 0.7))
		Hud.draw_pill(root, rect, Color(0.035, 0.043, 0.066, 0.94))
		var ink: Color = _ink if lit else _ink.lerp(VisualStyle.MUTED, 0.55)
		if index > active: ink.a = 0.35
		if meter.ghost_visible(): Hud.draw_pill(root, Rect2(rect.position, Vector2(span.y * clampf(meter.ghost, 0.0, 1.0), BAR_HEIGHT)), VisualStyle.CORAL)
		if meter.value > 0.001: Hud.draw_pill(root, Rect2(rect.position, Vector2(span.y * clampf(meter.value, 0.0, 1.0), BAR_HEIGHT)), ink)
		if str(segments[index].kind) != "core":
			# Parts carry a small mark: a hollow ring for a shield generator, a bead for a sub-core.
			var mark := Vector2(rect.position.x + 8.0, rect.position.y + BAR_HEIGHT * 0.5)
			if str(segments[index].kind) == "shield_generator": root.draw_arc(mark, 3.0, 0.0, TAU, 12, Color(0.02, 0.02, 0.03, 0.9), 1.5, true)
			else: root.draw_circle(mark, 2.5, Color(0.02, 0.02, 0.03, 0.9))
	Hud.draw_usec += Time.get_ticks_usec() - started
