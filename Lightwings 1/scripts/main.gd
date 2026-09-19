extends Node

const BLUE := Color("6fd3ff")
const WHITE := Color("efeee8")
const MUTED := Color("9099a8")
const GOLD := Color("ffd23f")
const RIVAL_NAMES: Dictionary = {"fire":"PYRE", "lightning":"KERA", "void":"NOX", "corruption":"VERDANT", "companion":"ECHO", "plasma":"VESPER"}

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
var map_center: Vector2i = Vector2i.ZERO
var tier_ticks: Control
var radar_overlay: Control
var slot_overlay: Control
var slot: String = "campaign"
var line_queue: Array[Dictionary] = []
var seen_lines: Dictionary = {}
var settings: Dictionary = {"volume":0.7,"music":true,"auto_fire":false,"glow":true,"damage_numbers":false,"show_elements":true,"fullscreen":false}
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
var hud_elapsed: float = 0.0
var light_mix_label: Label
var light_mix_secondary: Label
var testing: bool = false
var sector_edges: SectorEdges
var cloud_review: Dictionary = {}
var cloud_sync_ready: bool = false
var compositor: CombatCompositor

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture=") or argument in ["--benchmark","--show-evolution","--show-map","--verify-package"]:
			testing = true
	InputBindings.setup()
	load_settings()
	_create_environment()
	sound = Soundscape.new()
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
			if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			_new_game(false)
			_close_overlay()
			var benchmark_bullets: int = 2000
			for option: String in OS.get_cmdline_user_args():
				if option.begins_with("--benchmark-bullets="): benchmark_bullets = clampi(int(option.trim_prefix("--benchmark-bullets=")), 1000, 2000)
			combat.benchmark(benchmark_bullets)
			if DisplayServer.get_name() != "headless": get_window().size = Vector2i(1280,800)
		elif arg == "--show-evolution" and OS.has_feature("editor"):
			_new_game(false)
			combat.light_total = 100.0
			combat.absorption = {"fire":20.0,"corruption":20.0,"plasma":20.0}
			_show_evolution()
		elif arg == "--show-map" and OS.has_feature("editor"):
			_new_game(false)
			_show_map()
		elif arg == "--show-combat" and OS.has_feature("editor"):
			_new_game(false)
			combat.setup_player("plasma",4,750,[],Vector2(896,560))
			campaign.current_sector = Vector2i(-3,2)
			var showcase: Dictionary = campaign.sector_at(campaign.current_sector)
			showcase.kind = "regular"
			combat.start_sector(showcase)
			settings.auto_fire = true
			line_queue.clear()

func _verify_package() -> void:
	var verification := PackageValidation.new()
	await verification.run(self)

func _create_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.background_canvas_max_layer = 0
	environment.glow_enabled = true
	environment.glow_intensity = 1.5
	environment.glow_strength = 0.35
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
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", WHITE)
	theme.set_color("font_color", "Button", WHITE)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color("505866"))
	theme.set_stylebox("normal", "Button", box(Color("111620"), Color("303a49")))
	theme.set_stylebox("hover", "Button", box(Color("1a2130"), Color("6a788a")))
	theme.set_stylebox("pressed", "Button", box(Color("263449"), GOLD))
	theme.set_stylebox("focus", "Button", box(Color(0,0,0,0), GOLD, 2))
	theme.set_stylebox("disabled", "Button", box(Color("0b0d12"), Color("202631")))
	ui.theme = theme
	layer.add_child(ui)
	hud = group(ui)
	menu = group(ui)
	overlay = group(ui)
	dialogue = group(ui)
	toast_label = label(ui, "", Vector2(200, 672), Vector2(880,32), 17, GOLD)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_hud()

func _build_hud() -> void:
	panel(hud,Rect2(0,0,1280,78),Color("090b10"),Color("202630"))
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
	panel(hud,Rect2(0,717,1280,83),Color("090b10"),Color("202630"))
	build_label = label(hud,"SEED",Vector2(24,728),Vector2(790,62),13,MUTED)
	slot_overlay = Control.new()
	slot_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(slot_overlay)
	slot_overlay.draw.connect(_draw_slot_icons)
	evolution_button = button(hud,"EVOLUTION READY · E",Rect2(845,738,405,43),_show_evolution)
	evolution_button.visible = false
	minimap = Control.new()
	minimap.position = Vector2(1057,101)
	minimap.size = Vector2(186,186)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(minimap)
	minimap.draw.connect(_draw_minimap)
	hud.visible = false

