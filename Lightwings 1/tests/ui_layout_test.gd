extends SceneTree
## Modernization M6: the interface fits every window it can be given.
##
## Every screen and every HUD state is built once in the real main.gd, then laid out at the four
## sizes of tests/support/viewport_matrix.gd (1280x720, 1280x800, 1920x1080, 2560x1080) at text
## scale 1.0 and 1.3, and at UI scale 0.8 and 1.4. At each, four instruments:
## - SAFE: every visible Control stays inside the 24 px safe rect (full-bleed backdrops and bars
##   excepted);
## - TEXT: no single-line Label is wider than its box (font.get_string_size), no wrapped Label has
##   lines its box cannot show, no Button needs more width than it has;
## - APART: the HUD's clusters, the dialogue box and the toast do not overlap one another;
## - the stretch rule: the UI rect is the expected logical size (height 800, "expand"), and a
##   window wider than 21:9 is pillarboxed at 1920 px.
## Plus composition: at 1280x800, UI scale 1 and text scale 1 every canvas screen is laid out
## exactly at its design coordinates (scale 1, offset 0).
## Plus the world side: the compositor's stages and camera centre follow the visible rect, and the
## arena backdrop's trace tiles cover every world px the camera shows.
## Negative controls, one per instrument line: a 200-character label (TEXT, label); a wrapped label
## grown into the text below it (TEXT, collisions); a button with a long caption (TEXT, button); a
## HUD cluster nudged off-screen (SAFE); a cluster moved onto its neighbour (APART); the UI layer
## scaled to 140 % without refitting the root (UI scale); the window's content scale forced to
## "expand" at 32:9 (the pillarbox rule); the pre-M6 fixed 1600x1000 trace tile at 21:9 (coverage).
## M19 UX review: the "options_gameplay" state is retired (its two rows joined Accessibility) and
## replaced by "options_accessibility", now the Options tab with the most rows.
const Harness = preload("res://tests/support/harness.gd")
const ViewportMatrix = preload("res://tests/support/viewport_matrix.gd")

const SCREENS: Array[String] = ["menu", "menu_saves", "level_select_campaign", "level_select_dev", "options_audio", "options_display", "options_controls", "options_accessibility", "pause", "evolution", "evolution_dev", "map", "death", "level_complete", "ending_campaign", "ending_demo", "cloud", "confirm_new", "import_confirm", "hud_origin", "hud_combat", "hud_evolve_ready", "hud_radar", "hud_dev", "dialogue", "toast"]

var h := Harness.new("UI layout")
var measured: Dictionary = {"layouts": 0, "controls": 0}
var min_canvas_scale: float = 1.0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for screen: String in SCREENS:
		await _screen(screen)
	print("measure: %d layouts, %d control placements checked; smallest canvas-screen scale %.3f" % [measured.layouts, measured.controls, min_canvas_scale])
	await _world_view()
	await _controls()
	h.finish(self)

func _new_app() -> Node:
	root.size = Vector2i(1280, 800)
	SaveService.storage_root = "user://ui-layout-%d" % Time.get_ticks_usec()
	var app: Node = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	return app

func _step(app: Node, ticks: int) -> void:
	app.combat.set_physics_process(false)
	for tick: int in range(ticks): app.combat._physics_process(1.0 / 60.0)

func _write_saves(app: Node) -> void:
	app._new_game(true)
	SaveService.save_snapshot(app.campaign.to_dict(), {}, "demo")
	app._new_game(false)
	SaveService.save_snapshot(app.campaign.to_dict(), {}, "campaign")

