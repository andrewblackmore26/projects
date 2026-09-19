extends SceneTree

var app: Node

func _initialize() -> void:
	_run.call_deferred()

func measure(label_text: String, duration_ms: int = 3500) -> void:
	var frames: int = 0
	var process_ms: float = 0
	var physics_ms: float = 0
	var simulation_ms: float = 0
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < duration_ms:
		await process_frame
		frames += 1
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS)*1000
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000
		simulation_ms += app.combat.simulation_ms
	print("PROFILE ",label_text," ",JSON.stringify({"fps":frames*1000.0/(Time.get_ticks_msec()-start),"process_ms":process_ms/frames,"physics_ms":physics_ms/frames,"simulation_ms":simulation_ms/frames,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)}))

func _run() -> void:
	app = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	await process_frame
	app._new_game(false)
	app._close_overlay()
	app.benchmark_mode = true
	app.combat.benchmark(2000)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await create_timer(2).timeout
	for phase: int in range(6 if "--long" in OS.get_cmdline_user_args() else 1):
		await measure("full_" + str(phase), 10000 if "--long" in OS.get_cmdline_user_args() else 3500)
	app.combat.active = false
	await measure("physics_stopped")
	app.compositor.background_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	app.compositor.visible = false
	await measure("world_hidden")
	await app._stop_audio()
	quit()