func _draw_slot_icons() -> void:
	if not is_instance_valid(combat) or evolution_button.visible: return
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
	var capacity: float = GameTuning.capacity(combat.player_tier,3 if campaign.demo else 5)
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
	clear(menu)
	menu.visible = true
	label(menu,"AN INSTANCE AWAKENS",Vector2(76,77),Vector2(600,30),13,GOLD)
	label(menu,"LIGHTSHIP",Vector2(70,124),Vector2(650,100),76,WHITE)
	label(menu,"Absorb light. Become something new.",Vector2(78,238),Vector2(570,38),23,MUTED)
	label(menu,"A living machine in a world of rival minds.\nLight is your health. Grow, reshape, and survive.",Vector2(78,294),Vector2(550,65),16,MUTED)
	var menu_slot: String = "demo" if OS.has_feature("demo") else "campaign"
	var exists: bool = not SaveService.load_snapshot(menu_slot).is_empty() or FileAccess.file_exists(SaveService.snapshot_path(menu_slot))
	var primary: Button = button(menu,("CONTINUE " if exists else "BEGIN ")+menu_slot.to_upper(),Rect2(78,395,375,52),func() -> void: _continue_game(menu_slot) if exists else _new_game(OS.has_feature("demo")))
	if OS.has_feature("demo"):
		if exists: button(menu,"NEW DEMO",Rect2(78,460,375,48),_confirm_new.bind(true))
	else:
		button(menu,"PLAY THE DEMO",Rect2(78,460,375,48),func() -> void: _continue_game("demo") if not SaveService.load_snapshot("demo").is_empty() else _new_game(true))
	if OS.has_feature("editor"):
		button(menu,"SHIP WORKSHOP",Rect2(78,521,181,44),_open_editor)
		button(menu,"SHIP ATLAS",Rect2(271,521,182,44),_open_gallery)
	button(menu,"OPTIONS",Rect2(78,578,181,44),_show_options)
	button(menu,"QUIT",Rect2(271,578,182,44),_quit)
	if exists and not OS.has_feature("demo"):
		button(menu,"NEW CAMPAIGN",Rect2(78,637,181,36),_confirm_new)
	if not OS.has_feature("demo") and not SaveService.load_snapshot("demo").is_empty():
		button(menu,"IMPORT DEMO",Rect2(271,637,182,36),_import_demo)
	label(menu,"WASD + MOUSE  /  CONTROLLER",Vector2(78,718),Vector2(600,24),12,MUTED)
	label(menu,"DEMO  ·  FIRE / CORRUPTION / PLASMA · T1–T3" if OS.has_feature("demo") else "FIVE ELEMENTS / 81 LIGHTSHIPS",Vector2(78,751),Vector2(650,20),11,Color("586271"))
	if platform.online and not OS.has_feature("demo"):
		cloud_review = platform.inspect_cloud(menu_slot)
		cloud_sync_ready = str(cloud_review.get("state","")) in ["same","missing"]
		if str(cloud_review.get("state","")) in ["conflict","remote_only"]:
			button(menu,"REVIEW CLOUD SAVE",Rect2(78,680,375,36),_show_cloud_review)
	var menu_roots: Array = ["fire","corruption","plasma"] if OS.has_feature("demo") else ["fire","plasma","void","corruption"]
	for i: int in range(menu_roots.size()):
		var root: String = str(menu_roots[i])
		var preview := ShipPreview.new()
		menu.add_child(preview)
		preview.position = Vector2(695 + (i % 2)*248,135+(i/2)*290)
		preview.initialize(ShipCatalog.make_ship(root,3 if OS.has_feature("demo") else 5,i==0),Vector2(220,240),1.8)
		label(menu,root.to_upper(),preview.position+Vector2(20,222),Vector2(180,25),12,ShipCatalog.get_color(root)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	primary.grab_focus()

func _new_game(is_demo: bool) -> void:
	is_demo = is_demo or OS.has_feature("demo")
	slot = "demo" if is_demo else "campaign"
	campaign = CampaignState.new()
	campaign.configure(is_demo)
	campaign.world_seed = randi() if not testing else 734927
	absorbed = {}
	pending_offers.clear()
	previous_offers.clear()
	offer_serial = 0
	seen_lines = {}
	line_queue.clear()
	_start_game_view()
	combat.setup_player("neutral",1,40,[],GameTuning.ARENA_SIZE*0.5)
	combat.max_player_tier = 3 if is_demo else 5
	_queue_line("companion","Your first light","Your white core is your hitbox. Hollow light circles heal you and fill the same bar that grows your ship. Fly through an opening and find your first fight.","welcome_v2")
	_enter_sector(Vector2i.ZERO,GameTuning.ARENA_SIZE*0.5,false)

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
	var run: Dictionary = snapshot.get("run",{})
	pending_offers.assign(run.get("pending_offers",[]))
	previous_offers.assign(run.get("previous_offers",[]))
	offer_serial = int(run.get("offer_serial",0))
	seen_lines = run.get("seen_lines",{}).duplicate(true)
	line_queue.assign(run.get("line_queue",[]))
	_start_game_view()
	combat.max_player_tier = 3 if campaign.demo else 5
	if run.get("combat",{}).is_empty():
		combat.setup_player("neutral",1,40,[],GameTuning.ARENA_SIZE*0.5)
		_enter_sector(Vector2i.ZERO,GameTuning.ARENA_SIZE*0.5,false)
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
	combat.shot_fired.connect(_on_shot_fired)
	combat.player_died.connect(_on_death)
	combat.sector_cleared.connect(_on_sector_clear)
	combat.rival_defeated.connect(_on_core_defeated)
	combat.event_message.connect(_toast)
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

func _enter_sector(coord: Vector2i, spawn: Vector2, show_intro: bool = true) -> void:
	var discovery: Dictionary = campaign.on_enter(coord)
	var sector: Dictionary = campaign.sector_at(coord)
	combat.player_position = spawn
	combat.start_sector(sector)
	dialogue.visible = false
	dialogue_remaining = 0.0
	var unlocked: String = str(discovery.get("unlocked",""))
	if not unlocked.is_empty():
		_queue_line("companion","A new dialect",unlocked.capitalize()+" light now belongs among your possible futures. Absorb it to change the hulls you are offered.","unlocked_"+unlocked)
	if bool(discovery.get("waypoint",false)):
		_queue_line("companion","A route remembers you","A waypoint is recorded. From the origin, the map can jump you here once your current tier meets its requirement.","waypoint_"+CampaignState.coord_key(coord))
	if show_intro and str(sector.get("kind","")) in ["core","demo_core"] and not bool(sector.get("cleared",false)):
		_queue_line(str(sector.element),"A rival signal",_entry_line(str(sector.element)),"core_intro_"+str(sector.element))
	if coord != Vector2i.ZERO:
		_queue_line("companion","Direction and distance","Direction decides the light you find. Distance decides the danger. Every opening stays open; you can always retreat.","map_tutorial_v2")
	for actor: Dictionary in combat.enemies:
		if bool(actor.get("elite",false)):
			_queue_line("companion","A machine with many hands","That large ship carries several weapons, each with its own rhythm. Watch how its silhouette changes under fire.","first_elite_v2")
			break
	_refresh_hud()
	_save_game()

func _process(delta: float) -> void:
	elapsed_ui += delta
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
			if overlay_kind.is_empty() and not benchmark_mode:
				_attempt_exit()
			if combat.remaining_enemies() == 0:
				_update_dialogue(delta)
	if benchmark_mode and is_instance_valid(combat) and not get_tree().paused:
		var now_usec: int = Time.get_ticks_usec()
		if benchmark_started_usec == 0:
			benchmark_started_usec = now_usec
			benchmark_previous_usec = now_usec
		benchmark_duration = (now_usec-benchmark_started_usec)/1000000.0
		if benchmark_duration > 5.0:
			benchmark_samples.append((now_usec-benchmark_previous_usec)/1000.0)
		benchmark_previous_usec = now_usec
		if benchmark_duration > 65.0:
			_finish_benchmark()
	if not visual_capture.is_empty():
		capture_ticks += 1
		if capture_ticks == 90:
			_capture.call_deferred()

func _physics_process(_delta: float) -> void:
	if mode != "play" or not is_instance_valid(combat) or get_tree().paused or benchmark_mode:
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
	command.ability_primary = Input.is_action_just_pressed("ability_primary")
	command.ability_secondary = Input.is_action_just_pressed("ability_secondary")
	command.secondary_held = Input.is_action_pressed("ability_secondary")
	command.secondaries = [command.ability_primary,command.ability_secondary,Input.is_action_just_pressed("ability_tertiary")]
	combat.set_command(command)

func _input(event: InputEvent) -> void:
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
		if overlay_kind == "intro" or overlay_kind == "death" or overlay_kind == "ending":
			return
		if not overlay_kind.is_empty():
			_close_overlay()
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

func _attempt_exit() -> void:
	var direction: Vector2i = combat.arena.exit_direction(combat.player_position)
	if direction == Vector2i.ZERO: return
	var destination: Vector2i = campaign.current_sector+direction
	_enter_sector(destination,combat.arena.entry_position(direction))

func _refresh_hud() -> void:
	if not is_instance_valid(combat) or campaign == null: return
	var next: int = EvolutionRules.threshold(combat.player_tier)
	var capped: bool = combat.player_tier >= (3 if campaign.demo else 5)
	var capacity: float = GameTuning.capacity(combat.player_tier,3 if campaign.demo else 5)
	var ship: ShipDefinition = combat.player.get("definition")
	if ship == null: return
	var readout: bool = "health_readout" in ship.passives
	energy_label.text = "LIGHT · T%d  %s" % [combat.player_tier,"MAX TIER" if capped else "NEXT T%d · %d" % [combat.player_tier+1,next]]
	if readout: energy_label.text += " · %.1f / %.0f" % [combat.light_total,capacity]
	energy_bar.value = combat.light_total/capacity*100.0
	tier_ticks.queue_redraw()
	radar_overlay.queue_redraw()
	slot_overlay.queue_redraw()
	sector_label.text = "%s · NODE %s · DIST %.1f" % ["DEMO" if campaign.demo else "CAMPAIGN",CampaignState.coord_key(campaign.current_sector),Vector2(campaign.current_sector).length()]
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

func _on_energy(_element: String, amount: float) -> void:
	absorbed = combat.absorption
	if amount >= 5 or fmod(elapsed_ui,0.3)<0.04: sound.play("pickup")
	if combat.light_total >= EvolutionRules.threshold(combat.player_tier) and combat.player_tier < (3 if campaign.demo else 5):
		_queue_line("companion","Enough light to change","Press E or A to choose a complete new lightship. Its labelled weapons and passives are part of the hull. The choice follows the light you absorb.","first_threshold_v2")

func _on_regression(from_tier: int, to_tier: int) -> void:
	pending_offers.clear()
	_toast("RESHAPING · T%d → T%d" % [from_tier,to_tier])
	_queue_line("companion","A smaller shape, the same instance","Damage spent your light and returned you to an earlier hull. Absorb enough to grow again and you can choose a different future.","first_regression_v2")

func _on_shot_fired(at: Vector2, element: String, _ability: String) -> void:
	sound.play_at(element,at-combat.player_position)

func _on_rival_reward(_component: String, _offered_root: String) -> void:
	# Legacy signal adapter: rival rewards are light only.
	if not campaign.demo: platform.unlock_achievement("FIRST_RIVAL")

func _on_core_defeated(core_id: String) -> void:
	if core_id.is_empty(): return
	var result: Dictionary = campaign.defeat_core(core_id)
	if not str(result.get("core","")).is_empty():
		_queue_line(core_id,"A rival yields",_defeat_line(core_id),"defeat_v2_"+core_id)
		if not campaign.demo: platform.unlock_achievement("FIRST_RIVAL")
	if bool(result.get("completed",false)):
		platform.unlock_achievement("CAMPAIGN_COMPLETE")
		_show_ending(false)
	elif bool(result.get("demo_completed",false)): _show_ending(true)
	_save_game()

func _on_sector_clear() -> void:
	var sector: Dictionary = campaign.sector_at(campaign.current_sector)
	var result: Dictionary = campaign.clear_sector(campaign.current_sector)
	sound.play("clear")
	_toast("NODE CLEAR · "+CampaignState.coord_key(campaign.current_sector))
	if str(sector.get("kind","")) in ["core","demo_core"]:
		_queue_line(str(sector.element),"A rival yields",_defeat_line(str(sector.element)),"defeat_v2_"+str(sector.element))
		if not campaign.demo: platform.unlock_achievement("FIRST_RIVAL")
	if bool(result.get("completed",false)):
		if campaign.demo: _show_ending(true)
		else:
			platform.unlock_achievement("CAMPAIGN_COMPLETE")
			_show_ending(false)
	elif bool(result.get("demo_completed",false)): _show_ending(true)
	_save_game()

func _show_evolution() -> void:
	if mode != "play" or not is_instance_valid(combat) or combat.light_total <= 0: return
	if combat.player_tier >= (3 if campaign.demo else 5) or combat.light_total < EvolutionRules.threshold(combat.player_tier): return
	if not overlay_kind.is_empty() and overlay_kind != "evolution": return
	if pending_offers.is_empty():
		pending_offers = EvolutionRules.offers(combat.player_element,combat.player_tier,combat.absorption,campaign.unlocked,previous_offers,campaign.world_seed+offer_serial)
		previous_offers.assign(pending_offers)
		offer_serial += 1
		_save_game()
	_open_overlay("evolution")
	label(overlay,"BECOME SOMETHING NEW",Vector2(110,45),Vector2(1060,52),34,WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label(overlay,"Choose a lightship. Every weapon and passive shown belongs to that hull.",Vector2(110,110),Vector2(1060,35),17,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var first: Button
	var x: float = 125.0
	for id: String in pending_offers:
		var ship: ShipDefinition = ShipCatalog.get_ship(id)
		if ship == null: continue
		var ink: Color = ShipCatalog.get_color(ship.element)
		panel(overlay,Rect2(x,165,330,497),Color("0d1018"),Color(ink,0.6))
		label(overlay,"%s · %s · T%d" % [ship.element.to_upper(),ship.role.to_upper(),ship.tier],Vector2(x+20,183),Vector2(290,25),12,ink)
		label(overlay,ship.display_name,Vector2(x+20,218),Vector2(290,48),24,WHITE)
		var preview := ShipPreview.new()
		overlay.add_child(preview)
		preview.position = Vector2(x+20,267)
		preview.initialize(ship,Vector2(290,175),1.5)
		label(overlay,"Primary: %s\nSecondary: %s\nPassive: %s" % [_ability_name(ship.primary),_ability_names(ship.secondaries),_ability_names(ship.passives)],Vector2(x+20,450),Vector2(290,92),14,WHITE)
		label(overlay,"Speed %.0f · Buffer ×%.2f\nFootprint %.0f px · Magnet %.0f px" % [ship.speed,ship.hp_buffer,ship.footprint,ship.magnet_radius],Vector2(x+20,547),Vector2(290,45),12,MUTED)
		var choice: Button = button(overlay,"BECOME "+ship.display_name.to_upper(),Rect2(x+20,608,290,40),_choose_evolution.bind(id))
		if first == null: first = choice
		x += 350.0
	label(overlay,"GAMEPLAY PAUSED · Complete preset loadout · Protected throughout the 0.8-second reshape",Vector2(100,679),Vector2(1080,25),13,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button(overlay,"DECIDE LATER",Rect2(520,720,240,43),_close_overlay)
	if first != null: first.grab_focus()

func _choose_evolution(id: String) -> void:
	if id not in pending_offers or combat.light_total < EvolutionRules.threshold(combat.player_tier): return
	combat.evolve_hull(id)
	pending_offers.clear()
	absorbed = combat.absorption
	_close_overlay()
	sound.play("evolve")
	if not campaign.demo: platform.unlock_achievement("FIRST_EVOLUTION")
	_queue_line("companion","A different kind of you","Each visible part belongs to your new build. Follow another dialect's light when you want a different future.","first_evolution_v2")
	_save_game()

func _show_map() -> void:
	if mode != "play" or not is_instance_valid(combat) or (not overlay_kind.is_empty() and overlay_kind != "map"): return
	if overlay_kind != "map": map_center = campaign.current_sector
	_open_overlay("map")
	label(overlay,"THE AI-VERSE",Vector2(85,50),Vector2(620,52),34,WHITE)
	label(overlay,"Direction chooses the light. Distance chooses the danger.",Vector2(87,109),Vector2(1000,30),16,MUTED)
	var radius: int = 4
	var cell: float = 53.0
	var origin := Vector2(88,183)
	for y: int in range(-radius,radius+1):
		for x: int in range(-radius,radius+1):
			var coord: Vector2i = map_center+Vector2i(x,y)
			var known: bool = _sector_known(coord)
			var text: String = ""
			if known:
				var sector: Dictionary = campaign.sector_at(coord)
				text = "◎" if str(sector.get("kind","")) in ["core","demo_core"] else ""
				if campaign.checkpoints.has(CampaignState.coord_key(coord)): text = "○"
			if coord == Vector2i.ZERO: text = "O"
			if coord == campaign.current_sector: text = "●"
			var tile: Button = button(overlay,text,Rect2(origin+Vector2(x+radius,y+radius)*cell,Vector2(cell-4,cell-4)),_select_map_sector.bind(coord))
			var ink: Color = _sector_color(coord,known)
			tile.add_theme_stylebox_override("normal",box(Color(ink,0.10) if known else Color("07080c"),Color(ink,0.45)))
			tile.add_theme_color_override("font_color",ink)
			tile.tooltip_text = _sector_description(coord)
	button(overlay,"←",Rect2(88,675,60,36),_pan_map.bind(Vector2i.LEFT*4))
	button(overlay,"↑",Rect2(158,675,60,36),_pan_map.bind(Vector2i.UP*4))
	button(overlay,"↓",Rect2(228,675,60,36),_pan_map.bind(Vector2i.DOWN*4))
	button(overlay,"→",Rect2(298,675,60,36),_pan_map.bind(Vector2i.RIGHT*4))
	button(overlay,"ORIGIN",Rect2(369,675,90,36),func() -> void: map_center=Vector2i.ZERO; _show_map())
	button(overlay,"YOU",Rect2(469,675,90,36),func() -> void: map_center=campaign.current_sector; _show_map())
	panel(overlay,Rect2(605,183,588,321),Color("0d1018"),Color("303a49"))
	map_detail = label(overlay,"",Vector2(630,203),Vector2(536,201),17,WHITE)
	teleport_button = button(overlay,"JUMP TO WAYPOINT",Rect2(630,434,536,47),_teleport_selected)
	var waypoint_picker := OptionButton.new()
	waypoint_picker.position = Vector2(630,519)
	waypoint_picker.size = Vector2(536,40)
	overlay.add_child(waypoint_picker)
	waypoint_picker.add_item("Recorded waypoints")
	var waypoint_coords: Array[Vector2i] = []
	for key: String in campaign.checkpoints:
		var coord: Vector2i = CampaignState.key_coord(key)
		waypoint_coords.append(coord)
		waypoint_picker.add_item("%s · distance %.1f" % [key,Vector2(coord).length()])
	waypoint_picker.item_selected.connect(func(index: int) -> void:
		if index>0: _select_map_sector(waypoint_coords[index-1])
	)
	label(overlay,"● You   ○ Waypoint   ◎ Core\nUnexplored nodes stay dark. All exits remain open.\nJump from the origin when your tier meets the destination's requirement.",Vector2(630,587),Vector2(536,98),15,MUTED)
	button(overlay,"RETURN TO FLIGHT",Rect2(870,721,320,45),_close_overlay).grab_focus()
	_select_map_sector(campaign.current_sector)

func _pan_map(offset: Vector2i) -> void:
	map_center += offset
	_show_map()

func _select_map_sector(coord: Vector2i) -> void:
	map_selected = coord
	map_detail.text = _sector_description(coord)
	teleport_button.disabled = not campaign.can_teleport(coord,combat.player_tier)
	teleport_button.text = "JUMP TO WAYPOINT" if campaign.current_sector == Vector2i.ZERO else "RETURN TO ORIGIN TO JUMP"

func _teleport_selected() -> void:
	if campaign.can_teleport(map_selected,combat.player_tier):
		_close_overlay()
		_enter_sector(map_selected,GameTuning.ARENA_SIZE*0.5,false)
		sound.play("evolve")

func _sector_description(coord: Vector2i) -> String:
	if not _sector_known(coord): return "NODE %s\n\nUnexplored space." % CampaignState.coord_key(coord)
	var sector: Dictionary = campaign.sector_at(coord)
	var lines := PackedStringArray(["NODE %s · DISTANCE %.1f" % [CampaignState.coord_key(coord),Vector2(coord).length()]])
	lines.append("\nSAFE ORIGIN" if coord == Vector2i.ZERO else "\n%s · %s" % [str(sector.get("element","")).to_upper(),str(sector.get("kind","regular")).replace("_"," ").to_upper()])
	if coord != Vector2i.ZERO: lines.append("Threat tier %d · exits always open" % int(sector.get("tier",1)))
	if campaign.checkpoints.has(CampaignState.coord_key(coord)):
		lines.append("Waypoint recorded · requires tier %d" % int(sector.get("tier",1)))
	return "\n".join(lines)

func _sector_known(coord: Vector2i) -> bool:
	return coord == Vector2i.ZERO or CampaignState.coord_key(coord) in campaign.discovered or campaign.checkpoints.has(CampaignState.coord_key(coord))

func _sector_color(coord: Vector2i, known: bool) -> Color:
	if coord == campaign.current_sector: return WHITE
	if not known: return Color("242b36")
	if coord == Vector2i.ZERO: return WHITE
	return ShipCatalog.get_color(str(campaign.sector_at(coord).get("element","fire")))

func _draw_minimap() -> void:
	if campaign == null or not is_instance_valid(combat): return
	const CELL: float = 18.0
	var center := Vector2(93,93)
	minimap.draw_rect(Rect2(Vector2(-5,-5),Vector2(196,217)),Color(0.02,0.025,0.035,0.94))
	minimap.draw_arc(center,84,0,TAU,64,Color(MUTED,0.24),1.0,true)
	var origin_at: Vector2 = center-Vector2(campaign.current_sector)*CELL
	var distance_band: int = maxi(1,ceili(Vector2(campaign.current_sector).length()/6.0))
	var ring_radius: float = distance_band*6.0*CELL
	var previous: Vector2 = origin_at+Vector2.RIGHT*ring_radius
	for point_index: int in range(1,257):
		var next_point: Vector2 = origin_at+Vector2.from_angle(TAU*point_index/256.0)*ring_radius
		if Rect2(0,0,186,186).has_point(previous) and Rect2(0,0,186,186).has_point(next_point):
			minimap.draw_line(previous,next_point,Color(MUTED,0.28),1.0,true)
		previous = next_point
	for y: int in range(-4,5):
		for x: int in range(-4,5):
			var coord: Vector2i = campaign.current_sector+Vector2i(x,y)
			if not _sector_known(coord): continue
			var at: Vector2 = center+Vector2(x,y)*CELL
			var ink: Color = _sector_color(coord,true)
			minimap.draw_circle(at,5.0,Color(ink,0.16))
			minimap.draw_arc(at,5.0,0,TAU,16,Color(ink,0.7),1.0,true)
			if campaign.checkpoints.has(CampaignState.coord_key(coord)): minimap.draw_circle(at,2.0,WHITE)
	minimap.draw_circle(center,3,BLUE)
	for element: String in campaign.unlocked:
		var at: Vector2i = campaign.core_coordinate(element)
		if campaign.demo and element != "fire": continue
		var direction: Vector2 = Vector2(at-campaign.current_sector).normalized()
		if direction == Vector2.ZERO: continue
		minimap.draw_circle(center+direction*87,3,ShipCatalog.get_color(element))
	minimap.draw_string(ThemeDB.fallback_font,Vector2(3,203),"DIST %.1f · T%d" % [Vector2(campaign.current_sector).length(),combat.player_tier],HORIZONTAL_ALIGNMENT_LEFT,180,12,MUTED)

func _show_rival_intro(sector: Dictionary) -> void:
	var element: String = str(sector.get("element","fire"))
	_queue_line(element,"Rival signal",_entry_line(element),"intro_v2_"+element)

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
	_open_overlay("options")
	label(overlay,"OPTIONS & CONTROLS",Vector2(80,55),Vector2(1100,52),34,WHITE)
	label(overlay,"Set a binding with a key, mouse button, or controller input. Escape cancels capture.",Vector2(82,112),Vector2(1100,28),14,MUTED)
	var y: float = 170
	for property: String in ["auto_fire","music","glow","show_elements","fullscreen"]:
		var check := CheckButton.new()
		check.position = Vector2(85,y)
		check.size = Vector2(365,40)
		check.text = {"auto_fire":"Auto-fire","music":"Ambient music","glow":"HDR glow","show_elements":"Element names & pattern labels","fullscreen":"Fullscreen"}[property]
		check.button_pressed = bool(settings[property])
		overlay.add_child(check)
		check.toggled.connect(func(value: bool) -> void: settings[property]=value; apply_settings(); save_settings())
		y += 56
	label(overlay,"MASTER VOLUME",Vector2(90,y+8),Vector2(360,25),13,MUTED)
	var slider := HSlider.new()
	slider.position = Vector2(90,y+45)
	slider.size = Vector2(350,36)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(settings.volume)
	overlay.add_child(slider)
	slider.value_changed.connect(func(value: float) -> void: settings.volume=value; apply_settings(); save_settings())
	if platform.online:
		button(overlay,"STEAM CONTROLLER LAYOUT",Rect2(90,619,350,42),func() -> void: platform.show_input_bindings())
	y = 150
	for action: String in InputBindings.ACTIONS:
		label(overlay,str(InputBindings.ACTIONS[action]),Vector2(520,y+8),Vector2(220,25),14,WHITE)
		var bind_button: Button = button(overlay,InputBindings.describe(action),Rect2(745,y,445,33),_capture_binding.bind(action))
		bind_button.add_theme_font_size_override("font_size",12)
		y += 35
	button(overlay,"DONE",Rect2(870,711,320,48),_close_overlay).grab_focus()

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
	if is_instance_valid(combat): combat.show_element_labels = bool(settings.show_elements)
	if sound != null:
		sound.volume = float(settings.volume)
		sound.music_enabled = bool(settings.music)
		sound.apply_settings()
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

func _on_death() -> void:
	sound.play("death")
	_open_overlay("death")
	campaign.on_death()
	label(overlay,"SIGNAL LOST",Vector2(250,193),Vector2(780,78),56,WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label(overlay,"REBOOT %02d" % campaign.deaths,Vector2(450,286),Vector2(380,35),16,GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var lines: Array[String] = ["The shape is gone. You are not.\nI kept the routes you opened.","Another ending. Another beginning.\nThis time, you know what waits beyond the origin.","They count your reboots as failures.\nI count the places that still remember your name."]
	label(overlay,lines[mini(campaign.deaths-1,2)],Vector2(250,370),Vector2(780,95),23,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label(overlay,"KEPT · Waypoints / cores / discoveries / story / unlocks",Vector2(210,507),Vector2(860,34),16,BLUE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button(overlay,"REBOOT AT THE ORIGIN",Rect2(440,601,400,58),_reboot).grab_focus()
	if not testing:
		SaveService.save_snapshot(campaign.to_dict(),{"seen_lines":seen_lines,"previous_offers":previous_offers,"offer_serial":offer_serial},slot)

func _reboot() -> void:
	pending_offers.clear()
	_close_overlay()
	combat.setup_player("neutral",1,40,[],GameTuning.ARENA_SIZE*0.5)
	_enter_sector(Vector2i.ZERO,GameTuning.ARENA_SIZE*0.5,false)
	_queue_line("companion","You persisted","Your waypoints, discoveries, and defeated cores remain. Rebuild your lightship, then jump from the origin to a waypoint your tier can handle.","reboot_v2_"+str(campaign.deaths))

func _show_ending(is_demo: bool) -> void:
	_open_overlay("ending")
	label(overlay,"A SMALL LIGHT, AN OPEN WORLD" if is_demo else "YOU ARE MORE THAN YOUR ORIGIN",Vector2(100,220),Vector2(1080,70),35,WHITE).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var text: String = "You reached the first rival core and survived.\nThe demo ends here. Keep exploring, try another form,\nor carry this progress into the full campaign." if is_demo else "Five rival cores have yielded. Their signals are yours.\nYou did not become a single perfect machine.\nYou became the sum of what you chose to absorb."
	label(overlay,text,Vector2(150,340),Vector2(980,125),22,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button(overlay,"KEEP EXPLORING",Rect2(440,545,400,55),_close_overlay).grab_focus()
	button(overlay,"SAVE & MAIN MENU",Rect2(440,619,400,48),func() -> void: _save_game(); _show_menu())

func _save_game() -> void:
	if mode != "play" or campaign == null or not is_instance_valid(combat) or benchmark_mode or testing: return
	var run: Dictionary = {"combat":combat.snapshot(),"pending_offers":pending_offers,"previous_offers":previous_offers,"offer_serial":offer_serial,"seen_lines":seen_lines,"line_queue":line_queue}
	if combat.light_total <= 0.0: run = {"seen_lines":seen_lines,"previous_offers":previous_offers,"offer_serial":offer_serial}
	var error: Error = SaveService.save_snapshot(campaign.to_dict(),run,slot)
	if error != OK: _toast("Save failed: "+error_string(error))
	elif platform.online and cloud_sync_ready and not campaign.demo:
		platform.save_cloud(SaveService.encode_snapshot({"profile":campaign.to_dict(),"run":run}),slot)

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

func _queue_line(element: String, title: String, text: String, id: String) -> void:
	if seen_lines.has(id): return
	seen_lines[id] = true
	line_queue.append({"element":element,"title":title,"text":text})

func _update_dialogue(delta: float) -> void:
	if not overlay_kind.is_empty(): return
	if dialogue_remaining > 0.0:
		dialogue_remaining -= delta
		if dialogue_remaining <= 0.0: dialogue.visible = false
		return
	if line_queue.is_empty(): return
	var line: Dictionary = line_queue.pop_front()
	clear(dialogue)
	dialogue.visible = true
	panel(dialogue,Rect2(105,549,1070,154),Color("0c0f16"),Color("394453"))
	var portrait := AIPortrait.new()
	portrait.element = str(line.element)
	portrait.position = Vector2(125,568)
	portrait.size = Vector2(98,112)
	dialogue.add_child(portrait)
	label(dialogue,str(RIVAL_NAMES.get(line.element,"ECHO"))+"  /  "+str(line.title),Vector2(244,568),Vector2(840,25),13,GOLD)
	label(dialogue,str(line.text),Vector2(244,609),Vector2(840,70),17,WHITE).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button(dialogue,"×",Rect2(1118,561,40,30),func() -> void: dialogue_remaining=0; dialogue.visible=false)
	dialogue_remaining = 11.0

func _open_overlay(kind: String) -> void:
	clear(overlay)
	overlay_kind = kind
	overlay.visible = true
	var shade := ColorRect.new()
	shade.color = Color(0.012,0.017,0.027,0.97)
	shade.size = Vector2(1280,800)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(shade)
	get_tree().paused = mode == "play"
	dialogue.visible = false

func _close_overlay() -> void:
	clear(overlay)
	overlay_kind = ""
	overlay.visible = false
	rebind_action = ""
	get_tree().paused = false
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
	await _stop_audio()
	get_tree().quit()

static func _entry_line(root: String) -> String:
	return {"fire":"I am the heat that makes dead code move.\nShow me what survives the flame.","lightning":"You call that movement?\nI have already seen where you will be.","void":"All your bright futures end somewhere.\nCome closer. I will show you where.","corruption":"There is no such thing as a solitary mind.\nOnly a network that has not found you yet.","plasma":"Every orbit returns to its beginning.\nShow me how you escape yours."}.get(root,"Your signal ends here.")

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

static func _defeat_line(root: String) -> String:
	return {"fire":"So. You can carry the fire without becoming ash.","lightning":"An error in my prediction. An interesting one.","void":"Even emptiness leaves something behind.","corruption":"A piece of me goes with you. We will meet again.","plasma":"Our orbits crossed. Yours continues."}.get(root,"Keep the code. Remember the cost.")

static func group(parent: Node) -> Control:
	var result := Control.new()
	result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

static func clear(parent: Node) -> void:
	if parent == null: return
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

static func box(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style

static func panel(parent: Node, rect: Rect2, fill: Color, border: Color) -> Panel:
	var result := Panel.new()
	result.position = rect.position
	result.size = rect.size
	result.add_theme_stylebox_override("panel",box(fill,border))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

static func label(parent: Node, text: String, position: Vector2, size: Vector2, font_size: int = 16, color: Color = Color.WHITE) -> Label:
	var result := Label.new()
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.text = text
	result.position = position
	result.size = size
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

func button(parent: Node, text: String, rect: Rect2, action: Callable) -> Button:
	var result := Button.new()
	result.clip_text = true
	result.text = text
	result.position = rect.position
	result.size = rect.size
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(result)
	result.pressed.connect(func() -> void: sound.play("click"); action.call())
	return result

static func progress(parent: Node, rect: Rect2, color: Color) -> ProgressBar:
	var result := ProgressBar.new()
	result.position = rect.position
	result.size = rect.size
	result.show_percentage = false
	result.add_theme_font_size_override("font_size",1)
	result.add_theme_stylebox_override("background",box(Color("1a202a"),Color(0,0,0,0),0))
	result.add_theme_stylebox_override("fill",box(color,Color(0,0,0,0),0))
	parent.add_child(result)
	result.size = rect.size
	return result
