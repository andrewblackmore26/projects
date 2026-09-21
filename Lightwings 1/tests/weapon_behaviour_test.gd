extends SceneTree
## The twenty catalogue weapons added for the ship design spec (§6.3). One fresh world per weapon
## (lessons: shared state makes scenarios dependent). Each weapon must produce ITS effect, and the
## same scenario run with `radar` - a passive that does nothing when activated - must not.
## Enemy-cast hits the player cannot dodge on reaction must not land before 0.5 s (v0.3 §16).
const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")
const Pool = preload("res://scripts/combat/bullet_pool.gd")
const STEP: float = 1.0 / 60.0

var t: RefCounted

func _initialize() -> void: call_deferred("run")

func make_world() -> CombatWorld:
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 400, [], Vector2(500, 500))
	w.ai_firing_disabled = true # only the weapon under test may act
	return w

func release(w: CombatWorld) -> void:
	w._clear_encounter()
	w.free()

func _target(w: CombatWorld, at: Vector2) -> Dictionary:
	var enemy: Dictionary = w._spawn_enemy("fire", 2, at, false)
	enemy.vel = Vector2.ZERO
	return enemy

func _bullets(w: CombatWorld, flag: int = -1) -> int:
	var count: int = 0
	for index: int in w.bullets.active_indices:
		if flag < 0 or (w.bullets.flags[index] & flag) != 0: count += 1
	return count

## The player casts `id` at an enemy 150 px to the right; returns what the world then holds.
func _cast(id: String) -> Dictionary:
	var w: CombatWorld = make_world()
	var enemy: Dictionary = _target(w, Vector2(650, 500))
	w._last_dt = STEP
	w._activate_component(w.player, id, Vector2(w.player.pos), Vector2.RIGHT, "")
	var found: Dictionary = {"world": w, "enemy": enemy, "bullets": _bullets(w), "clouds": w.clouds.size(), "drones": w.drones.size(), "telegraphs": w.telegraphs.size(), "tethers": w.viruses.size(), "beams": w.beams.size()}
	found.anything = int(found.bullets) + int(found.clouds) + int(found.drones) + int(found.telegraphs) + int(found.tethers) + int(found.beams)
	return found

func _expect(id: String, what: String, holds: Callable) -> void:
	var cast: Dictionary = _cast(id)
	t.check(holds.call(cast), "%s: %s (bullets %d, clouds %d, drones %d, telegraphs %d, tethers %d, beams %d)" % [id, what, cast.bullets, cast.clouds, cast.drones, cast.telegraphs, cast.tethers, cast.beams])
	t.check(int((cast.world as CombatWorld).ability_events.get(id, 0)) == 1, "%s is counted once in the play census" % id)
	release(cast.world)

## Seconds until an ENEMY casting `id` at the player first costs the player light; -1 if never in 4 s.
func _first_hurt(id: String) -> float:
	var w: CombatWorld = make_world()
	var enemy: Dictionary = _target(w, Vector2(620, 500))
	w.player_invulnerable = 0.0
	w._last_dt = STEP
	w._activate_component(enemy, id, Vector2(enemy.pos), Vector2.LEFT, "")
	var light: float = w.light_total
	var seconds: float = -1.0
	for tick: int in range(240):
		w.set_command(ShipCommand.new())
		w._physics_process(STEP)
		if w.light_total < light - 0.001:
			seconds = float(tick + 1) * STEP
			break
	release(w)
	return seconds

