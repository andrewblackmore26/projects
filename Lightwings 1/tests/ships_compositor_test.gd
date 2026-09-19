extends SceneTree

var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node2D = Node2D.new()
	root.add_child(scene)
	var world: CombatWorld = CombatWorld.new()
	scene.add_child(world)
	world.setup_player("corruption", 1, 0, [], Vector2(250, 400))
	var void_actor: Dictionary = world._spawn_enemy("void", 5, Vector2(640, 400), true)
	var compositor: CombatCompositor = CombatCompositor.new()
	compositor.follow_player = false
	scene.add_child(compositor)
	compositor.attach(world)
	_check(world.get_parent() == compositor.background_viewport, "World renders into background HDR")
	_check(world.process_mode == Node.PROCESS_MODE_PAUSABLE, "Gameplay remains pausable")
	_check(world._bullet_canvas.get_parent() == compositor.foreground, "Threats render in foreground")
	_check(void_actor.renderer.get_parent() == compositor.foreground, "Opaque Void hull masks processed background")
	_check(world.player.renderer.get_parent() == compositor.foreground, "Player remains visible above Void")
	_check(compositor._hull_masks.size() == 1, "Source hull suppresses occluded emissions before background glow")
	paused = true
	var frozen: float = world.elapsed
	var before_visual: float = void_actor.renderer.animation_time
	await create_timer(0.08, true).timeout
	_check(world.elapsed == frozen, "Simulation freezes while map or evolution is open")
	_check(void_actor.renderer.animation_time > before_visual, "Running lights continue during pause")
	paused = false
	compositor.detach()
	_check(world.get_parent() == scene and world._bullet_canvas.get_parent() == world, "Detach restores original ownership")
	_check(void_actor.renderer.get_parent() == world, "Detach restores actor rendering")
	scene.queue_free()
	await process_frame
	print("Ship compositor: ", failures, " failures")
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

