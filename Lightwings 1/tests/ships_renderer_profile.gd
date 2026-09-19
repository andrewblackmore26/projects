extends SceneTree
## Run one GPU benchmark at a time. --compositor profiles the actual two-stage
## arena renderer with paused simulation; default profiles twenty T5 ships.

var tick: int = 0
var samples: int = 0
var frame_ms: float = 0.0
var ship_draw_ms: float = 0.0
var process_ms: float = 0.0
var physics_ms: float = 0.0
var draw_calls: float = 0.0
var compositor_mode: bool = false
var wall_started: int = 0
var first_sample_frame: int = 0

func _initialize() -> void:
	compositor_mode = "--compositor" in OS.get_cmdline_user_args()
	root.size = Vector2i(1280, 800)
	root.use_hdr_2d = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_build.call_deferred()

func _build() -> void:
	var scene: Node2D = Node2D.new()
	root.add_child(scene)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.glow_enabled = true
	environment.glow_hdr_threshold = 1.0
	environment.glow_intensity = 1.5
	environment.glow_strength = 0.35
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for level: int in range(7): environment.set_glow_level(level, 0.6 if level == 0 else 0.0)
	environment_node.environment = environment
	scene.add_child(environment_node)
	var world: CombatWorld
	if compositor_mode:
		world = CombatWorld.new()
		scene.add_child(world)
		world.setup_player("corruption", 5, 1500, [], Vector2(640, 680))
	for row: int in range(4):
		for column: int in range(5):
			var element: String = ShipCatalog.ELEMENTS[row]
			var at: Vector2 = Vector2(135 + column * 240, 120 + row * 170)
			if compositor_mode:
				world._spawn_enemy(element, 5, at, false)
			else:
				var renderer: ShipRenderer = ShipRenderer.new()
				scene.add_child(renderer)
				renderer.position = at
				renderer.set_ship(ShipCatalog.make_ship(element, 5))
	if compositor_mode:
		var compositor: CombatCompositor = CombatCompositor.new()
		scene.add_child(compositor)
		compositor.attach(world)
	paused = true
	wall_started = Time.get_ticks_msec()

func _process(delta: float) -> bool:
	tick += 1
	if wall_started > 0 and Time.get_ticks_msec() - wall_started > 2000:
		if samples == 0: first_sample_frame = Engine.get_frames_drawn()
		samples += 1
		frame_ms += delta * 1000.0
		ship_draw_ms += float(ShipRenderer.frame_draw_usec) / 1000.0
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	if samples > 0 and Time.get_ticks_msec() - wall_started > 5000:
		print(JSON.stringify({"mode": "compositor_21_t5" if compositor_mode else "gallery_20_t5", "samples": samples, "rendered_frames": Engine.get_frames_drawn() - first_sample_frame, "mean_frame_ms": frame_ms / samples, "mean_ship_draw_ms": ship_draw_ms / samples, "mean_process_ms": process_ms / samples, "mean_physics_ms": physics_ms / samples, "mean_draw_calls": draw_calls / samples}))
		quit()
	return false