func run() -> void:
	t = Harness.new("WEAPON BEHAVIOUR")
	var nothing: Dictionary = _cast("radar")
	t.control("the same cast with `radar`, which does nothing when activated", int(nothing.anything) == 0)
	release(nothing.world)

	_expect("spiral_shot", "two shots weaving about the aim", func(c: Dictionary) -> bool: return int(c.bullets) == 2)
	_expect("pulse_ring", "a ring of twelve", func(c: Dictionary) -> bool: return int(c.bullets) == 12)
	_expect("chain_infection", "one shot that chains AND infects", func(c: Dictionary) -> bool: return _bullets(c.world, Pool.CHAIN) == 1 and _bullets(c.world, Pool.INFECT) == 1)
	_expect("phase_shot", "one phasing shot", func(c: Dictionary) -> bool: return _bullets(c.world, Pool.PHASE) == 1)
	_expect("void_orb", "one slow heavy orb", func(c: Dictionary) -> bool: return _bullets(c.world, Pool.PIERCING) == 1 and (c.world as CombatWorld).bullets.velocities[(c.world as CombatWorld).bullets.active_indices[0]].length() < 200.0)
	_expect("drone_hatch", "two drones", func(c: Dictionary) -> bool: return int(c.drones) == 2)
	_expect("drone_swarm", "four fragile drones", func(c: Dictionary) -> bool: return int(c.drones) == 4 and float((c.world as CombatWorld).drones[0].hp) == 20.0)
	_expect("slow_field", "a field that slows and does not hurt", func(c: Dictionary) -> bool: return int(c.clouds) == 1 and float((c.world as CombatWorld).clouds[0].damage) == 0.0)
	_expect("black_hole_shot", "one black hole, and the pull pass armed", func(c: Dictionary) -> bool: return _bullets(c.world, Pool.BLACK_HOLE) == 1 and (c.world as CombatWorld).black_holes == 1)
	_expect("arc_tether", "a tether on the enemy in range", func(c: Dictionary) -> bool: return int(c.tethers) == 1 and str((c.world as CombatWorld).viruses[0].kind) == "arc_tether")
	_expect("siphon_tether", "a siphoning tether", func(c: Dictionary) -> bool: return int(c.tethers) == 1 and str((c.world as CombatWorld).viruses[0].kind) == "siphon_tether")
	_expect("siphon_leech", "a leeching tether", func(c: Dictionary) -> bool: return int(c.tethers) == 1)
	_expect("ignition_lance", "a beam", func(c: Dictionary) -> bool: return int(c.beams) >= 1)
	_expect("discharge", "a telegraphed blast centred on the caster", func(c: Dictionary) -> bool: return int(c.telegraphs) == 1 and Vector2((c.world as CombatWorld).telegraphs[0].from).distance_to(Vector2(500, 500)) < 1.0)
	_expect("collapse_charge", "a telegraphed blast ahead", func(c: Dictionary) -> bool: return int(c.telegraphs) == 1 and Vector2((c.world as CombatWorld).telegraphs[0].from).x > 600.0)
	_expect("nova_pulse", "a telegraphed nova", func(c: Dictionary) -> bool: return int(c.telegraphs) == 1 and str((c.world as CombatWorld).telegraphs[0].kind) == "nova")
	_expect("blink_mine", "a mine telegraphed 300 px AHEAD, not behind", func(c: Dictionary) -> bool: return int(c.telegraphs) == 1 and Vector2((c.world as CombatWorld).telegraphs[0].from).x > 750.0)
	_expect("refract_beam", "two telegraphed segments joined at an elbow", func(c: Dictionary) -> bool: return int(c.telegraphs) == 2 and Vector2((c.world as CombatWorld).telegraphs[0].to).distance_to(Vector2((c.world as CombatWorld).telegraphs[1].from)) < 0.001)
	_expect("incendiary_spores", "three telegraphed spores", func(c: Dictionary) -> bool: return int(c.telegraphs) == 3)
	_expect("overcharge", "one shot", func(c: Dictionary) -> bool: return int(c.bullets) == 1)

	_test_overcharge_fourth()
	_test_phase_passes_limbs()
	_test_tether_lifecycle()
	_test_black_hole_pulls()
	_test_nova_and_spores_bloom()
	_test_virus_lets_go_of_the_player()

	# v0.3 §16: what cannot be dodged on reaction warns for at least half a second.
	for id: String in ["discharge", "collapse_charge", "nova_pulse", "refract_beam", "arc_tether", "siphon_leech"]:
		var seconds: float = _first_hurt(id)
		t.check(seconds < 0.0 or seconds >= 0.5 - STEP, "An enemy's %s does not hurt before 0.5 s (first hurt at %s)" % [id, ("%.2f s" % seconds) if seconds >= 0.0 else "never in 4 s"])
	var instant: float = _first_hurt_with_no_warning()
	t.control("a tether with its draw-in removed (first hurt at %.3f s)" % instant, instant >= 0.0 and instant < 0.5 - STEP)
	t.finish(self)

