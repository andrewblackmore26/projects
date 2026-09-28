class_name ComboMeter
extends RefCounted
## The top-centre combo meter of the floating HUD (modernization M11b). Hidden until the first
## kill; then a drain ring and, beside it, "×1.8" in Exo 2 Black Italic over the chain count.
## - every kill pops the multiplier 1.25 -> 1 (out-back, POP_SECONDS). A kill is read from the
##   sim's `run_kills`, not from `combo_count`, which stops at COMBO_MAX_COUNT: a kill at the cap
##   still pops (hud_model_test's control counts the count's rises and comes up short);
## - the ring is the combo WINDOW: combo_timer / GameTuning.COMBO_WINDOW_SECONDS, the constant the
##   sim resets the timer to on every kill;
## - the colour climbs at ×1.5, ×2 and ×2.5, gold to white-hot;
## - the window lapsing is the break: a 3 px shake, then a fade while the count drains.

const POP_SECONDS: float = 0.14
const POP_FROM: float = 1.25
const SHAKE_PX: float = 3.0
const SHAKE_SECONDS: float = 0.24
const FADE_SECONDS: float = 0.22
## While the count drains after a break the meter stays readable at this opacity.
const DRAINING_ALPHA: float = 0.4
const RING_RADIUS: float = 22.0
const RING_BOX: float = 52.0
const GAP: float = 10.0
## Colour tiers by multiplier: [from, colour].
const TIERS: Array = [[0.0, Color(0.93, 0.8, 0.5)], [1.5, VisualStyle.ACCENT], [2.0, Color(1.0, 0.86, 0.55)], [2.5, Color(1.0, 0.98, 0.93)]]

var app: Node
var root: Control
var multiplier_label: Label
var count_label: Label
## Pops shown so far (tests: exactly one per kill).
var pops: int = 0
var breaks: int = 0
var alpha: float = 0.0
var _kills_seen: int = -1
var _pop_elapsed: float = -1.0
var _shake_elapsed: float = -1.0
var _timer_seen: float = 0.0
var _label_rest: Vector2
var _count_rest: Vector2
var _window_fraction: float = 0.0
var _ink: Color = VisualStyle.ACCENT

func _init(owner: Node) -> void:
	app = owner

func build(parent: Control) -> void:
	root = Hud.cluster(parent, "Combo")
	root.draw.connect(_draw)
	multiplier_label = UiKit.label(root, "×1.0", Vector2.ZERO, Vector2(100, 40), 32, VisualStyle.ACCENT)
	multiplier_label.add_theme_font_override("font", Hud.font(&"combo"))
	count_label = UiKit.label(root, "0 CHAIN", Vector2.ZERO, Vector2(100, 16), 12, VisualStyle.MUTED)
	count_label.add_theme_font_override("font", Hud.font(&"body"))
	for label: Label in [multiplier_label, count_label]: label.autowrap_mode = TextServer.AUTOWRAP_OFF
	root.visible = false

## A new run: nothing seen, nothing to pop.
func reset() -> void:
	_kills_seen = -1
	_timer_seen = 0.0
	_pop_elapsed = -1.0
	_shake_elapsed = -1.0
	alpha = 0.0

## The meter's rest layout; returns its size. Sized for its widest text, so it never reflows.
func layout() -> Vector2:
	var number: Vector2 = Vector2(UiLayout.text_width(multiplier_label, "×8.8") + 6.0, multiplier_label.get_minimum_size().y)
	var caption: Vector2 = Vector2(UiLayout.text_width(count_label, "88 CHAIN") + 2.0, count_label.get_minimum_size().y)
	# The two boxes stack edge to edge (touching text boxes are a layout collision), and the slot
	# stays under Hud.TOP_BAR at text scale 130 %, where the toast begins.
	var height: float = maxf(RING_BOX, number.y + caption.y)
	_label_rest = Vector2(RING_BOX + GAP, (height - number.y - caption.y) * 0.5)
	_count_rest = _label_rest + Vector2(2.0, number.y)
	multiplier_label.size = number
	count_label.size = caption
	multiplier_label.position = _label_rest
	count_label.position = _count_rest
	root.size = Vector2(RING_BOX + GAP + maxf(number.x, caption.x + 2.0), height)
	return root.size

