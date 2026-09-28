class_name LightBar
extends RefCounted
## The top-left cluster of the floating HUD (modernization M11b): the Light bar.
##
##   (T3)  NODE -3,2 · RING 3                  NEXT T4 · 500    [ EVOLVE (E) ]
##         [██████████████|▒▒▒ghost▒▒|·····|··········]
##          T2            T3
##         ● FIRE 62%   ● PLASMA 30%   ● VOID 8%
##
## - the tier emblem at the left end;
## - the fill on GhostMeter's spring, its coral LOSS ghost and bright GAIN lead;
## - a labelled tick at every tier threshold under the capacity (x = threshold / capacity x width);
##   the fill crossing one flashes it and pops the bar;
## - the regression floor, coral, pulsing below 112 % of it (the pre-M11b semantics);
## - three element pips: the leading absorptions since the last evolution;
## - the EVOLVE capsule attached at the right end, breathing gold while an evolution is ready,
##   with the device's glyph for `evolve`; the light bank (M13) fills along its lower edge.
## Bars and rings read the sim every frame; a Label's text is set only when it changes.

const EMBLEM: float = 48.0
const BAR_X: float = 60.0
const BAR_HEIGHT: float = 14.0
const BAR_WIDTH: float = 360.0
const BAR_MIN: float = 200.0
## The bar's share of the UI width, before the clamp above.
const BAR_SHARE: float = 0.28
const CAPSULE_HEIGHT: float = 30.0
const CAPSULE_GAP: float = 10.0
## A tick's flash and the bar's pop when the fill crosses a tick.
const FLASH_SECONDS: float = 0.45
const POP_SECONDS: float = 0.14
const POP_FROM: float = 1.25
## The floor marker pulses while the light is under this multiple of the floor.
const FLOOR_WARNING: float = 1.12
const PIPS: int = 3

const CORAL := VisualStyle.CORAL
const BLUE := VisualStyle.BLUE
const GOLD := VisualStyle.ACCENT
const LEAD := Color(0.86, 0.95, 1.0)

var app: Node
var cluster: Control
var tier_label: Label
var sector_label: Label
var status_label: Label
var evolve: Button
var meter := GhostMeter.new()
var width: float = BAR_WIDTH
var bar_y: float = 24.0
## Every tick crossing so far (tests count them).
var crossings: int = 0
var _tier: int = -1
var _capacity: float = 1.0
var _flash: Dictionary = {}
var _pop_elapsed: float = -1.0
var _evolve_ready: bool = false
var _bank_fraction: float = 0.0
var _glyph_path: String = "-"
var _capsule_style: StyleBoxFlat

func _init(owner: Node) -> void:
	app = owner

func build(parent: Control) -> void:
	cluster = Hud.cluster(parent, "TopLeft")
	cluster.draw.connect(_draw)
	tier_label = UiKit.label(cluster, "T1", Vector2.ZERO, Vector2(EMBLEM, 24), 20, VisualStyle.TEXT)
	tier_label.add_theme_font_override("font", Hud.font(&"display"))
	tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sector_label = UiKit.label(cluster, "ORIGIN", Vector2(BAR_X, 0), Vector2(200, 17), 12, VisualStyle.MUTED)
	status_label = UiKit.label(cluster, "", Vector2(BAR_X, 0), Vector2(120, 17), 12, Color(0.78, 0.88, 1.0))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for single: Label in [tier_label, sector_label, status_label]:
		single.autowrap_mode = TextServer.AUTOWRAP_OFF
		single.add_theme_font_override("font", Hud.font(&"display") if single == tier_label else Hud.font(&"body"))
	# Informational and variable-length: on a narrow bar the node readout trims rather than spill.
	sector_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	evolve = app.button(parent, "EVOLVE", Rect2(Vector2.ZERO, Vector2(120, CAPSULE_HEIGHT)), app._show_evolution)
	evolve.name = "EvolveCapsule"
	evolve.focus_mode = Control.FOCUS_NONE
	evolve.clip_text = false
	evolve.add_theme_font_size_override("font_size", 13)
	evolve.add_theme_font_override("font", Hud.font(&"display"))
	evolve.add_theme_constant_override("icon_max_width", 22)
	evolve.add_theme_constant_override("h_separation", 6)
	_capsule_style = UiKit.glass_box(Color(0.16, 0.12, 0.03, 0.96), GOLD, 2, UiTokens.CAPSULE)
	_capsule_style.content_margin_left = 12
	_capsule_style.content_margin_right = 14
	_capsule_style.content_margin_top = 4
	_capsule_style.content_margin_bottom = 4
	_capsule_style.shadow_color = UiTokens.FOCUS_GLOW
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]: evolve.add_theme_stylebox_override(state, _capsule_style)
	for ink: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]: evolve.add_theme_color_override(ink, Color(1.0, 0.93, 0.7))
	evolve.draw.connect(_draw_bank)
	evolve.visible = false

