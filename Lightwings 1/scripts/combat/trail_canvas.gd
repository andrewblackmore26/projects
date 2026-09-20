extends Node2D
## Draws every live trail from a single `TrailPool` in one canvas item - no
## per-trail node (spec §23 "pooled segment buffers, not nodes"). Width is
## computed from the live canvas scale each draw, the same way
## `ship_renderer.gd` keeps rim/line widths constant in screen space at any
## zoom, so the warp's 1.30x zoom cannot thicken a trail.

var world: Node2D
var pool: TrailPool

func _draw() -> void:
	if pool == null: return
	var canvas_scale: float = maxf(0.01, get_global_transform_with_canvas().get_scale().abs().x)
	for id: Variant in pool.trails:
		_draw_trail(pool.trails[id], canvas_scale)

func _draw_trail(trail: TrailPool.Trail, canvas_scale: float) -> void:
	var points: PackedVector2Array = trail.points
	var count: int = points.size()
	if count < 2: return
	var fade: float = clampf(1.0 - trail.age / TrailPool.FADE_SECONDS, 0.0, 1.0)
	# Head (newest) is points[count-1]; tail (oldest) is points[0]. Step index
	# 0 must be the head, so walk backward - "segments stepping down" (§19),
	# no blur, no gradient: one draw_line per segment at its own stepped
	# width/alpha, breaking (not smoothing) at a dash kink.
	for i: int in range(count - 1, 0, -1):
		var step: int = count - 1 - i
		var width: float = TrailPool.width_for_step(trail.width, step, count) / canvas_scale
		var alpha: float = TrailPool.STEP_SCALES[clampi(step, 0, TrailPool.STEP_SCALES.size() - 1)] * fade
		var color: Color = trail.color
		color.a = alpha
		draw_line(points[i], points[i - 1], color, width, false)
		if trail.kinked.size() > i and bool(trail.kinked[i]):
			draw_circle(points[i], width * 1.4, Color(trail.color, alpha * 0.6))
