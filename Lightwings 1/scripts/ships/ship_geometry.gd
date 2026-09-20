class_name ShipGeometry
extends RefCounted
## Curves are sampled once, not once per frame. No raster art or fabricated glow.
## Exactly two primitives: a circle (filled disc or unfilled ring, bright rim,
## dark fill) and a line (straight, each end clipped at a circle's rim).

static func outline(shape: String, radius: float) -> PackedVector2Array:
	var p: PackedVector2Array = []
	if shape != "circle": return p
	var count: int = 48
	var start: float = -PI * 0.5
	for i: int in range(count + 1):
		p.append(Vector2.from_angle(start + TAU * float(i) / float(count)) * radius)
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

static func clipped_line(from: Dictionary, to: Dictionary) -> PackedVector2Array:
	var start: Vector2 = from.position
	var finish: Vector2 = to.position
	var direction: Vector2 = (finish - start).normalized()
	var left: float = float(from.radius)
	var right: float = float(to.radius)
	if start.distance_to(finish) <= left + right: return PackedVector2Array()
	return PackedVector2Array([start + direction * left, finish - direction * right])