## Places the cluster at `origin` for a UI `size` wide. Returns the right edge the cluster
## reserves, the EVOLVE capsule's included whether or not it shows (the combo slot never moves
## when it appears).
func layout(origin: Vector2, size: Vector2) -> float:
	width = clampf(size.x * BAR_SHARE, BAR_MIN, BAR_WIDTH)
	_refresh_capsule_text()
	var header: float = maxf(sector_label.get_minimum_size().y, status_label.get_minimum_size().y)
	bar_y = header + 6.0
	var status_width: float = status_label.get_minimum_size().x
	status_label.size = Vector2(status_width, header)
	status_label.position = Vector2(BAR_X + width - status_width, 0)
	sector_label.position = Vector2(BAR_X, 0)
	sector_label.size = Vector2(maxf(0.0, width - status_width - 12.0), header)
	var tier_size: Vector2 = tier_label.get_minimum_size()
	tier_label.size = tier_size
	tier_label.position = _emblem_center() - tier_size * 0.5
	var pip_line: float = float(UiLayout.text_px(11)) * 1.4
	cluster.position = origin
	cluster.size = Vector2(BAR_X + width, maxf(_emblem_center().y + EMBLEM * 0.5, bar_y + BAR_HEIGHT + 20.0 + pip_line))
	evolve.size = Vector2(evolve.get_minimum_size().x, CAPSULE_HEIGHT)
	evolve.position = origin + Vector2(BAR_X + width + CAPSULE_GAP, bar_y + BAR_HEIGHT * 0.5 - CAPSULE_HEIGHT * 0.5)
	return evolve.position.x + evolve.size.x

func _emblem_center() -> Vector2:
	return Vector2(EMBLEM * 0.5, bar_y + BAR_HEIGHT * 0.5)

## The labelled ticks for a bar of `bar_width` at `tier`: every threshold strictly under the
## capacity (the capacity itself is the bar's end, where the EVOLVE capsule sits). The tick at
## THRESHOLDS[i] is where tier i + 2 begins.
static func ticks(tier: int, max_tier: int, bar_width: float) -> Array[Dictionary]:
	var capacity: float = GameTuning.capacity(tier, max_tier)
	var result: Array[Dictionary] = []
	for index: int in range(GameTuning.THRESHOLDS.size()):
		var threshold: float = GameTuning.THRESHOLDS[index]
		if threshold >= capacity - GhostMeter.EPSILON: continue
		result.append({"value": threshold, "x": threshold / capacity * bar_width, "label": "T%d" % (index + 2), "index": index})
	return result

## One frame: read the sim, step the meter, set text that changed. `dt` 0 only re-reads.
func update(dt: float) -> void:
	var combat: CombatWorld = app.combat
	var max_tier: int = app.mode_config.max_tier()
	var tier: int = combat.player_tier
	var capacity: float = GameTuning.capacity(tier, max_tier)
	if tier != _tier or not is_equal_approx(capacity, _capacity):
		# A new tier is a new scale: nothing carries across it (no ghost from the old bar).
		_tier = tier
		_capacity = capacity
		meter.reset(combat.light_total)
		_flash.clear()
		_set_text(tier_label, "T%d" % tier)
	var before: float = meter.value
	meter.step(combat.light_total, dt)
	for tick: Dictionary in ticks(tier, max_tier, width):
		var threshold: float = float(tick.value)
		if (before < threshold) != (meter.value < threshold):
			_flash[int(tick.index)] = FLASH_SECONDS
			_pop_elapsed = 0.0
			crossings += 1
	for index: Variant in _flash.keys():
		_flash[index] = float(_flash[index]) - dt
		if float(_flash[index]) <= 0.0: _flash.erase(index)
	if _pop_elapsed >= 0.0:
		_pop_elapsed += dt
		if _pop_elapsed >= POP_SECONDS: _pop_elapsed = -1.0
	var campaign: CampaignState = app.campaign
	var sector_text: String = "%sNODE %s · RING %d" % ["DEMO · " if campaign.demo else "", CampaignState.coord_key(campaign.current_sector), CampaignState.ring(campaign.current_sector)]
	var capped: bool = tier >= max_tier
	var next: int = EvolutionRules.threshold(tier)
	var ship: ShipDefinition = combat.player.get("definition")
	var status: String = "MAX TIER" if capped else "NEXT T%d · %d" % [tier + 1, next]
	if ship != null and "health_readout" in ship.passives: status = "%.1f / %.0f" % [combat.light_total, capacity]
	var relayout: bool = _set_text(sector_label, sector_text)
	relayout = _set_text(status_label, status) or relayout
	var ready: bool = not capped and combat.light_total >= next and combat.light_total > 0.0
	if ready != _evolve_ready:
		_evolve_ready = ready
		evolve.visible = ready
		if ready: UiMotion.pop(evolve, 0.8, 1.0)
	if is_instance_valid(combat.player.get("renderer")): combat.player.renderer.evolution_ready = ready
	var bank_cap: float = combat.light_bank_cap()
	_bank_fraction = clampf(combat.light_bank / bank_cap, 0.0, 1.0) if bank_cap > 0.0 else 0.0
	relayout = _refresh_capsule_text() or relayout
	if ready:
		var breath: float = 0.5 + 0.5 * sin(float(app.elapsed_ui) * 3.2)
		_capsule_style.shadow_size = roundi(lerpf(4.0, 14.0, breath))
		_capsule_style.shadow_color = Color(GOLD, lerpf(0.22, 0.5, breath))
		evolve.queue_redraw()
	if relayout: app.hud_view.layout()
	cluster.queue_redraw()

