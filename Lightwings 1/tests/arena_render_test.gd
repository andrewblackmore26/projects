extends SceneTree
## Real Vulkan pixels: the node rim renders as a circle, a press brightens the predicted
## destination arc (modernization M3) and nothing 90 deg away, and the ~80 px of dead space
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

	# Case: an interior node at rest (modernization M3: the whole rim is exit, 8 arcs).
	var world: CombatWorld = _make_world(center, radius, CampaignState.NEIGHBOURS)
	var backdrop: ArenaBackdrop = ArenaBackdrop.new()
	backdrop.world = world
	scene.add_child(backdrop)
	await _frame()
	var image: Image = root.get_texture().get_image()
	# M6 (aspect "expand"): the capture is the whole window, never a letterboxed part of it.
	_check(image.get_size() == root.size, "the capture is exactly root.size %s (got %s)" % [root.size, image.get_size()])
	var background: float = _sample(image, Vector2i(2, 2)) # Inside the fill rect, far from any drawn shape.
	var rest_ne: float = _sample(image, _rim(center, radius, CONTACT))
	_check(_bright(image, Vector2i(center+Vector2(radius,0)), background), "Rim renders as a circle (pixel found on the +X radius)")
	var dead_zone: float = _ring_max(image, center, radius+GameTuning.ARENA_MARGIN+10.0)
	_check(dead_zone < background+0.001, "The 80 px beyond the rim contains no trace pixels (measured %.4f, background %.4f)" % [dead_zone,background])
	backdrop.queue_free()
	world.queue_free()
	await process_frame

	# Case (M3, retires the membrane-vs-wall pixel check): pressing into the NE arc. Sampled ON the
	# rim at the contact angle, against the same angle at rest and against the SE arc 90 deg away.
	var pressed: Dictionary = await _press_capture(center, radius, Vector2i(1,-1), 0.0, true)
	_check(pressed.ne > rest_ne*1.5, "The predicted destination arc brightens under a press (%.4f pressed vs %.4f at rest)" % [pressed.ne,rest_ne])
	_check(pressed.ne > pressed.se*1.5, "Only the predicted arc brightens, not one 90 deg away (%.4f vs %.4f)" % [pressed.ne,pressed.se])
	# Negative controls: the highlight moved to the wrong arc (SE); the highlight removed.
	var wrong: Dictionary = await _press_capture(center, radius, Vector2i(1,1), PI*0.5, true)
	_control("highlight placed on the wrong arc (SE, %.4f at NE)" % wrong.ne, not (wrong.ne > rest_ne*1.5 and wrong.ne > wrong.se*1.5))
	var dark: Dictionary = await _press_capture(center, radius, Vector2i(1,-1), 0.0, false)
	_control("no highlight (%.4f at NE)" % dark.ne, not (dark.ne > rest_ne*1.5 and dark.ne > dark.se*1.5))
	var membrane_bright: float = pressed.ne
	var sealed_bright: float = rest_ne

	# Negative control: disable the dead-zone clip itself (the pre-fix formula drew
	# traces without it), proving the instrument can see a failure when it is removed.
	var unclipped_world: CombatWorld = _make_world(center, radius, CampaignState.NEIGHBOURS)
	var unclipped_backdrop: ArenaBackdrop = ArenaBackdrop.new()
	unclipped_backdrop.world = unclipped_world
	unclipped_backdrop.dead_zone_clip_enabled = false
	scene.add_child(unclipped_backdrop)
	await _frame()
	var unclipped_image: Image = root.get_texture().get_image()
	var unclipped_background: float = _sample(unclipped_image, Vector2i(2, 2))
	var unclipped_dead_zone: float = _ring_max(unclipped_image, center, radius+GameTuning.ARENA_MARGIN+10.0)
	_control("dead-zone clip removed (pre-fix unclipped trace formula)", unclipped_dead_zone >= unclipped_background+0.001)
	unclipped_backdrop.queue_free()
	unclipped_world.queue_free()
	await process_frame

	print("Arena rendering: background=%.4f pressed_ne=%.4f rest_ne=%.4f pressed_se=%.4f wrong_arc_ne=%.4f no_highlight_ne=%.4f dead_zone=%.4f (unclipped %.4f), failures=%d, controls %d/%d" % [background,membrane_bright,sealed_bright,pressed.se,wrong.ne,dark.ne,dead_zone,unclipped_dead_zone,failures,controls_caught,controls_total])
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
	world.arena.set_exits(exits)
	world.player_position = center
	world.set_physics_process(false) # the press cases pin warp state by hand; no sim tick may undo it
	return world

const CONTACT: float = -PI*0.25 # the NE bearing (y down)

func _rim(center: Vector2, radius: float, angle: float) -> Vector2i:
	return Vector2i(center+Vector2.from_angle(angle)*radius)

## One frame of a full-depth press with the contact at the NE bearing. `direction` is the arc the
## backdrop is told to highlight and `offset` shifts its centre (both only differ for the control).
func _press_capture(center: Vector2, radius: float, direction: Vector2i, offset: float, enabled: bool) -> Dictionary:
	var world: CombatWorld = _make_world(center, radius, CampaignState.NEIGHBOURS)
	world.player.pos = center+Vector2.from_angle(CONTACT)*(radius-2.0)
	world.warp_phase = CombatWorld.WARP_PUSH
	world.warp_progress = 1.0
	world.warp_direction = direction
	world.visible = false # the player's ship sits on the contact point; sample the rim, not the ship
	var backdrop: ArenaBackdrop = ArenaBackdrop.new()
	backdrop.world = world
	backdrop.highlight_offset = offset
	backdrop.highlight_enabled = enabled
	scene.add_child(backdrop)
	await _frame()
	var image: Image = root.get_texture().get_image()
	var result: Dictionary = {"ne": _sample(image, _rim(center, radius, CONTACT)), "se": _sample(image, _rim(center, radius, CONTACT+PI*0.5))}
	backdrop.queue_free()
	world.queue_free()
	await process_frame
	return result

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
