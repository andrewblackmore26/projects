class_name Hud
extends RefCounted
## The in-combat HUD. Moved out of main.gd in modernization M2; M6 made it a set of named
## clusters anchored by `layout()`; M11b rebuilt their contents as the floating "Luminous
## Instrument" HUD: no bars across the screen, only instruments floating in the corners.
##
## - TopLeft, LightBar (light_bar.gd): the tier emblem and the Light bar with its ghost, lead,
##   ticks, floor and element pips; its EVOLVE capsule is a cluster of its own.
## - TopCenter: the combo meter (combo_meter.gd) or, while the node's rival lives, the boss bar
##   (boss_bar.gd). The slot keeps its rect while its meter fades, so nothing else takes the room.
## - Minimap (minimap.gd) in the top-right corner, clickable to open the map; under it TopRight,
##   the map and pause hints, each wearing the device's glyph (input_prompts.gd).
## - AbilityDock (ability_dock.gd) at the bottom centre.
## - EdgeIndicators (edge_indicators.gd) over the play area: the rival's chevron always, other
##   enemies' with `radar`, and every queued rim spawn.
## The build readout left the HUD (it is on the pause screen); `component_controls` stays for tests.
##
## Update rule: `update(dt)` runs every frame. Bars and rings read the sim every frame; a Label's
## text is set only when its formatted value changes. `refresh()` (dt 0) re-reads without motion.
## tests/ui_layout_test.gd holds every cluster inside the safe rect and apart from the others at
## four window sizes and two text and UI scales.

const BLUE := VisualStyle.BLUE
const WHITE := VisualStyle.TEXT
const MUTED := VisualStyle.MUTED
const GOLD := VisualStyle.ACCENT

## The bands the floating clusters occupy at the top and bottom of the UI rect: the toast sits
## under TOP_BAR and the dialogue box above BOTTOM_BAR (toast_stack.gd, dialogue_box.gd).
const TOP_BAR: float = 88.0
const BOTTOM_BAR: float = 96.0
## Clear space between clusters.
const GAP: float = 16.0
## The narrowest centred boss bar the top row may hold before the bar drops under the light bar.
const BOSS_TOP_MIN: float = 440.0
const HINT_HEIGHT: float = 30.0
## The minimap is a map, not a meter: it redraws at this period, not every frame.
const MINIMAP_PERIOD: float = 0.1
const FONT_DISPLAY_ITALIC: String = "res://assets/fonts/exo2/Exo2-Italic-Variable.ttf"

## HUD cost, microseconds, since the last reset: `update` (sim reads, models, text) and every
## widget's draw callback. tests/ui_hud_render_test.gd reads them over 300 frames.
static var update_usec: int = 0
static var draw_usec: int = 0
static var frames: int = 0
static var _fonts: Dictionary = {}
static var _pill: StyleBoxFlat

var app: Node
var root: Control
var light_bar: LightBar
var combo: ComboMeter
var boss_bar: BossBar
var dock: AbilityDock
var edges: EdgeIndicators
var minimap: Minimap
var top_left: Control
var top_center: Control
var top_right: Control
var map_button: Button
var pause_button: Button
var evolution_button: Button
var slot_overlay: Control
var radar_overlay: Control
var boss_mode: bool = false
var _combat_seen: Object
var _minimap_elapsed: float = 0.0
var _hint_paths: Dictionary = {}

func _init(owner: Node, hud_root: Control) -> void:
	app = owner
	root = hud_root

## Every cluster by name, for layout tests.
func clusters() -> Array[Control]:
	return [top_left, top_center, top_right, minimap.minimap, slot_overlay, evolution_button]

## M19 review: a screen that lays itself over the run (the evolution cards) fades the top
## clusters to DIM_ALPHA so its own header reads; the edge indicators (threats) stay at full.
const DIM_ALPHA: float = 0.25
func set_dimmed(on: bool) -> void:
	for item: Control in [top_left, top_center, top_right, minimap.minimap, evolution_button]:
		if is_instance_valid(item): UiMotion.tween(item).tween_property(item, "modulate:a", DIM_ALPHA if on else 1.0, UiMotion.duration(UiTokens.FAST, true))

