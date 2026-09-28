extends SceneTree
## Real Vulkan pixels for the M9 warp (camera/movement spec §7). Headless has no renderer and a
## failed shader renders black (lessons.md), so this needs a real window.
##
##   zoom      the rim stroke keeps its screen width at a 1.30x canvas scale (control: the
##             compensation defeated)
##   camera    through the real compositor and camera rig: the ship's (shake-free) screen position
##             holds steady through TRAVEL - the camera whips with the ship instead of leading it
##             (control: a focus lead restored, cam.overshoot 0.5)
##   streaks   they radiate from the ship: between 0.03 s and 0.10 s of TRAVEL their far ends move
##             outward on all four sides of the ship (control: the pre-M9 streaks, every one aimed
##             at one vanishing point ahead)
##   dim       BREAK/TRAVEL dim the world behind the ship to ~20 % of its linear light (control: no
##             dim), and the player's hull stays lit above it (control: the dim layer lifted over
##             the player)
## Every capture greps nothing itself: tools\test.ps1 fails the run on any SHADER/SCRIPT ERROR.

var failures: int = 0
var controls_caught: int = 0
var controls_total: int = 0
var scene: Node2D
const STEP: float = 1.0 / 60.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	scene = Node2D.new()
	root.add_child(scene)
	GameTuning.reset_feel()
	await _zoom_case()
	await _streak_case()
	await _dim_case()
	await _camera_case()
	_bulge_case()
	GameTuning.reset_feel()
	print("Warp pixels: failures=", failures, " controls_caught=", controls_caught, "/", controls_total)
	scene.queue_free()
	await process_frame
	quit(1 if failures or controls_caught != controls_total else 0)

func _make_world(center: Vector2, radius: float, parent: Node = null) -> CombatWorld:
	var world: CombatWorld = CombatWorld.new()
	(parent if parent != null else scene).add_child(world)
	world.visuals_enabled = false
	world.set_physics_process(false)
	world.setup_player("neutral", 1, 40, [], center)
	world.arena.center = center
	world.arena.radius = radius
	world.arena.exits.assign([Vector2i.RIGHT])
	world.player_position = center
	return world

## `zoom_holder.scale` stands in for what `combat_compositor.gd::_update_camera`
## does to `foreground`/`background_viewport.canvas_transform` at a 1.30x zoom -
## ArenaBackdrop reads the live canvas transform scale the same way
## `ship_renderer.gd` does, so wrapping it in a scaled parent is equivalent.
func _zoom_case() -> void:
	var center: Vector2 = Vector2(640, 400)
	var radius: float = 300.0
	var world_1x: CombatWorld = _make_world(center, radius)
	var backdrop_1x: ArenaBackdrop = ArenaBackdrop.new()
	backdrop_1x.world = world_1x
	scene.add_child(backdrop_1x)
	await _frame()
	var width_1x: float = _measure_rim_width(root.get_texture().get_image(), center, radius)
	backdrop_1x.queue_free()
	world_1x.queue_free()
	await process_frame

	var holder: Node2D = Node2D.new()
	holder.scale = Vector2(1.30, 1.30)
	scene.add_child(holder)
	var world_zoom: CombatWorld = _make_world(center, radius, holder)
	var backdrop_zoom: ArenaBackdrop = ArenaBackdrop.new()
	backdrop_zoom.world = world_zoom
	holder.add_child(backdrop_zoom)
	await _frame()
	var width_zoom: float = _measure_rim_width(root.get_texture().get_image(), center * 1.30, radius * 1.30)
	_check(absf(width_zoom - width_1x) <= WIDTH_TOLERANCE * width_1x, "Rim stroke weight at 1.30x zoom (%.3f) equals the weight at 1.00x (%.3f)" % [width_zoom, width_1x])
	backdrop_zoom.canvas_scale_override = 1.0
	await _frame()
	var width_broken: float = _measure_rim_width(root.get_texture().get_image(), center * 1.30, radius * 1.30)
	print("Rim stroke weight: 1.00x %.3f, 1.30x %.3f, 1.30x uncompensated %.3f" % [width_1x, width_zoom, width_broken])
	_control("canvas_scale forced to 1 at real 1.30x zoom", absf(width_broken - width_1x) > WIDTH_TOLERANCE * width_1x)
	holder.queue_free()
	await process_frame

