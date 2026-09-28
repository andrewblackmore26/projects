extends SceneTree
## M11b: real pixels for the floating HUD, in the real main.gd at 1920x1080 (16:9, an aspect M6's
## "expand" rule keeps unletterboxed: the grab must be the window's size, which is checked).
## - GHOST: after a scripted light loss the bar's segment between the new and the old value is
##   coral, measured against the same segment before the loss (relative, not a fixed threshold).
##   Control: the same loss with the ghost disabled.
## - COMBO: after kills the combo slot holds bright text; before them it holds none. Control: the
##   same kills with the meter's labels hidden.
## - Captures at 1920x1080 for review (artifacts/m11b_hud/): combat, a boss node, evolve ready.
## - COST: the HUD's update and draw time per frame over 300 rendered frames (Hud.update_usec and
##   Hud.draw_usec).

const Harness = preload("res://tests/support/harness.gd")
const SIZE: Vector2i = Vector2i(1920, 1080)
const STEP: float = 1.0 / 60.0

var h := Harness.new("UI HUD render")
var out_dir: String = ProjectSettings.globalize_path("res://artifacts/m11b_hud")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("ui_hud_render_test needs a GPU window")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = SIZE
	DisplayServer.window_move_to_foreground()
	await _ghost_case()
	await _combo_case()
	await _captures()
	await _cost()
	h.finish(self)

func _new_app() -> Node:
	SaveService.storage_root = "user://ui-hud-render-%d" % Time.get_ticks_usec()
	var app: Node = load("res://scripts/main.gd").new()
	app.testing = true
	# A window losing focus pauses a run (main.gd's NOTIFICATION_APPLICATION_FOCUS_OUT) except in
	# benchmark mode; with main's _process off, benchmark mode changes nothing else here.
	app.benchmark_mode = true
	root.add_child(app)
	return app

## A run with the sim frozen and the HUD driven by hand, so nothing moves between set-up and grab.
func _start(app: Node, element: String, tier: int, light: float) -> void:
	app._new_game(false)
	app.line_queue.clear()
	await process_frame
	app.set_process(false)
	var combat: CombatWorld = app.combat
	combat.set_physics_process(false)
	combat.setup_player(element, tier, light, [], combat.arena.center)
	combat._grant_invulnerability(1000.0, &"ui_hud_render_test")
	for actor: Dictionary in combat.enemies: actor.dead = true
	combat._cleanup_dead()
	combat.spawn_queue.clear()
	combat._physics_process(STEP)
	await _settle(app, 30)

func _settle(app: Node, frames: int) -> void:
	for frame: int in range(frames):
		app.hud_view.update(STEP)
		app.elapsed_ui += STEP
		await process_frame

func _grab(app: Node, name: String = "") -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var raw: Image = root.get_texture().get_image()
	h.check(raw.get_size() == root.size, "%s: the grab is the window's %s (got %s)" % [name, root.size, raw.get_size()])
	h.check(app.overlay_kind.is_empty() and not paused and app.hud.visible, "%s: the grab is the HUD the test built (overlay '%s', paused %s)" % [name, app.overlay_kind, paused])
	if name.is_empty(): return raw
	var encoded := Image.create(raw.get_width(), raw.get_height(), false, Image.FORMAT_RGB8)
	for y: int in range(raw.get_height()):
		for x: int in range(raw.get_width()):
			encoded.set_pixel(x, y, _srgb(raw, raw.get_pixel(x, y)))
	encoded.save_png(out_dir.path_join(name + ".png"))
	print("capture: %s" % out_dir.path_join(name + ".png"))
	return raw

func _srgb(image: Image, colour: Color) -> Color:
	return colour if image.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGB8] else colour.linear_to_srgb()

## The window pixel of a point in `control`'s local space.
func _pixel(control: Control, local: Vector2) -> Vector2i:
	var at: Vector2 = root.get_final_transform() * (control.get_global_transform_with_canvas() * local)
	return Vector2i(roundi(at.x), roundi(at.y))

static func _coral(colour: Color) -> bool:
	return colour.r > 0.75 and colour.g < 0.55 and colour.b < 0.45 and colour.r - colour.g > 0.35

