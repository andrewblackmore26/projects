class_name ShipGeometry
extends RefCounted
## Curves are sampled once, not once per frame. No raster art or fabricated glow.

static func outline(shape: String, size: Vector2) -> PackedVector2Array:
	var p: PackedVector2Array = []
	var half: Vector2 = size * 0.5
	match shape:
		"circle", "ellipse", "ring", "arc":
			var count: int = 48
			var start: float = -PI * 0.5
			var sweep: float = TAU
			if shape == "arc":
				count = 14
				sweep = PI * 0.36
				start = -PI * 0.68
			for i: int in range(count + 1):
				p.append(Vector2.from_angle(start + sweep * float(i) / float(count)) * half)
		"crescent":
			# A circle minus a smaller offset circle, open toward the nose.
			var radius: float = 1.0
			var inner: float = 0.84
			var offset: float = 0.42
			var y: float = (inner * inner - radius * radius - offset * offset) / (2.0 * offset)
			var x: float = sqrt(maxf(0, 1.0 - y * y))
			var a: float = atan2(y, x)
			for i: int in range(37):
				p.append(Vector2.from_angle(lerpf(a, PI - a, float(i) / 36.0)) * half)
			var inner_start: float = atan2(y + offset, -x)
			if inner_start < 0:
				inner_start += TAU
			var inner_end: float = atan2(y + offset, x)
			for i: int in range(1, 37):
				p.append((Vector2.from_angle(lerpf(inner_start, inner_end, float(i) / 36.0)) * inner + Vector2(0, -offset)) * half)
			p.append(p[0])
	return p

static func lengths(points: PackedVector2Array) -> PackedFloat32Array:
	var result: PackedFloat32Array = [0.0]
	for i: int in range(1, points.size()):
		result.append(result[-1] + points[i].distance_to(points[i - 1]))
	return result

static func section(points: PackedVector2Array, distances: PackedFloat32Array, from: float, to: float) -> PackedVector2Array:
	var result: PackedVector2Array = []
	if points.size() < 2 or distances.size() != points.size():
		return result
	var first_index: int = maxi(1, distances.bsearch(from))
	var last_index: int = mini(points.size() - 1, distances.bsearch(to))
	for i: int in range(first_index, last_index + 1):
		var low: float = distances[i - 1]
		var high: float = distances[i]
		if high < from or low > to or high - low < 0.0001:
			continue
		var first: Vector2 = points[i - 1].lerp(points[i], clampf((from - low) / (high - low), 0, 1))
		var last: Vector2 = points[i - 1].lerp(points[i], clampf((to - low) / (high - low), 0, 1))
		if result.is_empty() or not result[-1].is_equal_approx(first):
			result.append(first)
		result.append(last)
	return result

static func rim_distance(size: Vector2, rotation: float, direction: Vector2) -> float:
	var local: Vector2 = direction.rotated(-rotation)
	var half: Vector2 = size * 0.5
	return 1.0 / maxf(0.001, sqrt(pow(local.x / maxf(half.x, 0.001), 2) + pow(local.y / maxf(half.y, 0.001), 2)))

static func clipped_tether(from: Dictionary, to: Dictionary) -> PackedVector2Array:
	var start: Vector2 = from.position
	var finish: Vector2 = to.position
	var direction: Vector2 = (finish - start).normalized()
	var left: float = rim_distance(from.size, float(from.rotation), direction)
	var right: float = rim_distance(to.size, float(to.rotation), -direction)
	if start.distance_to(finish) <= left + right: return PackedVector2Array()
	return PackedVector2Array([start + direction * left, finish - direction * right])
