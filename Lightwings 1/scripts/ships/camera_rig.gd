class_name CameraRig
extends RefCounted
## M10: the trailing camera of docs/LIGHTSHIP_CAMERA_MOVEMENT_SPEC.md §6-§7, as pure maths with no
## node, clock or input of its own. The compositor steps it once per SIM tick with the sim's dt
## (spec preamble: "Where the camera steps"), so the ship never judders against the world and the
## maths is the same at 30, 60 or 144 Hz. Every number is a GameTuning.feel() key, read per step.
##
## Three layers, each with its own `*_on` switch so the §9 order can be tuned one at a time:
## - lag (§6.1): a point that chases the ship with time constant `cam.lag_tau`, blended toward the
##   faster `cam.recentre_s`/3 as the ship slows, and hard-clamped to `cam.lag_clamp` of the
##   half-width. At speed the ship sits AHEAD of screen centre;
## - speed zoom (§6.2): 1.00 at rest, `cam.zoom_top` at top speed, `cam.zoom_dash` at dash peak;
## - aim (§6.3): `cam.aim_frac` of the half-width toward the SHIP's aim (never the mouse, which
##   would feed the camera back into the aim it is used to compute).
## The sum of lag and aim is clamped to `cam.total_clamp`. Screen-space fractions are converted to
## world px through the current zoom, so a clamp means the same thing on screen at every zoom.

## The reference half-width every screen fraction is taken of: the 16:10 design width over 2. Kept
## fixed under M6's "expand" stretch on purpose. The logical height is 800 at every aspect and the
## clamps are RADIAL (limit_length), so scaling this with a 21:9 window would let the ship drift
## further vertically on wide monitors. One number keeps the feel identical on every display.
const HALF_WIDTH: float = 640.0
## A ship step longer than this in one tick is a teleport (the warp's node swap), not flight: the
## camera jumps with it, so the player sees the lag and never the swap.
const TELEPORT_PX: float = 400.0

## The lagging point, in world px.
var center: Vector2 = Vector2.ZERO
var aim_offset: Vector2 = Vector2.ZERO
var zoom: float = 1.0
## The world point drawn at screen centre: lag plus aim, clamped. What the compositor reads.
var focus: Vector2 = Vector2.ZERO
var ship: Vector2 = Vector2.ZERO

func reset(at: Vector2) -> void:
	center = at
	ship = at
	focus = at
	aim_offset = Vector2.ZERO
	zoom = 1.0

## The ship's offset from screen centre in SCREEN px (what "the ship sits ahead" means on screen).
func ship_screen_offset() -> Vector2:
	return (ship - focus) * zoom

## `mode` is the warp phase's camera override (§7): &"" or &"arrival" is ordinary flight, &"push"
## raises the smoothing so the camera falls behind, &"break" keeps it and snaps the zoom, &"warp"
## whips the camera past the ship with the short smoothing and an overshoot.
func step(dt: float, at: Vector2, velocity: Vector2, aim: Vector2, top_speed: float, mode: StringName = &"") -> void:
	if dt <= 0.0: return
	if at.distance_to(ship) > TELEPORT_PX:
		center += at - ship
		ship = at
	# The ship's own displacement this step, as a rate: the lag below is integrated EXACTLY for a
	# target moving at this rate, so the result is the same at any tick rate (acceptance test 7).
	var rate: Vector2 = (at - ship) / dt
	ship = at
	var speed_frac: float = velocity.length() / maxf(1.0, top_speed)
	_step_zoom(dt, speed_frac, mode)
	var half: float = HALF_WIDTH / maxf(0.01, zoom)
	if GameTuning.feel("cam.lag_on") > 0.5:
		var blend: float = clampf(speed_frac / maxf(0.001, GameTuning.feel("cam.recentre_speed_frac")), 0.0, 1.0)
		var tau: float = lerpf(GameTuning.feel("cam.recentre_s") / 3.0, GameTuning.feel("cam.lag_tau"), blend)
		var target: Vector2 = at
		match mode:
			&"push", &"break":
				tau = GameTuning.feel("cam.push_lag_tau")
			&"warp":
				tau = GameTuning.feel("cam.warp_lag_tau")
				if velocity.length_squared() > 0.0001: target = at + velocity.normalized() * GameTuning.feel("cam.overshoot") * half
		# Lag L = target - center obeys dL/dt = rate - L/tau: L(dt) = rate*tau + (L0 - rate*tau)*e^(-dt/tau).
		tau = maxf(0.0001, tau)
		var lag: Vector2 = target - rate * dt - center
		lag = rate * tau + (lag - rate * tau) * exp(-dt / tau)
		center = target - lag
		center = at + (center - at).limit_length(GameTuning.feel("cam.lag_clamp") * half)
	else:
		center = at
	var aim_target: Vector2 = Vector2.ZERO
	if GameTuning.feel("cam.aim_on") > 0.5 and aim.length_squared() > 0.0001:
		aim_target = aim.normalized() * GameTuning.feel("cam.aim_frac") * half
	aim_offset = aim_target + (aim_offset - aim_target) * exp(-dt / maxf(0.0001, GameTuning.feel("cam.aim_tau")))
	focus = at + (center - at + aim_offset).limit_length(GameTuning.feel("cam.total_clamp") * half)

func _step_zoom(dt: float, speed_frac: float, mode: StringName) -> void:
	var target: float = 1.0
	var zoom_on: bool = GameTuning.feel("cam.zoom_on") > 0.5
	if zoom_on:
		var top: float = GameTuning.feel("cam.zoom_top")
		if speed_frac <= 1.0:
			target = lerpf(1.0, top, speed_frac)
		else:
			var dash_ratio: float = maxf(1.001, GameTuning.feel("dash.peak_ratio"))
			target = lerpf(top, GameTuning.feel("cam.zoom_dash"), clampf((speed_frac - 1.0) / (dash_ratio - 1.0), 0.0, 1.0))
		match mode:
			&"push": target = GameTuning.feel("cam.push_zoom")
			&"break", &"warp": target = GameTuning.feel("cam.break_zoom")
	if mode == &"break" and zoom_on:
		zoom = target
		return
	# "Ease in over 0.40 s, ease out over 0.25 s" are 95 % settle times, so tau = seconds / 3.
	var seconds: float = GameTuning.feel("cam.zoom_in_s") if target < zoom else GameTuning.feel("cam.zoom_out_s")
	zoom = target + (zoom - target) * exp(-dt / maxf(0.0001, seconds / 3.0))