func _build(app: Node, screen: String) -> void:
	match screen:
		"menu": pass
		"menu_saves":
			_write_saves(app)
			app._show_menu()
		"level_select_campaign": app._show_level_select("campaign")
		"level_select_dev": app._show_level_select("dev")
		"options_audio", "options_display", "options_controls", "options_accessibility":
			app.options_tab = OptionsScreen.TAB_TITLES.find(screen.trim_prefix("options_").capitalize())
			app._show_options()
		"pause":
			app._new_game(false)
			_step(app, 1)
			app._close_overlay()
			app._show_pause()
		"evolution":
			app._new_game(false)
			_step(app, 1)
			app.combat.setup_player("lightning", 3, 1000, [], GameTuning.ARENA_CENTER)
			app.combat.absorption = {"lightning": 300.0, "fire": 100.0, "plasma": 80.0}
			app._show_evolution()
		"evolution_dev":
			app._new_game_as("dev")
			_step(app, 1)
			app.combat.collect_light(120.0, "lightning")
			app._show_evolution()
		"map":
			app._new_game(false)
			_step(app, 1)
			app._show_map()
		"death":
			app._new_game(false)
			_step(app, 1)
			app._on_death()
		"level_complete":
			app._new_game(false)
			_step(app, 1)
			app._show_level_complete({"next_level": 2, "revealed_element": "fire"})
		"ending_campaign", "ending_demo":
			app._new_game(screen == "ending_demo")
			_step(app, 1)
			app._show_ending(screen == "ending_demo")
		"cloud":
			app.cloud_review = {"state": "conflict", "local_summary": "Level 2 · T3 · 14 nodes", "remote_summary": "Level 1 · T2 · 6 nodes"}
			app._show_cloud_review()
		"confirm_new": app._confirm_new(false)
		"import_confirm":
			_write_saves(app)
			app._show_menu()
			app._import_demo()
		"hud_origin":
			app._new_game(false)
			app.line_queue.clear()
			_step(app, 30)
		"hud_combat", "hud_evolve_ready", "hud_radar":
			app._new_game(false)
			app.line_queue.clear()
			app.combat.set_physics_process(false)
			app.combat.setup_player("plasma", 4, 750, [], Vector2(896, 560))
			app.campaign.current_sector = Vector2i(-3, 2)
			var showcase: Dictionary = app.campaign.sector_at(app.campaign.current_sector)
			showcase.kind = "regular"
			app.combat.start_sector(showcase)
			if screen == "hud_evolve_ready":
				app.combat.setup_player("fire", 2, 0, [], Vector2(896, 560))
				app.combat.collect_light(float(EvolutionRules.threshold(2)) + 5.0, "fire")
			_step(app, 45)
			if screen == "hud_radar":
				# A long combo readout and a long toast at once: the busiest the HUD gets.
				app.combat.combo_count = 12
				app._toast("NODE CLEAR · the rival's signal yields · every exit is open")
		"hud_dev":
			app._new_game_as("dev")
			app.line_queue.clear()
			_step(app, 10)
			if is_instance_valid(app.dev_console): app.dev_console.toggle()
		"dialogue":
			app._new_game(false)
			_step(app, 1)
			# An immediate-lane line shows even with enemies up (the origin may hold a training wave).
			app.dialogue_director.queue_immediate("fire", "LAYOUT", "A companion line long enough to wrap onto a second line of the box at the design width, so the text scale has something to grow.", "m6_layout")
			app._update_dialogue(0.0)
			h.check(app.dialogue.visible and app.dialogue.get_node_or_null("DialoguePanel") != null, "the dialogue state shows its box")
		"toast":
			app._new_game(false)
			app.line_queue.clear()
			_step(app, 5)
			app._toast("NODE CLEAR · 0,0")
	if app.mode == "play" and is_instance_valid(app.combat): app._refresh_hud()

## Lays the UI out at `size`, text scale `text` and UI scale `ui_scale`, the way the game does.
func _apply(app: Node, size: Vector2i, text: float, ui_scale: float) -> void:
	app.settings.text_scale = text
	app.settings.ui_scale = ui_scale
	root.size = size
	app.apply_settings()
	await process_frame
	await process_frame
	if app.mode == "play" and is_instance_valid(app.combat): app._refresh_hud()

func _exempt(app: Node) -> Array:
	return [app.ui, app.hud, app.menu, app.overlay, app.dialogue]

## The rects APART judges, for the visible HUD clusters, dialogue panel and toast.
func _cluster_rects(app: Node) -> Dictionary:
	var rects: Dictionary = {}
	if app.hud.visible:
		for cluster: Control in app.hud_view.clusters():
			if cluster.is_visible_in_tree(): rects[str(cluster.name)] = cluster.get_global_rect()
	if app.dialogue.visible:
		var panel: Node = app.dialogue.get_node_or_null("DialoguePanel")
		if panel != null: rects["Dialogue"] = (panel as Control).get_global_rect()
	if app.toast_stack.label.is_visible_in_tree() and not app.toast_stack.label.text.is_empty(): rects["Toast"] = app.toast_stack.label.get_global_rect()
	return rects

