class_name TitleScreen
extends UiScreen
## The main menu (moved from main.gd's `_show_menu` in M2). It is built into main.gd's `menu`
## group, not the overlay host: overlays (level select, options, confirm, cloud review) open on
## top of it. main.gd's `_show_menu` still tears the run down and calls this.
##
## M15: ONE press starts. The gold capsule (CONTINUE with a save, BEGIN without) takes focus the
## frame the menu is built, before any of the intro has played; BEGIN on a profile with one playable
## level starts it directly instead of opening a level select with a single choice. Everything else
## is a compact secondary row, and the tools (Dev mode, and in the editor the Ship Workshop and
## Atlas) sit in a small corner. The intro - the wordmark's letters 30 ms apart, the column, the
## hero - is skipped by any press, and never delays control: the capsule is focusable from the
## start. Behind it: a slow parallax lattice, drifting motes and the hero ship on a slow orbit.

## The margin around the menu at the design size; M6 shrinks it toward the safe margin, then scales
## the whole layout down, when the UI rect is too small for the columns (UI scale 140%).
const SIDE_MARGIN: float = 80.0
const END_MARGIN: float = 56.0
const WORDMARK: String = "LIGHTSHIP"
const WORDMARK_SIZE: int = 80
const LETTER_STAGGER: float = 0.03
## How far the hero drifts on its orbit, px, and the orbit's period, s.
const ORBIT: Vector2 = Vector2(16, 10)
const ORBIT_PERIOD: float = 18.0
## The lattice pitch and how far the pointer shifts it (a fraction of the pointer's offset).
const LATTICE: float = 56.0
const PARALLAX: float = 0.018
const MOTES: int = 56

## Milliseconds from process start to the moment the primary action first held focus, for the
## launch -> control measurement (ui_focus_nav_test; `--launch-probe` prints it and quits).
static var cta_focus_msec: int = -1

var _layout: MarginContainer
var _columns: HBoxContainer
var _primary: Button
var _stage: MenuDraw
var _hero: ShipPreview
var _sky: MenuDraw
var _intro: Array[Tween] = []
var _parallax: Vector2 = Vector2.ZERO

## M6: fits the menu to the host. The margins give way first (to the safe margin), then the layout
## scales down as one; at 1280x800 and scale 1 the margins are the design's 80/56.
func layout() -> void:
	if not is_instance_valid(_layout) or not is_instance_valid(host): return
	var area: Vector2 = host.size
	var content: Vector2 = _columns.get_combined_minimum_size()
	# One px of slack each way: the margins below are rounded up to whole px, which would otherwise
	# push a layout scaled to fit exactly past the safe rect by the rounding (0.7 px measured).
	var safe: Vector2 = area - Vector2.ONE * (UiLayout.SAFE_MARGIN * 2.0 + 2.0)
	var s: float = minf(1.0, minf(safe.x / maxf(1.0, content.x), safe.y / maxf(1.0, content.y)))
	var inner: Vector2 = area / s
	var least: float = UiLayout.SAFE_MARGIN / s
	var side: float = clampf((inner.x - content.x) * 0.5, least, maxf(SIDE_MARGIN, least))
	var ends: float = clampf((inner.y - content.y) * 0.5, least, maxf(END_MARGIN, least))
	for edge: String in ["left", "right"]: _layout.add_theme_constant_override("margin_" + edge, ceili(side))
	for edge: String in ["top", "bottom"]: _layout.add_theme_constant_override("margin_" + edge, ceili(ends))
	_layout.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_layout.scale = Vector2(s, s)
	_layout.position = Vector2.ZERO
	_layout.size = inner

