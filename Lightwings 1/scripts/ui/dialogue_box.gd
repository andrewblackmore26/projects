class_name DialogueBox
extends RefCounted
## The companion's dialogue box (moved from main.gd's `_update_dialogue` in modernization M2).
## DialogueDirector decides WHICH line may show and when (queue, dedupe, the between-fights gate);
## this draws it into main.gd's `dialogue` group and keeps its on-screen timer. The lines
## themselves are still queued from main.gd (tests/dialogue_coverage_test.gd scans it).
##
## M15: a compact panel in the bottom-left corner (at most WIDTH wide, inside the safe rect, lifted
## above any HUD cluster it would cover), so a line never sits over the fight in the middle. The
## speaker's portrait slides in over PORTRAIT_SECONDS; the text types at CHARS_PER_SECOND; the line
## then holds for max(HOLD_MIN, HOLD_PER_CHAR per character) and hides itself. The skip input
## (`dialogue_skip`: Enter / pad Y, shown as its glyph in the corner) finishes the typing, and a
## second press dismisses the line. Under reduced motion the text appears whole.
##
## M6's rule stays: the box grows to fit the line's wrapped text at the current text scale
## (`layout`, which main.gd's layout_ui runs on every resize).

const WIDTH: float = 560.0
const MIN_HEIGHT: float = 112.0
const PORTRAIT: Vector2 = Vector2(72, 84)
const PAD: float = 16.0
const PORTRAIT_SECONDS: float = 0.18
const CHARS_PER_SECOND: float = 60.0
const HOLD_MIN: float = 4.0
const HOLD_PER_CHAR: float = 0.05
## The runtime-only skip action (not rebindable, so not in InputBindings.ACTIONS).
const SKIP_ACTION: StringName = &"dialogue_skip"
## Space kept between the box and a HUD cluster it steps around.
const GAP: float = 12.0

var app: Node
var root: Control
## Seconds the current line stays up; main.gd forwards `dialogue_remaining` here.
var remaining: float = 0.0
var _panel: Panel
var _portrait: AIPortrait
var _title: Label
var _text: Label
var _skip: TextureRect
var _skip_label: Label
var _typing: Tween
var _slide: Tween

func _init(owner: Node, dialogue_root: Control) -> void:
	app = owner
	root = dialogue_root
	if not InputMap.has_action(SKIP_ACTION):
		InputMap.add_action(SKIP_ACTION)
		for code: Key in [KEY_ENTER, KEY_KP_ENTER]:
			var key := InputEventKey.new()
			key.keycode = code
			InputMap.action_add_event(SKIP_ACTION, key)
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_Y
		InputMap.action_add_event(SKIP_ACTION, pad)

func dismiss() -> void:
	remaining = 0.0
	root.visible = false
	if _typing != null and _typing.is_valid(): _typing.kill()

## Seconds a line of `chars` characters stays up once it has finished typing.
static func hold_seconds(chars: int) -> float:
	return maxf(HOLD_MIN, HOLD_PER_CHAR * chars)

## Seconds the typewriter takes over `chars` characters (0 under reduced motion).
static func type_seconds(chars: int) -> float:
	return UiMotion.duration(chars / CHARS_PER_SECOND)

func typing() -> bool:
	return _typing != null and _typing.is_valid() and _typing.is_running()

## The skip input while a line is up: the first press finishes the typing, the next dismisses.
## Returns true when it used the event (main.gd's _unhandled_input marks it handled).
func skip_pressed(event: InputEvent) -> bool:
	if not root.visible or remaining <= 0.0 or not event.is_action_pressed(SKIP_ACTION): return false
	if not app.overlay_kind.is_empty(): return false
	skip()
	return true

func skip() -> void:
	if typing():
		_typing.custom_step(3600.0)
		remaining = minf(remaining, hold_seconds(_text.text.length()))
	else:
		dismiss()

