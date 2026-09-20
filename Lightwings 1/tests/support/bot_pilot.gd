extends RefCounted
## A scripted player that flies through the same ShipCommand a human produces.
## Extracted from campaign_playthrough_test.gd so every play measurement uses one pilot.
##   const BotPilot = preload("res://tests/support/bot_pilot.gd")
##
## `perfect` is the original bot. `novice` is deliberately worse, because a perfect bot makes
## "a new player evolves within two minutes" trivially true (it evolves in under seven seconds).

var dodge: bool = true
var fires: bool = true
var aim_error_degrees: float = 0.0
var aim_reroll_ticks: int = 30
var fire_duty: float = 1.0
var reaction_ticks: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _tick: int = 0
var _aim_error: float = 0.0
var _delayed: Array[ShipCommand] = []

static func perfect(seed_value: int = 1) -> RefCounted:
	var pilot: RefCounted = new()
	pilot._rng.seed = seed_value
	return pilot

static func novice(seed_value: int = 1) -> RefCounted:
	var pilot: RefCounted = new()
	pilot._rng.seed = seed_value
	pilot.dodge = false
	pilot.aim_error_degrees = 10.0
	pilot.fire_duty = 0.6
	pilot.reaction_ticks = 15
	return pilot

func command(combat: CombatWorld) -> ShipCommand:
	var decided: ShipCommand = _decide(combat)
	_tick += 1
	if reaction_ticks <= 0: return decided
	_delayed.append(decided)
	if _delayed.size() <= reaction_ticks: return ShipCommand.new()
	return _delayed.pop_front()

func _decide(combat: CombatWorld) -> ShipCommand:
	var decided: ShipCommand = ShipCommand.new()
	var position: Vector2 = combat.player_position
	var nearest: Dictionary = {}
	var distance: float = INF
	for actor: Dictionary in combat.enemies:
		if bool(actor.get("dead",false)): continue
		var candidate: float = position.distance_to(actor.pos)
		if candidate < distance:
			nearest = actor
			distance = candidate
	if not nearest.is_empty():
		var toward: Vector2 = Vector2(nearest.pos)-position
		if aim_error_degrees > 0.0 and _tick % aim_reroll_ticks == 0:
			_aim_error = deg_to_rad(_rng.randf_range(-aim_error_degrees,aim_error_degrees))
		decided.aim = (toward+Vector2(nearest.vel)*(distance/435.0)).normalized().rotated(_aim_error)
		var firing: bool = fires and float(_tick % 60) < fire_duty*60.0
		decided.fire = firing
		decided.ability_primary = firing
		decided.ability_secondary = firing
		decided.movement = toward.normalized() if distance > 280.0 else -toward.normalized() if distance < 200.0 else toward.normalized().orthogonal()
	var pickup_distance: float = INF
	var pickup_point: Vector2 = position
	for pickup: Dictionary in combat.pickups:
		var candidate: float = position.distance_to(pickup.pos)
		if candidate < pickup_distance:
			pickup_distance = candidate
			pickup_point = pickup.pos
	if pickup_distance < 180.0 or nearest.is_empty() and pickup_distance < INF:
		decided.movement = (pickup_point-position).normalized()
	if dodge:
		var avoidance: Vector2 = Vector2.ZERO
		for index: int in combat.bullets.active_indices:
			if combat.bullets.factions[index] == 0: continue
			var relative: Vector2 = position-combat.bullets.positions[index]
			var velocity: Vector2 = combat.bullets.velocities[index]
			if relative.length()>150.0 or velocity.length_squared()<1.0: continue
			var time: float = clampf(relative.dot(velocity)/velocity.length_squared(),0.0,0.4)
			var miss: Vector2 = relative-velocity*time
			if miss.length()<26.0: avoidance += miss.normalized() if miss.length()>1.0 else velocity.normalized().orthogonal()
		if not avoidance.is_zero_approx(): decided.movement = (decided.movement+avoidance*2.0).normalized()
	# Steer off the walls using the arena's own bounds, so the pilot survives a change of arena shape.
	var half: Vector2 = combat.arena.bounds.size*0.5
	var edge: Vector2 = (position-combat.arena.bounds.get_center())/(half-Vector2.ONE*100.0)
	if edge.length()>0.85: decided.movement = (decided.movement-edge.normalized()*1.5).normalized()
	return decided