static func colour_for(multiplier: float) -> Color:
	var ink: Color = TIERS[0][1]
	for tier: Array in TIERS:
		if multiplier >= float(tier[0]) - 0.0001: ink = tier[1]
	return ink

## One frame. `shown`: the slot is the combo's (not the boss bar's).
func update(dt: float, shown: bool) -> void:
	var combat: CombatWorld = app.combat
	var kills: int = int(combat.run_kills)
	if _kills_seen < 0 or kills < _kills_seen: _kills_seen = kills # a new run: nothing to pop
	if kills > _kills_seen:
		_kills_seen = kills
		pops += 1
		_pop_elapsed = 0.0
		_shake_elapsed = -1.0
	# The break: the window ran out with a chain still standing.
	if _timer_seen > 0.0 and combat.combo_timer <= 0.0 and combat.combo_count > 0:
		breaks += 1
		_shake_elapsed = 0.0
	_timer_seen = combat.combo_timer
	var live: bool = combat.combo_count > 0
	var goal: float = 0.0
	if live: goal = 1.0 if combat.combo_timer > 0.0 else DRAINING_ALPHA
	var fade: float = UiMotion.duration(FADE_SECONDS, true)
	alpha = move_toward(alpha, goal, dt / fade) if fade > 0.0 and dt > 0.0 else goal
	if dt <= 0.0 and live and alpha <= 0.0: alpha = goal
	root.visible = shown and alpha > 0.001
	if not root.visible: return
	var multiplier: float = combat.combo_multiplier()
	_ink = colour_for(multiplier)
	_window_fraction = clampf(combat.combo_timer / GameTuning.COMBO_WINDOW_SECONDS, 0.0, 1.0)
	LightBar._set_text(multiplier_label, "×%.1f" % multiplier)
	LightBar._set_text(count_label, "%d CHAIN" % combat.combo_count)
	multiplier_label.add_theme_color_override("font_color", _ink)
	root.modulate.a = alpha
	# The pop and the shake move the labels, never the cluster: the slot's rect stays put.
	var scale: float = 1.0
	if _pop_elapsed >= 0.0:
		_pop_elapsed += dt
		var t: float = clampf(_pop_elapsed / UiMotion.duration(POP_SECONDS), 0.0, 1.0) if UiMotion.duration(POP_SECONDS) > 0.0 else 1.0
		scale = lerpf(POP_FROM, 1.0, UiMotion.out_back(t))
		if t >= 1.0: _pop_elapsed = -1.0
	multiplier_label.pivot_offset = Vector2(0.0, multiplier_label.size.y * 0.6)
	multiplier_label.scale = Vector2.ONE * scale
	var shake := Vector2.ZERO
	if _shake_elapsed >= 0.0:
		_shake_elapsed += dt
		var t: float = _shake_elapsed / SHAKE_SECONDS
		if t >= 1.0 or UiMotion.reduced: _shake_elapsed = -1.0
		else: shake = Vector2(SHAKE_PX * (1.0 - t) * sin(t * TAU * 4.0), 0.0)
	multiplier_label.position = _label_rest + shake
	count_label.position = _count_rest + shake
	root.queue_redraw()

func _draw() -> void:
	var started: int = Time.get_ticks_usec()
	var center := Vector2(RING_BOX * 0.5, root.size.y * 0.5)
	root.draw_circle(center, RING_RADIUS + 3.0, UiTokens.GLASS)
	root.draw_arc(center, RING_RADIUS, 0.0, TAU, 48, Color(_ink, 0.18), 3.0, true)
	if _window_fraction > 0.0:
		root.draw_arc(center, RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * _window_fraction, 48, _ink, 3.0, true)
	# The core: brighter and larger up the tiers, a small echo of the ship's own core.
	var heat: float = clampf((app.combat.combo_multiplier() - 1.0) / (GameTuning.COMBO_MULTIPLIER_MAX - 1.0), 0.0, 1.0)
	root.draw_circle(center, 5.0 + 5.0 * heat, Color(_ink, 0.22))
	root.draw_circle(center, 3.0 + 2.5 * heat, _ink)
	Hud.draw_usec += Time.get_ticks_usec() - started
