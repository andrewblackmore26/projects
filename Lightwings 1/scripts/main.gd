extends Node

const BLUE := VisualStyle.BLUE
const WHITE := VisualStyle.TEXT
const MUTED := VisualStyle.MUTED
const GOLD := VisualStyle.ACCENT
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
## Per-overlay-kind policy: whether opening it pauses the tree, and whether
## Escape/ui_cancel is allowed to close it while it is open. Default (kind
## not listed) matches today's blanket behaviour.
## P7 additions (spec §7.4/§24, frictionless death):
## - `freezes_sim`: the sim is stopped WITHOUT pausing the tree, so a timer
##   and fresh-press detection can still run while it is up.
## - `any_input_dismiss`: a fresh press (not a hold, not motion) dismisses it.
## - `auto_close`: seconds after which it dismisses itself even with no input.
## - `input_guard`: seconds during which even a fresh press is ignored, so the
##   press that caused death cannot also dismiss the card the player never saw.
const SCREEN_POLICY: Dictionary = {
	"evolution": {"pauses": true, "escape_closes": true},
	"map": {"pauses": true, "escape_closes": true},
	"pause": {"pauses": true, "escape_closes": true},
	"options": {"pauses": true, "escape_closes": true},
	"death": {"pauses": false, "escape_closes": false, "freezes_sim": true, "any_input_dismiss": true, "auto_close": GameTuning.DEATH_CARD_SECONDS, "input_guard": GameTuning.DEATH_INPUT_GUARD_SECONDS},
	"ending": {"pauses": true, "escape_closes": false},
	"cloud": {"pauses": true, "escape_closes": true},
	"confirm": {"pauses": true, "escape_closes": true},
}
const DEFAULT_SCREEN_POLICY: Dictionary = {"pauses": true, "escape_closes": true, "freezes_sim": false, "any_input_dismiss": false, "auto_close": 0.0, "input_guard": 0.0}

var combat: CombatWorld
var campaign: CampaignState
var platform: PlatformService
var sound: Soundscape
var ui: Control
var hud: Control
var menu: Control
var overlay: Control
var dialogue: Control
var toast_label: Label
var energy_label: Label
var sector_label: Label
var build_label: Label
var evolution_button: Button
var energy_bar: ProgressBar
var minimap: Control
var map_detail: Label
var teleport_button: Button
var map_selected: Vector2i
var environment: Environment
var menu_ships: Array[ShipRenderer] = []
var mode: String = "menu"
var overlay_kind: String = ""
var absorbed: Dictionary = {}
var pending_offers: Array[String] = []
var previous_offers: Array[String] = []
var offer_serial: int = 0
## Which element's four hulls the evolution screen is showing when every hull is on offer (dev mode).
var evolution_tab: String = ""
var map_center: Vector2i = Vector2i.ZERO
var tier_ticks: Control
var radar_overlay: Control
var slot_overlay: Control
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
var _options_return: String = ""
var _options_focus: WeakRef
var elapsed_ui: float = 0.0
var toast_remaining: float = 0.0
var dialogue_remaining: float = 0.0
var last_hp: float = 100.0
var last_aim: Vector2 = Vector2.UP
var rebind_action: String = ""
var rebind_button: Button
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
var light_mix_label: Label
var light_mix_secondary: Label
var testing: bool = false
var sector_edges: SectorEdges
var cloud_review: Dictionary = {}
var cloud_sync_ready: bool = false
var compositor: CombatCompositor
var mode_config: ModeConfig = ModeConfig.from_demo(false)
var dev_console: DevConsole
var _debug_show_warp: bool = false # --show-warp capture aid only, see _process
var _capture_at_tick: int = 90 # --show-death needs a much shorter delay: the death card is only up for 1.2s
## --- Frictionless death (spec §7.4/§24, plan P7) -------------------------
## The next life is built the INSTANT the player dies (fresh hull, fresh
## sector descriptor, fresh seed already rolled by campaign.on_death()), so
## dismissing the card is just applying data already sitting here - no work
## happens on the dismiss path itself, which is what keeps it fast.
var _death_elapsed: float = 0.0
var _death_stats: Dictionary = {}
var _death_next_sector: Dictionary = {}
## Swallows N upcoming _physics_process command frames after a dismiss, so
## the very press that dismissed the card (e.g. held right-click) cannot
## also fire a dash the instant control returns.
var _input_swallow_frames: int = 0

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
	toast_label = label(ui, "", Vector2(200, 672), Vector2(880,32), 17, GOLD)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_hud()

func _build_hud() -> void:
	panel(hud,Rect2(0,0,1280,78),VisualStyle.PANEL,Color("34343b"))
	label(hud,"L I G H T S H I P",Vector2(24,12),Vector2(290,27),20,WHITE)
	sector_label = label(hud,"ORIGIN",Vector2(25,43),Vector2(330,23),11,MUTED)
	energy_label = label(hud,"LIGHT · T1",Vector2(365,8),Vector2(590,25),15,BLUE)
	energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	energy_bar = progress(hud,Rect2(365,37,590,10),BLUE)
	tier_ticks = Control.new()
	tier_ticks.position = Vector2(365,37)
	tier_ticks.size = Vector2(590,10)
	tier_ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(tier_ticks)
	tier_ticks.draw.connect(_draw_tier_ticks)
	radar_overlay = Control.new()
	radar_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(radar_overlay)
	radar_overlay.draw.connect(_draw_radar)
	light_mix_label = label(hud,"",Vector2(365,51),Vector2(295,20),10,MUTED)
	light_mix_secondary = label(hud,"",Vector2(660,51),Vector2(295,20),10,MUTED)
	button(hud,"MAP · TAB",Rect2(989,18,171,40),_show_map)
	button(hud,"Ⅱ",Rect2(1172,18,78,40),_show_pause)
	panel(hud,Rect2(0,717,1280,83),VisualStyle.PANEL,Color("34343b"))
	build_label = label(hud,"SEED",Vector2(24,728),Vector2(790,62),13,MUTED)
	slot_overlay = Control.new()
	slot_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(slot_overlay)
	slot_overlay.draw.connect(_draw_slot_icons)
	## Pill under the bar (spec §24: slot icons and the evolve prompt must
	## coexist, not overlap -- moved off the slot-icon strip at y=752).
	evolution_button = button(hud,"EVOLUTION READY · E",Rect2(845,690,405,22),_show_evolution)
	evolution_button.add_theme_font_size_override("font_size",12)
	evolution_button.visible = false
	minimap = Control.new()
	minimap.position = Vector2(1057,101)
	minimap.size = Vector2(186,186)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Review finding 6: the perimeter used to be a circular arc that both had
	# the wrong shape (the level boundary is a square Chebyshev ring, spec
	# §11) and spilled outside this panel across the playfield. Clip so
	# nothing this Control draws can ever leave its own declared rect.
	minimap.clip_contents = true
	hud.add_child(minimap)
	minimap.draw.connect(_draw_minimap)
	hud.visible = false

