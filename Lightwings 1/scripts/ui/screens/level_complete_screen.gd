class_name LevelCompleteScreen
extends UiScreen
## Level complete (spec §4/§11; moved from main.gd in M2): the next element is revealed and the
## next level unlocked by RunController.on_boss_defeated; this offers CONTINUE TO LEVEL N+1 /
## KEEP EXPLORING. args: {result} (CampaignState.complete_level()).
##
## M15: a reward beat. The revealed element's colour floods a ring around its glyph, the level's
## numbers count up beneath it (UiMotion.count_up), and CONTINUE is focused the moment the screen
## opens - the animation never holds the player. EndingScreen reuses the ring and the stat row.

const RING: Rect2 = Rect2(560, 236, 160, 160)
const STATS_Y: float = 432.0

func build() -> void:
	var result: Dictionary = args.result
	var level: int = app.campaign.level
	var next_level: int = int(result.get("next_level", level + 1))
	var revealed: String = str(result.get("revealed_element", ""))
	var beaten: String = LevelSelectScreen.element_of(level)
	var kicker: Label = centered_label(host, "LEVEL %d · %s" % [level, ElementStyle.display_name(beaten).to_upper()], Vector2(240, 86), Vector2(800, 20), UiTokens.TEXT_XS, UiTokens.KICKER)
	kicker.theme_type_variation = UiTokens.KICKER_LABEL
	centered_label(host, "LEVEL %d COMPLETE" % level, Vector2(140, 108), Vector2(1000, 56), UiTokens.TEXT_2XL, WHITE)
	var text: String = "The rival's signal yields. %s light now reveals itself in the world." % ElementStyle.display_name(revealed) if not revealed.is_empty() else "The rival's signal yields."
	centered_label(host, text, Vector2(240, 170), Vector2(800, 48), UiTokens.TEXT_M, MUTED)
	flood_ring(host, RING, [revealed if not revealed.is_empty() else LevelSelectScreen.element_of(next_level)], "NEW LIGHT" if not revealed.is_empty() else "NEXT")
	var best: Variant = app.campaign.best_ring.get(level, app.campaign.best_ring.get(str(level), 0))
	stat_row(host, [["NODES CHARTED", app.campaign.discovered.size()], ["KILLS", app.combat.run_kills if is_instance_valid(app.combat) else 0], ["BEST RING", int(best)], ["REBOOTS", app.campaign.deaths]], STATS_Y)
	_focus = button(host, "CONTINUE TO LEVEL %d" % next_level, Rect2(440, 540, 400, 56), app._begin_at_level.bind(app.mode_config.id, next_level))
	_focus.theme_type_variation = UiTokens.PRIMARY_BUTTON
	var explore: Button = button(host, "KEEP EXPLORING", Rect2(396, 612, 236, 44), app._close_overlay)
	var menu: Button = button(host, "SAVE & MAIN MENU", Rect2(648, 612, 236, 44), func() -> void: app._save_game(); app._show_menu())
	FocusChain.rows([[_focus], [explore, menu]])
	footer_hints(host, PromptHints.new([["ui_accept", "CONTINUE"], ["navigate", "MOVE"]]))

## M19 review: a centred screen's prompt row is centred too, on the canvas at the footer line.
static func footer_hints(parent: Control, row: PromptHints) -> PromptHints:
	return ConfirmScreen.centre_hints(parent, row, Rect2(0, 0, UiLayout.BASE_SIZE.x, 696))

## A ring in `rect` whose arc floods with each element's colour in turn (one equal segment each),
## the first element's glyph glowing in the centre, and a kicker under it. The flood runs on the
## MenuDraw's `progress` (0 -> 1 over UiTokens.CINE, after the screen's entrance).
static func flood_ring(parent: Control, rect: Rect2, elements: Array, caption: String) -> MenuDraw:
	var ring := MenuDraw.new(func(canvas: MenuDraw) -> void:
		var centre: Vector2 = canvas.size * 0.5
		var radius: float = minf(canvas.size.x, canvas.size.y) * 0.5 - 6.0
		var t: float = canvas.progress
		var lead: Color = ElementStyle.color(str(elements[0]))
		canvas.draw_circle(centre, radius, Color(lead.darkened(0.88), 0.35 + 0.55 * t))
		canvas.draw_arc(centre, radius, 0.0, TAU, 96, Color(UiTokens.STROKE, 0.9), 4.0, true)
		var span: float = TAU / float(elements.size())
		for index: int in range(elements.size()):
			var share: float = clampf(t * elements.size() - index, 0.0, 1.0)
			if share <= 0.0: continue
			var start: float = -PI * 0.5 + span * index
			var ink: Color = ElementStyle.color(str(elements[index]))
			canvas.draw_arc(centre, radius, start, start + span * share, 64, ink, 4.0, true)
			canvas.draw_arc(centre, radius + 7.0, start, start + span * share, 64, Color(ink, 0.18), 6.0, true)
		ElementStyle.draw_glyph(canvas, str(elements[0]), centre, radius * 0.42, Color(lead, 0.25 + 0.75 * t), 3.0))
	ring.name = "FloodRing"
	ring.position = rect.position
	ring.size = rect.size
	ring.progress = 0.0
	parent.add_child(ring)
	# Reduced motion: the flood is a fill, not a move, so it keeps a (capped) fade-length sweep.
	UiMotion.tween(ring).tween_property(ring, "progress", 1.0, UiMotion.duration(UiTokens.CINE * (1.0 + 0.25 * (elements.size() - 1)), true)).set_delay(UiMotion.duration(UiTokens.FAST)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var label: Label = centered_label(parent, caption, Vector2(rect.position.x - 60, rect.end.y + 10), Vector2(rect.size.x + 120, 18), UiTokens.TEXT_XS, ElementStyle.color(str(elements[0])))
	label.theme_type_variation = UiTokens.KICKER_LABEL
	label.add_theme_color_override("font_color", ElementStyle.color(str(elements[0])))
	return ring

## Stat blocks across the canvas at `y`: each value counts up from 0, its caption under it.
static func stat_row(parent: Control, stats: Array, y: float) -> void:
	var pitch: float = 180.0
	var left: float = 640.0 - pitch * stats.size() * 0.5
	for index: int in range(stats.size()):
		var x: float = left + pitch * index
		var value: Label = centered_label(parent, "0", Vector2(x, y), Vector2(pitch, 44), UiTokens.TEXT_XL, WHITE)
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		value.name = "Stat%d" % index
		var target: float = float(stats[index][1])
		var wait: Tween = UiMotion.tween(value)
		wait.tween_interval(UiMotion.duration(UiTokens.FAST + 0.05 * index))
		wait.tween_callback(func() -> void: UiMotion.count_up(value, 0.0, target))
		var caption: Label = centered_label(parent, str(stats[index][0]), Vector2(x, y + 46), Vector2(pitch, 18), UiTokens.TEXT_XS, MUTED)
		caption.theme_type_variation = UiTokens.KICKER_LABEL
		caption.add_theme_color_override("font_color", MUTED)
