extends SceneTree
## Real pixels for the rail grammar's two shader additions and for pillar 5 on ship RIMS.
##  - style 5: a rail is a dashed ring, 2 on / 5 off, dimmer than a rim, with no running light.
##  - line kind 2: a set-piece line starts at its hub's centre and shows INSIDE the hub.
##  - pillar 5 ("light blue is the player; nothing else uses it"): a silver-chassis hull's rim vs
##    the player's, by the same max-normalised colour distance the projectile lines use (S0).
## A shader that fails to compile draws black, so the runner's SHADER ERROR grep is part of this.
const PILLAR5_MIN_DISTANCE: float = 0.20 # same threshold and reasoning as combat_fx_render_test

var failures: int = 0
var controls_caught: int = 0
var controls_total: int = 0
const AT: Vector2 = Vector2(640, 400)

func _initialize() -> void: _run.call_deferred()

func _load(name: String, mutate: Callable = Callable()) -> ShipDefinition:
	var errors: PackedStringArray = PackedStringArray()
	var ship: ShipDefinition = ShipGrammar.load_json("res://tests/fixtures/ships_v4/%s.json" % name, errors)
	if mutate.is_valid(): mutate.call(ship)
	ShipCompiler.compile(ship)
	return ship

func _render(ship: ShipDefinition, after: Callable = Callable()) -> Image:
	var renderer: ShipRenderer = ShipRenderer.new()
	root.add_child(renderer)
	renderer.position = AT
	if after.is_valid(): after.call(ship)
	renderer.set_ship(ship)
	renderer.set_process(false)
	renderer.set_motion_tick(0)
	renderer._process(0)
	for i: int in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	renderer.queue_free()
	await process_frame
	return image

func _sum(pixel: Color) -> float: return pixel.r + pixel.g + pixel.b

## Fraction of a ring's samples that are lit, and the brightest of them.
func _ring(image: Image, radius: float) -> Dictionary:
	var lit: int = 0
	var peak: float = 0.0
	var samples: int = 1440
	for i: int in range(samples):
		var at: Vector2 = AT + Vector2.from_angle(TAU * float(i) / float(samples)) * radius
		var value: float = _sum(image.get_pixel(int(round(at.x)), int(round(at.y))))
		if value > 0.05: lit += 1
		peak = maxf(peak, value)
	return {"fraction": float(lit) / float(samples), "peak": peak}

## Mean colour of the lit pixels on a circle's rim, divided by its largest channel.
func _rim_colour(image: Image, centre: Vector2, radius: float) -> Vector3:
	var total: Vector3 = Vector3.ZERO
	for i: int in range(360):
		var at: Vector2 = centre + Vector2.from_angle(TAU * float(i) / 360.0) * radius
		var pixel: Color = image.get_pixel(int(round(at.x)), int(round(at.y)))
		if _sum(pixel) > 0.6: total += Vector3(pixel.r, pixel.g, pixel.b)
	var top: float = maxf(total.x, maxf(total.y, total.z))
	return total / top if top > 0.0 else Vector3.ZERO

