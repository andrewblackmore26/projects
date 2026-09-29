class_name LevelSelectScreen
extends UiScreen
## Level select (spec §4: "Menu: Campaign and Dev mode, each with level
## select"). Campaign offers levels 1..completed+1; dev offers all five.
## This chooses where a NEW run starts; an existing "continue" resumes
## exactly where the profile left off and does not go through this screen.
## args: {mode_id}.
##
## M15: the mode's levels as a constellation - one node per level in its element's colour and glyph,
## joined by rails, climbing left to right. A locked node is dim with a lock and cannot launch (a
## press shakes it). The focused node's card below says what it is: element, rival, best ring.
## Left/right (or up/down) walk the chain; down from the chain reaches BACK.
## M19 review: the card carries a gold LAUNCH call to action (wearing the confirm glyph; a click
## launches too); the focused node sits in one smooth radial glow instead of banded rings; a locked
## node keeps its element glyph at 40 % with a small lock badge on its rim.

const NODE_SIZE: float = 92.0
## Node centres on the 1280x800 canvas: a rising arc, level 1 at the left.
const NODE_AT: Array[Vector2] = [Vector2(236, 430), Vector2(438, 344), Vector2(640, 300), Vector2(842, 344), Vector2(1044, 430)]
## Wide enough that the body keeps to two lines beside the LAUNCH capsule at text size 130 %.
const CARD: Rect2 = Rect2(300, 516, 680, 150)
const LAUNCH_SIZE: Vector2 = Vector2(184, 48)
const LOCKED_GLYPH_ALPHA: float = 0.4
## The focus glow's reach (a multiple of the node's radius) and its peak alpha.
const HALO_REACH: float = 1.9
const HALO_ALPHA: float = 0.32
## The rails' canvas: the band the chain and the focus halo occupy (inside the safe rect, so it
## counts as content without pushing the design canvas off its coordinates).
const RAILS: Rect2 = Rect2(120, 220, 1040, 300)

var _nodes: Array[Button] = []
var _card_level: int = 1
var _rails: MenuDraw
var _card_kicker: Label
var _card_title: Label
var _card_body: Label
var _card_glyph: MenuDraw
var _launch_button: Button
var _levels: Array[int] = []
static var _halo: GradientTexture2D
var _playable: Array[int] = []
var _best: Dictionary = {}
var _mode_id: String = ""

