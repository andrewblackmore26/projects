class_name BossIntro
extends CanvasLayer
## Modernization M16b: the boss intro card. On a rival's first engagement (FeelDirector, from the
## sim's `boss_engage` feel event) letterbox bars close in over BARS_IN seconds, the rival's name
## types in (Exo 2, the display face), and a boss bar fills under it; then it all clears. The sim
## keeps running underneath: this is presentation only and never pauses or slows anything.
##
## Layer 9: above the world and the post pass (5), below the UI (10), so the HUD stays readable
## over the bars while the boss is already shooting. Every visual is a pure function of `elapsed`
## (stepped by `step`, real time, paused with the tree), so a test or a capture can place the card
## at any moment exactly. Reduced motion: no slide, no typing, no fill - one fade in and out.

const LAYER: int = 9
const BARS_IN: float = 0.25
const TYPE_START: float = 0.28
const TYPE_PER_CHAR: float = 0.07
const FILL_START: float = 0.55
const FILL_SECONDS: float = 0.75
const HOLD_UNTIL: float = 2.5
const OUT_SECONDS: float = 0.35
const REDUCED_FADE: float = 0.2
## Letterbox bar height as a fraction of the viewport height.
const BAR_FRACTION: float = 0.075
const NAME_SIZE: int = 76
const DURATION: float = HOLD_UNTIL + OUT_SECONDS

var reduced_motion: bool = false
## -1 while no card is up.
var elapsed: float = -1.0
var shown_count: int = 0
var rival_name: String = ""
var root: Control
var top_bar: ColorRect
var bottom_bar: ColorRect
var card: VBoxContainer
var kicker: Label
var name_label: Label
var rule: ColorRect
var bar_fill: ColorRect
var bar_track: ColorRect
var caption: Label

func _init() -> void:
	layer = LAYER
	name = "BossIntro"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	root = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	top_bar = _bar(Control.PRESET_TOP_WIDE)
	bottom_bar = _bar(Control.PRESET_BOTTOM_WIDE)
	card = VBoxContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", 6)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	# The lower third: below a camera-centred ship, above the bottom bar and the HUD's lower edge.
	card.anchor_top = 0.74
	card.anchor_bottom = 0.74
	card.offset_left = -360.0
	card.offset_right = 360.0
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(card)
	kicker = _label(UiKit.font(UiTokens.FONT_MONO, UiTokens.WEIGHT_MONO, false, 6), UiTokens.TEXT_S)
	name_label = _label(UiKit.font(UiTokens.FONT_DISPLAY, 800, false, 14), NAME_SIZE)
	# Characters are revealed after shaping, so the centred name does not slide as it types.
	name_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	var rule_row := CenterContainer.new()
	rule_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(rule_row)
	bar_track = ColorRect.new()
	bar_track.custom_minimum_size = Vector2(440, 4)
	bar_track.color = UiTokens.TRACK
	bar_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_row.add_child(bar_track)
	bar_fill = ColorRect.new()
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_track.add_child(bar_fill)
	rule = ColorRect.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_track.add_child(rule)
	caption = _label(UiKit.font(UiTokens.FONT_MONO, UiTokens.WEIGHT_MONO, false, 3), UiTokens.TEXT_XS)
	caption.add_theme_color_override("font_color", UiTokens.INK_MUTED)
	visible = false

## M19 review: a bar is smoked glass, not black on the black void: the scrim at 94 %, and over it a
## tint that deepens from the screen edge to the inner edge, where it takes on the rival's colour
## (`present` sets it), then the hairline. It still darkens its band to < 15 % of a mid-grey.
func _bar(preset: Control.LayoutPreset) -> ColorRect:
	var result := ColorRect.new()
	result.color = Color(UiTokens.SCRIM, 0.94)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.set_anchors_and_offsets_preset(preset)
	root.add_child(result)
	var tint := TextureRect.new()
	tint.name = "Tint"
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tint.stretch_mode = TextureRect.STRETCH_SCALE
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var texture := GradientTexture2D.new()
	texture.width = 4
	texture.height = 64
	texture.fill_from = Vector2(0.0, 0.0) if preset == Control.PRESET_TOP_WIDE else Vector2(0.0, 1.0)
	texture.fill_to = Vector2(0.0, 1.0) if preset == Control.PRESET_TOP_WIDE else Vector2(0.0, 0.0)
	texture.gradient = Gradient.new()
	tint.texture = texture
	result.add_child(tint)
	# A hairline in the rival's colour on the inner edge, so the bars read over the near-black void.
	var edge := ColorRect.new()
	edge.name = "Edge"
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if preset == Control.PRESET_TOP_WIDE else Control.PRESET_TOP_WIDE)
	if preset == Control.PRESET_TOP_WIDE: edge.offset_top = -1.0
	else: edge.offset_bottom = 1.0
	result.add_child(edge)
	return result

