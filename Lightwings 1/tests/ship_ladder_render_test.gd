extends SceneTree
## Ship design spec acceptance 2: "every 15 px hub measures 15 px, on a drone and on a boss alike"
## (§3: size comes from count, never scale). A pixel ruler finds a circle's left and right rims as
## sub-pixel brightness centroids and reports the span between them. Claims:
##  (a) a hub's span is the same on the radial elite, the boss and the player, and a core's is the
##      same on the drone and the boss - the spec's actual claim, ship against ship;
##  (b) the span is what a 15 px radius should give;
##  (c) at minimum zoom every span shrinks by the zoom and stays equal across ships;
##  (d) NOTHING scales with time (spec §9.3 pumps the radius of the RAIL): same span at two ticks.
## The rim is sampled, never the centre (lessons: sample where the effect is).

var failures: int = 0
var controls_caught: int = 0
var controls_total: int = 0
const AT: Vector2 = Vector2(640, 400)
const MIN_ZOOM: float = 0.6561

func _initialize() -> void: _run.call_deferred()

func _load(name: String, mutate: Callable = Callable()) -> ShipDefinition:
	var errors: PackedStringArray = PackedStringArray()
	var ship: ShipDefinition = ShipGrammar.load_json("res://tests/fixtures/ships_v4/%s.json" % name, errors)
	ShipCompiler.compile(ship)
	if mutate.is_valid(): mutate.call(ship)
	return ship

## Distance from `centre` along `direction` to the rim near `radius`: the brightness centroid of
## quarter-pixel samples within 4 px of it.
func _rim(image: Image, centre: Vector2, direction: Vector2, radius: float) -> float:
	var weight: float = 0.0
	var moment: float = 0.0
	var steps: int = 32
	for k: int in range(-steps / 2, steps / 2 + 1):
		var distance: float = radius + float(k) * 0.25
		var at: Vector2 = centre + direction * distance
		var pixel: Color = image.get_pixel(int(round(at.x)), int(round(at.y)))
		var value: float = maxf(0.0, pixel.r + pixel.g + pixel.b - 0.3)
		weight += value
		moment += value * distance
	return moment / weight if weight > 0.0 else NAN

## The direction to measure a circle ACROSS. The first version scanned horizontally and read the
## boss's core as 71.7 px, because a spoke lay exactly along the scan, and read a hub as 28.1 px at
## tick 137 once its own spoke had turned into the line. A cluster is measured along the TANGENT to
## its rail (its spoke, pods and set piece all lie radially); the core at 22.5 degrees, which is
## clear of every spoke on orders 3, 4, 6 and 8 at phase 0.
func _across(local: Vector2) -> Vector2:
	if local.length() < 1.0: return Vector2.from_angle(deg_to_rad(22.5))
	return local.normalized().orthogonal()

## Renders `ship` at `zoom` and `tick`, and measures circle `id`'s horizontal rim-to-rim span.
func _span(ship: ShipDefinition, id: String, zoom: float, tick: int) -> float:
	var renderer: ShipRenderer = ShipRenderer.new()
	root.add_child(renderer)
	renderer.position = AT
	renderer.visual_scale = zoom
	renderer.set_ship(ship)
	renderer.set_process(false)
	renderer.set_motion_tick(tick)
	renderer._process(0)
	for i: int in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
	var pose: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig)
	ShipMotion.step(rig, pose, tick)
	var index: int = rig.index_of(id)
	var centre: Vector2 = AT + pose.local[index] * zoom
	var radius: float = rig.radius[index] * zoom
	var across: Vector2 = _across(pose.local[index])
	var span: float = _rim(image, centre, across, radius) + _rim(image, centre, -across, radius)
	renderer.queue_free()
	await process_frame
	return span