func build() -> void:
	_mode_id = str(args.mode_id)
	var config := ModeConfig.from_id(_mode_id)
	var completed: Array = []
	var snapshot: Dictionary = SaveService.load_snapshot(config.save_slot())
	if not snapshot.is_empty():
		completed.assign(snapshot.get("profile", {}).get("levels_completed", []))
		_best = snapshot.get("profile", {}).get("best_ring", {})
	_playable = config.selectable_levels(completed)
	for level: int in range(1, config.level_cap() + 1): _levels.append(level)
	var kicker: Label = centered_label(host, config.menu_label() + " · CHOOSE WHERE TO BEGIN", Vector2(240, 96), Vector2(800, 24), UiTokens.TEXT_XS, UiTokens.KICKER)
	kicker.theme_type_variation = UiTokens.KICKER_LABEL
	centered_label(host, "SELECT A LEVEL", Vector2(240, 124), Vector2(800, 56), UiTokens.TEXT_2XL, WHITE)
	_rails = MenuDraw.new(_paint_rails)
	_rails.name = "Rails"
	_rails.position = RAILS.position
	_rails.size = RAILS.size
	_rails.animate = true
	host.add_child(_rails)
	var offset: int = (NODE_AT.size() - _levels.size()) / 2
	for index: int in range(_levels.size()):
		var level: int = _levels[index]
		var at: Vector2 = NODE_AT[index + offset]
		var node: Button = button(host, "", Rect2(at - Vector2.ONE * NODE_SIZE * 0.5, Vector2.ONE * NODE_SIZE), _launch.bind(level))
		node.name = "Level%d" % level
		node.clip_text = false
		node.set_meta(&"level", level)
		node.set_meta(&"locked", level not in _playable)
		_style_node(node, level)
		var glyph := MenuDraw.new(_paint_node.bind(level))
		glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		node.add_child(glyph)
		node.focus_entered.connect(_show_card.bind(level))
		node.focus_entered.connect(_rails.queue_redraw)
		var number: Label = centered_label(host, "LEVEL %d" % level, at + Vector2(-60, NODE_SIZE * 0.5 + 24), Vector2(120, 20), UiTokens.TEXT_XS, MUTED)
		number.theme_type_variation = UiTokens.KICKER_LABEL
		_nodes.append(node)
	UiKit.glass(host, CARD).name = "Card"
	_card_glyph = MenuDraw.new(_paint_card_glyph)
	_card_glyph.position = CARD.position + Vector2(24, 32)
	_card_glyph.size = Vector2(72, 72)
	host.add_child(_card_glyph)
	var text_width: float = CARD.size.x - 116 - LAUNCH_SIZE.x - 48
	_card_kicker = UiKit.label(host, "", CARD.position + Vector2(116, 24), Vector2(text_width, 20), UiTokens.TEXT_XS, GOLD)
	_card_kicker.theme_type_variation = UiTokens.KICKER_LABEL
	_card_title = UiKit.label(host, "", CARD.position + Vector2(116, 44), Vector2(text_width, 44), UiTokens.TEXT_XL, WHITE)
	_card_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_card_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_card_body = UiKit.label(host, "", CARD.position + Vector2(116, 94), Vector2(text_width, 44), UiTokens.TEXT_S, MUTED)
	# The call to action. Not a focus stop (the pad's confirm on a node launches it), but always
	# visible and clickable, wearing the confirm glyph of the device in hand.
	_launch_button = button(host, "LAUNCH", Rect2(CARD.end.x - 24 - LAUNCH_SIZE.x, CARD.get_center().y - LAUNCH_SIZE.y * 0.5, LAUNCH_SIZE.x, LAUNCH_SIZE.y), func() -> void: _launch(_card_level))
	_launch_button.name = "Launch"
	_launch_button.focus_mode = Control.FOCUS_NONE
	_launch_button.theme_type_variation = UiTokens.PRIMARY_BUTTON
	_launch_button.add_theme_constant_override("icon_max_width", 24)
	_launch_button.add_theme_constant_override("h_separation", 8)
	# Lit at rest: the primary capsule's solid gold, so the action reads before it is hovered.
	var solid: StyleBox = _launch_button.get_theme_stylebox("hover")
	_launch_button.add_theme_stylebox_override("normal", solid)
	_launch_button.add_theme_color_override("font_color", _launch_button.get_theme_color("font_hover_color"))
	_refresh_launch_glyph()
	InputPrompts.shared().device_changed.connect(_on_device_changed)
	var back: Button = button(host, "BACK", Rect2(540, 680, 200, 44), app._close_overlay)
	back.name = "Back"
	# Left/right walk the chain; up/down go between the chain and BACK.
	FocusChain.rows([_nodes, [back]])
	back.focus_neighbor_top = back.get_path_to(_nodes[0] if _playable.is_empty() else _nodes[_levels.find(_playable.back())])
	var hints := PromptHints.new([["change", "LEVEL"], ["ui_accept", "LAUNCH"], ["ui_cancel", "BACK"]])
	ConfirmScreen.centre_hints(host, hints, Rect2(0, 0, UiLayout.BASE_SIZE.x, 720))
	# The furthest level the profile can play is where the cursor starts.
	_focus = _nodes[_levels.find(_playable.back())] if not _playable.is_empty() else back
	_show_card(int(_focus.get_meta(&"level", 1)) if _focus != back else 1)

func exit() -> void:
	if InputPrompts.shared().device_changed.is_connected(_on_device_changed): InputPrompts.shared().device_changed.disconnect(_on_device_changed)

func _on_device_changed(_device: String, _family: String) -> void:
	_refresh_launch_glyph()

