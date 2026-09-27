extends SceneTree
const ReferenceRange = preload("res://scripts/combat/projectile_reference_range.gd")
const Harness = preload("res://tests/support/harness.gd")
var fixture: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var t: RefCounted = Harness.new("PROJECTILE_REFERENCE_RENDER")
	root.size = Vector2i(1280, 800)
	fixture = ReferenceRange.new()
	fixture.position = Vector2(130, 155)
	fixture.scale = Vector2(1.5, 1.5)
	root.add_child(fixture)
	fixture.set_physics_process(false)
	for tick: int in range(45): fixture.advance(1.0 / 60.0)
	await _frame()
	var image: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://artifacts/living-reference")
	var encoded: Image = Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()): encoded.set_pixel(x, y, image.get_pixel(x, y).linear_to_srgb())
	encoded.save_png("res://artifacts/living-reference/projectile-range-1280x800.png")
	t.check(fixture.canvas.trail_mesh.multimesh.visible_instance_count == 4, "all four reference bodies have their own GPU ribbon")
	for lane: int in range(4):
		var at: Vector2 = fixture.to_global(fixture.pool.positions[fixture.ids[lane]])
		var radius: float = fixture.RADII[lane] * 1.5
		var rim: float = _brightness(image, at + Vector2(radius, 0), 2)
		var center: float = _brightness(image, at, 0)
		t.check(rim > 0.4, "type %d has a visible saturated circular rim (%.3f)" % [lane, rim])
		if lane != 2: t.check(center < rim * 0.6, "type %d keeps a dark circular body" % lane)
		var tail: Vector2 = fixture.to_global(fixture.pool.history_position(fixture.ids[lane], 4))
		t.check(_brightness(image, tail, 1) > 0.25, "type %d actual recorded path renders as a ribbon" % lane)
	var seeker: Vector2 = fixture.to_global(fixture.pool.positions[fixture.ids[1]])
	var halo: float = (4.5 + 2.5 + sin(fixture.clock * 13.0) * 1.2) * 1.5
	t.check(_brightness(image, seeker + Vector2(0, -halo), 1) > 0.25, "radius-4.5 seeker has an external pulsing halo")
	fixture.canvas.trail_mesh.visible = false
	await _frame()
	var no_ribbon: Image = root.get_texture().get_image()
	var tail_point: Vector2 = fixture.to_global(fixture.pool.history_position(fixture.ids[0], 5))
	t.control("ribbon pass hidden", _brightness(no_ribbon, tail_point, 1) < _brightness(image, tail_point, 1) * 0.3)
	fixture.canvas.trail_mesh.visible = true
	fixture.friendly = true
	for index: int in fixture.pool.active_indices: fixture.pool.factions[index] = 0
	fixture.canvas.sync_pool(fixture.pool)
	await _frame()
	var friendly: Image = root.get_texture().get_image()
	var pulse: Vector2 = fixture.to_global(fixture.pool.positions[fixture.ids[0]])
	t.check(_brightness(friendly, pulse, 0) > _brightness(image, pulse, 0) + 0.3, "friendly shot adds a centre pip without replacing its type hue")
	var rocket: Vector2 = fixture.to_global(fixture.pool.positions[fixture.ids[2]])
	fixture.pool.ages[fixture.ids[2]] += 0.2
	fixture.canvas.sync_pool(fixture.pool)
	await _frame()
	var rotated: Image = root.get_texture().get_image()
	t.check(_difference(friendly, rotated, rocket, 7) > 0.02, "rocket diameter visibly rotates with simulation age")
	fixture.canvas.sync_pool(fixture.pool)
	await _frame()
	var paused: Image = root.get_texture().get_image()
	t.check(_difference(rotated, paused, rocket, 7) < 0.001, "paused projectile age freezes its internal motion")
	var beam_y: float = fixture.to_global(Vector2(110, 268)).y
	for i: int in range(4):
		var fraction: float = fposmod(fixture.clock * 0.85 + float(i) * 0.25, 1.0)
		var point: Vector2 = fixture.to_global(Vector2(110 + 464 * fraction, 268))
		t.check(_brightness(image, Vector2(point.x, beam_y + 3.5), 0) > 0.3, "beam travelling pulse %d has visible circular extent beyond its core" % i)
	# Static GPU instances stay allocated across holes/reuse, but cannot reveal a
	# removed projectile's old history even while the other three keep drawing.
	var removed_id: int = fixture.ids[0]
	fixture.pool.remove_at(fixture.pool.active_indices.find(removed_id))
	fixture.canvas.sync_pool(fixture.pool)
	await _frame()
	var removed_image: Image = root.get_texture().get_image()
	t.check(_brightness(removed_image, tail_point, 1) < _brightness(image, tail_point, 1) * 0.3, "inactive static ribbon slot does not draw stale samples")
	var reused_id: int = fixture.pool.add(Vector2(80, 70), Vector2.RIGHT, -1, 3, 3, 0, 0, 0)
	fixture.canvas.sync_pool(fixture.pool)
	await _frame()
	var reused_image: Image = root.get_texture().get_image()
	t.check(reused_id == removed_id and _brightness(reused_image, tail_point, 1) < _brightness(image, tail_point, 1) * 0.3, "reused static ribbon slot remains hidden until it has a fresh path")
	fixture.queue_free()
	await process_frame
	t.finish(self)

func _frame() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func _brightness(image: Image, at: Vector2, spread: int) -> float:
	var brightest: float = 0.0
	for y: int in range(roundi(at.y) - spread, roundi(at.y) + spread + 1):
		for x: int in range(roundi(at.x) - spread, roundi(at.x) + spread + 1):
			var color: Color = image.get_pixel(x, y)
			brightest = maxf(brightest, color.r + color.g + color.b)
	return brightest

func _difference(a: Image, b: Image, at: Vector2, spread: int) -> float:
	var total: float = 0.0
	for y: int in range(roundi(at.y) - spread, roundi(at.y) + spread + 1):
		for x: int in range(roundi(at.x) - spread, roundi(at.x) + spread + 1):
			var before: Color = a.get_pixel(x, y)
			var after: Color = b.get_pixel(x, y)
			total += absf(before.r - after.r) + absf(before.g - after.g) + absf(before.b - after.b)
	return total / float((spread * 2 + 1) * (spread * 2 + 1))