## SAFE, TEXT and APART at the current layout; returns the number of failures it reported.
func _judge(app: Node, where: String) -> int:
	var controls: Array[Control] = ViewportMatrix.visible_controls(app.ui)
	var ui_size: Vector2 = app.ui.size
	measured.layouts += 1
	measured.controls += controls.size()
	var bad: int = 0
	var outside: PackedStringArray = ViewportMatrix.safe_violations(controls, ui_size, _exempt(app))
	if not h.check(outside.is_empty(), "%s: %d control(s) outside the safe rect of %s: %s" % [where, outside.size(), ui_size, "; ".join(outside.slice(0, 4))]): bad += 1
	var spilling: PackedStringArray = ViewportMatrix.text_overflows(controls)
	if not h.check(spilling.is_empty(), "%s: %d text overflow(s): %s" % [where, spilling.size(), "; ".join(spilling.slice(0, 4))]): bad += 1
	var colliding: PackedStringArray = ViewportMatrix.text_collisions(controls)
	if not h.check(colliding.is_empty(), "%s: %d text box collision(s): %s" % [where, colliding.size(), "; ".join(colliding.slice(0, 4))]): bad += 1
	var clashing: PackedStringArray = ViewportMatrix.overlaps(_cluster_rects(app))
	if not h.check(clashing.is_empty(), "%s: overlapping clusters: %s" % [where, ", ".join(clashing)]): bad += 1
	return bad

func _screen(screen: String) -> void:
	var app: Node = _new_app()
	await process_frame
	_build(app, screen)
	# Let every entrance (UiMotion: a staggered rise) settle: the layout judged is the resting one.
	await create_timer(UiTokens.STAGGER_MAX + UiTokens.SLOW + 0.1, true, false, true).timeout
	var built: String = app.overlay_kind
	var canvas: bool = app.overlay.visible
	# As built, before any relayout the test itself triggers (the game's own refresh order).
	_judge(app, "%s as built" % screen)
	for size: Vector2i in ViewportMatrix.SIZES:
		for text: float in ViewportMatrix.TEXT_SCALES:
			await _apply(app, size, text, 1.0)
			var where: String = "%s @ %s text %.1f" % [screen, ViewportMatrix.label(size), text]
			h.check(app.ui.size.is_equal_approx(ViewportMatrix.LOGICAL[size]), "%s: UI rect %s is the logical %s" % [where, app.ui.size, ViewportMatrix.LOGICAL[size]])
			_judge(app, where)
			if canvas: min_canvas_scale = minf(min_canvas_scale, app.overlay.scale.x)
			# Dev mode's four-card tab is wider than any 16:10 screen by design: it is the one canvas
			# screen expected to scale (measured below as the smallest canvas scale).
			if canvas and size == Vector2i(1280, 800) and text == 1.0 and screen != "evolution_dev":
				h.check(app.overlay.scale.is_equal_approx(Vector2.ONE) and app.overlay.position.is_zero_approx(), "%s: the canvas is at its design coordinates (scale %s, at %s)" % [where, app.overlay.scale, app.overlay.position])
	for size: Vector2i in ViewportMatrix.SIZES:
		for ui_scale: float in ViewportMatrix.UI_SCALES:
			await _apply(app, size, 1.0, ui_scale)
			var where: String = "%s @ %s UI %.0f%%" % [screen, ViewportMatrix.label(size), ui_scale * 100.0]
			h.check(app.ui_layer.scale.is_equal_approx(Vector2(ui_scale, ui_scale)) and app.ui.size.is_equal_approx(ViewportMatrix.LOGICAL[size] / ui_scale), "%s: the UI layer is scaled and the root refitted (%s)" % [where, app.ui.size])
			_judge(app, where)
			if canvas: min_canvas_scale = minf(min_canvas_scale, app.overlay.scale.x)
	h.check(app.overlay_kind == built, "%s: the screen was not replaced while it was measured ('%s')" % [screen, app.overlay_kind])
	await _apply(app, Vector2i(1280, 800), 1.0, 1.0)
	await app._stop_audio()
	app.queue_free()
	await process_frame
	await process_frame