func build() -> void:
	var background := ColorRect.new()
	background.color = VisualStyle.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiLayout.mark_bleed(background)
	host.add_child(background)
	# A faint pool of the player's blue light behind the hero ship. A float texture: 8-bit steps of
	# a low alpha band visibly in HDR 2D's linear blending.
	var pool := GradientTexture2D.new()
	pool.width = 640
	pool.height = 400
	pool.use_hdr = true
	pool.fill = GradientTexture2D.FILL_RADIAL
	pool.fill_from = Vector2(0.69, 0.5)
	pool.fill_to = Vector2(1.03, 0.5)
	pool.gradient = Gradient.new()
	pool.gradient.set_color(0, Color(UiTokens.PLAYER, 0.035))
	pool.gradient.set_color(1, Color(UiTokens.PLAYER, 0.0))
	pool.gradient.add_point(0.45, Color(UiTokens.PLAYER, 0.012))
	var light_pool := TextureRect.new()
	light_pool.texture = pool
	light_pool.stretch_mode = TextureRect.STRETCH_SCALE
	light_pool.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	light_pool.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	light_pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.mark_bleed(light_pool)
	host.add_child(light_pool)
	_sky = MenuDraw.new(_paint_sky)
	_sky.name = "TitleSky"
	_sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sky.input_handler = _skip_intro
	_sky.animate = true
	UiLayout.mark_bleed(_sky)
	host.add_child(_sky)
	var margin := MarginContainer.new()
	margin.name = "MenuLayout"
	_layout = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, int(SIDE_MARGIN))
	for side: String in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, int(END_MARGIN))
	host.add_child(margin)
	var columns := HBoxContainer.new()
	_columns = columns
	# Text scale changes the columns' minimum after the fact (Labels re-measure): refit then too.
	columns.minimum_size_changed.connect(layout)
	columns.add_theme_constant_override("separation", 48)
	margin.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 440
	left.add_theme_constant_override("separation", 12)
	columns.add_child(left)
	var kicker: Label = menu_label(left, "AN INSTANCE AWAKENS", UiTokens.TEXT_XS, GOLD)
	kicker.theme_type_variation = UiTokens.KICKER_LABEL
	var wordmark := HBoxContainer.new()
	wordmark.name = "Wordmark"
	wordmark.add_theme_constant_override("separation", 1)
	left.add_child(wordmark)
	var letters: Array[Label] = []
	for letter: String in WORDMARK:
		letters.append(menu_label(wordmark, letter, WORDMARK_SIZE, WHITE))
	var tagline: Label = menu_label(left, "Absorb light. Become something new.", UiTokens.TEXT_L, MUTED)
	var gap := Control.new()
	gap.custom_minimum_size.y = 26
	left.add_child(gap)
	## Available modes for THIS build flavour (spec §4: a demo build offers
	## demo only -- Dev must never be reachable there). The old "PLAY THE
	## DEMO" full-build entry is gone: the demo is its own build flavour now
	## (approved preamble), not a menu option inside the full campaign.
	var available_modes: Array[String] = ModeConfig.available_modes(OS.has_feature("demo"))
	var menu_mode: String = available_modes[0]
	var menu_slot: String = ModeConfig.from_id(menu_mode).save_slot()
	var snapshot: Dictionary = SaveService.load_snapshot(menu_slot)
	var exists: bool = not snapshot.is_empty() or FileAccess.file_exists(SaveService.snapshot_path(menu_slot))
	_primary = button(left, "CONTINUE" if exists else "BEGIN", Rect2(0, 0, 0, 60), _start.bind(exists, menu_mode, menu_slot))
	_primary.name = "Primary"
	_primary.theme_type_variation = UiTokens.PRIMARY_BUTTON
	_primary.custom_minimum_size = Vector2(340, 60)
	_primary.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_primary.add_theme_font_size_override("font_size", UiTokens.TEXT_L)
	_primary.focus_entered.connect(_on_primary_focused)
	var status: Label = menu_label(left, _status_line(exists, menu_mode, snapshot), UiTokens.TEXT_S, MUTED)
	status.name = "SaveStatus"
	var gap_after := Control.new()
	gap_after.custom_minimum_size.y = 14
	left.add_child(gap_after)
	var secondary := HFlowContainer.new()
	secondary.name = "Secondary"
	secondary.add_theme_constant_override("h_separation", 8)
	secondary.add_theme_constant_override("v_separation", 8)
	left.add_child(secondary)
	_secondary(secondary, "OPTIONS", app._show_options)
	if exists and not OS.has_feature("demo"): _secondary(secondary, "NEW CAMPAIGN", app._confirm_new)
	if exists and OS.has_feature("demo"): _secondary(secondary, "NEW DEMO", app._confirm_new.bind(true))
	if not OS.has_feature("demo") and not SaveService.load_snapshot("demo").is_empty():
		_secondary(secondary, "IMPORT DEMO", app._import_demo)
	if app.platform.online and not OS.has_feature("demo"):
		app.cloud_review = app.platform.inspect_cloud(menu_slot)
		app.cloud_sync_ready = str(app.cloud_review.get("state", "")) in ["same", "missing"]
		if str(app.cloud_review.get("state", "")) in ["conflict", "remote_only"]:
			_secondary(secondary, "REVIEW CLOUD SAVE", app._show_cloud_review)
	_secondary(secondary, "QUIT", app._quit)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	var hints := PromptHints.new([["ui_accept", "START"], ["navigate", "MOVE"]])
	hints.name = "Hints"
	left.add_child(hints)
	var flavour: Label = menu_label(left, "DEMO · LIGHTNING / FIRE · LEVELS 1–2" if OS.has_feature("demo") else "FIVE ELEMENTS · ONE LIVING MACHINE", UiTokens.TEXT_XS, MUTED)
	flavour.theme_type_variation = UiTokens.KICKER_LABEL
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	columns.add_child(right)
	_stage = MenuDraw.new(_paint_orbit)
	_stage.name = "HeroStage"
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.custom_minimum_size = Vector2(360, 360) + ORBIT * 2.0
	_stage.on_tick = _orbit
	_stage.animate = true
	right.add_child(_stage)
	var hero := ShipPreview.new()
	hero.name = "MenuHero"
	hero.focus_mode = Control.FOCUS_NONE
	hero.custom_minimum_size = Vector2(360, 360)
	hero.preview_time_scale = 1.0
	hero.fit_margin = 48.0
	# M6: a stretched container reports only its custom minimum. Unstretched, a SubViewportContainer's
	# minimum is its viewport's size, which fit_to_area grows with the container: the hero could grow
	# with a wide window and then never let the menu shrink again.
	hero.stretch = true
	_stage.add_child(hero)
	hero.initialize(ShipCatalog.get_ship("player_lightning_t3_standard_a"), Vector2(560, 640), 1.8)
	_hero = hero
	_stage.resized.connect(func() -> void: _orbit(_stage, 0.0))
	var tools: Array = _tools(available_modes)
	var tool_buttons: Array = []
	if not tools.is_empty():
		var corner := HBoxContainer.new()
		corner.name = "Tools"
		corner.alignment = BoxContainer.ALIGNMENT_END
		corner.add_theme_constant_override("separation", 8)
		right.add_child(corner)
		var caption: Label = menu_label(corner, "TOOLS", UiTokens.TEXT_XS, MUTED)
		caption.theme_type_variation = UiTokens.KICKER_LABEL
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for tool: Array in tools: tool_buttons.append(_secondary(corner, str(tool[0]), tool[1]))
	_focus = _primary
	# Rows: the capsule, the secondary actions, the tools. Linked once the containers have sorted
	# (the up/down targets are chosen by position).
	var lines: Array = [[_primary], secondary.get_children(), tool_buttons]
	(func() -> void: FocusChain.rows(lines)).call_deferred()
	# The menu is not a router screen (it is built into main.gd's `menu` group), so it runs its own
	# entrance: the wordmark letter by letter, then the column top to bottom, then the ship.
	for index: int in range(letters.size()): _intro.append(_letter_in(letters[index], 0.06 + LETTER_STAGGER * index))
	var column: Array = [kicker, tagline, _primary, status, secondary.get_children(), hints, flavour]
	_intro.append_array(UiMotion.stagger(column, 0.06 + LETTER_STAGGER * letters.size()))
	_intro.append(UiMotion.enter(right, 0.12))
	if "--launch-probe" in OS.get_cmdline_user_args(): _primary.focus_entered.connect(_launch_probe, CONNECT_ONE_SHOT | CONNECT_DEFERRED)

