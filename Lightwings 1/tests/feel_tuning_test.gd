extends SceneTree
## Camera and movement spec §2, P11a: the speed budget as a TABLE, before anything reads it.
##   rule (a)  the player can always outrun everything except seekers, at every tier
##   rule (b)  the player's projectiles travel at least twice as fast as the enemy's
## Both are checked over the whole shipped roster and the whole projectile table, at the far end:
## the slowest player state there is (the slowest hull, slowed) against the fastest pursuer there is
## (the fastest archetype with the Thrusters passive). Each rule has its own sabotage.

const Harness = preload("res://tests/support/harness.gd")
const SLOW: float = 0.7        # combat_world.gd::_slow_multiplier
const THRUSTERS: float = 1.2   # combat_world.gd / combat_ai.gd
## Carried by a weapon mount but they are pursuers, not projectiles: rule (a) covers them.
const PURSUER_SHOTS: Array[String] = ["bay_drone"]

var t: RefCounted

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("FEEL TUNING")
	GameTuning.reset_feel()
	_store()
	_derivations()
	_rules()
	GameTuning.reset_feel()
	await process_frame
	t.finish(self)

func _store() -> void:
	t.check(is_equal_approx(GameTuning.feel("player_top_speed"), 460.0), "feel() reads the default")
	var revision: int = GameTuning.feel_revision
	t.check(GameTuning.set_feel("player_top_speed", 500.0) and is_equal_approx(GameTuning.feel("player_top_speed"), 500.0), "set_feel overrides a value")
	t.check(GameTuning.feel_revision > revision, "set_feel bumps feel_revision, so cached floats get re-read")
	t.check(is_equal_approx(float(GameTuning.FEEL_DEFAULTS.player_top_speed), 460.0), "an override never writes through to the defaults")
	revision = GameTuning.feel_revision
	t.check(not GameTuning.set_feel("player_top_sped", 1.0), "set_feel refuses an unknown key")
	t.check(not GameTuning.set_feel("player_top_speed", NAN) and not GameTuning.set_feel("player_top_speed", INF), "set_feel refuses NaN and infinity")
	t.check(GameTuning.feel_revision == revision and is_equal_approx(GameTuning.feel("player_top_speed"), 500.0), "a refused set changes nothing")
	GameTuning.reset_feel()
	t.check(is_equal_approx(GameTuning.feel("player_top_speed"), 460.0) and GameTuning.feel_overrides().is_empty(), "reset_feel restores every default")
	var not_numbers: Array[String] = []
	for key: String in GameTuning.FEEL_DEFAULTS:
		if typeof(GameTuning.FEEL_DEFAULTS[key]) != TYPE_FLOAT: not_numbers.append(key)
	t.check(not_numbers.is_empty(), "every default is a float, so a tuned value has the type of the one it replaces (%s)" % str(not_numbers))

## The spec's three handling timings come from one time constant. These are the PREDICTIONS the
## movement model is built on; P11b measures the ship against them.
func _derivations() -> void:
	var standard: Dictionary = GameTuning.movement_taus("standard")
	var compact: Dictionary = GameTuning.movement_taus("compact")
	var heavy: Dictionary = GameTuning.movement_taus("heavy")
	var reversal: float = log(20.0) * float(standard.accel)
	t.check(absf(reversal - 0.22) <= 0.02, "standard: t90 0.16 s predicts a reversal of %.4f s, within 0.02 of the spec's 0.22" % reversal)
	var compact_reversal: float = log(20.0) * float(compact.accel)
	t.check(absf(compact_reversal - 0.17) <= 0.005, "compact: predicted reversal %.4f s is the spec's 0.17" % compact_reversal)
	t.check(float(compact.accel) < float(standard.accel) and float(standard.accel) < float(heavy.accel), "time constants ordered compact < standard < heavy")
	var coast_left: float = exp(-0.40 / float(standard.coast))
	t.check(absf(coast_left - 0.05) <= 0.0005, "coast tau leaves %.4f of top speed at 0.40 s (spec: a stop, taken as 5 %%)" % coast_left)
	# Drift: replay the closed form. After a 90 degree step the old heading decays with `drift`
	# and the new one rises with `accel`; their ratio at drift_s is the tangent of the lag.
	var lag: float = rad_to_deg(atan2(exp(-0.15 / float(standard.drift)), 1.0 - exp(-0.15 / float(standard.accel))))
	t.check(absf(lag - 18.0) <= 0.05, "standard drift tau puts the velocity %.3f degrees off the input at 0.15 s (spec 18)" % lag)
	t.check(float(standard.drift) > float(standard.accel), "drift is slower than thrust, which is what carries the ship wide")
	GameTuning.set_feel("move.drift_deg", 89.9) # unreachable: the lateral part would have to GROW
	t.check(is_equal_approx(float(GameTuning.movement_taus("standard").drift), float(standard.accel)), "an unreachable drift target falls back to the isotropic model instead of a negative tau")
	GameTuning.reset_feel()