## The world side of "read the visible rect": at every size the compositor's stages match the
## visible rect (the HDR stage at the window's physical resolution), the camera centres on the
## visible rect's middle, and the arena backdrop's backing and trace tiles cover all of the world
## the camera shows. The radar's rim point lies on its own rect.
func _world_view() -> void:
	var app: Node = _new_app()
	await process_frame
	_build(app, "hud_combat")
	var backdrop: ArenaBackdrop = null
	for child: Node in app.combat.get_children():
		if child is ArenaBackdrop: backdrop = child
	h.check(backdrop != null, "the run has an arena backdrop")
	var widest_view: Rect2
	for size: Vector2i in ViewportMatrix.SIZES:
		root.size = size
		await process_frame
		await process_frame
		var where: String = ViewportMatrix.label(size)
		var compositor: CombatCompositor = app.compositor
		var logical: Vector2 = ViewportMatrix.LOGICAL[size]
		h.check(compositor.view_size.is_equal_approx(logical) and compositor.background_image.size.is_equal_approx(logical), "%s: the compositor's stages are the visible rect %s (view %s, image %s)" % [where, logical, compositor.view_size, compositor.background_image.size])
		h.check(compositor.background_viewport.size == size, "%s: the HDR stage renders at the physical %s (got %s)" % [where, size, compositor.background_viewport.size])
		h.check(compositor.world_to_screen(compositor.rig.focus).is_equal_approx(logical * 0.5), "%s: the camera focus lands on the visible centre %s (got %s)" % [where, logical * 0.5, compositor.world_to_screen(compositor.rig.focus)])
		if backdrop == null: continue
		var view: Rect2 = backdrop.visible_world_rect()
		var player: Vector2 = app.combat.player_position
		var tile := Vector2(ArenaBackdrop.TRACE_TILE)
		var covered: Rect2 = Rect2(player - tile * 0.5, tile)
		for shift: Vector2 in ArenaBackdrop.trace_repeats(player, view): covered = covered.merge(Rect2(player - tile * 0.5 + shift, tile))
		h.check(covered.encloses(view), "%s: the trace tiles cover the visible world %s" % [where, view])
		if view.size.x > widest_view.size.x: widest_view = view
	var old_tile: Rect2 = Rect2(app.combat.player_position - Vector2(800, 500), Vector2(1600, 1000))
	print("measure: widest visible world rect %s (%.0f x %.0f world px)" % [widest_view, widest_view.size.x, widest_view.size.y])
	h.control("the pre-M6 fixed 1600x1000 trace tile against the 21:9 view", not old_tile.encloses(widest_view))
	var rim := Rect2(Vector2.ZERO, Vector2(1000, 500))
	var on_rim: bool = true
	for step: int in range(16):
		var at: Vector2 = Hud.radar_rim_point(rim, Vector2(420, 260), Vector2(420, 260) + Vector2.from_angle(TAU * step / 16.0) * 4000.0)
		var edge: float = minf(minf(absf(at.x - rim.position.x), absf(at.x - rim.end.x)), minf(absf(at.y - rim.position.y), absf(at.y - rim.end.y)))
		on_rim = on_rim and edge < 0.01 and rim.grow(0.01).has_point(at)
	h.check(on_rim, "the radar puts an off-screen enemy on its rect's rim in all 16 directions")
	root.size = Vector2i(1280, 800)
	await process_frame
	await app._stop_audio()
	app.queue_free()
	await process_frame

