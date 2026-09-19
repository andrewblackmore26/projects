extends SceneTree
## GPU integration check: a real background halo must be removed by the hull,
## while a foreground threat at the same screen position remains emissive.

class TestLight extends Node2D:
	var point: Vector2
	var tint: Color = Color(3, 3, 3, 1)
	func _draw() -> void:
		draw_circle(point, 2.0, tint, true, -1, true)

var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.use_hdr_2d = true
	var scene: Node2D = Node2D.new()
	root.add_child(scene)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.glow_enabled = true
	environment.glow_hdr_threshold = 1.0
	environment.glow_intensity = 2.0
	environment.glow_strength = 1.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i: int in range(7): environment.set_glow_level(i, 0.6 if i < 2 else 0.0)
	environment_node.environment = environment
	scene.add_child(environment_node)
	var world: CombatWorld = CombatWorld.new()
	scene.add_child(world)
	world.setup_player("corruption", 1, 0, [], Vector2(250, 400))
	var actor: Dictionary = world._spawn_enemy("void", 1, Vector2(640, 400), false)
	actor.renderer.hull_only = true
	actor.renderer.definition.hull_radius = 19.0
	var external: TestLight = TestLight.new()
	external.point = Vector2(663, 400)
	world.add_child(external)
	var hidden: TestLight = TestLight.new()
	hidden.point = Vector2(645, 400)
	world.add_child(hidden)
	var compositor: CombatCompositor = CombatCompositor.new()
	compositor.follow_player = false
	scene.add_child(compositor)
	compositor.attach(world)
	paused = true
	for i: int in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var background: Image = compositor.background_viewport.get_texture().get_image()
	var final_image: Image = root.get_texture().get_image()
	var halo: Color = background.get_pixel(657, 400)
	var masked: Color = final_image.get_pixel(657, 400)
	_check(maxf(halo.r, maxf(halo.g, halo.b)) > 0.0001, "Test source produces background bloom inside the hull")
	_check(maxf(masked.r, maxf(masked.g, masked.b)) < 0.0001, "Post-bloom Void hull suppresses underlying halo")
	var threat: TestLight = TestLight.new()
	threat.point = Vector2(640, 400)
	threat.tint = Color(0.7, 1.4, 2.0, 1)
	world._bullet_canvas.add_child(threat)
	for i: int in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var danger: Color = root.get_texture().get_image().get_pixel(640, 400)
	_check(danger.b > 0.5, "Foreground threat remains visible over the opaque hull")
	print("Void rendering: halo=", halo, " masked=", masked, " threat=", danger, " failures=", failures)
	paused = false
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)

