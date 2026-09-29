extends SceneTree
## M16b: real Vulkan pixels for the boss intro card (scripts/ui/boss_intro.gd) and the big-kill
## radial flash (PostFx.request_flash with a centre). root.size is 1280x800, the project's 1.6 base
## aspect (tasks/lessons.md: another aspect silently letterboxes the readback). Measurements are
## RELATIVE to a card-off / uniform-flash baseline, each with its own negative control, and a real
## combat frame with a boss is saved at three moments for a human look:
## artifacts/boss_intro_{bars,typing,full}.png.

const Harness = preload("res://tests/support/harness.gd")

var t: RefCounted
var scene: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	t = Harness.new("BOSS_INTRO_RENDER")
	root.size = Vector2i(1280, 800)
	scene = Node2D.new()
	root.add_child(scene)
	await _card_case()
	await _radial_flash_case()
	await _combat_capture()
	t.finish(self)

func _rect(at: Rect2, colour: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = at.position
	rect.size = at.size
	rect.color = colour
	scene.add_child(rect)
	return rect

func _clear_scene() -> void:
	for child: Node in scene.get_children(): child.free()

func _frame() -> void:
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func _linear(image: Image, c: Color) -> Color:
	return c.srgb_to_linear() if image.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGB8] else c

func _lum_at(image: Image, x: int, y: int) -> float:
	var c: Color = _linear(image, image.get_pixel(x, y))
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

## Mean luminance of a rectangle, sampled every 2 px.
func _lum(image: Image, area: Rect2i) -> float:
	var total: float = 0.0
	var count: int = 0
	for y: int in range(area.position.y, area.end.y, 2):
		for x: int in range(area.position.x, area.end.x, 2):
			total += _lum_at(image, x, y)
			count += 1
	return total / maxf(1.0, float(count))

## Pixels in `area` brighter than `floor` (the name's glyph ink over a dark ground).
func _bright(image: Image, area: Rect2i, floor: float) -> int:
	var count: int = 0
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			if _lum_at(image, x, y) > floor: count += 1
	return count

func _card(reduced: bool = false) -> BossIntro:
	var card := BossIntro.new()
	card.reduced_motion = reduced
	root.add_child(card)
	# After add_child: entering the tree re-enables _process, which would advance the card on the
	# real clock between step() and the capture.
	card.set_process(false)
	return card

## The letterbox closes on the edges and the name is drawn, on a mid-grey ground.
func _card_case() -> void:
	_rect(Rect2(0, 0, 1280, 800), Color(0.35, 0.35, 0.35))
	await _frame()
	var off: Image = _capture()
	var card: BossIntro = _card()
	card.present("PYRE", "RIVAL SIGNAL", "FIRE DIALECT  ·  LEVEL 1", VisualStyle.CORAL)
	card.step(1.2)
	await _frame()
	var on: Image = _capture()
	var top_off: float = _lum(off, Rect2i(0, 4, 1280, 48))
	var top_on: float = _lum(on, Rect2i(0, 4, 1280, 48))
	var bottom_on: float = _lum(on, Rect2i(0, 752, 1280, 44))
	var middle_on: float = _lum(on, Rect2i(0, 200, 1280, 100))
	var middle_off: float = _lum(off, Rect2i(0, 200, 1280, 100))
	var name_area := Rect2i(340, 520, 600, 130)
	var ink_off: int = _bright(off, name_area, 0.6)
	var ink_on: int = _bright(on, name_area, 0.6)
	print("measure: capture %dx%d fmt %d; top band lum %.4f card-off vs %.4f on, bottom %.4f; middle %.4f vs %.4f; name ink px %d vs %d" % [on.get_width(), on.get_height(), on.get_format(), top_off, top_on, bottom_on, middle_off, middle_on, ink_off, ink_on])
	t.check(on.get_size() == Vector2i(1280, 800), "the capture is the full 1280x800 (%s)" % on.get_size())
	t.check(top_on < top_off * 0.15 and bottom_on < top_off * 0.15, "the letterbox bars black out the top and bottom bands (%.4f, %.4f vs %.4f)" % [top_on, bottom_on, top_off])
	t.check(absf(middle_on - middle_off) < middle_off * 0.05, "and leave the playfield between them untouched (%.4f vs %.4f)" % [middle_on, middle_off])
	t.check(ink_on > 1500, "the rival's name is drawn in bright display type (%d px)" % ink_on)
	t.control("no card: the same bands (%.4f, %d ink px)" % [top_off, ink_off], not (top_off < top_off * 0.15) and ink_off < 50)
	card.step(0.0)
	card.free()
	var still: BossIntro = _card(true)
	still.present("PYRE", "RIVAL SIGNAL", "FIRE DIALECT  ·  LEVEL 1", VisualStyle.CORAL)
	still.step(0.1)
	await _frame()
	var half: Image = _capture()
	var top_half: float = _lum(half, Rect2i(0, 4, 1280, 48))
	print("measure: reduced motion at 0.1 s: top band lum %.4f (a half fade of the full bar)" % top_half)
	t.check(top_half > top_on and top_half < top_off, "reduced motion fades the card in instead of sliding it (%.4f between %.4f and %.4f)" % [top_half, top_on, top_off])
	still.free()
	_clear_scene()