func _test_overcharge_fourth() -> void:
	var w: CombatWorld = make_world()
	w._last_dt = STEP
	var damages: Array[float] = []
	for shot: int in range(4):
		w._activate_component(w.player, "overcharge", Vector2(w.player.pos), Vector2.RIGHT, "")
		damages.append(w.bullets.damages[w.bullets.active_indices[-1]])
	t.check(is_equal_approx(damages[3], damages[0] * 3.0) and is_equal_approx(damages[1], damages[0]) and _bullets(w, Pool.CHAIN) == 1, "overcharge: the FOURTH shot, and only it, is triple and chains (%s)" % str(damages))
	release(w)

func _test_phase_passes_limbs() -> void:
	for id: String in ["phase_shot", "pulse_cannon"]:
		var w: CombatWorld = make_world()
		var elite: Dictionary = w._spawn_elite("fire", 3, Vector2(800, 500))
		elite.vel = Vector2.ZERO
		var limbs_before: float = 0.0
		for i: int in range(1, elite.part_hp.size()): limbs_before += float(elite.part_hp[i])
		w._last_dt = STEP
		for volley: int in range(40):
			for spread: int in range(-6, 7): w._activate_component(w.player, id, Vector2(w.player.pos), Vector2.RIGHT.rotated(float(spread) * 0.04), "")
			for tick: int in range(6):
				w.set_command(ShipCommand.new())
				w._physics_process(STEP)
		var limbs_after: float = 0.0
		for i: int in range(1, elite.part_hp.size()): limbs_after += float(elite.part_hp[i])
		if id == "phase_shot": t.check(is_equal_approx(limbs_after, limbs_before), "phase_shot: 520 shots fanned across an elite cost its limbs nothing (%.0f -> %.0f)" % [limbs_before, limbs_after])
		else: t.control("the same fan fired as pulse_cannon (limbs %.0f -> %.0f)" % [limbs_before, limbs_after], limbs_after < limbs_before)
		release(w)

func _test_tether_lifecycle() -> void:
	var w: CombatWorld = make_world()
	var enemy: Dictionary = _target(w, Vector2(650, 500))
	w._last_dt = STEP
	var hp: float = float(enemy.hp)
	w._activate_component(w.player, "arc_tether", Vector2(w.player.pos), Vector2.RIGHT, "")
	for tick: int in range(60): w._update_viruses(STEP)
	t.check(float(enemy.hp) < hp and w.viruses.size() == 1, "arc_tether: it hurts while it holds (%.1f -> %.1f in 1 s)" % [hp, float(enemy.hp)])
	enemy.pos = Vector2(1400, 500) # far past 1.3 x range
	w._update_viruses(STEP)
	t.check(w.viruses.is_empty(), "arc_tether: it snaps when the target gets out of reach")
	enemy.pos = Vector2(650, 500)
	w._activate_component(w.player, "arc_tether", Vector2(w.player.pos), Vector2.RIGHT, "")
	for tick: int in range(200): w._update_viruses(STEP)
	t.check(w.viruses.is_empty(), "arc_tether: it lets go after its 3 s")
	var far: Dictionary = _cast_at_distance("arc_tether", 900.0)
	t.control("a target 900 px away, outside the tether's range", int(far.tethers) == 0)
	release(far.world)
	# From a LOW bar: the player starts this test above the tier-1 capacity, where there is no room
	# for returned light and the first run read 400.00 -> 400.00.
	w.light_total = 30.0
	var light: float = w.light_total
	# A FRESH target: four seconds of arc tether above have very likely killed the first one, and a
	# tether onto a corpse attaches to nothing (the second run read 30.00 -> 30.00 for that reason).
	var fresh: Dictionary = _target(w, Vector2(650, 440))
	fresh.hp = 100000.0
	w._activate_component(w.player, "siphon_tether", Vector2(w.player.pos), Vector2(150, -60).normalized(), "")
	t.check(w.viruses.size() == 1, "siphon_tether: it attaches to the fresh target (%d tethers)" % w.viruses.size())
	for tick: int in range(120): w._update_viruses(STEP)
	t.check(w.light_total > light, "siphon_tether: it returns light to the player (%.2f -> %.2f)" % [light, w.light_total])
	release(w)

