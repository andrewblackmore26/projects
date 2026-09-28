extends SceneTree
## M16: real Vulkan pixels for the post pass (shaders/post_fx.gdshader via PostFx on CanvasLayer 5).
## Headless compiles no shaders and a failed shader renders black (tasks/lessons.md), so this needs
## a window; the runner fails on any SHADER ERROR in the log. root.size is 1280x800, the project's
## 1.6 base aspect, or the capture silently letterboxes (tasks/lessons.md). Every measurement has
## its own negative control, and thresholds are RELATIVE to a post-off baseline.

const Harness = preload("res://tests/support/harness.gd")

var t: RefCounted
var scene: Node2D
var post: PostFx
## The measured delta of a capped full-white flash (_flash_case): the bloom's centre is judged
## against it, not against a hand-picked constant.
var _capped_white: float = 0.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	t = Harness.new("POST_FX_RENDER")
	root.size = Vector2i(1280, 800)
	scene = Node2D.new()
	root.add_child(scene)
	await _vignette_case()
	await _aberration_case()
	await _flash_case()
	await _bloom_case()
	await _combat_capture()
	t.finish(self)

func _fresh_post() -> PostFx:
	if is_instance_valid(post): post.free()
	post = PostFx.new()
	# The test holds the envelopes still: `step` is driven by _process and would decay the hurt
	# state between setting it and the capture.
	post.set_process(false)
	root.add_child(post)
	return post

func _rect(at: Rect2, colour: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = at.position
	rect.size = at.size
	rect.color = colour
	scene.add_child(rect)
	return rect

func _clear_scene() -> void:
	for child: Node in scene.get_children(): child.free()
	if is_instance_valid(post): post.free()

func _frame() -> void:
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func _capture() -> Image:
	var image: Image = root.get_texture().get_image()
	return image

## Mean luminance of a 9x9 patch (linear if the capture is 8-bit sRGB).
func _lum(image: Image, at: Vector2i) -> float:
	var total: float = 0.0
	var count: int = 0
	for y: int in range(at.y - 4, at.y + 5):
		for x: int in range(at.x - 4, at.x + 5):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			var c: Color = _linear(image, image.get_pixel(x, y))
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			count += 1
	return total / maxf(1.0, float(count))

func _linear(image: Image, c: Color) -> Color:
	return c.srgb_to_linear() if image.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGB8] else c

func _vignette_ratio(image: Image) -> float:
	var corners: float = (_lum(image, Vector2i(8, 8)) + _lum(image, Vector2i(1271, 8)) + _lum(image, Vector2i(8, 791)) + _lum(image, Vector2i(1271, 791))) * 0.25
	return corners / maxf(0.0001, _lum(image, Vector2i(640, 400)))

func _vignette_case() -> void:
	_rect(Rect2(0, 0, 1280, 800), Color(0.5, 0.5, 0.5))
	await _frame()
	var baseline: Image = _capture()
	print("measure: capture %dx%d format %d" % [baseline.get_width(), baseline.get_height(), baseline.get_format()])
	t.check(baseline.get_size() == root.size, "the capture is the full root.size %s (got %s)" % [root.size, baseline.get_size()])
	var base_ratio: float = _vignette_ratio(baseline)
	var base_centre: float = _lum(baseline, Vector2i(640, 400))
	_fresh_post()
	await _frame()
	var on: Image = _capture()
	var ratio: float = _vignette_ratio(on)
	var centre: float = _lum(on, Vector2i(640, 400))
	_fresh_post().vignette_strength = 0.0
	post._apply()
	await _frame()
	var zero_ratio: float = _vignette_ratio(_capture())
	print("measure: vignette corner/centre ratio post-off %.3f, default %.3f, strength 0 %.3f; centre %.4f vs %.4f" % [base_ratio, ratio, zero_ratio, base_centre, centre])
	t.check(ratio < base_ratio * 0.95, "the default vignette darkens the corners by > 5%% relative to post-off (%.3f vs %.3f)" % [ratio, base_ratio])
	t.check(ratio > base_ratio * 0.70, "and stays subtle: corners keep > 70%% (%.3f)" % ratio)
	t.check(absf(centre - base_centre) <= base_centre * 0.02, "the centre is untouched within 2%% (%.4f vs %.4f)" % [centre, base_centre])
	t.control("vignette strength 0 (ratio %.3f)" % zero_ratio, not (zero_ratio < base_ratio * 0.95))
	_clear_scene()