static func cluster(parent: Control, name: String) -> Control:
	var result := Control.new()
	result.name = name
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

## The HUD's faces: `display` (Exo 2 Bold, tabular), `display_wide` (letter-spaced, for names),
## `display_semibold` (Exo 2 SemiBold, tabular, the light bar's tier ticks), `combo` (Exo 2 Black
## Italic) and `body` (Inter SemiBold, tabular).
static func font(role: StringName) -> Font:
	if _fonts.has(role): return _fonts[role]
	var result: Font
	match role:
		&"display": result = UiKit.font(UiTokens.FONT_DISPLAY, UiTokens.WEIGHT_DISPLAY, true)
		&"display_semibold": result = UiKit.font(UiTokens.FONT_DISPLAY, UiTokens.WEIGHT_BUTTON, true)
		&"display_wide": result = UiKit.font(UiTokens.FONT_DISPLAY, UiTokens.WEIGHT_DISPLAY, false, 3)
		&"combo": result = UiKit.font(FONT_DISPLAY_ITALIC, 900, true)
		_: result = UiKit.font(UiTokens.FONT_BODY, UiTokens.WEIGHT_BODY_STRONG, true)
	_fonts[role] = result
	return result

## A rounded bar segment (a capsule when it is wider than tall). One shared StyleBoxFlat: a
## StyleBoxFlat emits its geometry when drawn, so recolouring it between calls is safe.
static func draw_pill(canvas: CanvasItem, rect: Rect2, colour: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0: return
	if _pill == null:
		_pill = StyleBoxFlat.new()
		_pill.anti_aliasing = true
		_pill.corner_detail = 8
	_pill.bg_color = colour
	_pill.set_corner_radius_all(roundi(minf(rect.size.x, rect.size.y) * 0.5))
	canvas.draw_style_box(_pill, rect)

static func reset_cost() -> void:
	update_usec = 0
	draw_usec = 0
	frames = 0

func build() -> void:
	edges = EdgeIndicators.new(app)
	edges.build(root)
	radar_overlay = edges.root
	light_bar = LightBar.new(app)
	light_bar.build(root)
	top_left = light_bar.cluster
	evolution_button = light_bar.evolve
	top_center = cluster(root, "TopCenter")
	combo = ComboMeter.new(app)
	combo.build(top_center)
	boss_bar = BossBar.new(app)
	boss_bar.build(top_center)
	minimap = Minimap.new(app)
	minimap.build(root)
	# The minimap opens the full map on a click.
	minimap.minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap.minimap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	minimap.minimap.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: app._show_map())
	top_right = cluster(root, "TopRight")
	map_button = _hint(top_right, "MAP", app._show_map)
	pause_button = _hint(top_right, "PAUSE", app._show_pause)
	dock = AbilityDock.new(app)
	dock.build(root)
	slot_overlay = dock.root
	root.visible = false
	UiLayout.scale_text(root)
	layout()

## A small glass capsule: the action's device glyph and one word.
func _hint(parent: Control, word: String, action: Callable) -> Button:
	var result: Button = app.button(parent, word, Rect2(Vector2.ZERO, Vector2(80, HINT_HEIGHT)), action)
	result.name = word.capitalize() + "Hint"
	result.focus_mode = Control.FOCUS_NONE
	# Sized to its content by layout(), so it never clips (a clipping Button reports no text width).
	result.clip_text = false
	result.add_theme_font_size_override("font_size", UiTokens.TEXT_XS)
	result.add_theme_font_override("font", font(&"body"))
	# icon_max_width scales the 64 px glyph down AND counts it in the minimum size; expand_icon
	# would leave the icon out of the minimum, and layout() sizes the capsule to its minimum.
	result.add_theme_constant_override("icon_max_width", 20)
	result.add_theme_constant_override("h_separation", 6)
	var style: StyleBoxFlat = UiKit.glass_box(UiTokens.GLASS, UiTokens.STROKE, 1, UiTokens.CAPSULE)
	style.content_margin_left = 8
	style.content_margin_right = 12
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	var lit: StyleBoxFlat = style.duplicate()
	lit.border_color = GOLD
	for state: String in ["normal", "focus"]: result.add_theme_stylebox_override(state, style)
	for state: String in ["hover", "pressed", "hover_pressed"]: result.add_theme_stylebox_override(state, lit)
	result.add_theme_color_override("font_color", Color(MUTED, 1.0).lerp(WHITE, 0.4))
	result.set_meta(&"hint_word", word)
	return result

