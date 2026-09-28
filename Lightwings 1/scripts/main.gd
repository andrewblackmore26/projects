extends Node

## Rendered-frame gate budgets, ms/frame in the stress case: 2000 live bullets AND the 400-pickup
## cap AND 17 actors, mobile renderer, HDR 2D and glow on, 1280x800, vsync off, on the development
## desktop (RTX 5070 Ti / Ryzen 7 9800X3D). Two immediate-mode draw loops were found here and both
## are now batched MultiMeshes: CombatFX issued one draw_arc per live effect, up to 512 of them
## (~105 ms of a 133 ms frame), and pickups issued two arcs each at a 400 cap (~17 ms, which only
## became visible once FX stopped dwarfing it). Measured after both fixes, 30 s run:
##   mean 10.8 ms, p95 19.9 ms, with world_draw_ms down from ~17 to ~1.5
## so the frame is now SIMULATION-bound (sim_ms 6.6-8.6) rather than draw-bound. Against the spec's
## "2000 live projectiles at 60 fps" (16.67 ms): the mean clears it with room (about 92 fps); the
## worst 5% still dips to about 50 fps, and that is in the absolute stress case where the bullet and
## pickup pools are both at their caps at once, which is not typical play. Budgets below keep the
## ~1.3x-above-measured convention tests/combat_benchmark.gd uses. Nothing here is Steam Deck
## evidence - no Deck has been measured at any point in this upgrade.
const RENDERED_FRAME_BUDGET_MEAN_MS: float = 14.0
const RENDERED_FRAME_BUDGET_P95_MS: float = 26.0

var combat: CombatWorld
var campaign: CampaignState
var platform: PlatformService
var sound: Soundscape
var ui: Control
## The UI groups, bottom to top. Their builders live under scripts/ui/ since modernization M2:
## `hud` is drawn by Hud (scripts/ui/hud/), `menu` by TitleScreen, `overlay` is ScreenRouter's
## host for every other screen (scripts/ui/screens/), `dialogue` is DialogueBox's.
var hud: Control
var menu: Control
var overlay: Control
var dialogue: Control
var hud_view: Hud
## Held so the menu's own button callbacks outlive `_show_menu`.
var title_screen: TitleScreen
var screen_router: ScreenRouter
var dialogue_box: DialogueBox
var toast_stack: ToastStack
var environment: Environment
var mode: String = "menu"
## The open overlay's kind ("" when none): ScreenRouter's top screen.
var overlay_kind: String:
	get: return screen_router.kind() if screen_router != null else ""
## The HUD's slot-icon canvas (tests/hud_roster_test.gd redraws it directly).
var slot_overlay: Control:
	get: return hud_view.slot_overlay if hud_view != null else null
var absorbed: Dictionary = {}
var pending_offers: Array[String] = []
var previous_offers: Array[String] = []
var offer_serial: int = 0
## Which element's four hulls the evolution screen is showing when every hull is on offer (dev mode).
var evolution_tab: String = ""
var slot: String = "campaign"
## scripts/ui/dialogue_director.gd (plan P9): owns the queue, the seen_lines
## dedupe, the between-fights gate and the static line tables. `line_queue`/
## `seen_lines` stay as forwarding properties -- tests/support/make_v3_fixtures.gd
## and tests/golden_trace_test.gd read and write `app.seen_lines`/`app.line_queue`
## directly (tests/facade_contract_test.gd keeps that honest), and both getters
## return the director's own live containers, so `.clear()`/`.assign()` on the
## forwarded value still mutates the director's state.
var dialogue_director: DialogueDirector = DialogueDirector.new()
var line_queue: Array[Dictionary]:
	get: return dialogue_director.line_queue
	set(value): dialogue_director.line_queue = value
var seen_lines: Dictionary:
	get: return dialogue_director.seen_lines
	set(value): dialogue_director.seen_lines = value
var settings: Dictionary = {"volume":0.7,"effects_volume":0.55,"interface_volume":0.45,"ambience_volume":0.15,"pickup_cues":false,"music":true,"auto_fire":false,"glow":true,"damage_numbers":false,"show_elements":true,"fullscreen":false,"reduced_warp":false}
var options_tab: int = 0
var elapsed_ui: float = 0.0
## The dialogue box's on-screen timer (RunController clears it on reboot).
var dialogue_remaining: float:
	get: return dialogue_box.remaining
	set(value): dialogue_box.remaining = value
