extends SceneTree
## Modernization M12, real Vulkan pixels: the evolved hull assembles core-out through the render-only
## `assembly_t` uniform (shaders/ship_outline.gdshader, uploaded by ShipRenderer).
## - the RIM of the hull's outermost circle (sampled on its stroke, not its fill or centre - lessons:
##   sample where the effect is) is lit at assembly_t 1 and dark at assembly_t 0;
## - at MID (0.65) the rim of the off-centre circle with the smallest reach is already lit while the
##   outermost is still dark: the hull builds from the core out;
## - assembly_t 1 is the default and draws the same pixels as a renderer that never heard of it.
## Control, per line: the uniform never uploaded (ShipRenderer.assembly_upload_enabled = false), so
## the shader keeps its default 1 whatever assembly_t says.
## Headless compiles no shaders and a failed shader renders black (lessons), so this needs a window;
## tools/test.ps1 greps the log for SHADER ERROR.

const Harness = preload("res://tests/support/harness.gd")
const HULL: String = "player_lightning_t3_standard_a"
const AT: Vector2 = Vector2(640, 400)
const SCALE: float = 2.0
## Where the wavefront (band 0.35) has fully built a circle of reach 0.44 and not yet started one of
## reach 1: (0.65 x 1.35 - 0.44) / 0.35 > 1 and 0.65 x 1.35 < 1.
const MID: float = 0.65

var t: RefCounted
var scene: Node2D
var outer_rim: Vector2i
var inner_rim: Vector2i

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("EVOLUTION ASSEMBLY PIXELS")
	root.size = Vector2i(1280, 800)
	root.use_hdr_2d = true
	scene = Node2D.new()
	root.add_child(scene)
	var ship: ShipDefinition = ShipCatalog.get_ship(HULL)
	if not t.check(ship != null, "The hull %s exists" % HULL):
		t.finish(self)
		return
	_pick_samples(ship)
	var built: Image = await _capture(ship, 1.0, true, 0.0)
	var bare: Image = await _capture(ship, 1.0, false)
	var mid: Image = await _capture(ship, MID, true, 1.0)
	var empty: Image = await _capture(ship, 0.0, true, 1.0)
	var outer_built: float = _rim(built, outer_rim)
	var outer_empty: float = _rim(empty, outer_rim)
	var outer_mid: float = _rim(mid, outer_rim)
	var inner_mid: float = _rim(mid, inner_rim)
	var inner_built: float = _rim(built, inner_rim)
	print("measure: outer rim %s luma %.3f at t=1, %.3f at t=%.2f, %.3f at t=0; inner rim %s %.3f at t=1, %.3f at t=%.2f" % [outer_rim, outer_built, outer_mid, MID, outer_empty, inner_rim, inner_built, inner_mid, MID])
	t.check(_differs(outer_built, outer_empty), "The outer rim is lit at assembly_t 1 (%.3f) and dark at 0 (%.3f)" % [outer_built, outer_empty])
	t.check(_core_out(inner_mid, inner_built, outer_mid, outer_built), "At t=0.65 the inner rim is lit (%.3f of %.3f) while the outer is not (%.3f of %.3f): core-out" % [inner_mid, inner_built, outer_mid, outer_built])
	t.check(_same(built, bare), "assembly_t 1 draws exactly what a renderer that never set it draws")
	_save(built, "assembly_t1")
	_save(mid, "assembly_t065")
	_save(empty, "assembly_t0")
	# Control: the uniform is never uploaded.
	ShipRenderer.assembly_upload_enabled = false
	var stuck_empty: Image = await _capture(ship, 0.0, true, 1.0)
	var stuck_mid: Image = await _capture(ship, MID, true, 1.0)
	ShipRenderer.assembly_upload_enabled = true
	t.control("assembly_t never uploaded (outer rim %.3f at t=0)" % _rim(stuck_empty, outer_rim), not _differs(outer_built, _rim(stuck_empty, outer_rim)))
	t.control("assembly_t never uploaded (outer rim %.3f at t=0.65)" % _rim(stuck_mid, outer_rim), not _core_out(_rim(stuck_mid, inner_rim), inner_built, _rim(stuck_mid, outer_rim), outer_built))
	scene.queue_free()
	await process_frame
	t.finish(self)

