extends SceneTree
const Harness = preload("res://tests/support/harness.gd")
const Pool = preload("res://scripts/combat/bullet_pool.gd")
const Canvas = preload("res://scripts/combat/combat_canvas.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var t: RefCounted = Harness.new("PROJECTILE_REFERENCE")
	var pool: LightBulletPool = Pool.new()
	var cases: Array[int] = [0, Pool.HOMING, Pool.ROCKET, Pool.RICOCHET]
	var lengths: Array[int] = [9, 20, 16, 13]
	for i: int in range(cases.size()):
		var index: int = pool.add(Vector2.ZERO, Vector2.RIGHT, -1, 7, 3, 2, 1, 4, cases[i], 4.5)
		for sample: int in range(50):
			pool.positions[index] = Vector2(sample, sin(float(sample)))
			pool.sample_history(index)
		t.check(pool.history_count[index] == lengths[i] + 1, "type %d retains all %d reference trail segments" % [i, lengths[i]])
		t.check(pool.history_position(index, 0) == pool.positions[index], "history head follows current simulation position")
		t.check(pool.history_position(index, lengths[i]).x == 49 - lengths[i], "history wraps without stale samples")
		t.check(pool.radii[index] == 3 and pool.damages[index] == 7, "presentation history preserves collision radius and damage")
	var removed: int = pool.active_indices[0]
	pool.remove_at(0)
	t.check(pool.history[removed * Pool.HISTORY_STRIDE + Pool.HISTORY_POINTS] == Vector2.ZERO, "removed slot clears GPU ribbon metadata even while other slots remain visible")
	var recycled: int = pool.add(Vector2(800, 100), Vector2.ZERO, -1, 3, 3, 2, 0, 2)
	t.check(recycled == removed and pool.history_count[recycled] == 1 and pool.history_position(recycled, 0) == Vector2(800, 100), "reused slot starts a new ribbon without the old shot")
	t.check(pool.history[recycled * Pool.HISTORY_STRIDE + Pool.HISTORY_POINTS] == Vector2(0, 1) and pool.history[recycled * Pool.HISTORY_STRIDE + Pool.HISTORY_POINTS + 1] == Vector2(3, 0), "reused GPU slot resets head, count, radius and projectile type")
	var saved: Array = pool.to_array()
	pool.from_array(saved)
	t.check(pool.history_count[0] == 1, "load starts visual history at the saved position")
	var bend: PackedVector2Array = [Vector2.ZERO, Vector2(10, 0), Vector2(10, 90)]
	t.check(Canvas.point_along(bend, 0.5).is_equal_approx(Vector2(10, 40)), "beam pulse uses continuous traveled distance across uneven segments")
	t.control("old nearest-point beam sampling",not Vector2(10, 0).is_equal_approx(Canvas.point_along(bend, 0.5)))
	for i: int in range(100): pool.add(Vector2(i, 0), Vector2.RIGHT, -1, 3, 3, 1, 1, 0, Pool.HOMING, 4.5)
	for index: int in pool.active_indices: pool.sample_history(index)
	t.check(pool.count() > 40 and pool.history_count[pool.active_indices[-1]] == 2, "projectile ribbons do not compete for the 40 ship-trail slots")
	var fx: CombatFX = CombatFX.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	for i: int in range(100): fx.emit("impact", Vector2.ZERO, Pool.ROCKET_COLOR, rng)
	fx.emit("muzzle", Vector2(123, 456), Pool.PULSE_COLOR, rng)
	var kept: bool = false
	for index: int in fx.active_indices:
		if fx.kind[index] == CombatFX.Kind.RING and fx.pos[index] == Vector2(123, 456): kept = true
	t.check(kept and fx.live_count() <= CombatFX.CAPACITY, "effect flood prunes fragments before losing a new activation cue")
	var world: CombatWorld = CombatWorld.new()
	var definition: ShipDefinition = ShipDefinition.new()
	definition.core_weapon = "twin_barrel"
	definition.accent_color = "red"
	var actor: Dictionary = {"id":4, "element":"fire", "pos":Vector2(40,60), "definition":definition}
	world._emit_shot(actor, "pulse_cannon", actor.pos)
	var core_ring: int = world.fx.active_indices[0]
	t.check(world.fx.r0[core_ring] == 17 and world.fx.r1[core_ring] == 47 and is_equal_approx(world.fx.life[core_ring], 0.36), "actual core activation emits the reference17 to47px firing ring")
	t.check(world.fx.color[core_ring].is_equal_approx(Color("ffc6b5")), "core firing ring follows its red weapon marking")
	world.free()
	_test_orbit_release(t)
	_test_beam_onset(t)
	_test_refracted_path(t)
	_test_attached_emitters(t)
	t.finish(self)

func _test_orbit_release(t: RefCounted) -> void:
	var pool := Pool.new()
	var index: int = pool.add(Vector2.ZERO, Vector2.RIGHT, -1, 7, 3, 0, 0, 0, Pool.ORBIT)
	for frame: int in range(20):
		pool.positions[index] = Vector2(400 + frame, 100)
		pool.sample_history(index)
	t.check(pool.history_count[index] == 1 and pool.history_position(index, 0) == Vector2(419, 100), "orbit keeps a current seed without drawing a ribbon")
	pool.flags[index] &= ~Pool.ORBIT
	pool.positions[index] += Vector2(5, 0)
	pool.sample_history(index)
	t.check(pool.history_count[index] == 2 and pool.history_position(index, 0).distance_to(pool.history_position(index, 1)) == 5, "released orbit ribbon begins at the last orbital position, not the old spawn")

func _world() -> CombatWorld:
	var world := CombatWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.set_physics_process(false)
	world.setup_player("neutral", 1, 80, [], Vector2(500, 500))
	return world

func _muzzle_count(fx: CombatFX) -> int:
	var count: int = 0
	for index: int in fx.active_indices:
		if fx.kind[index] == CombatFX.Kind.RING and fx.r0[index] == 10 and fx.r1[index] == 23: count += 1
	return count

func _test_beam_onset(t: RefCounted) -> void:
	var world: CombatWorld = _world()
	var actor: Dictionary = world._make_actor(7, "fire", 3, Vector2(850, 500), 1, false)
	world._configure_actor(actor, ShipCatalog.get_ship("player_fire_t3_heavy"), true)
	var hub: int = -1
	for index: int in actor.gun_indices:
		if actor.rig.ability_id[index] == "beam": hub = index; break
	t.check(hub > 0, "beam onset fixture has a real armed hub")
	if hub < 0: world.free(); return
	actor.gun_indices = PackedInt32Array([hub])
	actor.part_aim[hub] = Vector2.RIGHT
	var base: float = ceilf(float(actor.part_max_hp[hub]) / 3.0) * 3.0 - float(actor.part_max_hp[hub]) + 0.1
	actor.age = base
	var rng_before: int = world._rng.state
	var cooldown_before: float = actor.part_cd[hub]
	world._update_guns(actor, 1.0 / 60.0, false)
	t.check(_muzzle_count(world.fx) == 1, "continuous enemy hub emits one onset flash at its physical emitter")
	actor.age = base + 0.1
	world._update_guns(actor, 1.0 / 60.0, false)
	t.check(_muzzle_count(world.fx) == 1, "ongoing beam window does not repeat its onset flash")
	actor.age = base + 3.0
	world._update_guns(actor, 1.0 / 60.0, false)
	t.check(_muzzle_count(world.fx) == 2, "next beam window emits a new onset flash")
	t.check(world._rng.state == rng_before and actor.part_cd[hub] == cooldown_before, "beam onset presentation leaves gameplay RNG and weapon cooldown unchanged")
	world.free()

func _test_refracted_path(t: RefCounted) -> void:
	var world: CombatWorld = _world()
	var enemy: Dictionary = world._spawn_enemy("fire", 1, Vector2(600, 500), false)
	enemy.hp = 1000.0
	enemy.max_hp = 1000.0
	enemy.hp_buffer = 1.0
	world._activate_component(world.player, "refract_beam", Vector2(500, 500), Vector2.RIGHT)
	t.check(world.telegraphs.size() == 2, "refraction retains two original damage and warning segments")
	var first: Dictionary = world.telegraphs[0]
	var second: Dictionary = world.telegraphs[1]
	t.check(first.warn == 0.6 and second.warn == 0.6 and first.hold == 0.25, "refraction retains its warning and fired hold timing")
	t.check(world._fired_beam_path(first).is_empty(), "warning never draws a live beam")
	world._update_telegraphs(0.599)
	t.check(enemy.hp == 1000.0 and not first.fired and not second.fired, "beam does no damage before its warning completes")
	world._update_telegraphs(0.002)
	var path: PackedVector2Array = world._fired_beam_path(first)
	t.check(path.size() == 3 and path[0] == first.from and path[1] == first.to and path[2] == second.to, "fired refraction exposes one connected polyline through the original elbow")
	t.check(world._fired_beam_path(second).is_empty() and bool(second.beam_continuation), "second damage segment does not restart or duplicate travelling pulses")
	t.check(is_equal_approx(float(enemy.hp), 1000.0 - float(first.damage) - float(second.damage)), "both original damage segments still land exactly once")
	var hp_after: float = enemy.hp
	world._update_telegraphs(0.1)
	t.check(enemy.hp == hp_after, "fired hold does not pay damage twice")
	var restored: Array = CombatPersistence.decode_value(JSON.parse_string(JSON.stringify(CombatPersistence.json_value(world.telegraphs))))
	t.check(world._fired_beam_path(restored[0]) == path and bool(restored[1].beam_continuation), "refracted visual path survives encounter JSON roundtrip")
	world.telegraphs.clear()
	for i: int in range(159): world.telegraphs.append({})
	world._activate_component(world.player, "refract_beam", Vector2(500, 500), Vector2.RIGHT)
	t.check(world.telegraphs.size() == 160 and world.telegraphs[-1].beam_path.size() == 2, "telegraph saturation renders only the segment actually queued")
	var laser: Dictionary = {"kind":"laser", "fired":true, "from":Vector2(10,20), "to":Vector2(100,60)}
	t.check(world._fired_beam_path(laser) == PackedVector2Array([laser.from,laser.to]), "ordinary fired laser segments use the same green beam path renderer")
	laser.fired = false
	t.check(world._fired_beam_path(laser).is_empty(), "ordinary laser warning remains a warning rather than a live beam")
	world.free()

func _test_attached_emitters(t: RefCounted) -> void:
	var world: CombatWorld = _world()
	var errors := PackedStringArray()
	var definition: ShipDefinition = ShipGrammar.load_json("res://tests/fixtures/ships_v4/radial_elite.json", errors)
	ShipCatalog.refresh(definition)
	var actor: Dictionary = world._make_actor(9, "lightning", 2, Vector2(900,500), 1, false)
	world._configure_actor(actor, definition, true)
	world.actors_by_id[9] = actor
	world.enemies.append(actor)
	var hub: int = actor.rig.index_of("r2s0")
	world.tick = 0
	world._step_motion(actor)
	var origin: Vector2 = world._part_position(actor, hub)
	var audio_requests: Array[int] = [0]
	world.shot_audio_requested.connect(func(_at: Vector2, _element: String, _ability: String, _owner: int): audio_requests[0] += 1)
	world._activate_component(actor, actor.rig.ability_id[hub], origin, Vector2.RIGHT, "r2s0", "r2s0")
	var muzzle: int = world.fx.active_indices[0]
	t.check(world.fx.emitter_owner[muzzle] == 9 and world.fx.emitter_part[muzzle] == "r2s0", "weapon activation binds its flash to the explicit firing component")
	var state: int = world._rng.state
	actor.pos += Vector2(35,18)
	actor.aim = Vector2.RIGHT.rotated(0.3)
	world.tick = 6
	world._step_motion(actor)
	world._update_effects(0.1)
	t.check(world.fx.pos[muzzle].is_equal_approx(world._part_position(actor, hub)) and world.fx.pos[muzzle].distance_to(origin) > 10, "muzzle follows actor translation, turning and its hub's orbit through the shared pose")
	t.check(world._rng.state == state and audio_requests[0] == 1, "emitter attachment updates neither gameplay RNG nor activation audio")
	var fixed: Vector2 = Vector2(250,200)
	world.fx.emit("impact", fixed, Pool.ROCKET_COLOR, world._fx_rng)
	var frozen: Vector2 = world.fx.pos[muzzle]
	world._destroy_part(actor, hub, world.player)
	actor.pos += Vector2(80,10)
	world._update_effect_attachments()
	t.check(world.fx.emitter_owner[muzzle] == -1 and world.fx.pos[muzzle] == frozen, "detaching the emitter freezes its existing pulse safely at the last attached position")
	var impacts_fixed: bool = true
	for index: int in world.fx.active_indices:
		if world.fx.kind[index] == CombatFX.Kind.RING and world.fx.r0[index] == 4: impacts_fixed = impacts_fixed and world.fx.pos[index] == fixed
	t.check(impacts_fixed, "impact shockwaves remain at their actual collision positions")
	world.fx.clear()
	world._emit_shot(actor, "bolt", actor.pos, "core")
	var core_ring: int = world.fx.active_indices[0]
	actor.pos += Vector2(45,-20)
	world._update_effect_attachments()
	t.check(world.fx.pos[core_ring] == actor.pos and world.fx.r0[core_ring] == 17, "core firing pulse stays attached to the moving core")
	actor.dead = true
	world._update_effect_attachments()
	var core_final: Vector2 = world.fx.pos[core_ring]
	actor.pos += Vector2(99,99)
	world._update_effect_attachments()
	t.check(world.fx.emitter_owner[core_ring] == -1 and world.fx.pos[core_ring] == core_final, "dead actors cannot drag an existing firing pulse")
	world.fx.update(0.5)
	world.fx.emit("muzzle", fixed, Pool.PULSE_COLOR, world._fx_rng)
	var reused: int = world.fx.active_indices[0]
	world._update_effect_attachments()
	t.check(reused == core_ring and world.fx.emitter_owner[reused] == -1 and world.fx.emitter_part[reused] == "" and world.fx.pos[reused] == fixed, "reused FX slots clear the previous emitter binding")
	world.free()