## Integrates brightness along a radial scan through the rim near angle 0 (the rim's thin strokes
## are too thin for a bright-pixel count to resolve a 1.30x change).
const WIDTH_TOLERANCE: float = 0.15
func _measure_rim_width(image: Image, center: Vector2, radius: float) -> float:
	var total: float = 0.0
	for r: int in range(-12, 13):
		var p: Vector2i = Vector2i(center + Vector2(radius + r, 0.0))
		if p.x < 0 or p.y < 0 or p.x >= image.get_width() or p.y >= image.get_height(): continue
		var pixel: Color = image.get_pixel(p.x, p.y)
		total += pixel.r + pixel.g + pixel.b
	return total

## Pins a world mid-TRAVEL `seconds` after the streaks began.
func _pin_travel(world: CombatWorld, seconds: float) -> void:
	world.warp_phase = CombatWorld.WARP_TRAVEL
	world.warp_direction = Vector2i.RIGHT
	world.warp_heading = Vector2.RIGHT
	world.warp_progress = seconds / 0.30
	world.sim_q = 100000
	world.warp_phase_start_q = world.sim_q - roundi(seconds * CombatWorld.SIM_Q_PER_SECOND)
	world.warp_deadline_q = world.warp_phase_start_q + 216

## Farthest streak pixel from `ship` inside a 70-degree wedge round each of right, down, left, up:
## a pixel counts when it is brighter than the same pixel of the streak-free `rest` frame.
func _reach(image: Image, rest: Image, ship: Vector2) -> Array[float]:
	var reach: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for y: int in range(0, image.get_height(), 2):
		for x: int in range(0, image.get_width(), 2):
			var offset: Vector2 = Vector2(x, y) - ship
			var d: float = offset.length()
			if d < 20.0: continue
			var pixel: Color = image.get_pixel(x, y)
			var before: Color = rest.get_pixel(x, y)
			if (pixel.r + pixel.g + pixel.b) - (before.r + before.g + before.b) <= 0.02: continue
			var side: int = posmod(roundi(offset.angle() / (PI * 0.5)), 4)
			if absf(angle_difference(offset.angle(), side * PI * 0.5)) > deg_to_rad(35.0): continue
			reach[side] = maxf(reach[side], d)
	return reach

## Streak reach on each side at two moments of TRAVEL. Returns [early reach, late reach].
func _streak_reach(vanishing: bool) -> Array:
	var center: Vector2 = Vector2(640, 400)
	# A rim far off screen: the frame holds only the backing, the traces and the streaks.
	var world: CombatWorld = _make_world(center + Vector2(4000, 0), 300.0)
	world.player_position = center
	var backdrop: ArenaBackdrop = ArenaBackdrop.new()
	backdrop.world = world
	backdrop.streak_vanishing = vanishing
	backdrop.dim_enabled = false
	scene.add_child(backdrop)
	await _frame()
	var rest: Image = root.get_texture().get_image()
	_pin_travel(world, 0.03)
	await _frame()
	var early: Array[float] = _reach(root.get_texture().get_image(), rest, center)
	_pin_travel(world, 0.10)
	await _frame()
	var late_image: Image = root.get_texture().get_image()
	var late: Array[float] = _reach(late_image, rest, center)
	if not vanishing: late_image.save_png("res://artifacts/m9_warp_streaks_test.png")
	backdrop.queue_free()
	world.queue_free()
	await process_frame
	return [early, late]

func _all_outward(result: Array) -> bool:
	var ok: bool = true
	for side: int in range(4): ok = ok and float(result[1][side]) > float(result[0][side]) + 40.0
	return ok

func _streak_case() -> void:
	var radial: Array = await _streak_reach(false)
	print("Streak reach right/down/left/up at 0.03 s %s, at 0.10 s %s" % [str(radial[0]), str(radial[1])])
	_check(_all_outward(radial), "Streak ends move outward on all four sides of the ship (0.03 s %s -> 0.10 s %s)" % [str(radial[0]), str(radial[1])])
	var old: Array = await _streak_reach(true)
	print("Control (vanishing-point streaks) reach at 0.03 s %s, at 0.10 s %s" % [str(old[0]), str(old[1])])
	_control("the pre-M9 streaks aimed at one vanishing point", not _all_outward(old))