## Dev mode where the build allows it (every full build: spec §4 keeps it shipped); the ship
## workshop and atlas only in the editor.
func _tools(available_modes: Array[String]) -> Array:
	var result: Array = []
	if "dev" in available_modes: result.append(["DEV MODE", app._show_level_select.bind("dev")])
	if OS.has_feature("editor"):
		result.append(["WORKSHOP", app._open_editor])
		result.append(["ATLAS", app._open_gallery])
	return result

## CONTINUE resumes the save; BEGIN starts level 1 at once when it is the only playable level
## (a fresh profile), and opens level select otherwise.
func _start(exists: bool, mode_id: String, save_slot: String) -> void:
	if exists:
		app._continue_game(save_slot)
		return
	if ModeConfig.from_id(mode_id).selectable_levels([]).size() == 1: app._begin_at_level(mode_id, 1)
	else: app._show_level_select(mode_id)

static func _status_line(exists: bool, mode_id: String, snapshot: Dictionary) -> String:
	var mode_name: String = ModeConfig.from_id(mode_id).menu_label().capitalize()
	if not exists: return "%s · a new instance, level 1" % mode_name
	var profile: Dictionary = snapshot.get("profile", {})
	var level: int = int(profile.get("level", 1))
	var cleared: int = Array(profile.get("levels_completed", [])).size()
	var reboots: int = int(profile.get("deaths", 0))
	return "%s · level %d · %d cleared · %d reboot%s" % [mode_name, level, cleared, reboots, "" if reboots == 1 else "s"]