## Each instrument line fails when its subject is sabotaged.
func _controls() -> void:
	var app: Node = _new_app()
	await process_frame
	_build(app, "hud_combat")
	await _apply(app, Vector2i(1280, 800), 1.0, 1.0)
	var controls: Array[Control] = ViewportMatrix.visible_controls(app.ui)
	h.check(ViewportMatrix.safe_violations(controls, app.ui.size, _exempt(app)).is_empty() and ViewportMatrix.text_overflows(controls).is_empty() and ViewportMatrix.text_collisions(controls).is_empty() and ViewportMatrix.overlaps(_cluster_rects(app)).is_empty(), "the unsabotaged HUD passes every instrument (the controls below start clean)")
	# TEXT, label: a 200-character line in a HUD-sized box.
	var long_label: Label = UiKit.label(app.hud_view.top_left, "M6 ".repeat(66) + "OK", Vector2(0, 0), Vector2(290, 27), 20, Color.WHITE)
	long_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.control("a 200-character label in a 290 px box", not ViewportMatrix.text_overflows(ViewportMatrix.visible_controls(app.ui)).is_empty())
	long_label.free()
	# TEXT, wrapped label: four wrapped lines authored in a one-line box above the node readout.
	var tall: Label = UiKit.label(app.hud_view.top_left, "A companion line long enough to wrap onto several lines in a narrow box.", Vector2(0, 0), Vector2(200, 20), 16, Color.WHITE)
	h.control("a wrapped label grown (to %.0f px) into the node readout below it" % tall.size.y, not ViewportMatrix.text_collisions(ViewportMatrix.visible_controls(app.ui)).is_empty())
	tall.free()
	# TEXT, button: a long caption on the map button.
	var caption: String = app.hud_view.map_button.text
	app.hud_view.map_button.text = "OPEN THE WHOLE MAP OF THE AI-VERSE · TAB"
	h.control("a map button caption longer than its capsule", not ViewportMatrix.text_overflows(ViewportMatrix.visible_controls(app.ui)).is_empty())
	app.hud_view.map_button.text = caption
	# SAFE: the top-right cluster nudged off the right edge.
	app.hud_view.top_right.position.x += 200.0
	h.control("the top-right cluster nudged 200 px off-screen", not ViewportMatrix.safe_violations(ViewportMatrix.visible_controls(app.ui), app.ui.size, _exempt(app)).is_empty())
	app.hud_view.layout()
	# APART: the light bar moved onto the title.
	app.hud_view.top_center.position = app.hud_view.top_left.position
	h.control("the light bar moved onto the top-left cluster", not ViewportMatrix.overlaps(_cluster_rects(app)).is_empty())
	app.hud_view.layout()
	# UI scale: the layer scaled to 140 % with the root left at the unscaled size.
	app.ui_layer.scale = Vector2(1.4, 1.4)
	var unscaled: Array[Control] = ViewportMatrix.visible_controls(app.ui)
	var screen_rect := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var escaped: int = 0
	for control: Control in unscaled:
		if control in _exempt(app) or UiLayout.is_bleed(control): continue
		var on_screen := Rect2(control.get_global_rect().position * 1.4, control.get_global_rect().size * 1.4)
		if not screen_rect.encloses(on_screen): escaped += 1
	h.control("the UI layer scaled 140%% without refitting the root (%d controls leave the screen)" % escaped, escaped > 0)
	app.layout_ui()
	var fitted: int = 0
	for control: Control in ViewportMatrix.visible_controls(app.ui):
		if control in _exempt(app) or UiLayout.is_bleed(control): continue
		var on_screen := Rect2(control.get_global_rect().position * app.ui_layer.scale.x, control.get_global_rect().size * app.ui_layer.scale.x)
		if not screen_rect.grow(0.5).encloses(on_screen): fitted += 1
	h.check(fitted == 0, "refitted at UI 100%%, every control is on screen (%d off)" % fitted)
	# The pillarbox rule: 32:9 is kept at 1920x800; forcing expand there makes the UI rect wider.
	root.size = Vector2i(3840, 1080)
	await process_frame
	h.check(root.get_visible_rect().size.is_equal_approx(Vector2(1920, 800)) and root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP, "32:9 is pillarboxed at 1920x800 (got %s)" % root.get_visible_rect().size)
	# The game re-applies the rule on every resize, so the sabotage unhooks it first.
	root.size_changed.disconnect(app.layout_ui)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = Vector2i(1280, 800)
	await process_frame
	h.control("32:9 forced to expand (UI rect %s)" % root.get_visible_rect().size, root.get_visible_rect().size.x > 1920.5)
	root.size_changed.connect(app.layout_ui)
	root.size = Vector2i(1280, 800)
	await process_frame
	h.check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND and root.get_visible_rect().size.is_equal_approx(Vector2(1280, 800)), "back at 16:10 the stretch is expand at 1280x800 again")
	await app._stop_audio()
	app.queue_free()
	await process_frame