var last_hp: float = 100.0
var last_aim: Vector2 = Vector2.UP
var rebind_action: String = ""
var benchmark_mode: bool = false
var visual_capture: String = ""
var capture_ticks: int = 0
var benchmark_samples: Array[float] = []
var benchmark_duration: float = 0.0
var benchmark_started_usec: int = 0
var benchmark_previous_usec: int = 0
## Rendered-frame gate (P9 perf pass, tasks/todo.md): `--benchmark-seconds=`
## shortens the 65s default run for `tools/gates.ps1` (default kept available
## via the bare `--benchmark`); `--benchmark-warmup=` scales with it so a 10s
## gate run still has time to settle. `--benchmark-assert` turns the report
## into a gate (exit 1 on budget miss, printed as `measure:`/`gate:` lines,
## the same convention `tests/combat_benchmark.gd` uses); `--benchmark-budget-scale=`
## is its negative control, mirroring that same test's `--budget-scale=`.
var benchmark_seconds: float = 65.0
var benchmark_warmup_seconds: float = 5.0
var benchmark_asserting: bool = false
var benchmark_budget_scale: float = 1.0
var hud_elapsed: float = 0.0
var testing: bool = false
var sector_edges: SectorEdges
var cloud_review: Dictionary = {}
var cloud_sync_ready: bool = false
var compositor: CombatCompositor
var mode_config: ModeConfig = ModeConfig.from_demo(false)
var dev_console: DevConsole
var _debug_show_warp: bool = false # --show-warp capture aid only, see _process
var _capture_at_tick: int = 90 # --show-death needs a much shorter delay: the death card is only up for 1.2s
## The run flow (start, enter node, warp swap, death/reboot, boss defeated, saves) lives in
## scripts/world/run_controller.gd since modernization M1; the methods below with the old names are
## one-line forwarders, kept because tests and package_validation.gd call them on `app`.
var run_controller: RunController
## Frictionless death (spec §7.4/§24, plan P7): seconds the death card has been up. The next life
## itself is prepared by RunController.on_death.
var _death_elapsed: float = 0.0
## Swallows N upcoming _physics_process command frames after a dismiss, so
## the very press that dismissed the card (e.g. held right-click) cannot
## also fire a dash the instant control returns.
var _input_swallow_frames: int = 0

func _init() -> void:
	run_controller = RunController.new(self)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture=") or argument.begins_with("--show-map-level=") or argument in ["--benchmark","--show-evolution","--show-map","--show-dev-console","--verify-package"]:
			testing = true
	InputBindings.setup()
	load_settings()
	_create_environment()
	sound = Soundscape.new()
	sound.configure(settings)
	add_child(sound)
	platform = PlatformService.new()
	add_child(platform)
	platform.initialize()
	_create_ui()
	apply_settings()
	_show_menu()
	get_tree().auto_accept_quit = false
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--demo":
			_new_game(true)
		elif arg == "--play":
			_new_game(false)
		elif arg == "--verify-package":
			_verify_package.call_deferred()
		elif arg.begins_with("--capture="):
			visual_capture = arg.trim_prefix("--capture=")
		elif arg == "--benchmark":
			benchmark_mode = true
			settings.glow = true
			settings.fullscreen = false
			# P9 finding: Godot's default physics catch-up (max 8 substeps/frame)
			# trapped this benchmark in a self-sustaining spiral the first time
			# it was measured (mean 112ms/frame) - once any one frame's cost
			# exceeds ~1/8 of the 16.67ms budget, the NEXT frame must run
			# several substeps to catch up, each substep costing as much as the
			# first, so it never recovers. Measured fix: pinning to 1 substep
			# here (benchmark/measurement only, not default gameplay) let the
			# sim fall into graceful slow-motion instead, dropping mean to
			# ~20-32ms - see `RENDERED_FRAME_BUDGET_MEAN_MS`'s header for the
			# full numbers this produced.
			Engine.max_physics_steps_per_frame = 1
			if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			_new_game(false)
			_close_overlay()
			var benchmark_bullets: int = 2000
			for option: String in OS.get_cmdline_user_args():
				if option.begins_with("--benchmark-bullets="): benchmark_bullets = clampi(int(option.trim_prefix("--benchmark-bullets=")), 1000, 2000)
				elif option.begins_with("--benchmark-seconds="): benchmark_seconds = maxf(1.0, option.trim_prefix("--benchmark-seconds=").to_float())
				elif option.begins_with("--benchmark-budget-scale="): benchmark_budget_scale = maxf(0.0, option.trim_prefix("--benchmark-budget-scale=").to_float())
				elif option == "--benchmark-assert": benchmark_asserting = true
			benchmark_warmup_seconds = minf(5.0, benchmark_seconds * 0.2)
			combat.profile_sections = "--benchmark-profile" in OS.get_cmdline_user_args()
			if "--benchmark-no-glow" in OS.get_cmdline_user_args(): environment.glow_enabled = false # diagnostic-only
			combat.benchmark(benchmark_bullets)
			# Diagnostic-only (P8): isolates whether the pooled FX/trail draw
			# passes are the rendered-frame cost, without touching simulation.
			if "--benchmark-no-fx" in OS.get_cmdline_user_args(): combat.fx.enabled = false
			if DisplayServer.get_name() != "headless": get_window().size = Vector2i(1280,800)
		elif arg == "--show-evolution" and OS.has_feature("editor"):
			_new_game(false)
			combat.light_total = 100.0
			combat.absorption = {"fire":20.0,"corruption":20.0,"plasma":20.0}
			_show_evolution()
		elif (arg == "--show-options" or arg.begins_with("--show-options=")) and OS.has_feature("editor"):
			if arg.contains("="): options_tab = maxi(0,["audio","display","gameplay","controls"].find(arg.get_slice("=",1)))
			_show_options()
		elif arg == "--show-pause" and OS.has_feature("editor"):
			_new_game(false)
			_close_overlay()
			_show_pause()
		elif arg == "--show-map" and OS.has_feature("editor"):
			_new_game(false)
			_show_map()
		elif arg.begins_with("--show-map-level=") and OS.has_feature("editor"):
			_new_game_as("dev")
			campaign.travel_to_level(int(arg.trim_prefix("--show-map-level=")))
			_show_map()
		elif arg == "--show-dev-console" and OS.has_feature("editor"):
			_new_game_as("dev")
			if is_instance_valid(dev_console): dev_console.toggle()
		elif arg == "--show-combat" and OS.has_feature("editor"):
			_new_game(false)
			combat.setup_player("plasma",4,750,[],Vector2(896,560))
			campaign.current_sector = Vector2i(-3,2)
			var showcase: Dictionary = campaign.sector_at(campaign.current_sector)
			showcase.kind = "regular"
			combat.start_sector(showcase)
			settings.auto_fire = true
			line_queue.clear()
		elif arg == "--show-combat-boss" and OS.has_feature("editor"):
			_new_game(false)
			combat.setup_player("fire",1,400,[],Vector2(896,900))
			combat.start_sector({"id":"p4b_boss","kind":"boss","element":"fire","tier":1,"resource_budget":200,"enemy_hulls":[],"boss_hull":"boss_fire"})
			settings.auto_fire = true
			line_queue.clear()
		elif arg == "--show-combo" and OS.has_feature("editor"):
			# Debug-only capture aid: forces a few kills so the combo readout
			# (spec §7.2/§24) has something to show at capture time, rather
			# than hoping auto-fire's default aim happens to land real hits.
			_new_game(false)
			combat.setup_player("plasma",4,750,[],Vector2(896,560))
			campaign.current_sector = Vector2i(-3,2)
			var combo_showcase: Dictionary = campaign.sector_at(campaign.current_sector)
			combo_showcase.kind = "regular"
			combat.start_sector(combo_showcase)
			for i: int in range(4):
				for actor: Dictionary in combat.enemies:
					if not bool(actor.dead):
						combat._damage_actor(actor,100000.0,0,0)
						break
			settings.auto_fire = true
			line_queue.clear()
		elif arg == "--show-death" and OS.has_feature("editor"):
			# Debug-only capture aid (plan P7 "LOOK at it"): the death card
			# (spec §7.4/§24) is only up for GameTuning.DEATH_CARD_SECONDS, so
			# the capture must fire soon after death, not at the default
			# 90-tick delay other --show-* captures use.
			_new_game(false)
			combat.setup_player("fire",3,400,[],GameTuning.ARENA_CENTER)
			combat.player_invulnerable = 0.0
			combat.player.invulnerable = 0.0
			combat._damage_actor(combat.player,1000000.0,1,1)
			line_queue.clear()
			_capture_at_tick = 20
		elif arg == "--show-warp" and OS.has_feature("editor"):
			# Debug-only capture aid (plan P6 "LOOK at it"): pins the sim in
			# WARP_TRAVEL every frame (see `_process`'s `_debug_show_warp`
			# branch) instead of setting it once, since the state machine
			# would otherwise spring back a few ticks later with no listener
			# ever confirming the (nonexistent, in this debug capture) swap.
			_new_game(false)
			_debug_show_warp = true
			line_queue.clear()
		elif arg == "--show-dialogue" and OS.has_feature("editor"):
			# Debug-only capture aid (plan P9 "LOOK at it"): the companion box
			# with a line up. `_new_game_as` already queues "welcome_v2" and the
			# origin node has no enemies (combat_clear from tick 1), so no extra
			# state is needed -- just do NOT clear line_queue the way the other
			# --show-* aids do.
			_new_game(false)
		elif arg == "--show-demo-ending" and OS.has_feature("editor"):
			# Debug-only capture aid (plan P9 "LOOK at it"): the demo ending,
			# reached by the real _on_boss_defeated path (not a hand-built
			# overlay) after both of the demo's two levels report complete.
			_new_game_as("demo")
			campaign.level = 1
			campaign.complete_level()
			campaign.travel_to_level(2)
			_on_boss_defeated("fire")
			line_queue.clear()