## A compact secondary action: a small ghost capsule.
func _secondary(parent: Node, text: String, action: Callable) -> Button:
	var result: Button = button(parent, text, Rect2(0, 0, 0, 34), action)
	result.clip_text = false
	result.custom_minimum_size.y = 34
	result.add_theme_font_size_override("font_size", UiTokens.TEXT_XS)
	var ghost: StyleBoxFlat = UiKit.glass_box(Color(UiTokens.GLASS, 0.45), Color(UiTokens.STROKE, 0.9), 1, UiTokens.CAPSULE)
	ghost.content_margin_left = UiTokens.SPACE_4
	ghost.content_margin_right = UiTokens.SPACE_4
	ghost.content_margin_top = UiTokens.SPACE_1
	ghost.content_margin_bottom = UiTokens.SPACE_1
	result.add_theme_stylebox_override("normal", ghost)
	for state: String in ["hover", "focus", "pressed"]:
		var lit: StyleBoxFlat = result.get_theme_stylebox(state, &"Button").duplicate()
		lit.content_margin_left = ghost.content_margin_left
		lit.content_margin_right = ghost.content_margin_right
		lit.content_margin_top = ghost.content_margin_top
		lit.content_margin_bottom = ghost.content_margin_bottom
		result.add_theme_stylebox_override(state, lit)
	return result

## A letter drops in: a fade and a scale from 70 % on the out-back pop, `delay` s after the build.
func _letter_in(letter: Label, delay: float) -> Tween:
	var result: Tween = UiMotion.enter(letter, delay)
	letter.scale = Vector2.ONE * 0.7
	result.tween_method(func(t: float) -> void:
		letter.pivot_offset = letter.size * Vector2(0.5, 0.8)
		letter.scale = Vector2.ONE * lerpf(0.7, 1.0, UiMotion.out_back(t)), 0.0, 1.0, UiMotion.duration(UiTokens.BASE)).set_delay(UiMotion.duration(delay))
	return result

## Any press finishes the intro at once (the press itself still does what it does: Enter on the
## focused capsule both skips and starts).
func _skip_intro(event: InputEvent) -> void:
	if _intro.is_empty(): return
	var press: bool = (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed) or (event is InputEventJoypadButton and event.pressed)
	if not press: return
	for tween: Tween in _intro:
		if tween != null and tween.is_valid(): tween.custom_step(60.0)
	_intro.clear()

func intro_running() -> bool:
	for tween: Tween in _intro:
		if tween != null and tween.is_valid() and tween.is_running(): return true
	return false

func _on_primary_focused() -> void:
	if cta_focus_msec < 0: cta_focus_msec = Time.get_ticks_msec()

## `--launch-probe`: print launch -> control and quit (a real, windowed launch; see the M15 report).
func _launch_probe() -> void:
	print("LAUNCH PROBE: cta_focus_ms=%d focusable=%s" % [cta_focus_msec, str(_primary.focus_mode != Control.FOCUS_NONE and _primary.is_visible_in_tree())])
	app._quit()