## The capsule wears the evolve glyph for the device in hand; with no glyph on disk, its text.
func _refresh_capsule_text() -> bool:
	var prompt: Dictionary = InputPrompts.shared().prompt_for("evolve")
	var path: String = str(prompt.path) if prompt.texture != null else ""
	if path == _glyph_path: return false
	_glyph_path = path
	evolve.icon = prompt.texture
	evolve.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	evolve.text = "EVOLVE" if prompt.texture != null else "EVOLVE · %s" % str(prompt.text)
	return true

static func _set_text(label: Label, text: String) -> bool:
	if label.text == text: return false
	label.text = text
	return true

func _x(value: float) -> float:
	return BAR_X + clampf(value / maxf(0.001, _capacity), 0.0, 1.0) * width

func _draw() -> void:
	var started: int = Time.get_ticks_usec()
	var combat: CombatWorld = app.combat
	if not is_instance_valid(combat):
		return
	var canvas: Control = cluster
	var elapsed: float = float(app.elapsed_ui)
	# The emblem: a smoked-glass disc on a blue ring (gold while an evolution is ready).
	var center: Vector2 = _emblem_center()
	var ring_ink: Color = GOLD if _evolve_ready else BLUE
	canvas.draw_circle(center, EMBLEM * 0.5 + 3.0, Color(ring_ink, 0.10))
	canvas.draw_circle(center, EMBLEM * 0.5, UiTokens.GLASS)
	canvas.draw_arc(center, EMBLEM * 0.5 - 1.0, 0.0, TAU, 48, ring_ink, 2.0, true)
	canvas.draw_arc(center, EMBLEM * 0.5 - 5.0, 0.0, TAU, 48, Color(ring_ink, 0.25), 1.0, true)
	# The bar, popped about its middle for POP_SECONDS after a tick crossing.
	var pop: float = 1.0
	if _pop_elapsed >= 0.0: pop = lerpf(POP_FROM, 1.0, UiMotion.out_back(clampf(_pop_elapsed / POP_SECONDS, 0.0, 1.0)))
	var middle: float = bar_y + BAR_HEIGHT * 0.5
	var height: float = BAR_HEIGHT * pop
	var top: float = middle - height * 0.5
	var track := Rect2(BAR_X, top, width, height)
	Hud.draw_pill(canvas, track.grow(1.0), UiTokens.STROKE)
	Hud.draw_pill(canvas, track, Color(0.035, 0.043, 0.066, 0.94))
	var fill_x: float = _x(meter.value)
	if meter.ghost_visible(): Hud.draw_pill(canvas, Rect2(BAR_X, top, _x(meter.ghost) - BAR_X, height), CORAL)
	if meter.lead_visible(): Hud.draw_pill(canvas, Rect2(BAR_X, top, _x(meter.lead) - BAR_X, height), LEAD)
	if fill_x > BAR_X + 0.5:
		# A soft halo first: the light bar is light.
		Hud.draw_pill(canvas, Rect2(BAR_X - 2.0, top - 3.0, fill_x - BAR_X + 4.0, height + 6.0), Color(BLUE, 0.12))
		Hud.draw_pill(canvas, Rect2(BAR_X, top, fill_x - BAR_X, height), BLUE)
		# A lighter upper half and a bright leading edge: the fill reads as light, not paint.
		Hud.draw_pill(canvas, Rect2(BAR_X + 2.0, top + 2.0, maxf(0.0, fill_x - BAR_X - 4.0), height * 0.32), Color(1.0, 1.0, 1.0, 0.22))
		canvas.draw_line(Vector2(fill_x - 1.0, top + 1.0), Vector2(fill_x - 1.0, top + height - 1.0), Color(LEAD, 0.9), 2.0)
	var font: Font = Hud.font(&"body")
	var tick_size: int = UiLayout.text_px(10)
	for tick: Dictionary in ticks(_tier, app.mode_config.max_tier(), width):
		var x: float = BAR_X + float(tick.x)
		var flash: float = clampf(float(_flash.get(int(tick.index), 0.0)) / FLASH_SECONDS, 0.0, 1.0)
		var ink: Color = Color(0.05, 0.06, 0.09, 0.9).lerp(GOLD, flash)
		canvas.draw_line(Vector2(x, top + 1.0), Vector2(x, top + height - 1.0), ink, 2.0 + 2.0 * flash)
		canvas.draw_line(Vector2(x, top + height + 1.0), Vector2(x, top + height + 4.0), Color(VisualStyle.MUTED, 0.8).lerp(GOLD, flash), 1.0)
		canvas.draw_string(font, Vector2(x - 20.0, top + height + 5.0 + tick_size), str(tick.label), HORIZONTAL_ALIGNMENT_CENTER, 40.0, tick_size, Color(VisualStyle.MUTED, 0.9).lerp(GOLD, flash))
	var floor_value: float = GameTuning.regression_floor(_tier)
	if floor_value > 0.0:
		var warning: bool = combat.light_total < floor_value * FLOOR_WARNING
		var alpha: float = 0.55 + 0.45 * sin(elapsed * 7.0) if warning else 0.65
		var floor_x: float = _x(floor_value)
		canvas.draw_line(Vector2(floor_x, top - 4.0), Vector2(floor_x, top + height + 4.0), Color(CORAL, alpha), 2.0)
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(floor_x - 4.0, top - 7.0), Vector2(floor_x + 4.0, top - 7.0), Vector2(floor_x, top - 2.0)]), Color(CORAL, alpha))
	_draw_pips(canvas, font, top + height + 11.0 + tick_size)
	Hud.draw_usec += Time.get_ticks_usec() - started