func _verify_package() -> void:
	var verification := PackageValidation.new()
	await verification.run(self)

func _create_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.background_canvas_max_layer = 0
	environment.glow_enabled = true
	VisualStyle.configure_glow(environment)
	environment.glow_hdr_threshold = 1.0
	environment.glow_bloom = 0.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for index: int in range(7):
		environment.set_glow_level(index, 0.8 if index == 0 else 0.0)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

func _create_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = UiKit.make_theme()
	layer.add_child(ui)
	hud = group(ui)
	menu = group(ui)
	overlay = group(ui)
	dialogue = group(ui)
	toast_stack = ToastStack.new(ui)
	screen_router = ScreenRouter.new(self,overlay)
	dialogue_box = DialogueBox.new(self,dialogue)
	hud_view = Hud.new(self,hud)
	hud_view.build()

func _show_menu() -> void:
	mode = "menu"
	_close_overlay()
	hud.visible = false
	dialogue.visible = false
	if is_instance_valid(combat):
		combat.active = false
		combat.queue_free()
		combat = null
	if is_instance_valid(sector_edges): sector_edges.queue_free()
	if is_instance_valid(compositor): compositor.queue_free()
	if is_instance_valid(dev_console): dev_console.queue_free()
	dev_console = null
	clear(menu)
	menu.visible = true
	sound.set_context("menu")
	title_screen = TitleScreen.new()
	title_screen.enter({"app":self,"host":menu})
	title_screen.default_focus().grab_focus()

