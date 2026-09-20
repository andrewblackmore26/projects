extends SceneTree

const World = preload("res://scripts/combat/combat_world.gd")

## `-- --assert` turns the report into a gate. Budgets are milliseconds of headless simulation per
## tick on the development desktop: a regression detector, not Steam Deck qualification.
## Measured at the v0.2 baseline over three runs: 1000 bullets mean 3.6-3.8 / p95 4.3-4.8,
## 2000 bullets mean 6.0-6.9 / p95 7.8-9.3. Budgets sit about 1.3x above the worst of those.
## `-- --assert --budget-scale=0.01` is the negative control: it must exit 1.
const BUDGETS: Dictionary = {1000: {"mean": 5.5, "p95": 7.0}, 2000: {"mean": 9.0, "p95": 12.0}}

func _initialize() -> void:
	call_deferred("_run")

## `--fill-scale=2` is the negative control for the pool-fill line, which the budget scale cannot reach.
func _scale_argument(prefix: String) -> float:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix): return maxf(0.0, argument.trim_prefix(prefix).to_float())
	return 1.0

func _run() -> void:
	var reports: Array = []
	var asserting: bool = "--assert" in OS.get_cmdline_user_args()
	var scale: float = _scale_argument("--budget-scale=")
	var fill_scale: float = _scale_argument("--fill-scale=")
	var gate_checks: int = 0
	var gate_failures: int = 0
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
		if asserting and BUDGETS.has(requested):
			var report: Dictionary = reports[-1]
			var measured: Dictionary = {"mean": report.mean_simulation_ms, "p95": report.p95_simulation_ms}
			for key: String in measured:
				var budget: float = float(BUDGETS[requested][key]) * scale
				var ok: bool = float(measured[key]) <= budget
				gate_checks += 1
				if not ok: gate_failures += 1
				print("measure: benchmark bullets=%d %s_ms=%.3f budget_ms=%.3f ok=%d" % [requested, key, measured[key], budget, int(ok)])
			var required: int = roundi(requested * fill_scale)
			var filled: bool = int(report.peak_bullets) >= required and int(report.pool_rejected) == 0
			gate_checks += 1
			if not filled: gate_failures += 1
			print("measure: benchmark bullets=%d peak=%d required=%d rejected=%d ok=%d" % [requested, report.peak_bullets, required, report.pool_rejected, int(filled)])
		world.queue_free()
		await process_frame
	print("COMBAT BENCHMARK: " + JSON.stringify({"engine": Engine.get_version_info().string, "platform": OS.get_name(), "mode": "Headless simulation plus instance-buffer preparation; excludes GPU rendering and is not Steam Deck qualification", "reports": reports}))
	if asserting: print("COMBAT BENCHMARK GATE: %d checks, %d failures (budget scale %.2f)" % [gate_checks, gate_failures, scale])
	quit(1 if asserting and gate_failures > 0 else 0)
