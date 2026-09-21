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
	# v0.3's void hulls carried an opaque occlusion disc (`hull_radius`) and were lifted into the
	# foreground to mask the background. Spec v2's void is a silver chassis with black fills and no
	# disc (Appendix A), so a rail void hull is an ordinary hull: it has a renderer and no mask.
	_check(is_instance_valid(void_actor.renderer) and float((void_actor.definition as ShipDefinition).hull_radius) == 0.0, "A rail void hull is an ordinary hull with no occlusion disc")
	_check(world.player.renderer.get_parent() == compositor.foreground, "Player remains visible above Void")
	# With no occlusion disc on any rail hull there is nothing to mask (the mask machinery goes in S12).
	_check(compositor._hull_masks.size() == 0, "No rail hull carries an occlusion disc, so the compositor builds no hull mask")
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