## Level select for a NEW run in `mode_id` (scripts/ui/screens/level_select_screen.gd).
func _show_level_select(mode_id: String) -> void:
	screen_router.replace("level_select",{"mode_id":mode_id})

func _begin_at_level(mode_id: String, level: int) -> void: run_controller.begin_at_level(mode_id,level)
func _new_game_as(mode_id: String) -> void: run_controller.new_game_as(mode_id)
func _new_game(is_demo: bool) -> void: run_controller.new_game(is_demo)
func _travel_to_level(level: int) -> void: run_controller.travel_to_level(level)
func _continue_game(save_slot: String) -> void: run_controller.continue_game(save_slot)

func _start_game_view() -> void:
	_close_overlay()
	clear(menu)
	menu.visible = false
	hud.visible = true
	mode = "play"
	sound.set_context("play")
	if is_instance_valid(combat):
		combat.active = false
		combat.queue_free()
	if is_instance_valid(sector_edges): sector_edges.queue_free()
	if is_instance_valid(compositor): compositor.queue_free()
	combat = CombatWorld.new()
	combat.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(combat)
	var backdrop := ArenaBackdrop.new()
	backdrop.world = combat
	combat.add_child(backdrop)
	combat.light_collected.connect(_on_energy)
	combat.player_regressed.connect(_on_regression)
	combat.shot_audio_requested.connect(_on_shot_fired)
	combat.player_died.connect(_on_death)
	combat.sector_cleared.connect(_on_sector_clear)
	combat.boss_defeated.connect(_on_boss_defeated)
	combat.event_message.connect(_toast)
	combat.warp_committed.connect(_on_warp_committed)
	combat.warp_reduced = bool(settings.get("reduced_warp",false))
	compositor = CombatCompositor.new()
	add_child(compositor)
	compositor.attach(combat)
	sector_edges = SectorEdges.new()
	sector_edges.z_index = 50
	sector_edges.campaign = campaign
	sector_edges.world = combat
	compositor.add_world_overlay(sector_edges)
	last_hp = 100.0
	apply_settings()
	if is_instance_valid(dev_console): dev_console.queue_free()
	dev_console = null
	## Dev console: spec §4 "stays in the shipped build", present only for
	## dev-mode saves (mode_isolation_test.gd checks the node's presence is
	## exactly the console_enabled() guard, both ways).
	if mode_config.console_enabled():
		dev_console = DevConsole.new()
		hud.add_child(dev_console)
		dev_console.command_submitted.connect(_on_dev_command)

func _enter_sector(coord: Vector2i, spawn: Vector2, show_intro: bool = true) -> void: run_controller.enter_sector(coord,spawn,show_intro)

## Companion lines the run flow triggers. They stay here (tests/dialogue_coverage_test.gd scans this
## file for every trigger id); RunController calls them, and scripts/ui/dialogue_box.gd shows them.
func _queue_welcome_line() -> void:
	_queue_line("companion","Your first light","Your white core is your hitbox. Hollow light circles heal you and fill the same bar that grows your ship. Fly through an opening and find your first fight.","welcome_v2")

## A node was just entered (a direct entry or the warp's swap): close the dialogue box and queue
## the node's lines.
func _on_node_entered(sector: Dictionary, coord: Vector2i, show_intro: bool) -> void:
	dialogue_box.dismiss()
	if show_intro and str(sector.get("kind","")) == "boss" and not bool(sector.get("boss_down",false)):
		# Immediate lane (spec §25 "a line ... on encounter"): this must be able
		# to show on entry, not only once the boss it announces is already dead.
		_queue_line(str(sector.element),"A rival signal",DialogueDirector.entry_line(str(sector.element)),"boss_intro_"+str(sector.element),true)
	if coord != Vector2i.ZERO:
		_queue_line("companion","Direction and distance","Direction decides the light you find. Distance decides the danger. Every opening stays open; you can always retreat.","map_tutorial_v2")
	for actor: Dictionary in combat.enemies:
		if bool(actor.get("elite",false)):
			_queue_line("companion","A machine with many hands","That large ship carries several weapons, each with its own rhythm. Watch how its silhouette changes under fire.","first_elite_v2")
			break

func _queue_reboot_line() -> void:
	_queue_line("companion","You persisted","Your discoveries, defeated cores and unlocks remain. Rebuild your lightship, then push outward again.","reboot_v2_"+str(campaign.deaths))

func _queue_defeat_line(element: String) -> void:
	_queue_line(element,"A rival yields",DialogueDirector.defeat_line(element),"defeat_v2_"+element)