## The hints wear the glyph of the device in hand. Returns whether one changed (the row resizes).
func _refresh_hints() -> bool:
	var changed: bool = false
	for pair: Array in [[map_button, "map"], [pause_button, "pause"]]:
		var button: Button = pair[0]
		var prompt: Dictionary = InputPrompts.shared().prompt_for(str(pair[1]))
		var key: String = str(prompt.path) if prompt.texture != null else "text:" + str(prompt.text)
		if _hint_paths.get(pair[1], "") == key: continue
		_hint_paths[pair[1]] = key
		button.icon = prompt.texture
		var word: String = str(button.get_meta(&"hint_word"))
		button.text = word if prompt.texture != null else "%s · %s" % [word, str(prompt.text)]
		changed = true
	return changed

## Places every cluster for the current UI rect (main.gd's layout_ui runs it on every resize and
## text-scale change; the widgets run it when their shape changes). Pure placement.
func layout() -> void:
	if top_left == null: return
	var size: Vector2 = root.size
	var safe: Rect2 = UiLayout.safe_rect(size)
	var left_end: float = light_bar.layout(safe.position, size)
	# Top right: the minimap in the corner, the hints right-aligned under it.
	minimap.layout(Vector2(safe.end.x, safe.position.y))
	var corner: Rect2 = Rect2(minimap.minimap.position, minimap.minimap.size)
	_refresh_hints()
	var x: float = 0.0
	for button: Button in [map_button, pause_button]:
		button.size = Vector2(button.get_minimum_size().x, HINT_HEIGHT)
		button.position = Vector2(x, 0)
		x += button.size.x + 8.0
	top_right.size = Vector2(x - 8.0, HINT_HEIGHT)
	top_right.position = Vector2(safe.end.x - top_right.size.x, corner.end.y + 8.0)
	# Top centre: the combo or the boss bar, centred on the screen in the room between the corners.
	var room_from: float = left_end + GAP
	var room_to: float = corner.position.x - GAP
	combo.root.position = Vector2.ZERO
	boss_bar.root.position = Vector2.ZERO
	if boss_mode:
		_layout_boss(size, safe, room_from, room_to)
	else:
		var slot: Vector2 = combo.layout()
		top_center.size = slot
		var left: float = clampf(size.x * 0.5 - slot.x * 0.5, room_from, maxf(room_from, room_to - slot.x))
		top_center.position = Vector2(roundf(left), safe.position.y)
	dock.layout(size, safe)
	edges.layout(safe)
	# The toasts stack under the top clusters: they follow the boss bar when it comes and goes.
	var toasts: Variant = app.get("toast_stack")
	if toasts != null and not toasts.toasts.is_empty(): toasts.layout(toasts.parent.size, true)

## The boss bar is always centred on the screen. It takes the top row when a centred bar at least
## BOSS_TOP_MIN wide fits between the corner clusters (21:9); otherwise (16:9, 16:10: the light bar
## and its EVOLVE reserve reach past the centre line's room) it drops to the row under the light
## bar, still centred, where only the minimap column limits it.
func _layout_boss(size: Vector2, safe: Rect2, room_from: float, room_to: float) -> void:
	var centre: float = size.x * 0.5
	var top_room: float = 2.0 * minf(centre - room_from, room_to - centre)
	var y: float = safe.position.y
	var room: float = top_room
	if top_room < BOSS_TOP_MIN:
		y = top_left.position.y + top_left.size.y + GAP
		room = 2.0 * minf(centre - safe.position.x, room_to - centre)
	var slot: Vector2 = boss_bar.layout(maxf(0.0, room))
	top_center.size = slot
	top_center.position = Vector2(roundf(centre - slot.x * 0.5), roundf(y))