func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.use_hdr_2d = true
	# --- The rail dash. 140 is clear of every cluster on the boss's third rail? No: use the drone,
	# whose single rail at 52 carries three r4 nodes and nothing else.
	var drone: Image = await _render(_load("drone"))
	var rail: Dictionary = _ring(drone, 52.0)
	var rim: Dictionary = _ring(drone, 34.0)
	print("rail ring: lit fraction %.3f peak %.3f | core rim: lit fraction %.3f peak %.3f" % [rail.fraction, rail.peak, rim.fraction, rim.peak])
	_check(float(rail.fraction) > 0.20 and float(rail.fraction) < 0.55, "A rail is dashed: %.3f of its circumference is lit (2 on / 5 off is 0.29, plus three nodes and anti-aliasing)" % float(rail.fraction))
	_check(float(rim.fraction) > 0.95, "A core rim is solid: %.3f lit" % float(rim.fraction))
	var hidden: Image = await _render(_load("drone"), func(s: ShipDefinition) -> void:
		for part: PartDefinition in s.parts:
			if part.style == 5: part.style = -1
			if part.id.begins_with("r1s"): part.radius = 0.0)
	var solid_ring: Dictionary = _ring(hidden, 52.0)
	_control("the rail drawn as an ordinary solid ring (lit %.3f)" % float(solid_ring.fraction), not (float(solid_ring.fraction) < 0.55))

	# --- A set-piece line inside its hub. The radial elite's top hub sits at (0,-96); its red pin
	# runs from the hub's centre outward, so 8 px along it is well INSIDE the r15 hub.
	var elite_ship: ShipDefinition = _load("radial_elite", func(s: ShipDefinition) -> void: s.rails[1].phase = 0.0)
	var elite: Image = await _render(elite_ship)
	var inside: Vector2 = AT + Vector2(0, -96 - 8)
	var pin: Color = _peak(elite, inside)
	_check(pin.r > 0.5 and pin.r > pin.g * 2.0, "The v_rack's red pin is visible inside the hub (%s)" % str(pin))
	var clipped: Image = await _render(_load("radial_elite", func(s: ShipDefinition) -> void: s.rails[1].phase = 0.0), func(s: ShipDefinition) -> void:
		for part: PartDefinition in s.parts:
			if part.style == 6: part.style = -1)
	var gone: Color = _peak(clipped, inside)
	_control("set-piece lines clipped at the hub rim like ordinary lines (%s)" % str(gone), not (gone.r > 0.5 and gone.r > gone.g * 2.0))

	# --- Pillar 5 on ship rims: every enemy chassis colour against the player's blue.
	var player: Vector3 = _rim_colour(await _render(_load("player_t3")), AT, 34.0)
	_check(player != Vector3.ZERO, "The player's core rim is found")
	for colour: String in ["red", "yellow", "green", "violet", "silver"]:
		var image: Image = await _render(_load("drone", func(s: ShipDefinition) -> void:
			s.chassis_color = colour
			s.core_weapon = ""))
		var enemy: Vector3 = _rim_colour(image, AT, 34.0)
		var distance: float = enemy.distance_to(player)
		print("pillar5 rim %s: colour=%s distance_from_player=%.3f" % [colour, enemy, distance])
		_check(enemy != Vector3.ZERO and distance > PILLAR5_MIN_DISTANCE, "A %s chassis rim is not player light blue (distance %.3f)" % [colour, distance])
	var twin: Vector3 = _rim_colour(await _render(_load("player_t3")), AT, 34.0)
	print("pillar5 rim player (control): distance_from_player=%.3f" % twin.distance_to(player))
	_control("a second player hull through the same detector", not (twin.distance_to(player) > PILLAR5_MIN_DISTANCE))
	# 90 px out on the DRONE: past its one rail and nodes. (On the elite, 70 px crosses the arms.)
	_control("a rim sampled where there is none", _rim_colour(drone, AT, 90.0) == Vector3.ZERO)

	print("Rail rendering: failures=%d, controls %d/%d" % [failures, controls_caught, controls_total])
	quit(1 if failures or controls_caught != controls_total else 0)

func _peak(image: Image, at: Vector2) -> Color:
	var best: Color = Color.BLACK
	for y: int in range(int(at.y) - 2, int(at.y) + 3):
		for x: int in range(int(at.x) - 2, int(at.x) + 3):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.r > best.r: best = pixel
	return best

func _check(condition: bool, label: String) -> void:
	if condition: print("ok: " + label)
	else:
		failures += 1
		push_error(label)

func _control(what_was_sabotaged: String, instrument_noticed: bool) -> void:
	controls_total += 1
	if instrument_noticed: controls_caught += 1
	else: push_error("Negative control not caught: " + what_was_sabotaged)