## R and B edges of a white block's right edge, on row y; returns (lastR - lastB) / 2.
func _edge_offset(image: Image, y: int) -> float:
	var last_r: int = -1
	var last_b: int = -1
	for x: int in range(900, 1100):
		var c: Color = image.get_pixel(x, y)
		if c.r > 0.5: last_r = x
		if c.b > 0.5: last_b = x
	return float(last_r - last_b) * 0.5

func _aberration_case() -> void:
	_rect(Rect2(0, 0, 1280, 800), Color.BLACK)
	_rect(Rect2(700, 350, 300, 100), Color.WHITE)
	await _frame()
	var base: float = _edge_offset(_capture(), 400)
	_fresh_post().hurt(1.0)
	await _frame()
	var hurt_offset: float = _edge_offset(_capture(), 400)
	var calm: PostFx = _fresh_post()
	calm.reduced_motion = true
	calm.hurt(1.0)
	await _frame()
	var calm_offset: float = _edge_offset(_capture(), 400)
	print("measure: R/B edge offset px: post-off %.1f, hurt %.1f, hurt with aberration 0 (reduced motion) %.1f" % [base, hurt_offset, calm_offset])
	t.check(hurt_offset >= 2.0 and hurt_offset - base >= 2.0, "the hurt state splits R and B at a white edge by >= 2 px (%.1f)" % hurt_offset)
	t.check(hurt_offset <= 3.5, "and by no more than the 3 px contract, +0.5 px filtering (%.1f)" % hurt_offset)
	t.control("aberration 0 (reduced motion) with the hurt state on (offset %.1f)" % calm_offset, not (calm_offset >= 2.0 and calm_offset - base >= 2.0))
	_clear_scene()

func _flash_case() -> void:
	_rect(Rect2(0, 0, 1280, 800), Color(0.2, 0.2, 0.2))
	await _frame()
	var base: float = _lum(_capture(), Vector2i(640, 400))
	_fresh_post().vignette_strength = 0.0
	post.request_flash(1.0)
	await _frame()
	var capped: float = _lum(_capture(), Vector2i(640, 400)) - base
	_capped_white = capped
	var open: PostFx = _fresh_post()
	open.vignette_strength = 0.0
	open.limit_luminance = false
	open.request_flash(1.0)
	await _frame()
	var uncapped: float = _lum(_capture(), Vector2i(640, 400)) - base
	print("measure: flash luminance delta (linear) capped %.3f, cap off %.3f" % [capped, uncapped])
	t.check(capped > 0.1, "a full-white flash request is visible (delta %.3f)" % capped)
	t.check(capped <= PostFx.MAX_FLASH_DELTA * 1.08, "and its measured luminance delta stays <= 0.25 (+8%% readback tolerance): %.3f" % capped)
	t.control("luminance cap off (delta %.3f)" % uncapped, uncapped > PostFx.MAX_FLASH_DELTA * 1.08)
	_clear_scene()

