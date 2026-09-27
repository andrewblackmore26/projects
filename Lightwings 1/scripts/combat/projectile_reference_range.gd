extends Node2D
## Deterministic reference fixture. Bodies, ribbons, beams and impacts use the
## production renderer; only these isolated range trajectories are scripted.
const BulletCanvas = preload("res://scripts/combat/combat_canvas.gd")
const FxCanvas = preload("res://scripts/combat/fx_canvas.gd")
const Pool = preload("res://scripts/combat/bullet_pool.gd")
const LABELS: Array[String] = ["Pulse", "Seeker", "Rocket", "Ricochet", "Beam"]
const FLAGS: Array[int] = [0, Pool.HOMING, Pool.ROCKET, Pool.RICOCHET]
const RADII: Array[float] = [4.0, 4.5, 9.0, 5.0]
const SPEEDS: Array[float] = [372.0, 264.0, 192.0, 324.0]
var pool: LightBulletPool = Pool.new()
var fx: CombatFX = CombatFX.new()
var canvas: Node2D
var fx_canvas: Node2D
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var clock: float = 0.0
var ids: Array[int] = [-1, -1, -1, -1]
var cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var bounce_direction: float = 1.0
var beam_on: bool = false
var beam_spark: float = 0.0
var friendly: bool = false

func _ready() -> void:
	rng.seed = 727
	canvas = BulletCanvas.new()
	canvas.z_index = 10
	add_child(canvas)
	fx_canvas = FxCanvas.new()
	add_child(fx_canvas)

func _physics_process(dt: float) -> void:
	advance(dt)

func advance(dt: float) -> void:
	clock += dt
	fx.update(dt)
	for lane: int in range(4):
		var y: float = 44.0 + float(lane) * 56.0
		if ids[lane] < 0:
			cooldowns[lane] -= dt
			if cooldowns[lane] > 0.0: continue
			ids[lane] = pool.add(Vector2(110, y), Vector2(SPEEDS[lane], 0), -1, 0, 3, 0, 0 if friendly else 1, 0, FLAGS[lane], RADII[lane])
			fx.emit("muzzle", Vector2(110, y), Pool.projectile_color(FLAGS[lane]), rng)
		var index: int = ids[lane]
		var at: Vector2 = pool.positions[index] + Vector2(SPEEDS[lane] * dt, 0)
		if lane == 1: at.y = y + sin(at.x * 0.031) * 20.0
		if lane == 2: at.y = y + sin(at.x * 0.019) * 11.0
		if lane == 3:
			at.y += 204.0 * dt * bounce_direction
			if absf(at.y - y) >= 21.0:
				at.y = y + signf(at.y - y) * 21.0
				bounce_direction *= -1.0
				fx.emit("impact", at, Pool.RICOCHET_COLOR, rng)
		pool.positions[index] = at
		pool.ages[index] += dt
		pool.sample_history(index)
		if at.x >= 573.0:
			fx.emit("impact", Vector2(573, at.y), Pool.projectile_color(FLAGS[lane]), rng)
			pool.remove_at(pool.active_indices.find(index))
			ids[lane] = -1
			cooldowns[lane] = 0.7
	var next_beam: bool = fposmod(clock, 2.2) < 1.3
	if next_beam and not beam_on: fx.emit("muzzle", Vector2(110, 268), Pool.BEAM_COLOR, rng)
	beam_on = next_beam
	beam_spark -= dt
	if beam_on and beam_spark <= 0.0:
		fx.emit("beam_spark", Vector2(574, 268), Pool.BEAM_COLOR, rng)
		beam_spark = 0.12
	canvas.sync_pool(pool)
	fx_canvas.sync(fx)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 680, 316), Color("050507"))
	for lane: int in range(5):
		var y: float = 44.0 + float(lane) * 56.0
		var color: Color = Pool.projectile_color(FLAGS[lane]) if lane < 4 else Pool.BEAM_COLOR
		draw_circle(Vector2(588, y), 15, Color("141018"), true, -1, true)
		draw_arc(Vector2(588, y), 15, 0, TAU, 48, Color("7d7c77"), 1.5, true)
		draw_arc(Vector2(588, y), 6.5, 0, TAU, 32, Color("7d7c77"), 1.0, true)
		draw_circle(Vector2(110, y), 10, Color("0b1119"), true, -1, true)
		draw_arc(Vector2(110, y), 10, 0, TAU, 32, color, 1.6, true)
		draw_string(ThemeDB.fallback_font, Vector2(18, y + 4), LABELS[lane], HORIZONTAL_ALIGNMENT_LEFT, 74, 12, Color("9c9a92"))
	if beam_on: BulletCanvas.draw_beam(self, PackedVector2Array([Vector2(110, 268), Vector2(574, 268)]), clock, friendly)