func _label(font: Font, size: int) -> Label:
	var result := Label.new()
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_override("font", font)
	result.add_theme_font_size_override("font_size", size)
	card.add_child(result)
	return result

## Shows the card for a rival named `title`, in its element `color`. Restarts a card already up.
func present(title: String, top_line: String, bottom_line: String, color: Color) -> void:
	rival_name = title
	name_label.text = title
	kicker.text = top_line
	caption.text = bottom_line
	kicker.add_theme_color_override("font_color", color)
	name_label.add_theme_color_override("font_color", UiTokens.INK)
	bar_fill.color = color
	for edge: ColorRect in [top_bar.get_node("Edge"), bottom_bar.get_node("Edge")]: edge.color = Color(color, 0.55)
	for bar: ColorRect in [top_bar, bottom_bar]:
		var gradient: Gradient = ((bar.get_node("Tint") as TextureRect).texture as GradientTexture2D).gradient
		gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		gradient.colors = PackedColorArray([Color(UiTokens.GLASS_RAISED, 0.0), Color(UiTokens.GLASS_RAISED, 0.55), Color(color.lerp(UiTokens.GLASS_RAISED, 0.55), 0.5)])
	rule.color = Color(color.lightened(0.5), 0.9)
	elapsed = 0.0
	shown_count += 1
	visible = true
	step(0.0)

func active() -> bool:
	return elapsed >= 0.0

## Takes the card down at once (the run left the node, the player died, the menu came back).
func dismiss() -> void:
	elapsed = -1.0
	visible = false

func _process(delta: float) -> void:
	if active(): step(delta)

## Advances the card by `dt` real seconds and lays every element out from `elapsed`.
func step(dt: float) -> void:
	if not active(): return
	elapsed += dt
	if elapsed >= DURATION:
		dismiss()
		return
	var height: float = root.get_viewport_rect().size.y if root.is_inside_tree() else 800.0
	var bar_height: float = roundf(height * BAR_FRACTION)
	var out: float = clampf((elapsed - HOLD_UNTIL) / OUT_SECONDS, 0.0, 1.0)
	if reduced_motion:
		var alpha: float = minf(clampf(elapsed / REDUCED_FADE, 0.0, 1.0), 1.0 - out)
		root.modulate.a = alpha
		_layout(bar_height, name_label.text.length(), 1.0, 1.0)
		return
	root.modulate.a = 1.0
	var close: float = _ease_out(clampf(elapsed / BARS_IN, 0.0, 1.0)) * (1.0 - _ease_in(out))
	var typed: int = clampi(floori((elapsed - TYPE_START) / TYPE_PER_CHAR) + 1, 0, rival_name.length()) if elapsed >= TYPE_START else 0
	var fill: float = _ease_out(clampf((elapsed - FILL_START) / FILL_SECONDS, 0.0, 1.0))
	var text_alpha: float = clampf((elapsed - BARS_IN * 0.4) / 0.18, 0.0, 1.0) * (1.0 - out)
	_layout(bar_height * close, typed, fill, text_alpha)

func _layout(bar_now: float, typed: int, fill: float, text_alpha: float) -> void:
	top_bar.offset_bottom = bar_now
	bottom_bar.offset_top = -bar_now
	name_label.visible_characters = typed
	card.modulate.a = text_alpha
	var width: float = bar_track.custom_minimum_size.x
	bar_fill.size = Vector2(width * fill, bar_track.custom_minimum_size.y)
	# A bright leading edge rides the fill, then settles as a thin rule across the whole bar.
	rule.position = Vector2(maxf(0.0, width * fill - 3.0), -1.0)
	rule.size = Vector2(3.0, bar_track.custom_minimum_size.y + 2.0)
	rule.visible = fill < 1.0

static func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)

static func _ease_in(t: float) -> float:
	return t * t * t
