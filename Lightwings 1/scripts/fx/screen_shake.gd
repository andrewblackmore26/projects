class_name ScreenShake
extends RefCounted
## M10: screen shake, docs/LIGHTSHIP_CAMERA_MOVEMENT_SPEC.md §6.5 ("keep it small; this is a game
## about reading bullets"). Trauma-squared: an event starts a trauma of 1 that falls linearly to 0
## over its duration and shakes by amplitude * trauma^2, so it bites and then fades. Concurrent
## events take the MAX amplitude, never the sum: a hit during a dash still reads as a 4 px hit.
##
## Deterministic: the noise is hashed from this object's step count, never a clock or a shared RNG,
## so the same events stepped the same way shake the same way. Presentation only: the compositor
## applies `offset`/`rotation` after the camera clamp, and `screen_to_world` never sees them, so the
## aim a player computes from the mouse cannot jitter.

## feel_event kind -> its §6.5 row (GameTuning keys "shake.<row>.px" and "shake.<row>.s").
const ROWS: Dictionary = {&"dash": "dash", &"player_hit": "hit", &"regression": "regression", &"elite_limb": "limb", &"boss_kill": "boss_death"}
## The noise takes a new value every NOISE_STEPS steps and eases between them (30 Hz at a 60 Hz sim),
## a shake rather than a per-tick buzz.
const NOISE_STEPS: int = 2

## The player's `screen_shake` setting, 0..1.
var intensity: float = 1.0
## Reduced motion zeroes the shake outright.
var reduced_motion: bool = false
var offset: Vector2 = Vector2.ZERO
var rotation: float = 0.0
var steps: int = 0
## One per live event: x amplitude px, y duration s, z age s.
var _active: Array[Vector3] = []

## False for a kind with no §6.5 row, or a row tuned to zero length.
func add(kind: StringName) -> bool:
	if not ROWS.has(kind): return false
	var row: String = ROWS[kind]
	var seconds: float = GameTuning.feel("shake.%s.s" % row)
	if seconds <= 0.0: return false
	_active.append(Vector3(GameTuning.feel("shake.%s.px" % row), seconds, 0.0))
	return true

func clear() -> void:
	_active.clear()
	offset = Vector2.ZERO
	rotation = 0.0

## The settings scale: 0 under reduced motion or with the layer switched off.
func scale() -> float:
	if reduced_motion or GameTuning.feel("shake.on") <= 0.5: return 0.0
	return clampf(intensity, 0.0, 1.0)

## Screen px, after the settings scale. The loudest live event, not the sum.
func amplitude() -> float:
	var loudest: float = 0.0
	for shake: Vector3 in _active:
		var trauma: float = 1.0 - clampf(shake.z / shake.y, 0.0, 1.0)
		loudest = maxf(loudest, shake.x * trauma * trauma)
	return loudest * scale()

## Sets `offset`/`rotation` from the events' current ages, then ages them by `dt`, so the first step
## after an event shakes at its full amplitude.
func step(dt: float) -> void:
	var amount: float = amplitude()
	if amount > 0.0:
		offset = Vector2(_noise(0), _noise(1)).limit_length(1.0) * amount
		rotation = _noise(2) * amount * GameTuning.feel("shake.rotation_per_px")
	else:
		offset = Vector2.ZERO
		rotation = 0.0
	steps += 1
	for index: int in range(_active.size() - 1, -1, -1):
		var shake: Vector3 = _active[index]
		shake.z += dt
		if shake.z >= shake.y: _active.remove_at(index)
		else: _active[index] = shake

func _noise(axis: int) -> float:
	var cell: int = steps / NOISE_STEPS
	var t: float = smoothstep(0.0, 1.0, float(steps % NOISE_STEPS) / float(NOISE_STEPS))
	return lerpf(_hash_signed(cell * 3 + axis), _hash_signed((cell + 1) * 3 + axis), t)

## An integer hash (lowbias32) mapped to [-1, 1]. Pure arithmetic, so it is the same on every run.
static func _hash_signed(n: int) -> float:
	var x: int = n & 0xffffffff
	x = ((x ^ (x >> 16)) * 0x7feb352d) & 0xffffffff
	x = ((x ^ (x >> 15)) * 0x846ca68b) & 0xffffffff
	x = x ^ (x >> 16)
	return float(x & 0xffff) / 32767.5 - 1.0
