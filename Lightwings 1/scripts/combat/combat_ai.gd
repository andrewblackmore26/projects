class_name CombatAI
extends RefCounted
## P4b: archetype behaviour lives here, out of combat_world.gd's `_update_ai`.
## Spec §14: "Regular enemies run fixed patterns. Elites and bosses make
## decisions: lead the player's movement, retreat when limbs are lost,
## protect the core when exposed." with human-like limits on the
## decision-driven ones: 150-300 ms reaction delay, 2-5 deg aim error,
## resampled per decision (never per shot) - the challenge is the decision,
## never the aim. Regular archetypes (drone/sentry/chain) get NONE of this
## machinery: they always aim at the target's TRUE current position.
##
## The reaction delay is not a bolted-on timer: a decision-driven actor's
## `decision_cd` re-roll IS its perception cadence (0.15-0.30 s, matching the
## spec band exactly). Each decision captures the target's position/velocity
## and stores it as `_next_*`; the value actually used for aim and movement
## THIS decision is `_delayed_*`, which was `_next_*` from the PREVIOUS
## decision - i.e. the observation is always exactly one decision-interval
## (150-300 ms) old. `CombatWorld.ai_reaction_disabled` collapses that lag to
## ~0 for the negative control; `CombatWorld.ai_aim_error_disabled` collapses
## every sampled error to 0 for its own negative control.

const REACTION_MIN: float = 0.15
const REACTION_MAX: float = 0.30
const AIM_ERROR_MIN_DEG: float = 2.0
const AIM_ERROR_MAX_DEG: float = 5.0
## An elite/boss retreats once fewer than half its weapon circles (by the
## count authored at spawn, `actor.gun_total`) remain attached and alive.
const RETREAT_LIMB_FRACTION: float = 0.5
## While retreating, the actor steers away until it has opened this much
## distance from its (delayed) target; below it, it still steers away.
const RETREAT_RANGE: float = 420.0
## "Protect the core when exposed": bias the ship's facing so the side
## carrying more surviving circles is the one presented toward the threat.
const PROTECT_BIAS_MAX_RAD: float = 0.45 # ~26 degrees

## Single choke point for what counts as "an elite or boss decision, not a
## regular's fixed pattern" - both archetype dispatch and the tests use it.
static func is_decision_driven(actor: Dictionary) -> bool:
	return bool(actor.get("elite", false)) or bool(actor.get("rival", false))

static func archetype_of(actor: Dictionary) -> String:
	if bool(actor.get("rival", false)): return "boss"
	var id: String = str(actor.get("hull_id", ""))
	if id.begins_with("elite_radial"): return "radial"
	if id.begins_with("elite_irregular"): return "irregular"
	if id.begins_with("enemy_sentry"): return "sentry"
	if id.begins_with("enemy_chain"): return "chain"
	return "drone"

static func sample_aim_error(rng: RandomNumberGenerator) -> float:
	var degrees: float = rng.randf_range(AIM_ERROR_MIN_DEG, AIM_ERROR_MAX_DEG)
	if rng.randf() < 0.5: degrees = -degrees
	return deg_to_rad(degrees)

## Entry point: called once per physics tick per enemy actor from
## `CombatWorld._update_ai`. Owns the decision timer, movement and gun aim
## for every archetype; firing itself still goes through the world's
## existing ability plumbing (`_fire_primary`, `_use_secondary`,
## `_update_guns`, `_regular_pattern`) so damage/cooldown/telegraph code is
## not duplicated.
static func update(world, actor: Dictionary, dt: float) -> void:
	match archetype_of(actor):
		"sentry": _update_sentry(world, actor, dt)
		"chain": _update_regular(world, actor, dt)
		"radial", "irregular": _update_decision_driven(world, actor, dt)
		"boss": _update_decision_driven(world, actor, dt)
		_: _update_regular(world, actor, dt)

## --- Regular archetypes: fixed pattern, full information, no error --------