func _process(delta: float) -> void:
	if _debug_show_warp and is_instance_valid(combat):
		combat.warp_direction = Vector2i.RIGHT
		combat.warp_phase = CombatWorld.WARP_TRAVEL
		combat.warp_progress = 0.5
		combat.warp_commit_speed = 260.0
		combat.player.vel = Vector2.RIGHT*260.0
	elapsed_ui += delta
	if overlay_kind == "death":
		_death_elapsed += delta
		var policy: Dictionary = ScreenRouter.policy("death")
		if _death_elapsed >= float(policy.auto_close): _dismiss_death_card()
	if platform != null:
		platform.set_input_context(mode != "play" or get_tree().paused)
	toast_stack.tick(delta)
	if mode == "play" and is_instance_valid(combat):
		hud_elapsed += delta
		if hud_elapsed >= 0.1:
			hud_elapsed = 0.0
			_refresh_hud()
		if not get_tree().paused:
			if combat.player_hp < last_hp:
				sound.play("hurt")
			last_hp = combat.player_hp
			# spec §25 "speaks only between fights", except the one immediate-lane
			# case (a boss's own encounter line). DialogueDirector.can_show_next
			# arbitrates that, not this call site, so `_update_dialogue` now runs
			# every play tick and only ever shows a line the director allows.
			_update_dialogue(delta)
	if benchmark_mode and is_instance_valid(combat) and not get_tree().paused:
		var now_usec: int = Time.get_ticks_usec()
		if benchmark_started_usec == 0:
			benchmark_started_usec = now_usec
			benchmark_previous_usec = now_usec
		benchmark_duration = (now_usec-benchmark_started_usec)/1000000.0
		if benchmark_duration > benchmark_warmup_seconds:
			benchmark_samples.append((now_usec-benchmark_previous_usec)/1000.0)
			if combat.profile_sections and benchmark_samples.size() % 90 == 0:
				print("BENCH SECTIONS ",JSON.stringify({"frame_ms":benchmark_samples[-1],"sim_ms":combat.simulation_ms,"upload_ms":combat.section_ms.get("upload",0.0),"bullet_upload_ms":combat._bullet_canvas.upload_ms,"fx_upload_ms":combat._fx_canvas.upload_ms,"world_draw_ms":combat.world_draw_ms,"projectiles_draw_ms":combat.projectiles_draw_ms,"pickups":combat.pickups.size(),"bullets":combat.bullets.count()}))
		benchmark_previous_usec = now_usec
		if benchmark_duration > benchmark_seconds:
			_finish_benchmark()
	if not visual_capture.is_empty():
		capture_ticks += 1
		if capture_ticks == _capture_at_tick:
			_capture.call_deferred()

func _physics_process(_delta: float) -> void:
	if mode != "play" or not is_instance_valid(combat) or get_tree().paused or benchmark_mode:
		return
	if _input_swallow_frames > 0:
		_input_swallow_frames -= 1
		combat.set_command(ShipCommand.new())
		return
	var command := ShipCommand.new()
	var steam_command: ShipCommand = platform.get_command(last_aim)
	if steam_command != null:
		steam_command.fire = steam_command.fire or bool(settings.auto_fire)
		last_aim = steam_command.aim
		combat.set_command(steam_command)
		return
	command.movement = Input.get_vector("move_left","move_right","move_up","move_down")
	var devices: Array[int] = Input.get_connected_joypads()
	var stick: Vector2 = Input.get_vector("aim_left","aim_right","aim_up","aim_down")
	if stick.length() > 0.22:
		last_aim = stick.normalized()
	elif DisplayServer.mouse_get_position() != Vector2i.ZERO and Input.get_last_mouse_velocity().length() > 0.1:
		last_aim = (compositor.screen_to_world(ui.get_global_mouse_position())-combat.player_position).normalized()
	elif devices.is_empty():
		last_aim = (compositor.screen_to_world(ui.get_global_mouse_position())-combat.player_position).normalized()
	command.aim = last_aim
	command.fire = Input.is_action_pressed("fire") or bool(settings.auto_fire)
	command.dash = Input.is_action_pressed("dash")
	command.ability_primary = Input.is_action_just_pressed("ability_primary")
	command.ability_secondary = Input.is_action_just_pressed("ability_secondary")
	command.secondary_held = Input.is_action_pressed("ability_secondary")
	command.secondaries = [command.ability_primary,command.ability_secondary,Input.is_action_just_pressed("ability_tertiary")]
	combat.set_command(command)

func _input(event: InputEvent) -> void:
	if overlay_kind == "death":
		var policy: Dictionary = ScreenRouter.policy("death")
		if bool(policy.any_input_dismiss) and _death_elapsed >= float(policy.input_guard):
			# Fresh press only (a key/mouse/pad button transitioning to pressed,
			# or an axis rising past a threshold) - never a hold, never motion,
			# so a held fire button cannot skip a card the player never saw.
			var fresh: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5)
			if fresh:
				_dismiss_death_card()
				get_viewport().set_input_as_handled()
		return
	if not rebind_action.is_empty():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			rebind_action = ""
			_show_options()
			get_viewport().set_input_as_handled()
			return
		var valid: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value)>0.7)
		if valid:
			InputBindings.rebind(rebind_action,event)
			rebind_action = ""
			_show_options()
			get_viewport().set_input_as_handled()
		return

func _unhandled_input(event: InputEvent) -> void:
	if not rebind_action.is_empty(): return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if not overlay_kind.is_empty():
			if not screen_router.escape(): return
		elif mode == "play":
			_show_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and mode == "play":
		if overlay_kind == "map":
			_close_overlay()
		elif overlay_kind.is_empty():
			_show_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("evolve") and mode == "play" and overlay_kind.is_empty():
		_show_evolution()
		get_viewport().set_input_as_handled()

## The warp's node swap (spec §12/plan P6): see RunController.on_warp_committed.
func _on_warp_committed(direction: Vector2i) -> void: run_controller.on_warp_committed(direction)

func _refresh_hud() -> void: hud_view.refresh()