## M19: the evolution's flash is a bloom on the ship, not a grey wash. Driven through FeelDirector's
## `evolved` row (the real mapping; with no world bound it centres on the screen, where the camera
## keeps the ship) over the game's own near-black void, and again off-centre straight through
## request_flash. Corners: mean of the four 9x9 corner patches. Controls: the M16b radial flash
## (30 % floor) at the same strength and centre, which is the wash (corner line); the flash setting
## at 0 (centre line).
func _bloom_case() -> void:
	_rect(Rect2(0, 0, 1280, 800), VisualStyle.BG)
	await _frame()
	var base: Image = _capture()
	var director: FeelDirector = FeelDirector.new()
	director.set_process(false)
	director.post.set_process(false)
	director.post.vignette_strength = 0.0
	root.add_child(director)
	director.on_feel_event(&"evolved", Vector2.ZERO, 2.0, 0)
	await _frame()
	var bloom: Image = _capture()
	var centre: float = _lum(bloom, Vector2i(640, 400)) - _lum(base, Vector2i(640, 400))
	var corners: float = _corners(bloom) - _corners(base)
	var near: float = _lum(bloom, Vector2i(640 + 160, 400)) - _lum(base, Vector2i(640 + 160, 400))
	director.post.flash_level = 0.0
	director.post._apply()
	# Off-centre, direct: the glow follows the ship's screen position.
	var off: PostFx = _fresh_post()
	off.vignette_strength = 0.0
	off.request_flash(0.25, Vector2(0.3, 0.4), true)
	await _frame()
	var shifted: Image = _capture()
	var off_at: float = _lum(shifted, Vector2i(384, 320)) - _lum(base, Vector2i(384, 320))
	var off_mirror: float = _lum(shifted, Vector2i(896, 480)) - _lum(base, Vector2i(896, 480))
	var old: PostFx = _fresh_post()
	old.vignette_strength = 0.0
	old.request_flash(0.25, Vector2(0.5, 0.5))
	await _frame()
	var wash: float = _corners(_capture()) - _corners(base)
	post.free()
	director.post.flash_setting = 0.0
	director.post.flash_level = 0.0
	director.post.step(1.0)
	director.post.request_flash(0.25, Vector2(0.5, 0.5), true)
	await _frame()
	var off_centre_setting: float = _lum(_capture(), Vector2i(640, 400)) - _lum(base, Vector2i(640, 400))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	bloom.save_png("res://artifacts/post_fx_evolve_bloom.png")
	print("measure: evolve bloom delta (linear) centre %.4f, 160 px out %.4f, corners %.5f (sRGB corner %.2f/255); off-centre at %.4f, mirror %.4f; old radial corners %.4f; setting 0 centre %.4f" % [centre, near, corners, _corner_srgb(bloom) - _corner_srgb(base), off_at, off_mirror, wash, off_centre_setting])
	var bright: float = 0.7 * _capped_white
	t.check(centre >= bright and bright > 0.05, "the evolve bloom lights the ship: centre delta >= 70%% of a capped white flash, %.4f (%.4f)" % [bright, centre])
	t.check(centre <= PostFx.MAX_FLASH_DELTA * 1.08, "and stays under the 0.25 luminance cap (%.4f)" % centre)
	t.check(corners <= 0.003, "the corners barely change: delta <= 0.003 linear (%.5f)" % corners)
	t.check(off_at >= bright and off_mirror <= 0.01, "an off-centre bloom sits on its centre (%.4f) and not across the screen (%.4f)" % [off_at, off_mirror])
	t.control("the M16b radial flash with its 30%% floor (corners %.4f)" % wash, not (wash <= 0.003))
	t.control("flash intensity 0 (centre %.4f)" % off_centre_setting, not (off_centre_setting >= bright))
	director.free()
	_clear_scene()

func _corners(image: Image) -> float:
	return (_lum(image, Vector2i(8, 8)) + _lum(image, Vector2i(1271, 8)) + _lum(image, Vector2i(8, 791)) + _lum(image, Vector2i(1271, 791))) * 0.25

## The corners' mean green channel in 8-bit sRGB steps (what the eye sees on the void).
func _corner_srgb(image: Image) -> float:
	var total: float = 0.0
	for at: Vector2i in [Vector2i(8, 8), Vector2i(1271, 8), Vector2i(8, 791), Vector2i(1271, 791)]:
		var c: Color = image.get_pixel(at.x, at.y)
		if not image.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGB8]: c = c.linear_to_srgb()
		total += c.g * 255.0
	return total * 0.25

## A real combat frame (player + enemies, no compositor) with and without the hurt state, saved for
## a human look: artifacts/post_fx_hurt.png and artifacts/post_fx_calm.png.
func _combat_capture() -> void:
	_rect(Rect2(0, 0, 1280, 800), VisualStyle.BG)
	var world: CombatWorld = CombatWorld.new()
	scene.add_child(world)
	world.set_physics_process(false)
	world.setup_player("fire", 1, 40, [], Vector2(640, 400))
	world._spawn_enemy("fire", 1, Vector2(900, 330), false)
	world._spawn_enemy("lightning", 1, Vector2(380, 520), false)
	world._sync_visuals()
	_fresh_post()
	await _frame()
	var calm: Image = _capture()
	post.request_flash(0.25, Vector2(0.5, 0.5), true)
	await _frame()
	var evolve: Image = _capture()
	post.flash_level = 0.0
	post.hurt(1.0)
	await _frame()
	var hurt: Image = _capture()
	post.set_low_light(true)
	post.step(1.0)
	post.hurt(1.0)
	await _frame()
	var low: Image = _capture()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	calm.save_png("res://artifacts/post_fx_calm.png")
	evolve.save_png("res://artifacts/post_fx_evolve_combat.png")
	hurt.save_png("res://artifacts/post_fx_hurt.png")
	low.save_png("res://artifacts/post_fx_low_light.png")
	var edge_calm: Color = _linear(calm, calm.get_pixel(60, 400))
	var edge_hurt: Color = _linear(hurt, hurt.get_pixel(60, 400))
	print("measure: combat frame left-edge pixel calm %s, hurt %s" % [edge_calm, edge_hurt])
	t.check(edge_hurt.r - edge_hurt.b > edge_calm.r - edge_calm.b + 0.005, "the hurt state warms the screen edge toward coral (r-b %.4f vs %.4f)" % [edge_hurt.r - edge_hurt.b, edge_calm.r - edge_calm.b])
	_clear_scene()