## Drone and chain: pursue/small-orbit on a flat cadence, aim exactly at the
## target's true current position (no delay, no error - spec: "Regular
## enemies run fixed patterns").
static func _update_regular(world, actor: Dictionary, dt: float) -> void:
	actor.decision_cd = float(actor.decision_cd) - dt
	if float(actor.decision_cd) <= 0.0:
		actor.decision_cd = 0.3
		var target: Dictionary = world._choose_target(actor)
		var relative: Vector2 = Vector2(target.get("pos", world.player_position)) - Vector2(actor.pos)
		actor.desired_aim = relative.normalized()
		var desired: Vector2 = actor.desired_aim
		if relative.length() < 300.0: desired = desired.orthogonal() * 0.6
		actor.desired = desired
	_steer(world, actor, dt, 0.45)
	world._regular_pattern(actor, dt)
	for i: int in range(actor.secondaries.size()): world._use_secondary(actor, i)

## Sentry: speed 0 always (never moves - spec §14/§16), the weapon tracks the
## target continuously (full information, no human limits: it is a regular
## archetype), and its shot is a telegraphed long-range attack (>=0.5 s
## warning via the existing `laser_prong`/`_queue_attack` path, already
## authored on tier>=2 sentries).
static func _update_sentry(world, actor: Dictionary, dt: float) -> void:
	actor.vel = Vector2.ZERO
	var target: Dictionary = world._choose_target(actor)
	var relative: Vector2 = Vector2(target.get("pos", world.player_position)) - Vector2(actor.pos)
	if relative.length_squared() > 0.0001:
		actor.desired_aim = relative.normalized()
		actor.aim = Vector2.from_angle(rotate_toward(Vector2(actor.aim).angle(), actor.desired_aim.angle(), float(actor.turn_rate) * dt))
	world._fire_primary(actor, dt)
	for i: int in range(actor.secondaries.size()): world._use_secondary(actor, i)

## --- Decision-driven: elites and bosses ------------------------------------

static func _update_decision_driven(world, actor: Dictionary, dt: float) -> void:
	actor.decision_cd = float(actor.decision_cd) - dt
	var timer_due: bool = float(actor.decision_cd) <= 0.0
	if timer_due: actor.decision_cd = world._rng.randf_range(REACTION_MIN, REACTION_MAX)
	# `ai_reaction_disabled` (test-only negative control) collapses the whole
	# decision cadence, not just the delayed observation inside it: a "zero
	# reaction delay" enemy re-decides every tick, exactly like the pre-P4b
	# code that aimed every gun perfectly at the nearest target every tick.
	var new_decision: bool = timer_due or bool(world.ai_reaction_disabled)
	if new_decision: _decide(world, actor)
	_steer(world, actor, dt, 0.45 if bool(actor.get("elite", false)) else 0.85)
	if actor.get("gun_indices", PackedInt32Array()).size() > 0:
		world._update_guns(actor, dt, new_decision)
	else:
		world._fire_primary(actor, dt)
		for i: int in range(actor.secondaries.size()): world._use_secondary(actor, i)