## Fraction of the bar's middle row between light values `from` and `to` that reads coral.
func _coral_fraction(app: Node, image: Image, from: float, to: float) -> float:
	var bar: LightBar = app.hud_view.light_bar
	var y: float = bar.bar_y + LightBar.BAR_HEIGHT * 0.5
	var left: Vector2i = _pixel(bar.cluster, Vector2(bar._x(from) + 3.0, y))
	var right: Vector2i = _pixel(bar.cluster, Vector2(bar._x(to) - 3.0, y))
	var hits: int = 0
	var count: int = 0
	for x: int in range(left.x, right.x + 1):
		count += 1
		if _coral(_srgb(image, image.get_pixel(x, left.y))): hits += 1
	return float(hits) / maxf(1.0, float(count))

func _ghost_case() -> void:
	var app: Node = _new_app()
	await process_frame
	await _start(app, "plasma", 3, 420.0)
	var combat: CombatWorld = app.combat
	var fractions: Dictionary = {}
	for mode: String in ["ghost", "control"]:
		combat.light_total = 420.0
		combat.player.hp = 420.0
		app.hud_view.light_bar.meter.reset(420.0)
		app.hud_view.light_bar.meter.ghost_enabled = mode == "ghost"
		await _settle(app, 4)
		var before: float = _coral_fraction(app, await _grab(app), 340.0, 420.0)
		combat.light_total = 280.0
		combat.player.hp = 280.0
		# 0.1 s after the loss: inside the ghost's 0.35 s hold, with the fill already down.
		await _settle(app, 6)
		# The segment the ghost covers: from just past where the fill's spring has reached (the
		# 0.1 s spring leaves it ~43 above 280) to the old value.
		var fill_now: float = app.hud_view.light_bar.meter.value
		h.check(fill_now < 340.0, "%s: the fill has dropped under the sampled segment (%.1f)" % [mode, fill_now])
		var after: float = _coral_fraction(app, await _grab(app, "ghost_after_loss" if mode == "ghost" else ""), 340.0, 420.0)
		fractions[mode] = Vector2(before, after)
	var ghost: Vector2 = fractions.ghost
	var control: Vector2 = fractions.control
	print("measure: coral share of the lost segment before/after the loss: ghost %.3f -> %.3f; ghost disabled %.3f -> %.3f" % [ghost.x, ghost.y, control.x, control.y])
	h.check(ghost.y - ghost.x > 0.6, "the lost segment turns coral after a loss (%.3f -> %.3f)" % [ghost.x, ghost.y])
	h.control("the same loss with the ghost disabled (%.3f -> %.3f)" % [control.x, control.y], not (control.y - control.x > 0.6))
	await _free(app)

## Bright text pixels in the combo meter's multiplier box.
func _text_pixels(app: Node, image: Image) -> int:
	var label: Label = app.hud_view.combo.multiplier_label
	var from: Vector2i = _pixel(label, Vector2.ZERO)
	var to: Vector2i = _pixel(label, label.size)
	var count: int = 0
	for y: int in range(maxi(0, from.y), mini(image.get_height(), to.y)):
		for x: int in range(maxi(0, from.x), mini(image.get_width(), to.x)):
			var colour: Color = _srgb(image, image.get_pixel(x, y))
			if colour.r > 0.8 and colour.g > 0.6: count += 1
	return count

func _kill(combat: CombatWorld, count: int) -> void:
	for kill: int in range(count):
		var actor: Dictionary = combat._spawn_enemy("fire", 1, combat.player_position + Vector2(260, 0), false)
		actor.invulnerable = 0.0
		combat._damage_actor(actor, 1.0e7, 0, 0)
	combat._cleanup_dead()

func _combo_case() -> void:
	var app: Node = _new_app()
	await process_frame
	await _start(app, "plasma", 3, 300.0)
	var combat: CombatWorld = app.combat
	var before: int = _text_pixels(app, await _grab(app))
	_kill(combat, 6)
	await _settle(app, 20)
	var after: int = _text_pixels(app, await _grab(app, "combo_after_kills"))
	app.hud_view.combo.multiplier_label.visible = false
	await _settle(app, 2)
	var hidden: int = _text_pixels(app, await _grab(app))
	app.hud_view.combo.multiplier_label.visible = true
	var floor_pixels: int = maxi(40, before * 3)
	print("measure: combo multiplier box bright pixels: before kills %d, after 6 kills %d ('%s'), labels hidden %d" % [before, after, app.hud_view.combo.multiplier_label.text, hidden])
	h.check(after > floor_pixels, "the combo text is on screen after kills (%d bright px vs %d before)" % [after, before])
	h.control("the kills with the meter's text hidden (%d bright px)" % hidden, not (hidden > floor_pixels))
	await _free(app)