func _on_attack_performed(element: String, ability: String) -> void:
	sound.play(element if ability == "fire" else "ability")

func _on_energy(element: String, amount: float) -> void:
	absorbed = combat.absorption
	if campaign.unlock_element(element,amount):
		_queue_line("companion","A new dialect",element.capitalize()+" light now belongs among your possible futures. Absorb it to change the hulls you are offered.","unlocked_"+element)
	sound.play("pickup")
	if combat.light_total >= EvolutionRules.threshold(combat.player_tier) and combat.player_tier < mode_config.max_tier():
		_queue_line("companion","Enough light to change","Press E or A to choose a complete new lightship. Its labelled weapons and passives are part of the hull. The choice follows the light you absorb.","first_threshold_v2")

func _on_regression(from_tier: int, to_tier: int) -> void:
	pending_offers.clear()
	_toast("RESHAPING · T%d → T%d" % [from_tier,to_tier])
	_queue_line("companion","A smaller shape, the same instance","Damage spent your light and returned you to an earlier hull. Absorb enough to grow again and you can choose a different future.","first_regression_v2")

func _on_shot_fired(at: Vector2, element: String, _ability: String, actor_id: int = 1) -> void:
	sound.play_at(element,at-combat.player_position,"player" if actor_id == 0 else "enemy")

## Applies a validated DevConsole.parse() result. Only ever reachable when
## mode_config.console_enabled() (the dev_console node does not exist
## otherwise), so this never needs to re-check the mode guard itself.
func _on_dev_command(result: Dictionary) -> void:
	if not bool(result.get("ok",false)) or not is_instance_valid(combat): return
	match str(result.get("command","")):
		"tier":
			var args: Dictionary = result.args
			var element: String = str(args.get("element","")) if not str(args.get("element","")).is_empty() else combat.player_element
			var tier: int = int(args.tier)
			# evolve_hull only permits a +1 step above threshold; the console
			# is a debug jump to ANY tier, so it goes through the same
			# adapter the ship editor/tests use to force an exact tier.
			combat.evolve_player(element,tier,[])
		"level":
			_travel_to_level(int(result.args.level))
		"light":
			combat.collect_light(float(result.args.amount),combat.player_element if not combat.player_element.is_empty() else "lightning")
		"tune":
			_dev_say(_apply_tune(result.args))
		"help":
			pass
	_refresh_hud()

## Camera and movement spec: live tuning of GameTuning.FEEL_DEFAULTS. Returns the line to show.
## `dump` prints every override as a paste-ready block on stdout (the console shows one line).
func _apply_tune(args: Dictionary) -> String:
	match str(args.get("action","")):
		"set":
			var key: String = str(args.key)
			if not GameTuning.set_feel(key,float(args.value)): return "ERROR: %s rejected (unknown key or not a finite number)" % key
			return "%s = %s (default %s)" % [key,str(GameTuning.feel(key)),str(GameTuning.FEEL_DEFAULTS[key])]
		"get":
			return "%s = %s (default %s)" % [str(args.key),str(GameTuning.feel(str(args.key))),str(GameTuning.FEEL_DEFAULTS[str(args.key)])]
		"reset":
			GameTuning.reset_feel()
			return "all tuning back to defaults"
		"dump":
			var overrides: Dictionary = GameTuning.feel_overrides()
			for key: String in overrides: print("\t\"%s\": %s," % [key,str(overrides[key])])
			return "%d override(s) printed to stdout" % overrides.size()
	return "ERROR: unknown tune action"

func _dev_say(line: String) -> void:
	print("dev: "+line)
	if is_instance_valid(dev_console) and is_instance_valid(dev_console.log_label): dev_console.log_label.text = line

func _achieve(id: String) -> void:
	if mode_config.achievements_enabled(): platform.unlock_achievement(id)

func _on_rival_reward(_component: String, _offered_root: String) -> void:
	# Legacy signal adapter: rival rewards are light only.
	_achieve("FIRST_RIVAL")

func _on_boss_defeated(element: String) -> void: run_controller.on_boss_defeated(element)

## Level complete (spec §4/§11): RunController.on_boss_defeated has revealed the next element,
## unlocked the next level and granted the achievement; the screen offers CONTINUE TO LEVEL N+1 /
## KEEP EXPLORING.
func _show_level_complete(result: Dictionary) -> void:
	screen_router.replace("level_complete",{"result":result})

func _on_sector_clear() -> void:
	sound.play("clear")
	_toast("NODE CLEAR · "+CampaignState.coord_key(campaign.current_sector))
	_save_game() # calm moment (plan P6 item 6): once per node, not per tick
	_save_game()

func _show_evolution() -> void:
	if mode != "play" or not is_instance_valid(combat) or combat.light_total <= 0: return
	if combat.player_tier >= mode_config.max_tier() or combat.light_total < EvolutionRules.threshold(combat.player_tier): return
	if not overlay_kind.is_empty() and overlay_kind != "evolution": return
	if pending_offers.is_empty():
		# Spec §4: dev mode offers every next-tier hull, campaign and demo the ranked three.
		if mode_config.offer_policy() == "all_hulls": pending_offers = EvolutionRules.all_offers(combat.player_tier)
		else: pending_offers = EvolutionRules.offers(combat.player_element,combat.player_tier,combat.absorption,campaign.unlocked,previous_offers,campaign.world_seed+offer_serial)
		previous_offers.assign(pending_offers)
		offer_serial += 1
		_save_game()
	screen_router.replace("evolution")