func _draw_slot_icons() -> void:
	## Spec §24: slot icons with cooldowns AND the evolve prompt are both
	## required on screen at once (P1 left this returning early because they
	## used to overlap -- the evolve pill moved in _build_hud so they no
	## longer do; slot icons must stay visible regardless of its visibility).
	if not is_instance_valid(combat): return
	var ship: ShipDefinition = combat.player.get("definition")
	if ship == null: return
	var components: Array[String] = ship.mounted_components()
	for index: int in range(components.size()):
		var definition: AbilityDefinition = AbilityCatalog.get_definition(components[index])
		var at: Vector2 = Vector2(867+index*68,752)
		var ink: Color = ShipCatalog.get_color(definition.visual_color)
		slot_overlay.draw_circle(at,13,Color(ink.r*0.1,ink.g*0.1,ink.b*0.1))
		slot_overlay.draw_arc(at,13,0,TAU,28,ink,1.5,true)
		var cooldown: float = float(combat.player.get("fire_cd",0.0)) if index==0 else float(combat.player.get("cooldowns",{}).get("secondary_%d" % (index-1),0.0))
		var fill: float = 1.0-clampf(cooldown/maxf(0.001,definition.cooldown),0,1)
		slot_overlay.draw_arc(at,17,-PI/2,-PI/2+TAU*maxf(fill,0.005),32,Color(ink,0.6),1.0,true)
		var text: String = "LMB" if index==0 else (["SPACE","SHIFT","Q"][index-1] if index<=ship.secondaries.size() else "PASSIVE")
		slot_overlay.draw_string(ThemeDB.fallback_font,at+Vector2(-22,35),text,HORIZONTAL_ALIGNMENT_CENTER,44,9,Color("9099a8"))
	_draw_dash_icon()

## Dash cooldown icon (spec §26/plan P6): next to the existing slot icons,
## one fixed slot to their left rather than indexed with `components` (the
## dash is not an ability mount).
func _draw_dash_icon() -> void:
	var at: Vector2 = Vector2(867-68,752)
	var cooldown: float = float(combat.player.get("dash_cooldown",0.0))
	var fill: float = 1.0-clampf(cooldown/CombatWorld.DASH_COOLDOWN_SECONDS,0,1)
	var ready: bool = cooldown<=0.0
	var ink: Color = BLUE if ready else MUTED
	slot_overlay.draw_circle(at,13,Color(ink.r*0.1,ink.g*0.1,ink.b*0.1))
	slot_overlay.draw_arc(at,13,0,TAU,28,ink,1.5,true)
	slot_overlay.draw_arc(at,17,-PI/2,-PI/2+TAU*maxf(fill,0.005),32,Color(ink,0.6),1.0,true)
	slot_overlay.draw_string(ThemeDB.fallback_font,at+Vector2(-22,35),"RMB",HORIZONTAL_ALIGNMENT_CENTER,44,9,Color("9099a8"))

func _draw_radar() -> void:
	if not is_instance_valid(combat) or not combat.has_passive("radar"): return
	var visible_area: Rect2 = Rect2(22,94,1236,608)
	for actor: Dictionary in combat.enemies:
		if bool(actor.get("dead",false)): continue
		var screen: Vector2 = Vector2(actor.pos)-combat.player_position+Vector2(640,400)
		if visible_area.has_point(screen): continue
		var direction: Vector2 = screen-Vector2(640,400)
		var scale_factor: float = minf(610.0/maxf(0.001,absf(direction.x)),294.0/maxf(0.001,absf(direction.y)))
		var at: Vector2 = Vector2(640,400)+direction*scale_factor
		radar_overlay.draw_circle(at,3.5,ShipCatalog.get_color(str(actor.element)))

func _draw_tier_ticks() -> void:
	if not is_instance_valid(combat): return
	var capacity: float = GameTuning.capacity(combat.player_tier,mode_config.max_tier())
	for index: int in range(GameTuning.THRESHOLDS.size()):
		var threshold: float = GameTuning.THRESHOLDS[index]
		if threshold > capacity: continue
		var x: float = threshold/capacity*590.0
		tier_ticks.draw_line(Vector2(x,-3),Vector2(x,13),Color(WHITE,0.6),1.0)
	var floor_value: float = GameTuning.regression_floor(combat.player_tier)
	if floor_value > 0:
		var ink: Color = Color("ff5436")
		ink.a = 0.55+0.45*sin(elapsed_ui*7.0) if combat.light_total < floor_value*1.12 else 0.65
		var x: float = floor_value/capacity*590.0
		tier_ticks.draw_line(Vector2(x,-4),Vector2(x,14),ink,2.0)
	# Spec §24/§7.2: combo multiplier near the bar, decaying visibly - once
	# the 2.5s kill window lapses and the count is draining, the readout
	# pulses instead of holding solid.
	if combat.combo_count > 0:
		var draining: bool = combat.combo_timer <= 0.0
		var combo_alpha: float = (0.5+0.5*sin(elapsed_ui*9.0)) if draining else 1.0
		var combo_text: String = "COMBO x%.1f (%d)" % [combat.combo_multiplier(),combat.combo_count]
		tier_ticks.draw_string(ThemeDB.fallback_font,Vector2(590-160,-16),combo_text,HORIZONTAL_ALIGNMENT_RIGHT,160,13,Color(GOLD,combo_alpha))

func _show_menu() -> void:
	mode = "menu"
	get_tree().paused = false
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
	var background := ColorRect.new()
	background.color = VisualStyle.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(background)
	var margin := MarginContainer.new()
	margin.name = "MenuLayout"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 80)
	for side: String in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 56)
	menu.add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 64)
	margin.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 430
	left.add_theme_constant_override("separation", 14)
	columns.add_child(left)
	_menu_label(left, "AN INSTANCE AWAKENS", 12, GOLD)
	_menu_label(left, "LIGHTSHIP", 62, WHITE)
	_menu_label(left, "Absorb light. Become something new.", 20, MUTED)
	var gap := Control.new()
	gap.custom_minimum_size.y = 20
	left.add_child(gap)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	left.add_child(actions)
	## Available modes for THIS build flavour (spec §4: a demo build offers
	## demo only -- Dev must never be reachable there). The old "PLAY THE
	## DEMO" full-build entry is gone: the demo is its own build flavour now
	## (approved preamble), not a menu option inside the full campaign.
	var available_modes: Array[String] = ModeConfig.available_modes(OS.has_feature("demo"))
	var menu_slot: String = ModeConfig.from_id(available_modes[0]).save_slot()
	var exists: bool = not SaveService.load_snapshot(menu_slot).is_empty() or FileAccess.file_exists(SaveService.snapshot_path(menu_slot))
	var primary: Button = _menu_action(actions,("CONTINUE " if exists else "BEGIN ")+menu_slot.to_upper(),func() -> void: _continue_game(menu_slot) if exists else _show_level_select(available_modes[0]))
	primary.custom_minimum_size.y = 52
	primary.add_theme_stylebox_override("normal",box(Color("292820"),GOLD))
	if "dev" in available_modes:
		_menu_action(actions,"DEV MODE",_show_level_select.bind("dev"))
	if exists and OS.has_feature("demo"):
		_menu_action(actions,"NEW DEMO",_confirm_new.bind(true))
	if OS.has_feature("editor"):
		var tools_row := HBoxContainer.new()
		tools_row.add_theme_constant_override("separation", 10)
		actions.add_child(tools_row)
		_menu_action(tools_row,"SHIP WORKSHOP",_open_editor)
		_menu_action(tools_row,"SHIP ATLAS",_open_gallery)
	var utilities := HBoxContainer.new()
	utilities.add_theme_constant_override("separation", 10)
	actions.add_child(utilities)
	_menu_action(utilities,"OPTIONS",_show_options)
	_menu_action(utilities,"QUIT",_quit)
	if exists and not OS.has_feature("demo"):
		_menu_action(actions,"NEW CAMPAIGN",_confirm_new)
	if not OS.has_feature("demo") and not SaveService.load_snapshot("demo").is_empty():
		_menu_action(actions,"IMPORT DEMO",_import_demo)
	if platform.online and not OS.has_feature("demo"):
		cloud_review = platform.inspect_cloud(menu_slot)
		cloud_sync_ready = str(cloud_review.get("state","")) in ["same","missing"]
		if str(cloud_review.get("state","")) in ["conflict","remote_only"]:
			_menu_action(actions,"REVIEW CLOUD SAVE",_show_cloud_review)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	_menu_label(left,"WASD + MOUSE  /  CONTROLLER",11,MUTED)
	_menu_label(left,"DEMO · LIGHTNING / FIRE · LEVELS 1–2" if OS.has_feature("demo") else "FIVE ELEMENTS · ONE LIVING MACHINE",11,MUTED)
	var hero := ShipPreview.new()
	hero.name = "MenuHero"
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero.custom_minimum_size = Vector2(360, 360)
	hero.preview_time_scale = 1.0
	hero.fit_margin = 48.0
	columns.add_child(hero)
	hero.initialize(ShipCatalog.get_ship("player_lightning_t3_standard_a"),Vector2(560,640),1.8)
	primary.grab_focus()