## The three leading absorptions since the last evolution, as element pips.
func _draw_pips(canvas: Control, font: Font, y: float) -> void:
	var absorbed: Dictionary = app.combat.absorption
	var leading: Array = absorbed.keys()
	leading.sort_custom(func(a: String, b: String) -> bool: return float(absorbed[a]) > float(absorbed[b]))
	var total: float = 0.0
	for key: Variant in absorbed: total += float(absorbed[key])
	var size: int = UiLayout.text_px(11)
	var x: float = BAR_X + 5.0
	var line: float = y + size * 0.7
	for index: int in range(PIPS):
		var at := Vector2(x, line - size * 0.35)
		if index >= leading.size():
			canvas.draw_arc(at, 4.0, 0.0, TAU, 16, Color(VisualStyle.MUTED, 0.45), 1.0, true)
			x += 22.0
			continue
		var element: String = str(leading[index])
		var ink: Color = ShipCatalog.get_color(element)
		canvas.draw_circle(at, 6.5, Color(ink, 0.18))
		canvas.draw_circle(at, 4.0, ink)
		var text: String = "%s %d%%" % [element.to_upper(), roundi(100.0 * float(absorbed[element]) / maxf(0.001, total))]
		canvas.draw_string(font, Vector2(x + 10.0, line), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.8, 0.84, 0.9))
		x += 10.0 + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16.0

## The light bank (M13): what overflowed a full bar, paid in on evolve. A gold line along the
## capsule's lower edge, as full as the bank is.
func _draw_bank() -> void:
	if _bank_fraction <= 0.0: return
	var inset: float = CAPSULE_HEIGHT * 0.5
	var span: float = maxf(0.0, evolve.size.x - inset * 2.0)
	var y: float = evolve.size.y - 4.0
	evolve.draw_line(Vector2(inset, y), Vector2(inset + span, y), Color(GOLD, 0.25), 2.0)
	evolve.draw_line(Vector2(inset, y), Vector2(inset + span * _bank_fraction, y), Color(1.0, 0.9, 0.55), 2.0)