func update(delta: float) -> void:
	if not app.overlay_kind.is_empty(): return
	if remaining > 0.0:
		remaining -= delta
		if remaining <= 0.0: root.visible = false
		return
	var combat: CombatWorld = app.combat
	var combat_clear: bool = is_instance_valid(combat) and combat.remaining_enemies() == 0
	var director: DialogueDirector = app.dialogue_director
	if not director.can_show_next(combat_clear): return
	var line: Dictionary = director.pop_next(combat_clear)
	UiKit.clear(root)
	root.visible = true
	var element: String = str(line.element)
	var ink: Color = ElementStyle.color(element)
	_panel = UiKit.glass(root, Rect2(0, 0, WIDTH, MIN_HEIGHT), Color(ink, 0.45))
	_panel.name = "DialoguePanel"
	_portrait = AIPortrait.new()
	_portrait.name = "Portrait"
	_portrait.element = element
	_portrait.size = PORTRAIT
	root.add_child(_portrait)
	_title = UiKit.label(root, str(DialogueDirector.RIVAL_NAMES.get(element, "ECHO")) + "  ·  " + str(line.title).to_upper(), Vector2.ZERO, Vector2(300, 18), UiTokens.TEXT_XS, ink)
	_title.name = "Speaker"
	_title.theme_type_variation = UiTokens.KICKER_LABEL
	_title.add_theme_color_override("font_color", ink)
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_text = UiKit.label(root, str(line.text), Vector2.ZERO, Vector2(400, 60), UiTokens.TEXT_M, VisualStyle.TEXT)
	_text.name = "Line"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_skip = TextureRect.new()
	_skip.name = "SkipGlyph"
	_skip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_skip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_skip.size = Vector2(22, 22)
	_skip.modulate = Color(1, 1, 1, 0.7)
	_skip.texture = PromptHints.textures_for(SKIP_ACTION)[0] if not PromptHints.textures_for(SKIP_ACTION).is_empty() else null
	root.add_child(_skip)
	_skip_label = UiKit.label(root, "SKIP", Vector2.ZERO, Vector2(40, 16), UiTokens.TEXT_XS, UiTokens.INK_MUTED)
	_skip_label.name = "SkipCaption"
	_skip_label.theme_type_variation = UiTokens.KICKER_LABEL
	_skip_label.add_theme_color_override("font_color", UiTokens.INK_MUTED)
	_skip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	UiLayout.scale_text(root)
	layout()
	# The entrance: the panel fades up, the portrait slides in from the left edge, then the text
	# types. The timer covers the typing plus the hold.
	var chars: int = _text.text.length()
	remaining = type_seconds(chars) + hold_seconds(chars)
	UiMotion.enter(_panel)
	var rest: Vector2 = _portrait.position
	_portrait.position = rest - Vector2(PORTRAIT.x * 0.6, 0)
	_portrait.modulate.a = 0.0
	_slide = UiMotion.tween(_portrait).set_parallel(true)
	_slide.tween_property(_portrait, "position", rest, UiMotion.duration(PORTRAIT_SECONDS)).set_trans(UiTokens.EASE_IN_TRANS).set_ease(UiTokens.EASE_IN_EASE)
	_slide.tween_property(_portrait, "modulate:a", 1.0, UiMotion.duration(PORTRAIT_SECONDS, true))
	_text.visible_ratio = 0.0
	_typing = UiMotion.tween(_text)
	_typing.tween_property(_text, "visible_ratio", 1.0, type_seconds(chars)).set_delay(UiMotion.duration(PORTRAIT_SECONDS * 0.5))

## Places the open box for the current UI rect (main.gd's layout_ui runs it on every resize).
func layout() -> void:
	if not is_instance_valid(_panel): return
	var safe: Rect2 = UiLayout.safe_rect(root.size)
	var width: float = minf(WIDTH, safe.size.x)
	var height: float = _height_for(width)
	var box := Rect2(safe.position.x, safe.end.y - height, width, height)
	# Step up past any visible HUD cluster the box would cover (the build dock, the evolve pill).
	var clusters: Array = app.hud_view.clusters() if app.get("hud_view") != null and app.hud_view.has_method("clusters") else []
	for attempt: int in range(6):
		var moved: bool = false
		for cluster: Variant in clusters:
			if not cluster is Control or not (cluster as Control).is_visible_in_tree(): continue
			var rect: Rect2 = (cluster as Control).get_global_rect()
			if rect.size.x <= 0.0 or rect.size.y <= 0.0 or not rect.intersects(box): continue
			box.position.y = rect.position.y - GAP - height
			moved = true
		if not moved: break
	box.position.y = maxf(safe.position.y, box.position.y)
	_panel.position = box.position
	_panel.size = box.size
	_portrait.position = box.position + Vector2(PAD, PAD)
	var text_left: float = PAD + PORTRAIT.x + PAD
	var text_width: float = width - text_left - PAD
	var title_height: float = _title.get_minimum_size().y
	_title.position = box.position + Vector2(text_left, PAD - 2.0)
	_skip_label.size = _skip_label.get_minimum_size()
	# The speaker line stops short of the skip prompt in the corner.
	_title.size = Vector2(text_width - 22.0 - 4.0 - _skip_label.size.x - 12.0, title_height)
	_text.position = box.position + Vector2(text_left, PAD + title_height + 6.0)
	_text.size = Vector2(text_width, height - (PAD + title_height + 6.0) - PAD)
	_skip.position = box.position + Vector2(width - PAD - 22.0, PAD - 5.0)
	_skip_label.position = _skip.position + Vector2(-_skip_label.size.x - 4.0, 11.0 - _skip_label.size.y * 0.5)

## The box's height at `width`: the speaker row plus the line's wrapped text, never below MIN_HEIGHT.
func _height_for(width: float) -> float:
	var font: Font = _text.get_theme_font(&"font")
	var text_width: float = width - (PAD + PORTRAIT.x + PAD) - PAD
	var wrapped: float = font.get_multiline_string_size(_text.text, HORIZONTAL_ALIGNMENT_LEFT, text_width, _text.get_theme_font_size(&"font_size"), -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y
	return maxf(MIN_HEIGHT, PAD + _title.get_minimum_size().y + 6.0 + ceilf(wrapped) + 6.0 + PAD)
