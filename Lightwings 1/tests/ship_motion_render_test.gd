extends SceneTree
## Real Vulkan pixels: an orbiting circle must be drawn where ShipMotion says
## it is, not at its authored rest position, and a hull with ~120 circles and
## ~119 lines (the boss-scale slot-overflow detector) must still draw its
## LAST line. Headless has no renderer and a failed shader renders black
## (lessons.md), so this needs a real window.

var failures: int = 0
var controls_caught: int = 0
var controls_total: int = 0
var scene: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.use_hdr_2d = true
	scene = Node2D.new()
	root.add_child(scene)
	await _orbit_case()
	await _overflow_case()
	print("Ship motion pixels: failures=", failures, " controls_caught=", controls_caught, "/", controls_total)
	scene.queue_free()
	await process_frame
	quit(1 if failures or controls_caught != controls_total else 0)

func _orbit_ship() -> ShipDefinition:
	var definition: ShipDefinition = ShipDefinition.new()
	definition.is_player = true
	definition.core_radius = 6.0
	var core: PartDefinition = PartDefinition.new()
	core.id = "core"
	core.shape = "circle"
	core.radius = 6.0
	definition.parts.append(core)
	var arm: PartDefinition = PartDefinition.new()
	arm.id = "arm"
	arm.shape = "circle"
	arm.radius = 8.0
	arm.position = Vector2(50, 0)
	arm.parent_id = "core"
	arm.color_role = "player"
	definition.parts.append(arm)
	var group: GroupDefinition = GroupDefinition.new()
	group.root_id = "arm"
	group.orbit_radius = 50.0
	group.orbit_speed = 2.0
	definition.groups.append(group)
	return definition

func _orbit_case() -> void:
	var definition: ShipDefinition = _orbit_ship()
	var rig: ShipMotion.ShipRig = ShipMotion.get_rig(definition)
	var pose: ShipMotion.ShipPose = ShipMotion.ShipPose.new(rig)
	var tick: int = 45 # 0.75s at orbit_speed 2.0 rad/s: a clear displacement from rest
	ShipMotion.step(rig, pose, tick)
	var arm_index: int = rig.index_of("arm")
	# Sample the rim (stroke), not the fill: a mount's fill color is
	# deliberately dark, only its outline/running light is bright.
	var rim_offset: Vector2 = Vector2(8, 0)
	var moved: Vector2 = pose.local[arm_index] + rim_offset
	var rest: Vector2 = rig.rest[arm_index] + rim_offset
	var at: Vector2 = Vector2(300, 300)
	# Moving case: renderer driven by the sim's tick.
	var moving: ShipRenderer = ShipRenderer.new()
	scene.add_child(moving)
	moving.position = at
	moving.set_ship(definition)
	moving.set_process(false)
	moving.set_motion_tick(tick)
	moving._process(0)
	await _frame()
	var moving_image: Image = root.get_texture().get_image()
	_check(_bright(moving_image, Vector2i(at + moved)), "Rim pixels found at the position the sim reports")
	_check(not _bright(moving_image, Vector2i(at + rest)), "Rim pixels are NOT found at the authored rest position")
	moving.queue_free()
	await process_frame
	# Control: pose upload disabled (tick pinned to 0, i.e. never stepped) -
	# the "moved away from rest" claim must now fail.
	var frozen: ShipRenderer = ShipRenderer.new()
	scene.add_child(frozen)
	frozen.position = at
	frozen.set_ship(definition)
	frozen.set_process(false)
	frozen.set_motion_tick(0)
	frozen._process(0)
	await _frame()
	var frozen_image: Image = root.get_texture().get_image()
	_control("pose upload disabled (tick pinned to 0)", not _bright(frozen_image, Vector2i(at + moved)))
	frozen.queue_free()
	await process_frame

func _overflow_case() -> void:
	var definition: ShipDefinition = ShipDefinition.new()
	definition.is_player = false
	definition.element = "corruption"
	definition.core_radius = 4.0
	var core: PartDefinition = PartDefinition.new()
	core.id = "core"
	core.shape = "circle"
	core.radius = 4.0
	definition.parts.append(core)
	var previous_id: String = "core"
	var last_position: Vector2 = Vector2.ZERO
	var count: int = 119
	for i: int in range(count):
		var node: PartDefinition = PartDefinition.new()
		node.id = "n%d" % i
		node.shape = "circle"
		node.radius = 3.0
		node.position = Vector2(20 + i * 4, 0)
		node.parent_id = "core"
		definition.parts.append(node)
		var line: PartDefinition = PartDefinition.new()
		line.id = "line%d" % i
		line.shape = "line"
		line.from_id = previous_id
		line.to_id = node.id
		definition.parts.append(line)
		previous_id = node.id
		last_position = node.position
	_check(definition.parts.size() == 1 + count * 2, "Synthetic hull has 120 circles and 119 lines")
	var renderer: ShipRenderer = ShipRenderer.new()
	scene.add_child(renderer)
	renderer.position = Vector2(200, 600)
	renderer.set_ship(definition)
	renderer.set_process(false)
	renderer._process(0)
	await _frame()
	var image: Image = root.get_texture().get_image()
	var midpoint: Vector2 = renderer.position + Vector2(20 + (count - 1) * 4, 0).lerp(Vector2(20 + (count - 2) * 4, 0), 0.5)
	_check(_bright(image, Vector2i(midpoint)), "The last line of a ~120-circle/119-line hull is drawn (slot-overflow detector)")
	renderer.queue_free()
	await process_frame

func _bright(image: Image, at: Vector2i) -> bool:
	for y: int in range(at.y - 2, at.y + 3):
		for x: int in range(at.x - 2, at.x + 3):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			var pixel: Color = image.get_pixel(x, y)
			if pixel.r + pixel.g + pixel.b > 0.3: return true
	return false

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