func _capture() -> Image:
	return root.get_texture().get_image()

## An HDR 2D readback is linear half-float (tasks/lessons.md); saved as-is its anti-aliased edges
## lose their mid-tones and type looks jagged. The saved looks are encoded to sRGB first.
func _srgb(image: Image) -> Image:
	if image.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGB8]: return image
	var encoded := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGB8)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()): encoded.set_pixel(x, y, image.get_pixel(x, y).linear_to_srgb())
	return encoded

## A big kill's flash is brightest where the kill happened.
func _radial_flash_case() -> void:
	_rect(Rect2(0, 0, 1280, 800), Color(0.2, 0.2, 0.2))
	await _frame()
	var base: Image = _capture()
	var post := PostFx.new()
	post.vignette_strength = 0.0
	root.add_child(post)
	post.set_process(false)
	post.request_flash(0.25, Vector2(0.25, 0.5))
	await _frame()
	var radial: Image = _capture()
	var near: float = _lum(radial, Rect2i(300, 380, 40, 40)) - _lum(base, Rect2i(300, 380, 40, 40))
	var far: float = _lum(radial, Rect2i(1180, 380, 40, 40)) - _lum(base, Rect2i(1180, 380, 40, 40))
	post.free()
	var flat := PostFx.new()
	flat.vignette_strength = 0.0
	root.add_child(flat)
	flat.set_process(false)
	flat.request_flash(0.25)
	await _frame()
	var uniform: Image = _capture()
	var flat_near: float = _lum(uniform, Rect2i(300, 380, 40, 40)) - _lum(base, Rect2i(300, 380, 40, 40))
	var flat_far: float = _lum(uniform, Rect2i(1180, 380, 40, 40)) - _lum(base, Rect2i(1180, 380, 40, 40))
	flat.free()
	print("measure: flash delta near/far the kill: radial %.3f/%.3f, uniform %.3f/%.3f" % [near, far, flat_near, flat_far])
	t.check(near > far * 2.0, "a centred flash is brighter at the kill than across the screen (%.3f vs %.3f)" % [near, far])
	t.check(near <= PostFx.MAX_FLASH_DELTA * 1.08, "and its brightest point still keeps the 0.25 cap (+8%% readback): %.3f" % near)
	t.control("no centre: the flash is uniform (%.3f vs %.3f)" % [flat_near, flat_far], not (flat_near > flat_far * 2.0))
	_clear_scene()

## A real combat frame with the fire rival in view, with the card at three moments.
func _combat_capture() -> void:
	_rect(Rect2(0, 0, 1280, 800), VisualStyle.BG)
	var world: CombatWorld = CombatWorld.new()
	scene.add_child(world)
	world.set_physics_process(false)
	# Framed as the camera frames play: the ship at the centre, the rival just engaged above it.
	world.setup_player("fire", 1, 40, [], Vector2(640, 400))
	world._spawn_named_enemy(ShipGenerator.hull_id("boss", "boss", "fire", 1), "fire", 1, Vector2(760, 60), true, false)
	world._spawn_enemy("fire", 1, Vector2(330, 420), false)
	world._sync_visuals()
	var post := PostFx.new()
	root.add_child(post)
	post.set_process(false)
	var card: BossIntro = _card()
	card.present("PYRE", "RIVAL SIGNAL", "FIRE DIALECT  ·  LEVEL 1", VisualStyle.PALETTE["fire"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	for moment: Array in [[0.12, "bars"], [0.30, "typing"], [0.90, "full"]]:
		card.step(float(moment[0]) - maxf(0.0, card.elapsed))
		await _frame()
		_srgb(_capture()).save_png("res://artifacts/boss_intro_%s.png" % moment[1])
	print("measure: saved artifacts/boss_intro_{bars,typing,full}.png")
	card.free()
	post.free()
	_clear_scene()