## Mean brightness of a patch.
func _patch(image: Image, at: Vector2, half: int = 4) -> float:
	var total: float = 0.0
	var count: int = 0
	for y: int in range(int(at.y) - half, int(at.y) + half + 1):
		for x: int in range(int(at.x) - half, int(at.x) + half + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			var pixel: Color = image.get_pixel(x, y)
			total += pixel.r + pixel.g + pixel.b
			count += 1
	return total / maxf(1.0, float(count))

## The rim's brightness over the backing, at rest and at full BREAK dim. Returns the ratio.
func _dim_ratio(enabled: bool) -> float:
	var center: Vector2 = Vector2(640, 400)
	var world: CombatWorld = _make_world(center, 300.0)
	var backdrop: ArenaBackdrop = ArenaBackdrop.new()
	backdrop.world = world
	backdrop.dim_enabled = enabled
	scene.add_child(backdrop)
	var rim: Vector2 = center + Vector2(0.0, -300.0)
	await _frame()
	var image: Image = root.get_texture().get_image()
	var backing: float = _patch(image, Vector2(40, 40))
	var lit: float = _patch(image, rim, 2) - backing
	world.warp_phase = CombatWorld.WARP_BREAK
	world.warp_progress = 1.0
	await _frame()
	var dimmed: float = _patch(root.get_texture().get_image(), rim, 2) - backing
	backdrop.queue_free()
	world.queue_free()
	await process_frame
	return dimmed / maxf(0.0001, lit)

func _dim_case() -> void:
	var ratio: float = await _dim_ratio(true)
	var undimmed: float = await _dim_ratio(false)
	print("Rim light over the backing at full dim / at rest: %.3f (no-dim control %.3f)" % [ratio, undimmed])
	_check(ratio >= 0.1 and ratio <= 0.3, "BREAK dims the world to ~20 %% of its light (%.3f)" % ratio)
	_control("no dim (%.3f)" % undimmed, undimmed < 0.1 or undimmed > 0.3)

## The real stack: a CombatWorld under the compositor (camera rig, HDR stage, foreground), the
## backdrop with its warp layer mounted as main.gd mounts it, stepped tick by tick through a warp.
## Returns [ship screen positions over TRAVEL, hull brightness before commit, during TRAVEL].
func _camera_run(lifted: bool) -> Array:
	var holder: Node2D = Node2D.new()
	scene.add_child(holder)
	var world: CombatWorld = CombatWorld.new()
	holder.add_child(world)
	world.set_physics_process(false)
	world.setup_player("neutral", 1, 400, [], GameTuning.ARENA_CENTER)
	world.warp_committed.connect(func(_direction: Vector2i) -> void: world.confirm_warp_swap())
	var backdrop: ArenaBackdrop = ArenaBackdrop.new()
	backdrop.world = world
	world.add_child(backdrop)
	var compositor: CombatCompositor = CombatCompositor.new()
	holder.add_child(compositor)
	compositor.attach(world)
	backdrop.mount_warp_layer(compositor.foreground)
	if lifted: backdrop.warp_layer.z_index = 40
	world.player_position = world.arena.center + Vector2.RIGHT * (world.arena.radius - 300.0)
	world.player.vel = Vector2.RIGHT * 460.0
	world.command.movement = Vector2.RIGHT
	world.command.aim = Vector2.RIGHT
	var screen: Array[Vector2] = []
	var before: float = -1.0
	var during: float = -1.0
	for i: int in range(90):
		world._physics_process(STEP)
		compositor._update_camera()
		if world.warp_phase == CombatWorld.WARP_TRAVEL: screen.append(compositor.world_to_screen(world.player_position))
		if world.warp_phase == CombatWorld.WARP_PUSH and before < 0.0:
			await _frame()
			before = _patch(root.get_texture().get_image(), compositor.world_to_screen(world.player_position), 3)
		if world.warp_phase == CombatWorld.WARP_TRAVEL and screen.size() == 9:
			await _frame()
			var image: Image = root.get_texture().get_image()
			during = _patch(image, compositor.world_to_screen(world.player_position), 3)
			if not lifted: image.save_png("res://artifacts/m9_warp_travel_test.png")
		if world.warp_phase == CombatWorld.WARP_NONE and not screen.is_empty(): break
	compositor.detach()
	holder.queue_free()
	await process_frame
	return [screen, before, during]

func _spread(points: Array) -> float:
	if points.is_empty(): return INF
	var mean: Vector2 = Vector2.ZERO
	for p: Vector2 in points: mean += p
	mean /= points.size()
	var worst: float = 0.0
	for p: Vector2 in points: worst = maxf(worst, p.distance_to(mean))
	return worst

func _camera_case() -> void:
	var run: Array = await _camera_run(false)
	var screen: Array = run[0]
	var spread: float = _spread(screen)
	print("Ship screen position over %d TRAVEL ticks: first %s last %s, max distance from the mean %.2f px" % [screen.size(), str(screen[0]) if not screen.is_empty() else "-", str(screen[-1]) if not screen.is_empty() else "-", spread])
	_check(screen.size() == 18 and spread <= SCREEN_TOLERANCE, "The ship holds its screen position through TRAVEL (%d ticks, within %.2f px of its mean)" % [screen.size(), spread])
	var hull: float = float(run[2]) / maxf(0.0001, float(run[1]))
	print("Player hull patch before commit %.3f, mid-TRAVEL %.3f (ratio %.3f)" % [float(run[1]), float(run[2]), hull])
	_check(hull >= 0.8, "The player's hull stays lit above the dim (%.3f of its pre-commit brightness)" % hull)
	GameTuning.set_feel("cam.overshoot", 0.5)
	var lead: Array = await _camera_run(false)
	GameTuning.reset_feel()
	print("Control (focus lead, cam.overshoot 0.5): max distance from the mean %.2f px" % _spread(lead[0]))
	_control("a focus lead restored (cam.overshoot 0.5)", _spread(lead[0]) > SCREEN_TOLERANCE)
	var lifted: Array = await _camera_run(true)
	var lifted_ratio: float = float(lifted[2]) / maxf(0.0001, float(lifted[1]))
	print("Control (dim layer over the player): hull ratio %.3f" % lifted_ratio)
	_control("the dim layer lifted over the player (%.3f)" % lifted_ratio, lifted_ratio < 0.8)
const SCREEN_TOLERANCE: float = 12.0

## The membrane, from the backdrop's own pure `bulge_px()` on a real press stepped through the sim:
## `release_after` 0 holds to commit. Returns the bulge after every tick for 50 ticks.
func _bulge_trace(release_after: int, reduced: bool, flatten_release: bool = false) -> Array[float]:
	var world: CombatWorld = _make_world(GameTuning.ARENA_CENTER, GameTuning.ARENA_RADIUS)
	world.arena.set_exits(CampaignState.NEIGHBOURS)
	world.warp_reduced = reduced
	world.warp_committed.connect(func(_direction: Vector2i) -> void: world.confirm_warp_swap())
	var backdrop: ArenaBackdrop = ArenaBackdrop.new()
	backdrop.world = world
	world.player_position = world.arena.center + Vector2.RIGHT * (world.arena.radius - 4.0)
	world.command.movement = Vector2.RIGHT
	var trace: Array[float] = []
	for i: int in range(50):
		if release_after > 0 and i == release_after: world.command.movement = Vector2.ZERO
		world._physics_process(STEP)
		if flatten_release: world.warp_release_depth = 0.0
		trace.append(backdrop.bulge_px())
	backdrop.free()
	world.queue_free()
	return trace

func _bulge_case() -> void:
	var held: Array[float] = _bulge_trace(0, false)
	var rising: bool = true
	for i: int in range(1, 11): rising = rising and held[i] > held[i - 1]
	print("Bulge while pressing %s; after commit %s" % [str(held.slice(0, 12)), str(held.slice(11, 20))])
	_check(rising and held.max() <= 40.0 + 0.001 and held.slice(0, 11).max() < 40.0, "The rim bulges with the press depth, up to 40 px (%.1f max)" % held.max())
	_check(held.slice(11, 20).min() < -5.0, "The commit recoils: the bulge swings back past rest (%.1f)" % held.slice(11, 20).min())
	var let_go: Array[float] = _bulge_trace(7, false)
	print("Bulge after a release at tick 7: %s" % str(let_go.slice(6, 30)))
	_check(let_go.slice(7, 30).min() < -1.0 and absf(let_go[-1]) < 0.5, "A released press springs back with a wobble that settles (%.1f min, %.2f at the end)" % [let_go.slice(7, 30).min(), let_go[-1]])
	_control("a release with no spring (%.1f min)" % _bulge_trace(7, false, true).slice(7, 30).min(), _bulge_trace(7, false, true).slice(7, 30).min() >= -1.0)
	var calm: Array[float] = _bulge_trace(0, true)
	_check(calm.max() == 0.0 and calm.min() == 0.0, "Reduced warp: the rim never moves (cross-fade only)")

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