func _menu_label(parent: Node, text: String, font_size: int, ink: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",ink)
	parent.add_child(result)
	return result

func _menu_action(parent: Node, text: String, action: Callable) -> Button:
	var result: Button = button(parent,text,Rect2(0,0,0,40),action)
	result.custom_minimum_size.y = 40
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_font_size_override("font_size",14)
	return result

## Level select (spec §4: "Menu: Campaign and Dev mode, each with level
## select"). Campaign offers levels 1..completed+1; dev offers all five.
## This chooses where a NEW run starts; an existing "continue" resumes
## exactly where the profile left off and does not go through this screen.
func _show_level_select(mode_id: String) -> void:
	var config := ModeConfig.from_id(mode_id)
	var completed: Array = []
	var snapshot: Dictionary = SaveService.load_snapshot(config.save_slot())
	if not snapshot.is_empty(): completed.assign(snapshot.get("profile",{}).get("levels_completed",[]))
	_open_overlay("confirm")
	label(overlay,"SELECT A LEVEL · "+config.menu_label(),Vector2(200,120),Vector2(880,52),30,WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var levels: Array[int] = config.selectable_levels(completed)
	var first: Button
	for index: int in range(levels.size()):
		var level: int = levels[index]
		var choice: Button = button(overlay,"LEVEL %d · %s" % [level,GameTuning.ELEMENTS[mini(level-1,GameTuning.ELEMENTS.size()-1)].to_upper()],Rect2(200+float(index%2)*440,220+float(index/2)*70,400,52),_begin_at_level.bind(mode_id,level))
		if first == null: first = choice
	button(overlay,"CANCEL",Rect2(480,560,320,45),_close_overlay)
	if first != null: first.grab_focus()

func _begin_at_level(mode_id: String, level: int) -> void:
	_close_overlay()
	_new_game_as(mode_id)
	if level > 1: _travel_to_level(level)

func _new_game_as(mode_id: String) -> void:
	mode_config = ModeConfig.from_id(mode_id)
	slot = mode_config.save_slot()
	campaign = CampaignState.new()
	campaign.configure_mode(mode_id)
	campaign.world_seed = randi() if not testing else 734927
	absorbed = {}
	pending_offers.clear()
	previous_offers.clear()
	offer_serial = 0
	dialogue_director.reset()
	_start_game_view()
	combat.setup_player("neutral",1,40,[],GameTuning.ARENA_CENTER)
	combat.max_player_tier = mode_config.max_tier()
	_queue_line("companion","Your first light","Your white core is your hitbox. Hollow light circles heal you and fill the same bar that grows your ship. Fly through an opening and find your first fight.","welcome_v2")
	_enter_sector(Vector2i.ZERO,GameTuning.ARENA_CENTER,false)

## Kept for the many call sites (and tests) that only ever asked the old
## binary demo/campaign question.
func _new_game(is_demo: bool) -> void:
	_new_game_as("demo" if (is_demo or OS.has_feature("demo")) else "campaign")

func _travel_to_level(level: int) -> void:
	campaign.travel_to_level(level)
	_enter_sector(Vector2i.ZERO,GameTuning.ARENA_CENTER,false)

func _continue_game(save_slot: String) -> void:
	var snapshot: Dictionary = SaveService.load_snapshot(save_slot)
	if snapshot.is_empty():
		if not SaveService.last_error.is_empty():
			_toast("Save could not be restored: "+SaveService.last_error)
			return
		_new_game(save_slot == "demo")
		return
	slot = save_slot
	campaign = CampaignState.new()
	campaign.from_dict(snapshot.get("profile",{}))
	mode_config = ModeConfig.from_id(campaign.mode)
	var run: Dictionary = snapshot.get("run",{})
	pending_offers.assign(run.get("pending_offers",[]))
	previous_offers.assign(run.get("previous_offers",[]))
	offer_serial = int(run.get("offer_serial",0))
	dialogue_director.restore(run.get("seen_lines",{}),run.get("line_queue",[]))
	_start_game_view()
	combat.max_player_tier = mode_config.max_tier()
	if run.get("combat",{}).is_empty():
		combat.setup_player("neutral",1,40,[],GameTuning.ARENA_CENTER)
		_enter_sector(Vector2i.ZERO,GameTuning.ARENA_CENTER,false)
	else:
		combat.restore(run.combat)
	absorbed = combat.absorption
	_toast("Instance restored. Your light is still yours.")
	last_hp = combat.light_total
	_refresh_hud()

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

func _enter_sector(coord: Vector2i, spawn: Vector2, show_intro: bool = true) -> void:
	if is_instance_valid(combat) and not combat.sector.is_empty():
		campaign.record_node_left(campaign.current_sector,combat.elapsed,float(combat.sector_energy_remaining))
	campaign.on_enter(coord)
	var sector: Dictionary = campaign.sector_at(coord,combat.elapsed if is_instance_valid(combat) else 0.0)
	combat.player_position = spawn
	combat.start_sector(sector)
	dialogue.visible = false
	dialogue_remaining = 0.0
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
	_refresh_hud()
	_save_game()

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
		var policy: Dictionary = SCREEN_POLICY.get("death",DEFAULT_SCREEN_POLICY)
		if _death_elapsed >= float(policy.auto_close): _dismiss_death_card()
	if platform != null:
		platform.set_input_context(mode != "play" or get_tree().paused)
	toast_remaining = maxf(0.0,toast_remaining-delta)
	toast_label.visible = toast_remaining > 0.0
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
		var policy: Dictionary = SCREEN_POLICY.get("death",DEFAULT_SCREEN_POLICY)
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
		if not overlay_kind.is_empty() and not bool(SCREEN_POLICY.get(overlay_kind,DEFAULT_SCREEN_POLICY).escape_closes):
			return
		if not overlay_kind.is_empty():
			if overlay_kind == "options": _close_options()
			else: _close_overlay()
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

## Node-to-node transition is now the warp (spec §12/plan P6), not an instant
## cut: `combat` runs the push/commit/travel state machine itself and fires
## `warp_committed` the instant control locks. This handler does the sector
## swap SYNCHRONOUSLY (GDScript signal emission is synchronous), so it is
## done well before the travel phase ends and `confirm_warp_swap()` is
## always called in time - the "missing node swap springs back" case is a
## test-only scenario (nothing connects this signal), not something that can
## happen in play.
func _on_warp_committed(direction: Vector2i) -> void:
	if not is_instance_valid(combat) or campaign == null: return
	campaign.record_node_left(campaign.current_sector,combat.elapsed,float(combat.sector_energy_remaining))
	var destination: Vector2i = campaign.current_sector+direction
	campaign.on_enter(destination)
	var sector: Dictionary = campaign.sector_at(destination,combat.elapsed)
	combat.start_sector(sector)
	combat.confirm_warp_swap()
	dialogue.visible = false
	dialogue_remaining = 0.0
	if str(sector.get("kind","")) == "boss" and not bool(sector.get("boss_down",false)):
		# Immediate lane (spec §25 "a line ... on encounter"): this must be able
		# to show on entry, not only once the boss it announces is already dead.
		_queue_line(str(sector.element),"A rival signal",DialogueDirector.entry_line(str(sector.element)),"boss_intro_"+str(sector.element),true)
	if destination != Vector2i.ZERO:
		_queue_line("companion","Direction and distance","Direction decides the light you find. Distance decides the danger. Every opening stays open; you can always retreat.","map_tutorial_v2")
	for actor: Dictionary in combat.enemies:
		if bool(actor.get("elite",false)):
			_queue_line("companion","A machine with many hands","That large ship carries several weapons, each with its own rhythm. Watch how its silhouette changes under fire.","first_elite_v2")
			break
	# Saves moved off the per-node-entry critical path (plan P6 item 6): this
	# fires once, here, inside the warp's own locked window - never on the
	# old instant-cut hot path.
	_save_game()
	_refresh_hud()

func _refresh_hud() -> void:
	if not is_instance_valid(combat) or campaign == null: return
	var next: int = EvolutionRules.threshold(combat.player_tier)
	var capped: bool = combat.player_tier >= mode_config.max_tier()
	var capacity: float = GameTuning.capacity(combat.player_tier,mode_config.max_tier())
	var ship: ShipDefinition = combat.player.get("definition")
	if ship == null: return
	var readout: bool = "health_readout" in ship.passives
	energy_label.text = "LIGHT · T%d  %s" % [combat.player_tier,"MAX TIER" if capped else "NEXT T%d · %d" % [combat.player_tier+1,next]]
	if readout: energy_label.text += " · %.1f / %.0f" % [combat.light_total,capacity]
	energy_bar.value = combat.light_total/capacity*100.0
	tier_ticks.queue_redraw()
	radar_overlay.queue_redraw()
	slot_overlay.queue_redraw()
	sector_label.text = "%s · NODE %s · RING %d" % ["DEMO" if campaign.demo else "CAMPAIGN",CampaignState.coord_key(campaign.current_sector),CampaignState.ring(campaign.current_sector)]
	absorbed = combat.absorption
	var leading: Array = absorbed.keys()
	leading.sort_custom(func(a: String,b: String) -> bool: return float(absorbed[a])>float(absorbed[b]))
	var mix := PackedStringArray()
	for i: int in range(mini(3,leading.size())):
		mix.append("%s %.0f" % [str(leading[i]).to_upper(),float(absorbed[leading[i]])])
	light_mix_label.text = " / ".join(mix)
	light_mix_secondary.text = "ABSORBED SINCE EVOLUTION" if not mix.is_empty() else "ABSORB LIGHT TO HEAL AND GROW"
	build_label.text = "%s · T%d %s\nPrimary: %s  |  %s\nPassive: %s" % [ship.display_name,ship.tier,ship.role.capitalize(),_ability_name(ship.primary),_component_controls(),_ability_names(ship.passives)]
	evolution_button.visible = not capped and combat.light_total >= next and combat.light_total > 0.0
	if is_instance_valid(combat.player.get("renderer")): combat.player.renderer.evolution_ready = evolution_button.visible
	if evolution_button.visible: evolution_button.modulate = Color.WHITE*(0.88+0.12*sin(elapsed_ui*3.0))
	minimap.queue_redraw()

func _ability_name(id: String) -> String:
	var definition: AbilityDefinition = AbilityCatalog.get_definition(id)
	return definition.display_name if definition != null else id.replace("_"," ").capitalize()

func _ability_names(ids: Array) -> String:
	var names := PackedStringArray()
	for id: String in ids: names.append(_ability_name(id))
	return ", ".join(names) if not names.is_empty() else "None"

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

func _on_boss_defeated(element: String) -> void:
	if element.is_empty(): return
	# CampaignState.complete_level() is itself idempotent (tasks/todo.md:
	# "call it every time a boss dies; it only fires level_completed... the
	# first time"), so this handler needs no separate guard of its own.
	var result: Dictionary = campaign.complete_level()
	_queue_line(element,"A rival yields",DialogueDirector.defeat_line(element),"defeat_v2_"+element)
	_achieve("FIRST_RIVAL")
	if bool(result.get("level_completed",false)):
		if campaign.campaign_complete():
			_achieve("CAMPAIGN_COMPLETE")
			# CampaignState.campaign_complete() is now mode-aware (ModeConfig.level_cap):
			# for the demo this is true the instant level 2's boss dies, so this is
			# exactly the demo ending trigger spec §4/preamble asks for -- "on beating
			# the level-2 boss", not the old wedge-world "Fire core".
			_show_ending(mode_config.id == "demo")
		else:
			_show_level_complete(result)
	_save_game()

## Level complete (spec §4/§11): reveal the next element, unlock the next
## level, grant the achievement (already through the mode guard, `_achieve`
## above), and offer CONTINUE TO LEVEL N+1 / KEEP EXPLORING.
func _show_level_complete(result: Dictionary) -> void:
	var next_level: int = int(result.get("next_level",campaign.level+1))
	var revealed: String = str(result.get("revealed_element",""))
	_open_overlay("ending")
	label(overlay,"LEVEL %d COMPLETE" % campaign.level,Vector2(100,220),Vector2(1080,70),35,WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var text: String = "The rival's signal yields.\n%s light now reveals itself in the world." % revealed.capitalize() if not revealed.is_empty() else "The rival's signal yields."
	label(overlay,text,Vector2(150,340),Vector2(980,80),22,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button(overlay,"CONTINUE TO LEVEL %d" % next_level,Rect2(440,470,400,55),_begin_at_level.bind(mode_config.id,next_level)).grab_focus()
	button(overlay,"KEEP EXPLORING",Rect2(440,545,400,48),_close_overlay)
	button(overlay,"SAVE & MAIN MENU",Rect2(440,619,400,48),func() -> void: _save_game(); _show_menu())

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
	_open_overlay("evolution")
	label(overlay,"BECOME SOMETHING NEW",Vector2(110,45),Vector2(1060,52),34,WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label(overlay,"Choose a lightship. Every weapon and passive shown belongs to that hull.",Vector2(110,110),Vector2(1060,35),17,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var first: Button
	var x: float = 125.0
	# With every hull on offer (dev mode) the cards are grouped behind a one-element-at-a-time tab
	# strip: 20 cards will not fit, and 20 live ShipPreviews would mean 20 HDR SubViewports.
	var shown: Array[String] = pending_offers
	if pending_offers.size() > 3:
		var by_element: Dictionary = {}
		for id: String in pending_offers:
			var ship: ShipDefinition = ShipCatalog.get_ship(id)
			if ship == null: continue
			if not by_element.has(ship.element): by_element[ship.element] = [] as Array[String]
			by_element[ship.element].append(id)
		var elements: Array = by_element.keys()
		if not elements.has(evolution_tab): evolution_tab = str(elements[0]) if not elements.is_empty() else ""
		var tab_x: float = 125.0
		for element: String in elements:
			var tab: Button = button(overlay,element.to_upper(),Rect2(tab_x,128,190,30),func() -> void:
				evolution_tab = element
				_close_overlay()
				_show_evolution())
			tab.disabled = element == evolution_tab
			tab_x += 200.0
		shown = by_element.get(evolution_tab,[] as Array[String])
	for id: String in shown:
		var ship: ShipDefinition = ShipCatalog.get_ship(id)
		if ship == null: continue
		var ink: Color = ShipCatalog.get_color(ship.element)
		panel(overlay,Rect2(x,165,330,497),VisualStyle.PANEL,Color(ink,0.4))
		label(overlay,"%s · %s · T%d" % [ship.element.to_upper(),ship.role.to_upper(),ship.tier],Vector2(x+20,183),Vector2(290,25),12,ink)
		label(overlay,ship.display_name,Vector2(x+20,218),Vector2(290,48),24,WHITE)
		var preview := ShipPreview.new()
		preview.fit_margin = 14.0
		overlay.add_child(preview)
		preview.position = Vector2(x+20,267)
		preview.initialize(ship,Vector2(290,175),1.5)
		label(overlay,"Primary: %s\nSecondary: %s\nPassive: %s" % [_ability_name(ship.primary),_ability_names(ship.secondaries),_ability_names(ship.passives)],Vector2(x+20,450),Vector2(290,92),14,WHITE)
		label(overlay,"Speed %.0f · Buffer ×%.2f\nFootprint %.0f px · Magnet %.0f px" % [ship.speed,ship.hp_buffer,ship.footprint,ship.magnet_radius],Vector2(x+20,547),Vector2(290,45),12,MUTED)
		var choice: Button = button(overlay,"CHOOSE SHIP",Rect2(x+20,608,290,40),_choose_evolution.bind(id))
		if first == null: first = choice
		x += 350.0
	label(overlay,"GAMEPLAY PAUSED · Choose your next form",Vector2(100,679),Vector2(1080,25),13,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button(overlay,"DECIDE LATER",Rect2(520,720,240,43),_close_overlay)
	if first != null: first.grab_focus()

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

## The full map screen (spec §11). MinimapModel is the single source of
## truth: the whole level fits on screen at every level radius (R up to 12
## -> a 25x25 grid), so there is no panning, no waypoint picker, no JUMP.
func _show_map() -> void:
	if mode != "play" or not is_instance_valid(combat) or (not overlay_kind.is_empty() and overlay_kind != "map"): return
	_open_overlay("map")
	label(overlay,"THE AI-VERSE",Vector2(85,20),Vector2(620,40),28,WHITE)
	var model: MinimapModel = MinimapModel.build(campaign)
	label(overlay,"Boss bearing: %s · %d nodes" % [model.bearing_direction,model.bearing_distance],Vector2(87,58),Vector2(1000,26),16,GOLD)
	var side: int = model.grid_size()
	var area: float = 600.0
	var cell: float = area/float(side)
	var origin := Vector2(80,92)
	for map_cell: MinimapModel.Cell in model.cells:
		var local: Vector2i = map_cell.coord+Vector2i(model.radius,model.radius)
		var at: Vector2 = origin+Vector2(local)*cell
		var tile: Button = button(overlay,"",Rect2(at,Vector2(cell-1.5,cell-1.5)),_select_map_sector.bind(map_cell.coord))
		var ink: Color = _sector_color(map_cell.coord,map_cell.explored)
		var fill: Color = Color(ink,0.14) if map_cell.explored else Color("050608")
		var border: Color = Color(ink,0.55) if map_cell.explored else Color("1c2028")
		# A Chebyshev disc IS the square this grid draws, so the sealed
		# perimeter is the OUTERMOST RING, not a set of excluded cells: those
		# nodes' membranes never open outward (spec §11 "sits on the
		# perimeter"). Draw that ring as a solid wall regardless of element.
		var is_perimeter: bool = not map_cell.in_bounds or CampaignState.ring(map_cell.coord) == model.radius
		if is_perimeter:
			fill = Color("0b0d12") if not map_cell.in_bounds else fill
			border = MUTED
		tile.add_theme_stylebox_override("normal",box(fill,border,3 if is_perimeter else 1))
		tile.tooltip_text = _sector_description(map_cell.coord)
		if map_cell.is_boss: label(overlay,"◎",at,Vector2(cell,cell),12,GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		elif map_cell.current: label(overlay,"●",at,Vector2(cell,cell),12,WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel(overlay,Rect2(700,92,480,412),VisualStyle.PANEL,Color("34343b"))
	map_detail = label(overlay,"",Vector2(725,112),Vector2(430,201),17,WHITE)
	label(overlay,"● You   ◎ Boss (bearing above, from the first tick)\nDark = unexplored, reveals nothing. Wall border = sealed perimeter.\nLayouts re-roll every life (spec §7).",Vector2(725,330),Vector2(430,140),15,MUTED)
	button(overlay,"RETURN TO FLIGHT",Rect2(870,721,320,45),_close_overlay).grab_focus()
	_select_map_sector(campaign.current_sector)

func _select_map_sector(coord: Vector2i) -> void:
	map_selected = coord
	map_detail.text = _sector_description(coord)

func _sector_description(coord: Vector2i) -> String:
	if not campaign.in_bounds(coord): return "NODE %s\n\nSealed perimeter." % CampaignState.coord_key(coord)
	if not _sector_known(coord): return "NODE %s\n\nUnexplored space." % CampaignState.coord_key(coord)
	var sector: Dictionary = campaign.sector_at(coord)
	var lines := PackedStringArray(["NODE %s · RING %d" % [CampaignState.coord_key(coord),int(sector.get("ring",0))]])
	lines.append("\nSAFE ORIGIN" if coord == Vector2i.ZERO else "\n%s · %s" % [str(sector.get("element","")).to_upper(),str(sector.get("kind","regular")).replace("_"," ").to_upper()])
	if coord != Vector2i.ZERO: lines.append("Threat tier %d" % int(sector.get("tier",1)))
	return "\n".join(lines)

func _sector_known(coord: Vector2i) -> bool:
	return coord == Vector2i.ZERO or CampaignState.coord_key(coord) in campaign.discovered

func _sector_color(coord: Vector2i, known: bool) -> Color:
	if coord == campaign.current_sector: return WHITE
	if not known: return Color("242b36")
	if coord == Vector2i.ZERO: return WHITE
	return ShipCatalog.get_color(str(campaign.sector_at(coord).get("element","fire")))

func _draw_minimap() -> void:
	if campaign == null or not is_instance_valid(combat): return
	const CELL: float = 18.0
	var center := Vector2(93,93)
	var model: MinimapModel = MinimapModel.build(campaign)
	minimap.draw_rect(Rect2(Vector2(-5,-5),Vector2(196,217)),Color(0.02,0.025,0.035,0.94))
	# Review finding 6: the level boundary is a square Chebyshev ring around
	# the origin (§11's own "bounded disc" is `in_bounds`, a Chebyshev test -
	# see minimap_model.gd), not a Euclidean circle, and it does not move
	# with the player. The full map screen already draws this correctly as a
	# border on `ring == radius` (main.gd's own `_show_map`); this matches
	# that model instead of an independent (and wrong) circle.
	for map_cell: MinimapModel.Cell in model.cells:
		var offset: Vector2i = map_cell.coord-campaign.current_sector
		if maxi(absi(offset.x),absi(offset.y)) > 4: continue # local window only; boss marker (below) is unwindowed
		if not map_cell.in_bounds: continue
		var at: Vector2 = center+Vector2(offset)*CELL
		var is_perimeter: bool = CampaignState.ring(map_cell.coord) == model.radius
		if not map_cell.explored:
			minimap.draw_circle(at,4.0,Color("13161d")) # unexplored: dark, discloses nothing
			if is_perimeter: minimap.draw_rect(Rect2(at-Vector2(CELL,CELL)*0.5,Vector2(CELL,CELL)),Color(MUTED,0.5),false,2.0)
			continue
		var ink: Color = _sector_color(map_cell.coord,true)
		minimap.draw_circle(at,5.0,Color(ink,0.16))
		minimap.draw_arc(at,5.0,0,TAU,16,Color(ink,0.7),1.0,true)
		if is_perimeter: minimap.draw_rect(Rect2(at-Vector2(CELL,CELL)*0.5,Vector2(CELL,CELL)),Color(MUTED,0.5),false,2.0) # perimeter as a solid wall (spec §11), square not circular
	minimap.draw_circle(center,3,BLUE)
	# Boss marker + bearing, present from the first tick regardless of the
	# local window above (spec §11 M3: "always knows which way the boss is").
	var direction: Vector2 = Vector2(model.boss_coord-campaign.current_sector)
	if not direction.is_zero_approx():
		minimap.draw_circle(center+direction.normalized()*87,3,ShipCatalog.get_color(str(campaign.sector_at(model.boss_coord).get("element",""))))
	minimap.draw_string(ThemeDB.fallback_font,Vector2(3,203),"RING %d · T%d · BOSS %s %d" % [CampaignState.ring(campaign.current_sector),combat.player_tier,model.bearing_direction,model.bearing_distance],HORIZONTAL_ALIGNMENT_LEFT,180,12,MUTED)

func _reward_for(root: String, tier: int) -> String:
	return {"fire":"cinder_pod" if tier>=4 else "ember_gun","lightning":"capacitor","void":"satellite","corruption":"spore_bud"}.get(root,"laser_prong")

func _show_pause() -> void:
	if mode != "play" or not overlay_kind.is_empty(): return
	_open_overlay("pause")
	label(overlay,"INSTANCE PAUSED",Vector2(400,205),Vector2(480,58),35,WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button(overlay,"RESUME",Rect2(450,320,380,52),_close_overlay).grab_focus()
	button(overlay,"OPTIONS & CONTROLS",Rect2(450,387,380,52),_show_options)
	button(overlay,"SAVE & MAIN MENU",Rect2(450,454,380,52),func() -> void: _save_game(); _show_menu())
	button(overlay,"SAVE & QUIT",Rect2(450,521,380,52),_quit)

func _show_options() -> void:
	if overlay_kind != "options":
		_options_return = overlay_kind
		var focused: Control = get_viewport().gui_get_focus_owner()
		_options_focus = weakref(focused) if focused != null else null
	_open_overlay("options")
	label(overlay,"OPTIONS",Vector2(90,55),Vector2(1100,52),34,WHITE)
	var tabs := TabContainer.new()
	tabs.name = "OptionsTabs"
	tabs.position = Vector2(90,135)
	tabs.size = Vector2(1100,530)
	overlay.add_child(tabs)
	var pages: Dictionary = {}
	for title: String in ["Audio","Display","Gameplay","Controls"]:
		var page := MarginContainer.new()
		page.name = title
		for side: String in ["left","right","top","bottom"]: page.add_theme_constant_override("margin_"+side,28)
		tabs.add_child(page)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation",15)
		page.add_child(content)
		pages[title] = content
	_option_slider(pages.Audio,"Master volume","volume")
	_option_slider(pages.Audio,"Effects","effects_volume")
	_option_slider(pages.Audio,"Interface","interface_volume")
	_option_slider(pages.Audio,"Ambience","ambience_volume")
	_option_toggle(pages.Audio,"Ambient music","music")
	_option_toggle(pages.Audio,"Pickup cues","pickup_cues")
	_option_toggle(pages.Display,"Fullscreen","fullscreen")
	_option_toggle(pages.Display,"Soft glow","glow")
	_option_toggle(pages.Display,"Reduced warp effect","reduced_warp")
	_option_toggle(pages.Display,"Damage numbers","damage_numbers")
	_option_toggle(pages.Gameplay,"Auto-fire","auto_fire")
	_option_toggle(pages.Gameplay,"Element names and pattern labels","show_elements")
	_menu_label(pages.Controls,"Choose a binding, then press a key, mouse button or controller input.",14,MUTED)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation",18)
	grid.add_theme_constant_override("v_separation",10)
	pages.Controls.add_child(grid)
	for action: String in InputBindings.ACTIONS:
		var action_label: Label = _menu_label(grid,str(InputBindings.ACTIONS[action]),14,WHITE)
		action_label.custom_minimum_size.x = 125
		var bind_button: Button = button(grid,_binding_label(action),Rect2(0,0,0,34),_capture_binding.bind(action))
		bind_button.tooltip_text = InputBindings.describe(action)
		bind_button.custom_minimum_size = Vector2(300,34)
		bind_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bind_button.add_theme_font_size_override("font_size",12)
	if platform.online: _menu_action(pages.Controls,"STEAM CONTROLLER LAYOUT",func() -> void: platform.show_input_bindings())
	tabs.current_tab = options_tab
	tabs.tab_changed.connect(func(index: int) -> void: options_tab = index)
	button(overlay,"DONE",Rect2(870,711,320,48),_close_options).grab_focus()

func _close_options() -> void:
	var previous: String = _options_return
	var focus: Control = _options_focus.get_ref() as Control if _options_focus != null else null
	_close_overlay()
	_options_return = ""
	_options_focus = null
	if previous == "pause" and mode == "play": _show_pause()
	elif is_instance_valid(focus) and focus.is_visible_in_tree(): focus.grab_focus()

func _binding_label(action: String) -> String:
	var labels := PackedStringArray()
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			labels.append(OS.get_keycode_string(event.physical_keycode if event.physical_keycode else event.keycode))
		elif event is InputEventMouseButton:
			labels.append({MOUSE_BUTTON_LEFT:"Left click",MOUSE_BUTTON_RIGHT:"Right click",MOUSE_BUTTON_MIDDLE:"Middle click",MOUSE_BUTTON_WHEEL_UP:"Wheel up",MOUSE_BUTTON_WHEEL_DOWN:"Wheel down"}.get(event.button_index,"Mouse %d" % event.button_index))
		elif event is InputEventJoypadMotion:
			var direction: String = "−" if event.axis_value < 0 else "+"
			labels.append({JOY_AXIS_LEFT_X:"Left stick X"+direction,JOY_AXIS_LEFT_Y:"Left stick Y"+direction,JOY_AXIS_RIGHT_X:"Right stick X"+direction,JOY_AXIS_RIGHT_Y:"Right stick Y"+direction,JOY_AXIS_TRIGGER_LEFT:"LT",JOY_AXIS_TRIGGER_RIGHT:"RT"}.get(event.axis,"Pad axis %d%s" % [event.axis,direction]))
		elif event is InputEventJoypadButton:
			labels.append({JOY_BUTTON_A:"South / A",JOY_BUTTON_B:"East / B",JOY_BUTTON_X:"West / X",JOY_BUTTON_Y:"North / Y",JOY_BUTTON_LEFT_SHOULDER:"LB",JOY_BUTTON_RIGHT_SHOULDER:"RB",JOY_BUTTON_BACK:"Back",JOY_BUTTON_START:"Start",JOY_BUTTON_LEFT_STICK:"Left stick press",JOY_BUTTON_RIGHT_STICK:"Right stick press",JOY_BUTTON_DPAD_UP:"D-pad up",JOY_BUTTON_DPAD_DOWN:"D-pad down",JOY_BUTTON_DPAD_LEFT:"D-pad left",JOY_BUTTON_DPAD_RIGHT:"D-pad right"}.get(event.button_index,"Pad button %d" % event.button_index))
		else: labels.append(event.as_text())
	return "  ·  ".join(labels) if not labels.is_empty() else "Unbound"

func _option_toggle(parent: Node, title: String, property: String) -> CheckButton:
	var check := CheckButton.new()
	check.text = title
	check.custom_minimum_size.y = 40
	check.button_pressed = bool(settings[property])
	parent.add_child(check)
	check.toggled.connect(func(value: bool) -> void: settings[property]=value; apply_settings(); save_settings())
	return check

func _option_slider(parent: Node, title: String, property: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",24)
	row.custom_minimum_size.y = 42
	parent.add_child(row)
	var caption: Label = _menu_label(row,title,16,WHITE)
	caption.custom_minimum_size.x = 230
	var slider := HSlider.new()
	slider.name = property
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = float(settings[property])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label: Label = _menu_label(row,"%d%%" % roundi(slider.value*100),14,MUTED)
	value_label.custom_minimum_size.x = 65
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(value: float) -> void:
		settings[property]=value
		value_label.text="%d%%" % roundi(value*100)
		apply_settings()
		save_settings())

func _capture_binding(action: String) -> void:
	rebind_action = action
	_toast("BIND " + str(InputBindings.ACTIONS[action]).to_upper() + " · Press a key or controller input. ESC cancels.")
	toast_remaining = 60.0
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus()

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

## Frictionless death (spec §7.4/§24). No confirmation, no menu, no loading
## screen: the next life is built HERE, immediately, so `_reboot` (fired by
## the timer, a fresh press, or a test/fixture calling it directly) does no
## work of its own beyond swapping to data that already exists.
func _on_death() -> void:
	sound.play("death")
	var kills: int = combat.run_kills if is_instance_valid(combat) else 0
	var life_elapsed: float = combat.elapsed if is_instance_valid(combat) else 0.0
	var life_ring: int = campaign.ring_reached
	campaign.on_death() # spec §7.5: fresh seed the instant the player dies
	_death_stats = {"ring_reached":life_ring,"best_ring":int(campaign.best_ring.get(campaign.level,0)),"kills":kills,"time":life_elapsed}
	_death_next_sector = campaign.sector_at(Vector2i.ZERO,0.0)
	pending_offers.clear()
	_death_elapsed = 0.0
	_open_overlay("death")
	label(overlay,"SIGNAL LOST",Vector2(250,193),Vector2(780,78),56,WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label(overlay,"RING REACHED %d · BEST %d" % [int(_death_stats.ring_reached),int(_death_stats.best_ring)],Vector2(250,290),Vector2(780,42),28,GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label(overlay,"KILLS %d · TIME %s" % [int(_death_stats.kills),_format_run_time(float(_death_stats.time))],Vector2(250,340),Vector2(780,32),18,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not testing:
		SaveService.save_snapshot(campaign.to_dict(),{"seen_lines":seen_lines,"previous_offers":previous_offers,"offer_serial":offer_serial},slot)

func _format_run_time(seconds: float) -> String:
	var total: int = maxi(0,roundi(seconds))
	return "%d:%02d" % [total/60,total%60]

func _reboot() -> void:
	_close_overlay()
	combat.setup_player("neutral",1,40,[],GameTuning.ARENA_CENTER)
	campaign.on_enter(Vector2i.ZERO)
	combat.player_position = GameTuning.ARENA_CENTER
	combat.start_sector(_death_next_sector if not _death_next_sector.is_empty() else campaign.sector_at(Vector2i.ZERO,0.0))
	dialogue.visible = false
	dialogue_remaining = 0.0
	_input_swallow_frames = 1 # spec §7.4: swallow the dismissing press for one tick
	_queue_line("companion","You persisted","Your discoveries, defeated cores and unlocks remain. Rebuild your lightship, then push outward again.","reboot_v2_"+str(campaign.deaths))
	_refresh_hud()
	_save_game()
func _dismiss_death_card() -> void: _reboot()

func _show_ending(is_demo: bool) -> void:
	_open_overlay("ending")
	label(overlay,"A SMALL LIGHT, AN OPEN WORLD" if is_demo else "YOU ARE MORE THAN YOUR ORIGIN",Vector2(100,220),Vector2(1080,70),35,WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var text: String = "Lightning and Fire have both yielded.\nThe demo ends here. Keep exploring, try another form,\nor carry this progress into the full campaign." if is_demo else "Five level bosses have yielded. Their signals are yours.\nYou did not become a single perfect machine.\nYou became the sum of what you chose to absorb."
	label(overlay,text,Vector2(150,340),Vector2(980,125),22,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button(overlay,"KEEP EXPLORING",Rect2(440,545,400,55),_close_overlay).grab_focus()
	button(overlay,"SAVE & MAIN MENU",Rect2(440,619,400,48),func() -> void: _save_game(); _show_menu())

## Instrumented (plan P6 item 6): `save_timings_ms` is a rolling window a bot
## run / test can read p95/max off of. Saving itself only happens at calm
## moments now - warp commit (`_on_warp_committed`), node clear
## (`_on_sector_clear`), level complete/boss defeat (`_on_boss_defeated`),
## and pause/menu/quit - never on the old per-node-entry hot path.
const SAVE_TIMING_WINDOW: int = 500
var save_timings_ms: Array[float] = []
func _save_game() -> void:
	if mode != "play" or campaign == null or not is_instance_valid(combat) or benchmark_mode or testing: return
	var began: int = Time.get_ticks_usec()
	var run: Dictionary = {"combat":combat.snapshot(),"pending_offers":pending_offers,"previous_offers":previous_offers,"offer_serial":offer_serial,"seen_lines":seen_lines,"line_queue":line_queue}
	if combat.light_total <= 0.0: run = {"seen_lines":seen_lines,"previous_offers":previous_offers,"offer_serial":offer_serial}
	var error: Error = SaveService.save_snapshot(campaign.to_dict(),run,slot)
	save_timings_ms.append(float(Time.get_ticks_usec()-began)/1000.0)
	if save_timings_ms.size() > SAVE_TIMING_WINDOW: save_timings_ms.remove_at(0)
	if error != OK: _toast("Save failed: "+error_string(error))
	elif platform.online and cloud_sync_ready and mode_config.cloud_enabled():
		platform.save_cloud(SaveService.encode_snapshot({"profile":campaign.to_dict(),"run":run}),slot)

## p95/max over the rolling timing window (plan P6 item 6's own reporting
## requirement) - a bot run or test calls this after driving many warps.
func save_timing_stats() -> Dictionary:
	if save_timings_ms.is_empty(): return {"count":0,"p95":0.0,"max":0.0}
	var sorted: Array[float] = save_timings_ms.duplicate()
	sorted.sort()
	var p95_index: int = clampi(ceili(0.95*sorted.size())-1,0,sorted.size()-1)
	return {"count":sorted.size(),"p95":sorted[p95_index],"max":sorted[sorted.size()-1]}

func _show_cloud_review() -> void:
	_open_overlay("cloud")
	label(overlay,"CHOOSE YOUR INSTANCE",Vector2(180,165),Vector2(920,65),34,WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label(overlay,"This device and Steam have different saves. Neither will be replaced until you choose.",Vector2(200,250),Vector2(880,70),18,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label(overlay,"ON THIS DEVICE\n"+str(cloud_review.get("local_summary","No local save")),Vector2(215,350),Vector2(385,160),16,WHITE)
	label(overlay,"IN STEAM CLOUD\n"+str(cloud_review.get("remote_summary","Cloud save available")),Vector2(675,350),Vector2(385,160),16,WHITE)
	button(overlay,"KEEP THIS DEVICE",Rect2(215,550,385,52),_resolve_cloud.bind("keep_local"))
	button(overlay,"USE STEAM CLOUD",Rect2(675,550,385,52),_resolve_cloud.bind("use_cloud"))
	button(overlay,"DECIDE LATER",Rect2(480,658,320,45),_close_overlay).grab_focus()

func _resolve_cloud(choice: String) -> void:
	var result: Error = platform.resolve_cloud(choice,"campaign",cloud_review.get("remote_bytes",PackedByteArray()))
	if result != OK:
		_toast("Cloud save could not be changed: " + error_string(result))
		return
	cloud_sync_ready = true
	_close_overlay()
	_show_menu()

func _import_demo() -> void:
	var snapshot: Dictionary = SaveService.load_snapshot("demo")
	if snapshot.is_empty(): return
	if not SaveService.load_snapshot("campaign").is_empty():
		_open_overlay("confirm")
		label(overlay,"REPLACE CAMPAIGN WITH DEMO PROGRESS?",Vector2(180,260),Vector2(920,60),29,WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label(overlay,"The current campaign will remain in a separate archive.",Vector2(200,360),Vector2(880,50),18,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button(overlay,"IMPORT DEMO",Rect2(340,475,280,50),_perform_import)
		button(overlay,"CANCEL",Rect2(660,475,280,50),_close_overlay).grab_focus()
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
	_open_overlay("confirm")
	label(overlay,"BEGIN A NEW DEMO?" if is_demo else "BEGIN A NEW CAMPAIGN?",Vector2(300,270),Vector2(680,60),34,WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label(overlay,"Your current progress is kept in a separate archive.",Vector2(260,370),Vector2(760,45),18,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button(overlay,"NEW DEMO" if is_demo else "NEW CAMPAIGN",Rect2(340,470,280,52),func() -> void: _replace_game(is_demo))
	button(overlay,"CANCEL",Rect2(660,470,280,52),_close_overlay).grab_focus()

## `immediate` is spec §25's one named exception (a level boss's own
## ENCOUNTER line): it goes to the front of DialogueDirector's queue and is
## allowed to leave it even while the node still has live enemies. Every
## other call site leaves it false and stays behind the between-fights gate.
func _queue_line(element: String, title: String, text: String, id: String, immediate: bool = false) -> void:
	if immediate: dialogue_director.queue_immediate(element,title,text,id)
	else: dialogue_director.queue(element,title,text,id)

func _update_dialogue(delta: float) -> void:
	if not overlay_kind.is_empty(): return
	if dialogue_remaining > 0.0:
		dialogue_remaining -= delta
		if dialogue_remaining <= 0.0: dialogue.visible = false
		return
	var combat_clear: bool = is_instance_valid(combat) and combat.remaining_enemies() == 0
	if not dialogue_director.can_show_next(combat_clear): return
	var line: Dictionary = dialogue_director.pop_next(combat_clear)
	clear(dialogue)
	dialogue.visible = true
	panel(dialogue,Rect2(105,549,1070,154),VisualStyle.PANEL,Color("39393f"))
	var portrait := AIPortrait.new()
	portrait.element = str(line.element)
	portrait.position = Vector2(125,568)
	portrait.size = Vector2(98,112)
	dialogue.add_child(portrait)
	label(dialogue,str(DialogueDirector.RIVAL_NAMES.get(line.element,"ECHO"))+"  /  "+str(line.title),Vector2(244,568),Vector2(840,25),13,GOLD)
	label(dialogue,str(line.text),Vector2(244,609),Vector2(840,70),17,WHITE).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button(dialogue,"×",Rect2(1118,561,40,30),func() -> void: dialogue_remaining=0; dialogue.visible=false)
	dialogue_remaining = 11.0

func _open_overlay(kind: String) -> void:
	clear(overlay)
	overlay_kind = kind
	overlay.visible = true
	var shade := ColorRect.new()
	shade.color = VisualStyle.BG
	shade.size = Vector2(1280,800)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(shade)
	var policy: Dictionary = SCREEN_POLICY.get(kind,DEFAULT_SCREEN_POLICY)
	get_tree().paused = mode == "play" and bool(policy.pauses)
	sound.set_context("pause" if mode == "play" else "menu")
	dialogue.visible = false

func _close_overlay() -> void:
	clear(overlay)
	overlay_kind = ""
	overlay.visible = false
	rebind_action = ""
	get_tree().paused = false
	if sound != null: sound.set_context("play" if mode == "play" else "menu")
	if is_instance_valid(combat): combat.set_command(ShipCommand.new())

func _toast(text: String) -> void:
	toast_label.text = text
	toast_remaining = 4.0

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

func _component_controls() -> String:
	var ship: ShipDefinition = combat.player.get("definition")
	if ship == null: return ""
	var labels := PackedStringArray()
	for index: int in range(ship.secondaries.size()):
		var id: String = ship.secondaries[index]
		var cooldowns: Dictionary = combat.player.get("cooldowns",{})
		var cooldown: float = float(cooldowns.get("secondary_%d" % index,0.0))
		labels.append("%s: %s%s" % [["Space/LB","Shift/RB","Q/X"][index],_ability_name(id)," %.1fs" % cooldown if cooldown>0 else ""])
	return " | ".join(labels) if not labels.is_empty() else "Secondary: None"

## The following are thin forwarders to UiKit; kept so the many existing
## call sites in this file (and any external caller) keep working unchanged.
static func group(parent: Node) -> Control:
	return UiKit.group(parent)

static func clear(parent: Node) -> void:
	UiKit.clear(parent)

static func box(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	return UiKit.box(fill,border,width)

static func panel(parent: Node, rect: Rect2, fill: Color, border: Color) -> Panel:
	return UiKit.panel(parent,rect,fill,border)

static func label(parent: Node, text: String, position: Vector2, size: Vector2, font_size: int = 16, color: Color = Color.WHITE) -> Label:
	return UiKit.label(parent,text,position,size,font_size,color)

func button(parent: Node, text: String, rect: Rect2, action: Callable) -> Button:
	return UiKit.button(parent,text,rect,action,sound.play.bind("click"))

static func progress(parent: Node, rect: Rect2, color: Color) -> ProgressBar:
	return UiKit.progress(parent,rect,color)