func _differs(lit: float, dark: float) -> bool:
	return lit > 0.3 and dark < lit * 0.25

func _core_out(inner_mid: float, inner_built: float, outer_mid: float, outer_built: float) -> bool:
	return inner_mid > inner_built * 0.5 and outer_mid < outer_built * 0.25

func _same(a: Image, b: Image) -> bool:
	var worst: float = 0.0
	for y: int in range(200, 600, 2):
		for x: int in range(440, 840, 2):
			var d: Color = a.get_pixel(x, y) - b.get_pixel(x, y)
			worst = maxf(worst, absf(d.r) + absf(d.g) + absf(d.b))
	return worst < 0.02

## The circle with the largest reach (centre distance + radius, the shader's own order) and the
## off-centre circle with the smallest, each sampled on its rim on the side facing away from the
## ship's centre. Circles centred on the core (its rings) are skipped for the inner one: their
## "outward" side is arbitrary.
func _pick_samples(ship: ShipDefinition) -> void:
	var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
	var outer: int = -1
	var inner: int = -1
	for i: int in range(rig.rest.size()):
		var reach: float = rig.rest[i].length() + rig.radius[i]
		if rig.radius[i] < 2.5: continue
		if outer < 0 or reach > rig.rest[outer].length() + rig.radius[outer]: outer = i
		if rig.rest[i].length() > ship.core_radius + rig.radius[i] and (inner < 0 or reach < rig.rest[inner].length() + rig.radius[inner]): inner = i
	# At rest: the tick-0 pose of this hull draws every circle at its authored position (the
	# captures confirm it), while pose.local is in the rig's own frame.
	outer_rim = _rim_point(rig.rest[outer], rig.radius[outer])
	inner_rim = _rim_point(rig.rest[inner], rig.radius[inner]) if inner >= 0 else outer_rim
	var extent: float = rig.rest[outer].length() + rig.radius[outer]
	t.check(inner >= 0, "The hull has an off-centre circle to watch near its core (%s, reach %.0f of %.0f)" % [rig.ids[inner] if inner >= 0 else "none", (rig.rest[inner].length() + rig.radius[inner]) if inner >= 0 else 0.0, extent])

func _rim_point(center: Vector2, radius: float) -> Vector2i:
	var outward: Vector2 = center.normalized() if center.length() > 0.01 else Vector2.UP
	return Vector2i((AT + (center + outward * radius) * SCALE).round())

## A frame of `ship` at `assembly`. `from` >= 0 first draws it at that value and then moves it, the
## way EvolutionTransform animates it (so the upload of each change is exercised, not only the
## value set_ship uploads); `set_it` false never touches assembly_t at all.
func _capture(ship: ShipDefinition, assembly: float, set_it: bool = true, from: float = -1.0) -> Image:
	var renderer := ShipRenderer.new()
	scene.add_child(renderer)
	renderer.position = AT
	renderer.visual_scale = SCALE
	renderer.set_ship(ship)
	renderer.set_process(false)
	renderer.set_motion_tick(0)
	if set_it and from >= 0.0:
		renderer.assembly_t = from
		renderer._process(0.0)
		await process_frame
	if set_it: renderer.assembly_t = assembly
	renderer._process(0.0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	renderer.queue_free()
	await process_frame
	await process_frame
	return image

## The brightest luma in a 5x5 patch around `at`: the stroke is ~1.5 px wide and its exact pixel
## depends on rasterisation, so a patch, integrated as its maximum.
func _rim(image: Image, at: Vector2i) -> float:
	var best: float = 0.0
	for y: int in range(at.y - 2, at.y + 3):
		for x: int in range(at.x - 2, at.x + 3):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			var pixel: Color = image.get_pixel(x, y)
			best = maxf(best, pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722)
	return best

func _save(image: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/m12"))
	var copy: Image = image.duplicate()
	var linear: bool = copy.get_format() != Image.FORMAT_RGBA8 and copy.get_format() != Image.FORMAT_RGB8
	copy.convert(Image.FORMAT_RGBA8)
	if linear: copy.linear_to_srgb() # HDR captures read back linear (lessons)
	copy.save_png("res://artifacts/m12/%s.png" % name)
