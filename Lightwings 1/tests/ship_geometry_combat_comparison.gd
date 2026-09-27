extends SceneTree
## Before/after measurement against pinned pre-redesign geometry. Does not replace collision
## or persistence assertions: records the practical effect of changed silhouettes under fire.
const World = preload("res://scripts/combat/combat_world.gd")
const Bot = preload("res://tests/support/bot_pilot.gd")
const SEEDS: Array[int] = [101, 202, 303]
const STEPS: int = 1800

func _initialize() -> void: _run.call_deferred()

func _encounter(seed_value: int, catalog: String, modest: bool = false) -> Dictionary:
	ShipCatalog.catalog_root = catalog
	ShipCatalog.invalidate()
	var world: CombatWorld = World.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.set_physics_process(false)
	world._rng.seed = seed_value
	world.setup_player("corruption" if modest else "lightning", 3 if modest else 6, GameTuning.capacity(3) if modest else 100000.0, [], world.arena.center)
	world.set_player_hull("player_corruption_t3_standard_a" if modest else "player_lightning_t6_heavy")
	world.start_sector({"id": "geometry_%d" % seed_value, "kind": "regular", "element": "corruption", "tier": 1 if modest else 4, "resource_budget": 160 if modest else 2000,
		"encounter_seed": seed_value, "encounter_epoch": seed_value,
		"enemy_hulls": ["enemy_drone_lightning_t1", "enemy_drone_lightning_t1", "enemy_chain_lightning_t2"] if modest else ["enemy_drone_corruption_t4", "enemy_drone_corruption_t4", "enemy_sentry_corruption_t4", "enemy_sentry_corruption_t4"],
		"elite_hulls": [] if modest else ["elite_irregular_corruption_t4", "elite_radial_corruption_t4"]})
	var shot_counts: Array[int] = [0, 0]
	world.shot_audio_requested.connect(func(_at: Vector2, _element: String, _ability: String, actor_id: int) -> void:
		shot_counts[0 if actor_id == 0 else 1] += 1)
	var pilot: RefCounted = Bot.perfect(seed_value)
	var first_kill: int = -1
	var peak_bullets: int = 0
	var detached: Dictionary = {}
	var initial_light: float = world.light_total
	var minimum_light: float = initial_light
	for step: int in range(STEPS * 2 if modest else STEPS):
		world.command = pilot.command(world)
		world._physics_process(1.0 / 60.0)
		if first_kill < 0 and world.run_kills > 0: first_kill = step
		peak_bullets = maxi(peak_bullets, world.bullet_count)
		minimum_light = minf(minimum_light, world.light_total)
		for actor: Dictionary in world.enemies:
			if bool(actor.dead): continue
			var rig: ShipMotion.ShipRig = actor.rig
			for i: int in range(1, rig.ids.size()):
				if actor.part_max_hp[i] > 0.0 and not bool(actor.part_attached[i]): detached["%d/%s" % [actor.id, rig.ids[i]]] = true
	var remaining_hp: float = 0.0
	for actor: Dictionary in world.enemies: remaining_hp += maxf(0.0, float(actor.hp))
	var result: Dictionary = {"seed": seed_value, "kills": world.run_kills, "first_kill_tick": first_kill,
		"player_shots": shot_counts[0], "enemy_shots": shot_counts[1], "peak_bullets": peak_bullets,
		"remaining_enemy_core_hp": snappedf(remaining_hp, 0.001), "light": snappedf(world.light_total, 0.001),
		"minimum_light": snappedf(minimum_light, 0.001), "initial_light": initial_light, "paid_sector_reward": world.sector_energy_paid,
		"limb_detachments_observed_while_alive": detached.size(), "player_alive": not bool(world.player.dead)}
	world._clear_encounter()
	world.free()
	return result

func _run() -> void:
	var original: String = ShipCatalog.catalog_root
	var catalogs: Dictionary = {3: original}
	for revision: int in [1, 2]:
		var scratch: String = "user://geometry_comparison_v%d_%d" % [revision, Time.get_ticks_usec()]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch))
		for entry: Dictionary in RailRoster.manifest():
			ShipCatalog.save_ship(ShipCatalog.get_ship_revision(str(entry.id), revision), scratch.path_join(str(entry.id) + ".tres"))
		catalogs[revision] = scratch
	var report: Dictionary = {"stress_seconds": 30, "skirmish_seconds": 60, "stress_note": "Original high-light survival scenario; skirmish uses natural player capacity and normal enemy HP", "stress": {}, "skirmish": {}}
	for revision: int in [1, 2, 3]:
		report.stress[str(revision)] = []
		report.skirmish[str(revision)] = []
		for seed_value: int in SEEDS:
			report.stress[str(revision)].append(_encounter(seed_value, catalogs[revision]))
			report.skirmish[str(revision)].append(_encounter(seed_value, catalogs[revision], true))
			print("geometry v%d seed%d skirmish=%s" % [revision, seed_value, str(report.skirmish[str(revision)][-1])])
	var repeat: Dictionary = _encounter(SEEDS[0], original, true)
	var deterministic: bool = repeat == report.skirmish["3"][0]
	report.repeat_deterministic = deterministic
	var file: FileAccess = FileAccess.open("res://artifacts/geometry_combat_comparison.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	for revision: int in [1, 2]:
		var scratch: String = catalogs[revision]
		for entry: Dictionary in RailRoster.manifest(): DirAccess.remove_absolute(scratch.path_join(str(entry.id) + ".tres"))
		DirAccess.remove_absolute(scratch)
	ShipCatalog.catalog_root = original
	ShipCatalog.invalidate()
	print("GEOMETRY COMBAT COMPARISON: 18 encounters + deterministic repeat, failures=%d" % (0 if deterministic else 1))
	quit(0 if deterministic else 1)
