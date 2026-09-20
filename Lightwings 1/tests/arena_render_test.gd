extends SceneTree
## Real Vulkan pixels: the node rim renders as a circle, an open membrane reads as a
## measurably brighter arc than a sealed wall beside it, and the ~80 px of dead space
## beyond the rim shows no trace pixels. Headless has no renderer and a failed shader
## renders black (lessons.md), so this needs a real window.
##
## get_image() on this viewport returns LINEAR colour (small sRGB values compress a
## lot: measured background 0x050507 reads back as sum~0.0051, not the naive
## sRGB sum~0.066), so brightness is judged relative to a measured background
## sample, never against a hand-picked absolute constant.

var failures: int = 0
var controls_caught: int = 0
var controls_total: int = 0
var scene: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	scene = Node2D.new()
	root.add_child(scene)
	var center: Vector2 = Vector2(640, 400)
	var radius: float = 300.0

	# Case: normal arena, one open membrane (RIGHT), the other three sides sealed.
	var world: CombatWorld = _make_world(center, radius, [Vector2i.RIGHT])
	var backdrop: ArenaBackdrop = ArenaBackdrop.new()
	backdrop.world = world
	scene.add_child(backdrop)
	await _frame()
	var image: Image = root.get_texture().get_image()
	var background: float = _sample(image, Vector2i(2, 2)) # Inside the fill rect, far from any drawn shape.
	var membrane_bright: float = _sample(image, Vector2i(center+Vector2(radius,0)))
	var sealed_bright: float = _sample(image, Vector2i(center+Vector2(-radius,0)))
	_check(_bright(image, Vector2i(center+Vector2(radius,0)), background), "Rim renders as a circle (pixel found on the +X radius)")
	_check(membrane_bright > sealed_bright*1.5, "Open membrane arc is measurably brighter than the sealed wall beside it (%.4f vs %.4f)" % [membrane_bright,sealed_bright])
	var dead_zone: float = _ring_max(image, center, radius+GameTuning.ARENA_MARGIN+10.0)
	_check(dead_zone < background*2.0, "The 80 px beyond the rim contains no trace pixels (measured %.4f, background %.4f)" % [dead_zone,background])
	backdrop.queue_free()
	world.queue_free()
	await process_frame

	# Negative control: membrane styling forced off (no open exits at all) -> every
	# side is sealed, so the "brighter than the wall beside it" check must now fail.
	var plain_world: CombatWorld = _make_world(center, radius, [])
	var plain_backdrop: ArenaBackdrop = ArenaBackdrop.new()
	plain_backdrop.world = plain_world
	scene.add_child(plain_backdrop)
	await _frame()
	var plain_image: Image = root.get_texture().get_image()
	var plain_east: float = _sample(plain_image, Vector2i(center+Vector2(radius,0)))
	var plain_west: float = _sample(plain_image, Vector2i(center+Vector2(-radius,0)))
	_control("membrane styling forced off (no open exits)", not (plain_east > plain_west*1.5))
	plain_backdrop.queue_free()
	plain_world.queue_free()
	await process_frame

	# Negative control: disable the dead-zone clip itself (the pre-fix formula drew
	# traces without it), proving the instrument can see a failure when it is removed.
	var unclipped_world: CombatWorld = _make_world(center, radius, [Vector2i.RIGHT])
	var unclipped_backdrop: ArenaBackdrop = ArenaBackdrop.new()
	unclipped_backdrop.world = unclipped_world
	unclipped_backdrop.dead_zone_clip_enabled = false
	scene.add_child(unclipped_backdrop)
	await _frame()
	var unclipped_image: Image = root.get_texture().get_image()
	var unclipped_background: float = _sample(unclipped_image, Vector2i(2, 2))
	var unclipped_dead_zone: float = _ring_max(unclipped_image, center, radius+GameTuning.ARENA_MARGIN+10.0)
	_control("dead-zone clip removed (pre-fix unclipped trace formula)", unclipped_dead_zone >= unclipped_background*2.0)
	unclipped_backdrop.queue_free()
	unclipped_world.queue_free()
	await process_frame

	print("Arena rendering: background=%.4f membrane=%.4f sealed=%.4f dead_zone=%.4f (unclipped %.4f), failures=%d, controls %d/%d" % [background,membrane_bright,sealed_bright,dead_zone,unclipped_dead_zone,failures,controls_caught,controls_total])
	scene.queue_free()
	await process_frame
	quit(1 if failures or controls_caught != controls_total else 0)

func _make_world(center: Vector2, radius: float, exits: Array) -> CombatWorld:
	var world: CombatWorld = CombatWorld.new()
	scene.add_child(world)
	world.visuals_enabled = false
	world.setup_player("neutral", 1, 40, [], center)
	world.arena.center = center
	world.arena.radius = radius
	world.arena.exits.assign(exits)
	world.player_position = center
	return world

func _sample(image: Image, at: Vector2i) -> float:
	var total: float = 0.0
	var count: int = 0
	for y: int in range(at.y-4, at.y+5):
		for x: int in range(at.x-4, at.x+5):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			var pixel: Color = image.get_pixel(x, y)
			total += pixel.r+pixel.g+pixel.b
			count += 1
	return total/maxf(1.0,float(count))

func _bright(image: Image, at: Vector2i, background: float) -> bool:
	return _sample(image, at) > background*1.5

## Worst-case (max) brightness of any pixel at or beyond min_radius from centre.
## Trace dots are sparse (a couple of pixels each), so a full scan is used instead
## of a handful of sample points, which could miss every dot by bad luck.
func _ring_max(image: Image, center: Vector2, min_radius: float) -> float:
	var worst: float = 0.0
	var min_sq: float = min_radius*min_radius
	for y: int in range(0, image.get_height(), 2):
		for x: int in range(0, image.get_width(), 2):
			if Vector2(x,y).distance_squared_to(center) < min_sq: continue
			var pixel: Color = image.get_pixel(x, y)
			worst = maxf(worst, pixel.r+pixel.g+pixel.b)
	return worst

func _frame() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)

func _control(what_was_sabotaged: String, instrument_noticed: bool) -> void:
	controls_total += 1
	if instrument_noticed: controls_caught += 1
	else: push_error("Negative control not caught: " + what_was_sabotaged)
