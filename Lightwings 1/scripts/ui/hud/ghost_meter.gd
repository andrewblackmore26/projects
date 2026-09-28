class_name GhostMeter
extends RefCounted
## The motion model of one HUD meter (modernization M11b): the light bar and every boss-bar
## segment. Pure: `step(sim_value, dt)` once per frame with the value the sim holds NOW, then draw
## from `value`, `ghost` and `lead`. dt is real (UI) time, so hitstop and slow motion never slow it.
##
## - `value`, the fill, rides a critically damped spring toward the sim value. It is integrated in
##   closed form, so it lands the same at 30, 60 or 144 Hz.
## - `ghost`, the LOSS ghost: on a loss it stays where the fill was for HOLD s, then drains to the
##   fill over DRAIN s. A second loss during the hold restarts the hold from the ghost's top.
## - `lead`, the GAIN lead: on a gain it jumps to the new value at once and the fill catches it;
##   CATCH is the time the spring needs to close 98 % of a gain (tests/hud_model_test.gd measures it).

const HOLD: float = 0.35
const DRAIN: float = 0.40
const CATCH: float = 0.25
## The spring. UiTokens.SPRING_OMEGA (18) closes only 94 % of a gain in CATCH; 24 closes 98.3 %
## ((1 + 6) e^-6 = 0.017). hud_model_test's control runs the token omega and misses CATCH.
const OMEGA: float = 24.0
## Below this a difference is noise, not a loss or a gain.
const EPSILON: float = 0.0001

var omega: float = OMEGA
## Negative control (hud_model_test): the ghost follows the fill, as if there were none.
var ghost_enabled: bool = true
var value: float = 0.0
var velocity: float = 0.0
var target: float = 0.0
var ghost: float = 0.0
var lead: float = 0.0
var _hold_left: float = 0.0
var _drain_elapsed: float = -1.0
var _drain_from: float = 0.0
var _started: bool = false

## Snaps every part to `at` (a new run, a new tier's scale, a capture).
func reset(at: float) -> void:
	value = at
	velocity = 0.0
	target = at
	ghost = at
	lead = at
	_hold_left = 0.0
	_drain_elapsed = -1.0
	_started = true

func started() -> bool:
	return _started

func step(sim_value: float, dt: float) -> void:
	if not _started:
		reset(sim_value)
		return
	if sim_value < target - EPSILON:
		# A loss: the ghost marks where the fill stood and holds there.
		ghost = maxf(ghost, maxf(value, target))
		_hold_left = HOLD
		_drain_elapsed = -1.0
	target = sim_value
	_spring(dt)
	# The lead is the sim value while the fill is still climbing to it, and spent once it arrives
	# (after a loss the fill is above the sim value: no lead).
	lead = maxf(target, value)
	if not ghost_enabled:
		ghost = value
		return
	if ghost <= value + EPSILON:
		ghost = value
		_drain_elapsed = -1.0
		return
	if _hold_left > 0.0:
		_hold_left -= dt
		if _hold_left > 0.0: return
		# The drain starts inside this frame: carry the frame's remainder into it.
		_drain_elapsed = -_hold_left
		_hold_left = 0.0
		_drain_from = ghost
	elif _drain_elapsed < 0.0:
		_drain_elapsed = 0.0
		_drain_from = ghost
	else:
		_drain_elapsed += dt
	var t: float = clampf(_drain_elapsed / DRAIN, 0.0, 1.0)
	# In-cubic out (UiTokens' exit easing) would hide the start of the drain; a smoothstep reads
	# as "it let go" and still lands exactly at DRAIN.
	ghost = lerpf(_drain_from, value, t * t * (3.0 - 2.0 * t))
	if t >= 1.0: ghost = value

## The spring's exact solution over dt with the target held.
func _spring(dt: float) -> void:
	if dt <= 0.0: return
	var error: float = value - target
	var decay: float = exp(-omega * dt)
	var carry: float = velocity + omega * error
	value = target + (error + carry * dt) * decay
	velocity = (velocity - omega * carry * dt) * decay
	if absf(value - target) < EPSILON and absf(velocity) < EPSILON:
		value = target
		velocity = 0.0

## True while the loss ghost shows a segment.
func ghost_visible() -> bool:
	return ghost > value + EPSILON

func lead_visible() -> bool:
	return lead > value + EPSILON