func _cast_at_distance(id: String, distance: float) -> Dictionary:
	var w: CombatWorld = make_world()
	_target(w, Vector2(500 + distance, 500))
	w._last_dt = STEP
	w._activate_component(w.player, id, Vector2(w.player.pos), Vector2.RIGHT, "")
	return {"world": w, "tethers": w.viruses.size()}

func _test_black_hole_pulls() -> void:
	var w: CombatWorld = make_world()
	var enemy: Dictionary = _target(w, Vector2(620, 560))
	w._last_dt = STEP
	w._activate_component(w.player, "black_hole_shot", Vector2(w.player.pos), Vector2.RIGHT, "")
	var gap_before: float = Vector2(enemy.pos).distance_to(w.bullets.positions[w.bullets.active_indices[0]])
	for tick: int in range(30): w._update_black_holes(STEP)
	var gap_after: float = Vector2(enemy.pos).distance_to(w.bullets.positions[w.bullets.active_indices[0]])
	t.check(gap_after < gap_before - 20.0, "black_hole_shot: it drags a hostile in reach toward itself (%.1f -> %.1f px in 0.5 s)" % [gap_before, gap_after])
	w.bullets.clear()
	w._update_black_holes(STEP)
	t.check(w.black_holes == 0, "black_hole_shot: the pass recounts, so the counter cannot drift once the shot is gone")
	var still: Vector2 = Vector2(enemy.pos)
	for tick: int in range(30): w._update_black_holes(STEP)
	t.control("no black hole in play", Vector2(enemy.pos).distance_to(still) < 0.001)
	release(w)

func _test_nova_and_spores_bloom() -> void:
	var w: CombatWorld = make_world()
	_target(w, Vector2(900, 500))
	w._last_dt = STEP
	w._activate_component(w.player, "nova_pulse", Vector2(w.player.pos), Vector2.RIGHT, "")
	for tick: int in range(20): w._update_telegraphs(STEP)
	t.control("a nova asked for its shots before its warning is up", _bullets(w) == 0)
	for tick: int in range(30): w._update_telegraphs(STEP)
	t.check(_bullets(w) == 24, "nova_pulse: two rings of twelve when the warning ends (%d)" % _bullets(w))
	w._activate_component(w.player, "incendiary_spores", Vector2(w.player.pos), Vector2.RIGHT, "")
	for tick: int in range(60): w._update_telegraphs(STEP)
	t.check(w.clouds.size() == 3, "incendiary_spores: three burning clouds bloom where the spores land (%d)" % w.clouds.size())
	release(w)

func _test_virus_lets_go_of_the_player() -> void:
	var w: CombatWorld = make_world()
	var enemy: Dictionary = _target(w, Vector2(650, 500))
	w._last_dt = STEP
	w._attach_virus(enemy, 0, 1.0, 2)
	for tick: int in range(200): w._update_viruses(STEP)
	t.control("a virus asked about at 3.3 s", w.viruses.size() == 1)
	for tick: int in range(60): w._update_viruses(STEP)
	t.check(w.viruses.is_empty(), "A plain virus lets go of the PLAYER after four seconds (it used to hold for ever)")
	release(w)

## The tether's 0.5 s draw-in is what keeps it fair. Without it the first hurt is immediate.
func _first_hurt_with_no_warning() -> float:
	var w: CombatWorld = make_world()
	var enemy: Dictionary = _target(w, Vector2(620, 500))
	w.player_invulnerable = 0.0
	w._last_dt = STEP
	w._activate_component(enemy, "arc_tether", Vector2(enemy.pos), Vector2.LEFT, "")
	if not w.viruses.is_empty(): w.viruses[0].warn = 0.0
	var light: float = w.light_total
	var seconds: float = -1.0
	for tick: int in range(120):
		w.set_command(ShipCommand.new())
		w._physics_process(STEP)
		if w.light_total < light - 0.001:
			seconds = float(tick + 1) * STEP
			break
	release(w)
	return seconds
