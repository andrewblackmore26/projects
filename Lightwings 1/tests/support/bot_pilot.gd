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
## I4 finding: the pilot set the dead `ability_secondary` flag and never `secondaries`, so no bot had
## ever fired a secondary. It fires them with the primary now; false is the census control.
var fires_secondaries: bool = true
## Modernization M18: the exit this pilot is flying out through (ZERO = just fighting). Set with
## `route_to`; cleared by the pilot itself once the warp it asked for leaves PRESS.
var route: Vector2i = Vector2i.ZERO
## M18 fighter policy: < 0 keeps the original wall steer (off the walls ~200 px short of an 800 px
## rim, so it never nears the warp zone); >= 0 steers inward only within this many px of the rim,
## the way a player who uses the whole node and reacts to the rim does.
var wall_margin: float = -1.0
## Radians short of the chosen arc's edges that still count as "in it": nearer an edge than this,
## the pilot heads back toward the arc's centre line instead of pressing, so a press never engages
## the neighbouring arc by accident.
const ROUTE_ARC_MARGIN: float = 0.07
## The rim zone (`CombatWorld.WARP_REARM_ZONE`; the press engaged anywhere in it until M18, now
## only at the membrane): a routed pilot holds straight out inside it, the fighter policy steers
## off once in it, and the acceptance bot counts rim dwell inside it.
const RIM_ZONE: float = 60.0
## A pickup is fetched from this far inside RIM_ZONE (so from 720 px out on an 800 px rim: 75 px
## from light resting 5 px inside it, within the smallest hull's 90 px magnet).
const PICKUP_STANDOFF: float = 20.0

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

## Fly out through the rim toward `direction` (a neighbour offset): steer to the centre of its arc
## (`CircularArena.arc_for`), then hold straight outward through PRESS until the commit. The warp
## itself is the game's; the driver's `warp_committed` listener does the swap.
func route_to(direction: Vector2i) -> void: route = direction

func routing() -> bool: return route != Vector2i.ZERO

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
	# The warp this route asked for has committed (BREAK/TRAVEL/FADE/ARRIVAL): the route is done.
	if combat.warp_phase != CombatWorld.WARP_NONE and combat.warp_phase != CombatWorld.WARP_PUSH: route = Vector2i.ZERO
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
		var secondary: bool = firing and fires_secondaries
		decided.secondaries.assign([secondary,secondary,secondary])
		decided.movement = toward.normalized() if distance > 280.0 else -toward.normalized() if distance < 200.0 else toward.normalized().orthogonal()
	var pickup_distance: float = INF
	var pickup_point: Vector2 = position
	for pickup: Dictionary in combat.pickups:
		var candidate: float = position.distance_to(pickup.pos)
		if candidate < pickup_distance:
			pickup_distance = candidate
			pickup_point = pickup.pos
	var fetching: bool = false
	if pickup_distance < 180.0 or nearest.is_empty() and pickup_distance < INF:
		# M18: light that drifted to the rim is fetched from a standoff short of the warp zone (the
		# magnet reaches it from there), not chased into the rim. The wall steer below used to stop
		# the pilot ~200 px short - out of magnet range, so a node with rim light never cleared.
		var center: Vector2 = combat.arena.center
		var goal: Vector2 = center+(pickup_point-center).limit_length(combat.arena.radius-RIM_ZONE-PICKUP_STANDOFF)
		decided.movement = (goal-position).normalized() if position.distance_to(goal) > 6.0 else Vector2.ZERO
		fetching = true
	var pressing: bool = false
	var in_arc: bool = false
	if route != Vector2i.ZERO:
		var heading: Dictionary = _route_heading(combat)
		if not heading.is_empty():
			decided.movement = heading.movement
			pressing = heading.pressing
			in_arc = heading.in_arc
	if dodge and not pressing:
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
	if route != Vector2i.ZERO and not in_arc or route == Vector2i.ZERO and fetching:
		# On the way to its arc, or fetching light, a dodge must not press into the rim (measured: a
		# dodge while routing SW warped the pilot E, time-to-boss seed 5; dodges while fetching rim
		# light made 22 unintended warps in 20 x 600 s of pushing): near the rim, take out the
		# outward part of the input.
		var out: Vector2 = position-combat.arena.center
		if out.length() > combat.arena.radius-RIM_ZONE*1.5 and decided.movement.dot(out.normalized()) > 0.0:
			decided.movement = (decided.movement-out.normalized()*(decided.movement.dot(out.normalized())+0.3)).normalized()
	if route != Vector2i.ZERO or fetching: return decided # a route is meant to reach the rim, a fetch to stop short of it: no wall steering
	if wall_margin >= 0.0:
		var out: Vector2 = position-combat.arena.center
		if out.length() > combat.arena.radius-wall_margin: decided.movement = (decided.movement-out.normalized()*1.5).normalized()
		return decided
	# Steer off the walls using the arena's own bounds, so the pilot survives a change of arena shape.
	var half: Vector2 = combat.arena.bounds.size*0.5
	var edge: Vector2 = (position-combat.arena.bounds.get_center())/(half-Vector2.ONE*100.0)
	if edge.length()>0.85: decided.movement = (decided.movement-edge.normalized()*1.5).normalized()
	return decided

## The route's steering: `{movement, pressing, in_arc}`, or {} (and the route dropped) when `route` is not an
## exit of this node. Inside the arc (short of its edges by ROUTE_ARC_MARGIN) the pilot flies
## straight outward, which is also the press once it is within RIM_ZONE of the rim; outside it, it
## heads for a point on the arc's centre line first, so it never presses into a neighbouring arc.
func _route_heading(combat: CombatWorld) -> Dictionary:
	var arena: CircularArena = combat.arena
	var arc: Dictionary = arena.arc_for(route)
	if arc.is_empty():
		route = Vector2i.ZERO
		return {}
	var offset: Vector2 = combat.player_position-arena.center
	var half_width: float = (float(arc.to)-float(arc.from))*0.5
	var inside: bool = offset.length() > 1.0 and absf(angle_difference(float(arc.center),offset.angle())) < half_width-ROUTE_ARC_MARGIN
	if inside: return {"movement":offset.normalized(),"pressing":offset.length() >= arena.radius-RIM_ZONE,"in_arc":true}
	var approach: Vector2 = arena.center+Vector2.from_angle(float(arc.center))*arena.radius*0.6
	return {"movement":(approach-combat.player_position).normalized(),"pressing":false,"in_arc":false}