func _choose_evolution(id: String) -> void:
	if id not in pending_offers or combat.light_total < EvolutionRules.threshold(combat.player_tier): return
	combat.evolve_hull(id)
	pending_offers.clear()
	absorbed = combat.absorption
	_close_overlay()
	sound.play("evolve")
	_achieve("FIRST_EVOLUTION")
	_queue_line("companion","A different kind of you","Each visible part belongs to your new build. Follow another dialect's light when you want a different future.","first_evolution_v2")
	_save_game()

## The full map screen (spec §11; scripts/ui/screens/map_screen.gd).
func _show_map() -> void:
	if mode != "play" or not is_instance_valid(combat) or (not overlay_kind.is_empty() and overlay_kind != "map"): return
	screen_router.replace("map")

func _sector_description(coord: Vector2i) -> String: return MapScreen.sector_description(campaign,coord)
func _sector_known(coord: Vector2i) -> bool: return MapScreen.sector_known(campaign,coord)

func _reward_for(root: String, tier: int) -> String:
	return {"fire":"cinder_pod" if tier>=4 else "ember_gun","lightning":"capacitor","void":"satellite","corruption":"spore_bud"}.get(root,"laser_prong")

func _show_pause() -> void:
	if mode != "play" or not overlay_kind.is_empty(): return
	screen_router.replace("pause")

## Options opens OVER whatever is up (Pause, or nothing on the main menu) and `_close_options`
## returns to it; a rebind rebuilds Options in place.
func _show_options() -> void:
	if screen_router.top_id() == "options": screen_router.replace("options")
	else: screen_router.push("options")

func _close_options() -> void: screen_router.pop()

func apply_settings() -> void:
	ShipPreview.glow_enabled = bool(settings.glow)
	for preview: Node in get_tree().get_nodes_in_group("ship_previews"):
		if preview.environment != null: preview.environment.glow_enabled = bool(settings.glow)
	if environment != null: environment.glow_enabled = bool(settings.glow)
	if is_instance_valid(combat):
		combat.show_element_labels = bool(settings.show_elements)
		combat.warp_reduced = bool(settings.get("reduced_warp",false))
		combat.show_damage_numbers = bool(settings.get("damage_numbers",false)) # spec §24: off by default
	if sound != null:
		sound.configure(settings)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(settings.fullscreen) else DisplayServer.WINDOW_MODE_WINDOWED)

func save_settings() -> void:
	var config := ConfigFile.new()
	for key: String in settings: config.set_value("device",key,settings[key])
	config.save("user://device.cfg")

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://device.cfg") == OK:
		for key: String in settings: settings[key] = config.get_value("device",key,settings[key])

## Frictionless death (spec §7.4/§24). RunController.on_death builds the next life and saves the
## profile; this half plays the sound and shows the card. (The profile save used to run after the
## card was built; building the card touches no saved state, so the order does not matter.)
func _on_death() -> void:
	sound.play("death")
	run_controller.on_death()
	_death_elapsed = 0.0
	screen_router.replace("death",{"stats":run_controller.death_stats})

func _reboot() -> void: run_controller.reboot()
func _dismiss_death_card() -> void: _reboot()

func _show_ending(is_demo: bool) -> void:
	screen_router.replace("ending",{"is_demo":is_demo})

## Save hooks and their timing window: see RunController.save_game.
var save_timings_ms: Array[float]:
	get: return run_controller.save_timings_ms
	set(value): run_controller.save_timings_ms = value
func _save_game() -> void: run_controller.save_game()
func save_timing_stats() -> Dictionary: return run_controller.save_timing_stats()

func _show_cloud_review() -> void:
	screen_router.replace("cloud")

func _import_demo() -> void:
	var snapshot: Dictionary = SaveService.load_snapshot("demo")
	if snapshot.is_empty(): return
	if not SaveService.load_snapshot("campaign").is_empty(): screen_router.replace("confirm",{"variant":"import_demo"})
	else: _perform_import()

func _archive_slot(save_slot: String, reason: String) -> bool:
	var source: String = SaveService.snapshot_path(save_slot)
	if not FileAccess.file_exists(source): return true
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source)
	var destination: String = source+".before-"+reason+"-"+str(Time.get_unix_time_from_system()).replace(".","_")+".archive"
	var file: FileAccess = FileAccess.open(destination,FileAccess.WRITE)
	if file == null:
		_toast("Could not preserve the previous campaign. No progress was replaced.")
		return false
	file.store_buffer(bytes)
	file.flush()
	var status: Error = file.get_error()
	file.close()
	if status != OK or FileAccess.get_file_as_bytes(destination) != bytes:
		_toast("Previous-save archive could not be verified. No progress was replaced.")
		return false
	return true

func _perform_import() -> void:
	var snapshot: Dictionary = SaveService.load_snapshot("demo")
	if snapshot.is_empty() or not _archive_slot("campaign","demo-import"): return
	var state := CampaignState.new()
	state.import_demo(snapshot.get("profile",{}))
	var error: Error = SaveService.save_snapshot(state.to_dict(),{"seen_lines":snapshot.get("run",{}).get("seen_lines",{})},"campaign")
	if error != OK:
		_toast("Import failed: "+error_string(error))
		return
	_continue_game("campaign")