## Slowest the player can be made to go, as a ratio of player_top_speed.
func _slowest_player_ratio(players: Array[ShipDefinition]) -> Dictionary:
	var ratio: float = INF
	var id: String = ""
	for ship: ShipDefinition in players:
		var value: float = GameTuning.hull_speed_factor(ship.speed) * SLOW
		if value < ratio:
			ratio = value
			id = ship.id
	return {"ratio": ratio, "id": id}

func _fastest_pursuer_ratio() -> Dictionary:
	var ratio: float = 0.0
	var key_found: String = ""
	for key: String in GameTuning.FEEL_DEFAULTS:
		var pursuer: bool = key.begins_with("enemy_ratio.") or key == "shot.enemy.bay_drone"
		if pursuer and GameTuning.feel(key) * THRUSTERS > ratio:
			ratio = GameTuning.feel(key) * THRUSTERS
			key_found = key
	return {"ratio": ratio, "key": key_found}

func _rule_a(players: Array[ShipDefinition]) -> bool:
	return float(_slowest_player_ratio(players).ratio) > float(_fastest_pursuer_ratio().ratio)

func _shot_extreme(faction: String, want_max: bool) -> Dictionary:
	var best: float = -INF if want_max else INF
	var key_found: String = ""
	for key: String in GameTuning.FEEL_DEFAULTS:
		if not key.begins_with("shot.%s." % faction) or key.get_slice(".", 2) in PURSUER_SHOTS: continue
		var value: float = GameTuning.feel(key)
		if (want_max and value > best) or (not want_max and value < best):
			best = value
			key_found = key
	return {"ratio": best, "key": key_found}

func _rule_b() -> bool:
	return float(_shot_extreme("player", false).ratio) >= 2.0 * float(_shot_extreme("enemy", true).ratio)

func _rules() -> void:
	var players: Array[ShipDefinition] = []
	var fastest_hull: float = 0.0
	var fastest_id: String = ""
	for ship: ShipDefinition in ShipCatalog.all_forms():
		if not ship.is_player: continue
		players.append(ship)
		var sustained: float = GameTuning.hull_speed_factor(ship.speed) * (THRUSTERS if "thrusters" in ship.passives else 1.0)
		if sustained > fastest_hull:
			fastest_hull = sustained
			fastest_id = ship.id
	t.check(players.size() >= 100, "the rules are checked over the whole player roster (%d hulls)" % players.size())

	var slowest: Dictionary = _slowest_player_ratio(players)
	var pursuer: Dictionary = _fastest_pursuer_ratio()
	print("measure: feel_rule_a slowest_player=%s ratio=%.3f fastest_pursuer=%s ratio=%.3f ok=%d" % [slowest.id, slowest.ratio, pursuer.key, pursuer.ratio, int(_rule_a(players))])
	t.check(_rule_a(players), "rule (a): the slowest player state (%s slowed, %.3f) outruns the fastest pursuer (%s with thrusters, %.3f)" % [slowest.id, slowest.ratio, pursuer.key, pursuer.ratio])

	var slow_shot: Dictionary = _shot_extreme("player", false)
	var fast_shot: Dictionary = _shot_extreme("enemy", true)
	print("measure: feel_rule_b slowest_player_shot=%s ratio=%.3f fastest_enemy_shot=%s ratio=%.3f ok=%d" % [slow_shot.key, slow_shot.ratio, fast_shot.key, fast_shot.ratio, int(_rule_b())])
	t.check(_rule_b(), "rule (b): the slowest player shot (%s, %.2f) is at least 2x the fastest enemy shot (%s, %.2f)" % [slow_shot.key, slow_shot.ratio, fast_shot.key, fast_shot.ratio])

	# Reported, not gated. The seeker exemption in rule (a): is it ever needed?
	print("report: slowest player state %.3f vs seeker %.3f -> %s" % [slowest.ratio, GameTuning.feel("shot.enemy.seeker"), "a slowed %s still outruns a seeker in a straight line" % slowest.id if float(slowest.ratio) > GameTuning.feel("shot.enemy.seeker") else "a seeker catches it, as the spec intends"])
	# A hull faster than its own slowest shot flies into its own fire. The user's call to resolve.
	print("report: fastest sustained hull %s at %.3f vs slowest player shot %s at %.3f -> %s" % [fastest_id, fastest_hull, slow_shot.key, slow_shot.ratio, "THE SHIP OUTRUNS ITS OWN SHOTS" if fastest_hull > float(slow_shot.ratio) else "shots stay ahead of the ship"])

	# Controls: each sabotage must fail ITS rule and leave the other standing.
	GameTuning.set_feel("enemy_ratio.drone", 0.9)
	t.control("a drone at 0.9x the player's speed (rule a must fail)", not _rule_a(players))
	t.check(_rule_b(), "...and that sabotage leaves rule (b) untouched")
	GameTuning.reset_feel()
	GameTuning.set_feel("shot.enemy.bolt", 0.8)
	t.control("an enemy bolt at 0.8x (rule b must fail)", not _rule_b())
	t.check(_rule_a(players), "...and that sabotage leaves rule (a) untouched")
	GameTuning.reset_feel()
	t.control("an unknown tuning key (set_feel must refuse it)", not GameTuning.set_feel("enemy_ratio.dragon", 0.5))