func _refresh_launch_glyph() -> void:
	if not is_instance_valid(_launch_button): return
	var glyphs: Array[Texture2D] = PromptHints.textures_for("ui_accept")
	_launch_button.icon = glyphs[0] if not glyphs.is_empty() else null

func _launch(level: int) -> void:
	if level not in _playable:
		var node: Button = _nodes[_levels.find(level)]
		UiMotion.shake(node, 6.0)
		UiScreen.ui_cue(app, "ui_back")
		return
	app._begin_at_level(_mode_id, level)

static func element_of(level: int) -> String:
	return GameTuning.ELEMENTS[mini(level - 1, GameTuning.ELEMENTS.size() - 1)]

## A node is a circle: its element's dark fill and coloured ring; gold ring and glow when focused.
func _style_node(node: Button, level: int) -> void:
	var element: String = element_of(level)
	var ink: Color = ElementStyle.color(element)
	var locked: bool = level not in _playable
	var rest: StyleBoxFlat = UiKit.glass_box(Color(0.03, 0.035, 0.05, 0.96), Color(ink, 0.25 if locked else 0.85), 2, int(NODE_SIZE))
	var lit: StyleBoxFlat = UiKit.glass_box(Color(ink.darkened(0.82), 1.0), UiTokens.FOCUS, 3, int(NODE_SIZE), true)
	lit.shadow_size = 18
	for style: StyleBoxFlat in [rest, lit]: style.set_content_margin_all(0)
	node.add_theme_stylebox_override("normal", rest)
	node.add_theme_stylebox_override("disabled", rest)
	for state: String in ["hover", "focus", "pressed", "hover_pressed"]: node.add_theme_stylebox_override(state, lit)

func _paint_node(canvas: MenuDraw, level: int) -> void:
	var element: String = element_of(level)
	var centre: Vector2 = canvas.size * 0.5
	var locked: bool = level not in _playable
	var ink: Color = ElementStyle.color(element)
	if locked:
		ElementStyle.draw_glyph(canvas, element, centre, NODE_SIZE * 0.26, Color(ink, LOCKED_GLYPH_ALPHA), 2.5)
		# The lock is a badge on the rim (lower right), so the element still reads in the middle.
		var badge: Vector2 = centre + Vector2.from_angle(PI * 0.25) * NODE_SIZE * 0.5
		canvas.draw_circle(badge, 13.0, UiTokens.GLASS_RAISED, true, -1.0, true)
		canvas.draw_arc(badge, 12.5, 0.0, TAU, 32, UiTokens.STROKE.lightened(0.25), 1.5, true)
		ElementStyle.draw_lock(canvas, badge + Vector2(0, 1), 14.0, UiTokens.INK_MUTED)
		return
	ElementStyle.draw_glyph(canvas, element, centre, NODE_SIZE * 0.26, ink, 2.5)