func _replace_game(is_demo: bool) -> void:
	if _archive_slot("demo" if is_demo else "campaign","new-game"): _new_game(is_demo)

func _confirm_new(is_demo: bool = false) -> void:
	screen_router.replace("confirm",{"variant":"new_game","is_demo":is_demo})

## `immediate` is spec §25's one named exception (a level boss's own
## ENCOUNTER line): it goes to the front of DialogueDirector's queue and is
## allowed to leave it even while the node still has live enemies. Every
## other call site leaves it false and stays behind the between-fights gate.
func _queue_line(element: String, title: String, text: String, id: String, immediate: bool = false) -> void:
	if immediate: dialogue_director.queue_immediate(element,title,text,id)
	else: dialogue_director.queue(element,title,text,id)

func _update_dialogue(delta: float) -> void: dialogue_box.update(delta)

## Closes every open screen (ScreenRouter.close_all): unpauses, restores the play/menu sound
## context and clears the ship command.
func _close_overlay() -> void: screen_router.close_all()

func _toast(text: String) -> void: toast_stack.show(text)

func _open_editor() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ship_editor.tscn")

func _open_gallery() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/gallery.tscn")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and mode == "play" and overlay_kind.is_empty() and not benchmark_mode:
		_show_pause()

func _quit() -> void:
	_save_game()
	await _stop_audio()
	get_tree().quit()

func _stop_audio() -> void:
	mode = "closing"
	if is_instance_valid(combat): combat.active = false
	if is_instance_valid(sound):
		sound.shutdown()
		var deadline: int = Time.get_ticks_msec()+1500
		while not sound.audio_retired() and Time.get_ticks_msec()<deadline:
			await get_tree().create_timer(0.02,true,false,true).timeout

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if get_viewport().use_hdr_2d:
		var encoded := Image.create(image.get_width(),image.get_height(),false,Image.FORMAT_RGBA8)
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				encoded.set_pixel(x,y,image.get_pixel(x,y).linear_to_srgb())
		image = encoded
	var result: Error = image.save_png(visual_capture)
	print("CAPTURE ",visual_capture," ",error_string(result))
	visual_capture = ""
	await _stop_audio()
	get_tree().quit()

func _finish_benchmark() -> void:
	benchmark_mode = false
	benchmark_samples.sort()
	var total: float = 0.0
	for value: float in benchmark_samples: total += value
	var data: Dictionary = {"engine":Engine.get_version_info().string,"os":OS.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"bullets":combat.bullets.count(),"gpu":RenderingServer.get_video_adapter_name(),"resolution":"%dx%d" % [get_window().size.x,get_window().size.y],"cpu":OS.get_processor_name(),"glow":environment.glow_enabled,"hdr_2d":get_viewport().use_hdr_2d,"vsync":"disabled for capacity measurement","actors":combat.actors_by_id.size(),"player_hull":combat.hull_id,"player_tier":combat.player_tier,"moving_camera":true,"pickups":combat.pickups.size(),"drones":combat.drones.size(),"duration_seconds":benchmark_duration,"samples":benchmark_samples.size(),"mean_ms":total/maxi(1,benchmark_samples.size()),"p95_ms":benchmark_samples[int(benchmark_samples.size()*0.95)] if not benchmark_samples.is_empty() else 0.0,"note":"Desktop measurement only; not Steam Deck qualification."}
	var output_path: String = "res://artifacts/benchmark.json" if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("benchmark.json")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--benchmark-output="): output_path = argument.trim_prefix("--benchmark-output=")
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(data,"\t"))
	else: push_error("Could not write benchmark report: " + output_path)
	print("BENCHMARK ",JSON.stringify(data))
	var gate_failures: int = 0
	if benchmark_asserting:
		var mean_ms: float = float(data.mean_ms)
		var p95_ms: float = float(data.p95_ms)
		for check: Dictionary in [{"metric":"mean","measured":mean_ms,"budget":RENDERED_FRAME_BUDGET_MEAN_MS},{"metric":"p95","measured":p95_ms,"budget":RENDERED_FRAME_BUDGET_P95_MS}]:
			var budget: float = float(check.budget) * benchmark_budget_scale
			var ok: bool = float(check.measured) <= budget
			if not ok: gate_failures += 1
			print("measure: rendered_frame bullets=%d %s_ms=%.3f budget_ms=%.3f ok=%d" % [int(data.bullets),str(check.metric),float(check.measured),budget,int(ok)])
		print("RENDERED FRAME GATE: %d checks, %d failures (budget scale %.2f, duration %.1fs)" % [2,gate_failures,benchmark_budget_scale,benchmark_duration])
	await _stop_audio()
	get_tree().quit(1 if benchmark_asserting and gate_failures > 0 else 0)

func _component_controls() -> String: return hud_view.component_controls()

## Thin forwarders to UiKit. `button` is the one every screen builds with: it clicks through the
## soundscape.
static func group(parent: Node) -> Control:
	return UiKit.group(parent)

static func clear(parent: Node) -> void:
	UiKit.clear(parent)

func button(parent: Node, text: String, rect: Rect2, action: Callable) -> Button:
	return UiKit.button(parent,text,rect,action,sound.play.bind("click"))
