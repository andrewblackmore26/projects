extends RefCounted

## Frame-local broad/narrow-phase data. Actor dictionaries remain authoritative.
var actor: Dictionary
var id: int
var faction: int
var position: Vector2
var is_void: bool
var mouth_offset: Vector2
var slow_radius_squared: float = 0.0
var satellites: PackedVector2Array = PackedVector2Array()

func interception_t(from: Vector2, to: Vector2, radius: float) -> float:
	var earliest: float = INF
	if is_void and int(actor.stored) < 10:
		var mouth_t: float = LightBulletPool.segment_circle_t(from, to, position + mouth_offset, 9.0 + radius)
		if mouth_t >= 0.0:
			earliest = mouth_t
	for offset: Vector2 in satellites:
		var satellite_t: float = LightBulletPool.segment_circle_t(from, to, position + offset, 6.0 + radius)
		if satellite_t >= 0.0:
			earliest = minf(earliest, satellite_t)
	return -1.0 if earliest == INF else earliest