## The rails between consecutive nodes: lit (element-tinted) up to the furthest playable level, a
## faint dotted line beyond it; a bead of light runs the lit rails.
func _paint_rails(canvas: MenuDraw) -> void:
	for index: int in range(_nodes.size() - 1):
		var from: Vector2 = _nodes[index].position + _nodes[index].size * 0.5 - canvas.position
		var to: Vector2 = _nodes[index + 1].position + _nodes[index + 1].size * 0.5 - canvas.position
		var along: Vector2 = (to - from).normalized()
		var start: Vector2 = from + along * (NODE_SIZE * 0.5 + 8.0)
		var finish: Vector2 = to - along * (NODE_SIZE * 0.5 + 8.0)
		var open: bool = _levels[index + 1] in _playable
		if open:
			var ink: Color = ElementStyle.color(element_of(_levels[index + 1]))
			canvas.draw_line(start, finish, Color(ink, 0.45), 2.0, true)
			var t: float = fposmod(canvas.clock * 0.45 + index * 0.3, 1.0)
			canvas.draw_circle(start.lerp(finish, t), 2.5, Color(ink, 0.9))
		else:
			var length: float = start.distance_to(finish)
			var dash: float = 0.0
			while dash < length:
				canvas.draw_line(start + along * dash, start + along * minf(dash + 4.0, length), Color(UiTokens.INK_MUTED, 0.25), 1.5, true)
				dash += 11.0
	# A soft glow behind the focused node: one radial falloff (a smooth-step gradient texture), which
	# breathes a little, in place of three concentric rings that banded.
	var focused: Control = host.get_viewport().gui_get_focus_owner() if host.is_inside_tree() else null
	if focused in _nodes:
		var level: int = int(focused.get_meta(&"level", 1))
		var halo: Color = ElementStyle.color(element_of(level)) if level in _playable else UiTokens.INK_MUTED
		var centre: Vector2 = focused.position + focused.size * 0.5 - canvas.position
		var reach: float = NODE_SIZE * 0.5 * (HALO_REACH + 0.06 * sin(canvas.clock * 2.0))
		canvas.draw_texture_rect(halo_texture(), Rect2(centre - Vector2.ONE * reach, Vector2.ONE * reach * 2.0), false, Color(halo, HALO_ALPHA))

## A white radial falloff, opaque at the centre to clear at the edge along a smooth step, sampled
## finely enough (64 stops) that no ring shows even in linear-light blending.
static func halo_texture() -> GradientTexture2D:
	if _halo != null: return _halo
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var colours := PackedColorArray()
	for step: int in range(65):
		var t: float = step / 64.0
		var falloff: float = 1.0 - smoothstep(0.0, 1.0, t)
		offsets.append(t)
		colours.append(Color(1, 1, 1, falloff * falloff))
	gradient.offsets = offsets
	gradient.colors = colours
	_halo = GradientTexture2D.new()
	_halo.gradient = gradient
	_halo.fill = GradientTexture2D.FILL_RADIAL
	_halo.fill_from = Vector2(0.5, 0.5)
	_halo.fill_to = Vector2(1.0, 0.5)
	_halo.width = 256
	_halo.height = 256
	return _halo

func _show_card(level: int) -> void:
	_card_level = level
	var element: String = element_of(level)
	var rival: String = str(DialogueDirector.RIVAL_NAMES.get(element, "ECHO"))
	var locked: bool = level not in _playable
	var best: int = int(_best.get(str(level), _best.get(level, 0)))
	_card_kicker.text = "LEVEL %d · %s" % [level, ElementStyle.display_name(element).to_upper()]
	_card_kicker.add_theme_color_override("font_color", ElementStyle.color(element) if not locked else UiTokens.INK_MUTED)
	_card_title.text = ("RIVAL · " + rival) if not locked else "LOCKED"
	if locked: _card_body.text = "Defeat level %d's rival to open this level." % (level - 1)
	elif best > 0: _card_body.text = "Best ring reached: %d. The rival %s waits at the far edge." % [best, rival]
	else: _card_body.text = "Not yet explored. The rival %s waits at the far edge." % rival
	if is_instance_valid(_launch_button):
		_launch_button.disabled = locked
		_launch_button.text = "LOCKED" if locked else "LAUNCH"
	_card_glyph.queue_redraw()

func _paint_card_glyph(canvas: MenuDraw) -> void:
	var element: String = element_of(_card_level)
	var locked: bool = _card_level not in _playable
	var ink: Color = ElementStyle.color(element) if not locked else UiTokens.INK_MUTED
	var centre: Vector2 = canvas.size * 0.5
	canvas.draw_circle(centre, canvas.size.x * 0.5, Color(ink.darkened(0.85), 0.9))
	canvas.draw_arc(centre, canvas.size.x * 0.5 - 1.0, 0.0, TAU, 48, Color(ink, 0.7), 1.5, true)
	if locked: ElementStyle.draw_lock(canvas, centre, canvas.size.x * 0.34, ink)
	else: ElementStyle.draw_glyph(canvas, element, centre, canvas.size.x * 0.26, ink, 2.5)
