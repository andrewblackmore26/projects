extends RefCounted
## Rotation-invariant structure probes for an sRGB image of a rail ship. Rails rotate, so a pixel
## diff against the reference means nothing; what can be compared is WHAT sits on each ring.
## A probe walks a circle and looks for bright LOBES. A cluster circle subtends 15-27 degrees of its
## ring; a spoke or a rail dash about 2. Counting only wide lobes leaves the clusters.

const SAMPLES: int = 720
const BRIGHT: float = 0.45 # max channel, sRGB 0..1: a rim, a line or a running light
const CHROMA: float = 0.25 # Subdued green/blue remain colours; neutral text and core whites do not.
## "Inside a shape": rim OR fill, against the background. The first version looked for BRIGHT lobes
## and found none - a circle here is a dark fill inside a thin bright rim, so a ring crossing it
## sees two 2-degree rim hits, not one wide lobe. Measured: background max channel 0.08, fill 0.16.
const SHAPE: float = 0.12

static func _lit(image: Image, at: Vector2, band: int, level: float = SHAPE) -> bool:
	for dy: int in range(-band, band + 1):
		for dx: int in range(-band, band + 1):
			var x: int = int(round(at.x)) + dx
			var y: int = int(round(at.y)) + dy
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			var pixel: Color = image.get_pixel(x, y)
			if maxf(pixel.r, maxf(pixel.g, pixel.b)) > level: return true
	return false

## Centres (radians, clockwise from up) of the lobes at least `min_width` radians wide on the
## circle of `radius` px about `centre`.
static func lobes(image: Image, centre: Vector2, radius: float, band: int, min_width: float) -> PackedFloat32Array:
	var lit: PackedByteArray = PackedByteArray()
	lit.resize(SAMPLES)
	var any_dark: int = -1
	for i: int in range(SAMPLES):
		var angle: float = TAU * float(i) / float(SAMPLES)
		lit[i] = 1 if _lit(image, centre + Vector2(sin(angle), -cos(angle)) * radius, band) else 0
		if lit[i] == 0 and any_dark < 0: any_dark = i
	var found: PackedFloat32Array = PackedFloat32Array()
	if any_dark < 0: return found # lit all the way round: not a lobe pattern
	var run_start: int = -1
	for step: int in range(1, SAMPLES + 1):
		var i: int = (any_dark + step) % SAMPLES
		if lit[i] == 1 and run_start < 0: run_start = step
		if lit[i] == 0 and run_start >= 0:
			var width: float = TAU * float(step - run_start) / float(SAMPLES)
			if width >= min_width: found.append(fposmod(TAU * (float(any_dark) + float(run_start + step) * 0.5) / float(SAMPLES), TAU))
			run_start = -1
	return found

## Counts saturated bright pixels by colour family. Pale pixels (running lights) are ignored.
static func colour_census(image: Image, region: Rect2i) -> Dictionary:
	var census: Dictionary = {"amber": 0, "red": 0, "other": 0}
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			var pixel: Color = image.get_pixel(x, y)
			if pixel.v < BRIGHT or pixel.s < CHROMA: continue
			if pixel.h < 0.055 or pixel.h > 0.95: census.red += 1
			elif pixel.h < 0.20: census.amber += 1
			else: census.other += 1
	return census

static func count_red(image: Image, centre: Vector2, radius: float) -> int:
	var r: int = int(ceil(radius))
	var total: int = 0
	for y: int in range(int(centre.y) - r, int(centre.y) + r + 1):
		for x: int in range(int(centre.x) - r, int(centre.x) + r + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			if Vector2(x, y).distance_to(centre) > radius: continue
			var pixel: Color = image.get_pixel(x, y)
			if pixel.v >= BRIGHT and pixel.s >= CHROMA and (pixel.h < 0.055 or pixel.h > 0.95): total += 1
	return total

## The structural signature the reference comparison is made of. `scale` is px per ship unit.
static func signature(image: Image, centre: Vector2, scale: float) -> Dictionary:
	var result: Dictionary = {}
	# The core rim must be where the scale says it is, or every other probe samples garbage.
	# The rim is BRIGHT at 34 units; just inside is fill and just outside is background, neither bright.
	result.core_rim = _lit(image, centre + Vector2(34.0 * scale, 0), 1, BRIGHT) and not _lit(image, centre + Vector2(28.0 * scale, 0), 1, BRIGHT) and not _lit(image, centre + Vector2(41.0 * scale, 0), 1, BRIGHT)
	result.inner = lobes(image, centre, 52.0 * scale, 0, 0.17).size()
	var hubs: PackedFloat32Array = lobes(image, centre, 94.5 * scale, 0, 0.17)
	result.outer = hubs.size()
	var pods: Array[int] = []
	var armed: int = 0
	for angle: float in hubs:
		# The reference's hubs orbit at 92.9 and ours at 96; 94.5 sits inside both discs.
		var hub: Vector2 = centre + Vector2(sin(angle), -cos(angle)) * 94.5 * scale
		pods.append(lobes(image, hub, 30.0 * scale, 0, 0.22).size())
		if count_red(image, hub, 34.0 * scale) >= 12: armed += 1
	pods.sort()
	result.pods = pods
	result.armed_hubs = armed
	result.accent_core = count_red(image, centre, 9.0 * scale) >= 12
	var census: Dictionary = colour_census(image, Rect2i(0, 0, image.get_width(), image.get_height()))
	result.third_colour = int(census.other) > 30
	result.two_colours = int(census.amber) > 200 and int(census.red) > 50
	return result