func _captures() -> void:
	# In combat: a chain going, a secondary cooling, the dash spent, a loss still ghosting.
	var app: Node = _new_app()
	await process_frame
	await _start(app, "plasma", 4, 780.0)
	var combat: CombatWorld = app.combat
	_kill(combat, 4)
	combat.absorption = {"plasma": 320.0, "fire": 140.0, "void": 60.0}
	await _settle(app, 10)
	combat.light_total = 690.0
	combat.player.hp = 690.0
	var cooldowns: Dictionary = combat.player.get("cooldowns", {})
	cooldowns["secondary_0"] = 2.0
	combat.player.cooldowns = cooldowns
	combat.player.dash_cooldown_q = roundi(GameTuning.feel("dash.cooldown_s") * CombatWorld.SIM_Q_PER_SECOND * 0.4)
	await _settle(app, 5)
	await _grab(app, "hud_combat_1920x1080")
	# A boss node: the rival off-screen (its chevron), a hit on it still ghosting, a queued spawn.
	var boss: Dictionary = combat._spawn_enemy("void", 4, combat.player_position + Vector2(-2000, -300), true)
	await _settle(app, 5)
	var shields: PackedInt32Array = boss.get("shield_generator_indices", PackedInt32Array())
	if not shields.is_empty(): boss.part_hp[shields[0]] = boss.part_max_hp[shields[0]] * 0.35
	combat.spawn_queue.append({"hull": "", "element": "fire", "tier": 1, "elite": false, "rival": false, "pos": combat.player_position + Vector2(900, 700), "due_q": combat.encounter_q + 200, "tele": 0, "tele_left": 0})
	await _settle(app, 8)
	h.check(app.hud_view.boss_mode and app.hud_view.boss_bar.root.visible and not app.hud_view.combo.root.visible, "a living rival turns the top-centre slot into the boss bar")
	await _grab(app, "hud_boss_1920x1080")
	await _free(app)
	# Evolve ready, with light banked on the capsule.
	app = _new_app()
	await process_frame
	await _start(app, "fire", 2, 0.0)
	app.combat.collect_light(float(EvolutionRules.threshold(2)) + 5.0, "fire")
	app.combat.light_bank = app.combat.light_bank_cap() * 0.45
	await _settle(app, 40)
	h.check(app.hud_view.evolution_button.visible, "the EVOLVE capsule is up with an evolution ready")
	await _grab(app, "hud_evolve_ready_1920x1080")
	await _free(app)

func _cost() -> void:
	var app: Node = _new_app()
	await process_frame
	await _start(app, "plasma", 4, 700.0)
	_kill(app.combat, 3)
	var boss: Dictionary = app.combat._spawn_enemy("fire", 3, app.combat.player_position + Vector2(-2000, 0), true)
	await _settle(app, 10)
	Hud.reset_cost()
	var started: int = Time.get_ticks_usec()
	for frame: int in range(300):
		# Motion every frame: the light swings so the ghost, lead, pops and labels all work.
		app.combat.light_total = 700.0 - 120.0 * absf(sin(frame * 0.05))
		app.hud_view.update(STEP)
		app.elapsed_ui += STEP
		await process_frame
	var wall: float = (Time.get_ticks_usec() - started) / 1000.0 / 300.0
	var update_ms: float = Hud.update_usec / 1000.0 / maxf(1.0, float(Hud.frames))
	var draw_ms: float = Hud.draw_usec / 1000.0 / 300.0
	print("measure: HUD cost over %d frames: update %.3f ms/frame, draw callbacks %.3f ms/frame, total %.3f ms (frame wall %.2f ms)" % [Hud.frames, update_ms, draw_ms, update_ms + draw_ms, wall])
	h.check(Hud.frames == 300 and Hud.draw_usec > 0, "the cost counters ran (%d frames, %d us drawing)" % [Hud.frames, Hud.draw_usec])
	boss.dead = true
	await _free(app)

func _free(app: Node) -> void:
	await app._stop_audio()
	app.queue_free()
	await process_frame
	await process_frame