## What the edge chevrons must not draw over, in the EdgeIndicators' own coordinates: the dock and
## the open dialogue panel, each grown by KEEP_OUT (a chevron's reach: the spawn ring's widest
## radius, 22 px x 1.35 for an elite, plus a GAP of clear space).
const KEEP_OUT: float = 30.0 + GAP
func keep_out_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	var origin: Vector2 = edges.root.position
	if slot_overlay.visible: result.append(Rect2(slot_overlay.position - origin, slot_overlay.size).grow(KEEP_OUT))
	var panel: Control = app.dialogue.get_node_or_null("DialoguePanel") if app.get("dialogue") != null else null
	if panel != null and panel.is_visible_in_tree(): result.append(Rect2(panel.get_global_rect().position - root.get_global_rect().position - origin, panel.size).grow(KEEP_OUT))
	return result

## One frame of the HUD (main.gd's _process, every frame in play).
func update(dt: float) -> void:
	var started: int = Time.get_ticks_usec()
	refresh(dt)
	update_usec += Time.get_ticks_usec() - started
	frames += 1

func refresh(dt: float = 0.0) -> void:
	var combat: CombatWorld = app.combat
	var campaign: CampaignState = app.campaign
	if not is_instance_valid(combat) or campaign == null: return
	var ship: ShipDefinition = combat.player.get("definition")
	if ship == null: return
	if combat != _combat_seen:
		# A new run or a restored one: every meter starts from what the sim holds, with no motion.
		_combat_seen = combat
		light_bar.meter = GhostMeter.new()
		light_bar._tier = -1
		combo.reset()
		dock.reset()
	app.absorbed = combat.absorption
	var relayout: bool = false
	light_bar.update(dt)
	var boss: Dictionary = BossBar.boss_of(combat)
	var boss_up: bool = boss_bar.update(dt, boss)
	if boss_up != boss_mode:
		boss_mode = boss_up
		relayout = true
	combo.update(dt, not boss_mode)
	relayout = dock.update(dt) or relayout
	relayout = _refresh_hints() or relayout
	if relayout: layout()
	# The dialogue box comes and goes between layouts: the keep-out follows it every frame.
	edges.keep_out = keep_out_rects()
	edges.update()
	_minimap_elapsed += dt
	if dt <= 0.0 or _minimap_elapsed >= MINIMAP_PERIOD:
		_minimap_elapsed = 0.0
		minimap.redraw()

## The secondary bindings as text ("SPACE: Bolt | SHIFT: Nova 1.2s"), or "Secondary: None". The
## HUD no longer shows it (M11b); main.gd's `_component_controls` forwards here and the roster
## test drives it for every hull.
func component_controls() -> String:
	var combat: CombatWorld = app.combat
	var ship: ShipDefinition = combat.player.get("definition")
	if ship == null: return ""
	var labels := PackedStringArray()
	for index: int in range(ship.secondaries.size()):
		var id: String = ship.secondaries[index]
		var cooldowns: Dictionary = combat.player.get("cooldowns",{})
		var cooldown: float = float(cooldowns.get("secondary_%d" % index,0.0))
		labels.append("%s: %s%s" % [InputPrompts.shared().text_for(InputPrompts.SLOT_ACTIONS[index]),UiKit.ability_name(id)," %.1fs" % cooldown if cooldown>0 else ""])
	return " | ".join(labels) if not labels.is_empty() else "Secondary: None"

## Where the ray from `from` (inside `rim`) toward `to` leaves `rim` (EdgeIndicators places every
## chevron with it; ui_layout_test checks it in 16 directions).
static func radar_rim_point(rim: Rect2, from: Vector2, to: Vector2) -> Vector2:
	return EdgeIndicators.rim_point(rim, from, to)