## The hero's slow orbit inside its stage (and a slight bank with it). The hero is inset by the orbit
## so it never leaves the stage.
func _orbit(stage: MenuDraw, _delta: float) -> void:
	if not is_instance_valid(_hero): return
	var angle: float = TAU * stage.clock / ORBIT_PERIOD
	var inset: Vector2 = stage.size - ORBIT * 2.0
	if _hero.size != inset: _hero.size = inset
	_hero.position = ORBIT + Vector2(cos(angle) * ORBIT.x, sin(angle) * ORBIT.y)
	_hero.pivot_offset = inset * 0.5
	_hero.rotation = sin(angle * 0.5) * 0.035

## Two faint orbit rings around the hero with a bead of light travelling each.
func _paint_orbit(stage: MenuDraw) -> void:
	var centre: Vector2 = stage.size * 0.5
	var reach: float = minf(stage.size.x, stage.size.y) * 0.5
	for ring: int in range(2):
		var radii := Vector2(reach * (0.86 + ring * 0.1), reach * (0.34 + ring * 0.05))
		var tilt: float = -0.32 + ring * 0.5
		var points := PackedVector2Array()
		for step: int in range(73):
			points.append(centre + Vector2(cos(TAU * step / 72.0) * radii.x, sin(TAU * step / 72.0) * radii.y).rotated(tilt))
		stage.draw_polyline(points, Color(UiTokens.PLAYER, 0.07 + ring * 0.02), 1.0, true)
		var t: float = TAU * stage.clock / (11.0 + ring * 7.0) * (1.0 if ring == 0 else -1.0) + ring * 2.1
		var bead: Vector2 = centre + Vector2(cos(t) * radii.x, sin(t) * radii.y).rotated(tilt)
		stage.draw_circle(bead, 2.2, Color(UiTokens.PLAYER if ring == 0 else UiTokens.FOCUS, 0.7))
		stage.draw_circle(bead, 6.0, Color(UiTokens.PLAYER if ring == 0 else UiTokens.FOCUS, 0.08))

## The sky: a slow hex lattice of faint points that drifts and follows the pointer a little
## (parallax), and motes of light rising at three depths.
func _paint_sky(sky: MenuDraw) -> void:
	var area: Vector2 = sky.size
	var pointer: Vector2 = sky.get_local_mouse_position() if sky.is_inside_tree() else area * 0.5
	var target: Vector2 = (pointer - area * 0.5) * -PARALLAX if Rect2(Vector2.ZERO, area).has_point(pointer) else Vector2.ZERO
	_parallax = _parallax.lerp(target, 0.05)
	var drift := Vector2(sky.clock * 3.0, sky.clock * -1.5)
	var row_height: float = LATTICE * 0.866
	var origin: Vector2 = Vector2(fposmod(drift.x + _parallax.x, LATTICE), fposmod(drift.y + _parallax.y, row_height * 2.0)) - Vector2(LATTICE, row_height * 2.0)
	var rows: int = int(area.y / row_height) + 4
	var cols: int = int(area.x / LATTICE) + 3
	for row: int in range(rows):
		for col: int in range(cols):
			var at: Vector2 = origin + Vector2(col * LATTICE + (LATTICE * 0.5 if row % 2 == 1 else 0.0), row * row_height)
			# Fade the lattice toward the menu column so the text sits on clean black.
			var fade: float = clampf((at.x / area.x - 0.2) * 1.6, 0.25, 1.0)
			sky.draw_circle(at, 1.1, Color(UiTokens.PLAYER, 0.09 * fade))
	for index: int in range(MOTES):
		var seed_a: float = fposmod(sin(index * 12.9898) * 43758.5453, 1.0)
		var seed_b: float = fposmod(sin(index * 78.233) * 12543.1234, 1.0)
		var depth: int = index % 3
		var speed: float = 6.0 + depth * 7.0
		var y: float = fposmod(seed_b * (area.y + 40.0) - sky.clock * speed, area.y + 40.0) - 20.0
		var x: float = seed_a * area.x + sin(sky.clock * 0.25 + index) * 18.0 + _parallax.x * (1.0 + depth)
		var twinkle: float = 0.55 + 0.45 * sin(sky.clock * (0.8 + seed_a) + index * 1.7)
		var ink: Color = UiTokens.FOCUS if index % 9 == 0 else UiTokens.PLAYER
		sky.draw_circle(Vector2(x, y), 0.9 + depth * 0.55, Color(ink, (0.10 + depth * 0.07) * twinkle))
