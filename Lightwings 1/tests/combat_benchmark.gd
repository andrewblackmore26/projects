extends SceneTree

const World = preload("res://scripts/combat/combat_world.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var reports: Array = []
	for requested: int in ([2000] if "--long" in OS.get_cmdline_user_args() else [1000, 2000]):
		var world: CombatWorld = World.new()
		world.visuals_enabled = false
		world.profile_sections = true
		root.add_child(world)
		world.set_physics_process(false)
		world.benchmark(requested)
		var samples: Array[float] = []
		var upload_samples: Array[float] = []
		var highest_bullets: int = 0
		var highest_drones: int = 0
		var section_totals: Dictionary = {}
		for frame: int in range(3900 if "--long" in OS.get_cmdline_user_args() else 420):
			world._physics_process(1.0 / 60.0)
			if frame % 600 == 599: print("WINDOW ", frame, " ", JSON.stringify({"sections":world.section_ms,"actors":world.enemies.size(),"pickups":world.pickups.size(),"drones":world.drones.size(),"bullets":world.bullets.count()}))
			if frame >= 60:
				samples.append(world.simulation_ms)
				upload_samples.append(float(world._bullet_canvas.upload_ms))
				for key: String in world.section_ms:
					section_totals[key] = float(section_totals.get(key, 0.0)) + float(world.section_ms[key])
			highest_bullets = maxi(highest_bullets, world.bullets.count())
			highest_drones = maxi(highest_drones, world.drones.size())
		samples.sort()
		upload_samples.sort()
		var total: float = 0
		for sample: float in samples:
			total += sample
		for key: String in section_totals:
			section_totals[key] /= samples.size()
		print("CPU SECTIONS " + str(requested) + ": " + JSON.stringify(section_totals))
		reports.append({"target_bullets": requested, "peak_bullets": highest_bullets, "actors": world.enemies.size() + 1, "peak_drones": highest_drones, "mean_simulation_ms": total / samples.size(), "p95_simulation_ms": samples[int(samples.size() * 0.95)], "p95_projectile_upload_ms": upload_samples[int(upload_samples.size() * 0.95)], "max_simulation_ms": samples[-1], "pool_rejected": world.bullets.rejected})
		world.queue_free()
		await process_frame
	print("COMBAT BENCHMARK: " + JSON.stringify({"engine": Engine.get_version_info().string, "platform": OS.get_name(), "mode": "Headless simulation plus instance-buffer preparation; excludes GPU rendering and is not Steam Deck qualification", "reports": reports}))
	quit()