## One decision: capture the target's position/velocity, delay it by one
## decision-interval, then set movement (lead, retreat, protect-core bias).
static func _decide(world, actor: Dictionary) -> void:
	var target: Dictionary = world._choose_target(actor)
	actor.target = int(target.get("id", 0))
	var fresh_pos: Vector2 = Vector2(target.get("pos", world.player_position))
	var fresh_vel: Vector2 = Vector2(target.get("vel", Vector2.ZERO))
	var reaction_off: bool = bool(world.ai_reaction_disabled)
	var now_tick: int = int(world.tick)
	var delayed_pos: Vector2 = fresh_pos if reaction_off else Vector2(actor.get("_next_pos", fresh_pos))
	var delayed_vel: Vector2 = fresh_vel if reaction_off else Vector2(actor.get("_next_vel", fresh_vel))
	# `_delayed_tick` records the SIM TICK the observation now in `_delayed_pos`
	# was actually captured at - `enemy_ai_test.gd`'s reaction-delay measurement
	# reads `now_tick - _delayed_tick` directly instead of inferring a time lag
	# from a moving target's position (which conflates the delay itself with
	# how often decisions are sampled).
	actor._delayed_tick = now_tick if reaction_off else int(actor.get("_pos_tick", now_tick))
	actor._decided_tick = now_tick
	actor._pos_tick = now_tick
	actor._next_pos = fresh_pos
	actor._next_vel = fresh_vel
	actor._delayed_pos = delayed_pos
	actor._delayed_vel = delayed_vel
	var relative: Vector2 = delayed_pos - Vector2(actor.pos)
	var lead: Vector2 = delayed_vel * clampf(relative.length() / 600.0, 0.1, 0.6)
	var aim_point: Vector2 = relative + lead
	var desired_aim: Vector2 = aim_point.normalized() if aim_point.length_squared() > 0.0001 else Vector2(actor.aim)
	desired_aim = desired_aim.rotated(_protect_bias(actor))
	actor.desired_aim = desired_aim
	if _should_retreat(actor):
		actor.desired = (-relative).normalized() if relative.length_squared() > 0.0001 else Vector2(actor.aim)
	else:
		var desired: Vector2 = relative.normalized() if relative.length_squared() > 0.0001 else Vector2(actor.aim)
		if relative.length() < 300.0: desired = desired.orthogonal()
		actor.desired = desired

## "Retreat when limbs are lost" - measured, not guessed: fewer than half the
## weapon circles authored at spawn remain attached and alive.
static func _should_retreat(actor: Dictionary) -> bool:
	var total: int = int(actor.get("gun_total", 0))
	if total <= 0: return false
	var alive: int = 0
	var hp: PackedFloat32Array = actor.get("part_hp", PackedFloat32Array())
	var attached: PackedByteArray = actor.get("part_attached", PackedByteArray())
	for i: int in actor.get("gun_indices", PackedInt32Array()):
		if i < hp.size() and hp[i] > 0.0 and (i >= attached.size() or bool(attached[i])): alive += 1
	return float(alive) < float(total) * RETREAT_LIMB_FRACTION

## "Protect the core when exposed": the side of the hull with the most
## surviving peripheral circles turns toward the threat, per the plan's own
## stated rule. `rig.rest[i].x` is the authored (unrotated) local x, so its
## sign is a stable left/right split independent of current facing or orbit
## motion.
static func _protect_bias(actor: Dictionary) -> float:
	var rig: ShipMotion.ShipRig = actor.get("rig")
	if rig == null: return 0.0
	var hp: PackedFloat32Array = actor.get("part_hp", PackedFloat32Array())
	var attached: PackedByteArray = actor.get("part_attached", PackedByteArray())
	var left: int = 0
	var right: int = 0
	for i: int in range(1, rig.ids.size()):
		if i >= hp.size() or hp[i] <= 0.0 or (i < attached.size() and not bool(attached[i])): continue
		if rig.rest[i].x < -0.5: left += 1
		elif rig.rest[i].x > 0.5: right += 1
	var total: int = left + right
	if total <= 0: return 0.0
	return clampf(float(right - left) / float(total), -1.0, 1.0) * PROTECT_BIAS_MAX_RAD

static func _steer(world, actor: Dictionary, dt: float, base_speed_fraction: float) -> void:
	var thrusters: float = 1.2 if world._has_ability(actor, "thrusters") else 1.0
	var desired_aim: Vector2 = actor.get("desired_aim", actor.aim)
	actor.aim = Vector2.from_angle(rotate_toward(Vector2(actor.aim).angle(), desired_aim.angle(), float(actor.turn_rate) * thrusters * dt))
	var speed: float = float(actor.speed) * thrusters * base_speed_fraction
	actor.vel = Vector2(actor.get("desired", Vector2.ZERO)) * speed * world._slow_multiplier(actor)
	actor.pos = world.arena.clamp_point(Vector2(actor.pos) + Vector2(actor.vel) * dt, 18.0)