func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.use_hdr_2d = true
	var elite: ShipDefinition = _load("radial_elite")
	var boss: ShipDefinition = _load("boss")
	var player: ShipDefinition = _load("player_t3")
	var drone: ShipDefinition = _load("drone")
	# A hub whose horizontal diameter is clear of its own pods and set piece: the elite's and the
	# boss's rail-2 slot 0 sit at the top of the ship with their clusters fanning upward.
	var hub_elite: float = await _span(elite, "r2s0", 1.0, 0)
	var hub_boss: float = await _span(boss, "r2s0", 1.0, 0)
	var hub_player: float = await _span(player, "r1s0", 1.0, 0)
	var core_drone: float = await _span(drone, "core", 1.0, 0)
	var core_boss: float = await _span(boss, "core", 1.0, 0)
	print("ladder spans at zoom 1: hub elite %.3f boss %.3f player %.3f | core drone %.3f boss %.3f" % [hub_elite, hub_boss, hub_player, core_drone, core_boss])
	_check(absf(hub_elite - hub_boss) <= 0.5 and absf(hub_elite - hub_player) <= 0.5, "(a) A hub measures the same on an elite, a boss and the player (%.3f / %.3f / %.3f)" % [hub_elite, hub_boss, hub_player])
	_check(absf(core_drone - core_boss) <= 0.5, "(a) A core measures the same on a drone and a boss (%.3f / %.3f)" % [core_drone, core_boss])
	_check(absf(hub_elite - 30.0) <= HUB_TOLERANCE, "(b) A 15 px hub spans 30 px rim centre to rim centre (%.3f)" % hub_elite)
	_check(absf(core_drone - 68.0) <= HUB_TOLERANCE, "(b) A 34 px core spans 68 px (%.3f)" % core_drone)
	var small_elite: float = await _span(elite, "r2s0", MIN_ZOOM, 0)
	var small_boss: float = await _span(boss, "r2s0", MIN_ZOOM, 0)
	print("ladder spans at zoom %.4f: hub elite %.3f boss %.3f (ratio %.4f)" % [MIN_ZOOM, small_elite, small_boss, small_elite / hub_elite])
	_check(absf(small_elite - small_boss) <= 0.5 and absf(small_elite / hub_elite - MIN_ZOOM) <= 0.03, "(c) At minimum zoom hubs still match and shrink by the zoom (%.3f / %.3f, ratio %.4f)" % [small_elite, small_boss, small_elite / hub_elite])
	var later: float = await _span(elite, "r2s0", 1.0, 137)
	print("ladder span at tick 137: hub elite %.3f" % later)
	_check(absf(later - hub_elite) <= 0.5, "(d) Nothing scales with time: the same hub at tick 137 spans %.3f" % later)

	# Controls, one per line. A 16 px hub is 2 px wider: the ruler must see it.
	var fat_boss: float = await _span(_load("boss", func(s: ShipDefinition) -> void: _radius(s, "r2s0", 16.0)), "r2s0", 1.0, 0)
	_control("(a) a 16 px hub on the boss only (%.3f vs %.3f)" % [fat_boss, hub_elite], not (absf(hub_elite - fat_boss) <= 0.5))
	var fat_elite: float = await _span(_load("radial_elite", func(s: ShipDefinition) -> void: _radius(s, "r2s0", 16.0)), "r2s0", 1.0, 0)
	_control("(b) a 16 px hub (%.3f)" % fat_elite, not (absf(fat_elite - 30.0) <= HUB_TOLERANCE))
	var wrong_zoom: float = await _span(elite, "r2s0", 0.70, 0)
	_control("(c) rendered at 0.70 instead of the minimum zoom (ratio %.4f)" % (wrong_zoom / hub_elite), not (absf(wrong_zoom / hub_elite - MIN_ZOOM) <= 0.03))
	var breathing: ShipDefinition = _load("radial_elite")
	var breathing_span: float = await _span_scaled(breathing, "r2s0", 1.05)
	_control("(d) a hub scaled 1.05, as v0.3's breathing did (%.3f)" % breathing_span, not (absf(breathing_span - hub_elite) <= 0.5))

	print("Ship ladder pixels: failures=%d, controls %d/%d" % [failures, controls_caught, controls_total])
	quit(1 if failures or controls_caught != controls_total else 0)

## Measured on the first run and recorded in the S3 review: the ruler reads a 15 px hub as
## 30.0 +- this. It must stay under the 2 px a 16 px hub adds.
const HUB_TOLERANCE: float = 0.8

func _radius(ship: ShipDefinition, id: String, radius: float) -> void:
	for part: PartDefinition in ship.parts:
		if part.id == id: part.radius = radius

## The old breathing, reproduced through the pose: the hub's scale handed to the renderer as 1.05.
func _span_scaled(ship: ShipDefinition, id: String, scale: float) -> float:
	var renderer: ShipRenderer = ShipRenderer.new()
	root.add_child(renderer)
	renderer.position = AT
	renderer.set_ship(ship)
	renderer.set_process(false)
	renderer.set_motion_tick(0)
	var rig: ShipMotion.ShipRig = ShipMotion.get_rig(ship)
	var pose: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig)
	ShipMotion.step(rig, pose, 0)
	pose.scale[rig.index_of(id)] = scale
	renderer.external_pose = pose
	renderer._process(0)
	for i: int in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var index: int = rig.index_of(id)
	var centre: Vector2 = AT + pose.local[index]
	var across: Vector2 = _across(pose.local[index])
	var span: float = _rim(image, centre, across, rig.radius[index] * scale) + _rim(image, centre, -across, rig.radius[index] * scale)
	renderer.queue_free()
	await process_frame
	return span

func _check(condition: bool, label: String) -> void:
	if condition: print("ok: " + label)
	else:
		failures += 1
		push_error(label)

func _control(what_was_sabotaged: String, instrument_noticed: bool) -> void:
	controls_total += 1
	if instrument_noticed: controls_caught += 1
	else: push_error("Negative control not caught: " + what_was_sabotaged)
