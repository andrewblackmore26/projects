class_name TrailPool
extends RefCounted
## Lightstream trails (spec v0.3 §13/§19/§23). Pooled SEGMENT BUFFERS, not
## nodes: every live trail is a small ring buffer of recent world positions
## kept in one Dictionary, drawn by one canvas (`trail_canvas.gd`), never a
## per-trail scene node. Budget 40 simultaneous trails (§23); past that, the
## LOWEST-PRIORITY trail is evicted and the drop is counted in
## `dropped_count`, so the budget is observable rather than silent
## (tasks/lessons.md "a budget nobody measured is an assertion").
##
## Width and opacity taper toward the tail in discrete STEPS (§19: "no blur,
## no gradient, just segments stepping down"); the actual line width is
## computed by the renderer from `width_for_step`, divided by the live
## canvas scale there so it stays constant in screen space at any zoom (§23).
##
## Length is an explicit ARC-LENGTH cap passed at request time (camera/movement
## spec §5: 0 px at rest, 180 at top speed, 320 in a dash; M7). The oldest
## segment is shortened, not dropped, so the trail is exactly the cap long
## and shrinks back to nothing at rest. Before M7 the length fell out of a
## fixed point count x the sampling distance, so a ship that stopped kept its
## whole trail forever. `max_points` only bounds the buffer: it must hold the
## longest cap at `MIN_SAMPLE_DISTANCE` spacing.

const MAX_TRAILS: int = 40
const MIN_SAMPLE_DISTANCE: float = 6.0
const FADE_SECONDS: float = 0.35
const PLAYER_MAX_POINTS: int = 56 # 320 px / 6 px + head and tail
const ENEMY_MAX_POINTS: int = 7
const STEP_SCALES: PackedFloat32Array = [1.0, 0.82, 0.64, 0.46, 0.3, 0.16]

class Trail:
	var priority: float = 0.0
	var points: PackedVector2Array = PackedVector2Array()
	var kinked: PackedByteArray = PackedByteArray()
	var max_points: int = PLAYER_MAX_POINTS
	var width: float = 2.6
	var color: Color = Color.WHITE
	var age: float = 0.0
	var touched: bool = true

var trails: Dictionary = {}
var dropped_count: int = 0

## Called at most once per tick per potential owner. `priority` decides who
## survives when the pool is over budget (the player should pass an
## effectively-unbounded priority so it is never the one dropped).
func request(owner_id: int, position: Vector2, priority: float, width: float, color: Color, max_points: int = PLAYER_MAX_POINTS, max_length: float = INF) -> void:
	var trail: Trail = trails.get(owner_id)
	if trail == null:
		if trails.size() >= MAX_TRAILS:
			dropped_count += 1
			var evicted: int = _lowest_priority_id()
			if evicted == -1 or priority <= float(trails[evicted].priority):
				return # the INCOMING trail is the one that gets dropped
			trails.erase(evicted)
		trail = Trail.new()
		trails[owner_id] = trail
	trail.priority = priority
	trail.width = width
	trail.color = color
	trail.max_points = max_points
	trail.age = 0.0
	trail.touched = true
	if trail.points.is_empty() or trail.points[trail.points.size() - 1].distance_to(position) >= MIN_SAMPLE_DISTANCE:
		trail.points.append(position)
		trail.kinked.append(0)
		while trail.points.size() > trail.max_points:
			trail.points.remove_at(0)
			trail.kinked.remove_at(0)
	_cap_length(trail, max_length)

## Trims the TAIL until the polyline is at most `max_length` long, moving the last kept tail point
## along its segment so the length is exact rather than a whole segment short.
static func _cap_length(trail: Trail, max_length: float) -> void:
	if max_length == INF: return
	var total: float = 0.0
	for i: int in range(1, trail.points.size()): total += trail.points[i - 1].distance_to(trail.points[i])
	while total > max_length and trail.points.size() >= 2:
		var segment: float = trail.points[0].distance_to(trail.points[1])
		if total - segment >= max_length or segment <= 0.000001:
			trail.points.remove_at(0)
			trail.kinked.remove_at(0)
			total -= segment
		else:
			trail.points[0] = trail.points[0].move_toward(trail.points[1], total - max_length)
			total = max_length

## Dash (spec §13/§19): "a hard kink in the trail" - marks the most recent
## sample point of `owner_id`'s trail, so the renderer can break the smooth
## taper there instead of smoothing across the burst.
func kink(owner_id: int) -> void:
	var trail: Trail = trails.get(owner_id)
	if trail != null and trail.kinked.size() > 0: trail.kinked[trail.kinked.size() - 1] = 1

## Called once per physics tick. Untouched trails (their owner did not
## `request` this tick - dead, off-screen, cleared encounter) fade out and
## are removed after `FADE_SECONDS`, freeing their budget slot.
func update(dt: float) -> void:
	var stale: Array = []
	for id: Variant in trails:
		var trail: Trail = trails[id]
		if not trail.touched:
			trail.age += dt
			if trail.age >= FADE_SECONDS or trail.points.size() < 2: stale.append(id)
		trail.touched = false
	for id: Variant in stale: trails.erase(id)

func clear() -> void:
	trails.clear()

func live_count() -> int: return trails.size()

func _lowest_priority_id() -> int:
	var best: int = -1
	var best_priority: float = INF
	for id: Variant in trails:
		var p: float = float(trails[id].priority)
		if p < best_priority:
			best_priority = p
			best = int(id)
	return best

## `step_index` 0 is the head (brightest/widest), `step_count-1` the tail.
static func width_for_step(base_width: float, step_index: int, step_count: int) -> float:
	if step_count <= 1: return base_width
	var t: float = float(step_index) / float(step_count - 1)
	var scale_index: int = clampi(roundi(t * float(STEP_SCALES.size() - 1)), 0, STEP_SCALES.size() - 1)
	return base_width * STEP_SCALES[scale_index]
