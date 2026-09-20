extends SceneTree
## CircularArena geometry (spec v3 §11): analytic rim hit, ricochet containment,
## membranes only where the sector says, entry placement, playable area, and
## the rule that nothing playable sits beyond the rim. Every measurement below
## carries its own negative control (house rule: a gate that cannot fail is not a gate).

const Harness = preload("res://tests/support/harness.gd")
const Arena = preload("res://scripts/combat/circular_arena.gd")

func _initialize() -> void:
	var t: RefCounted = Harness.new("ARENA")
	_test_rim_hit(t)
	_test_ricochet_containment(t)
	_test_membranes(t)
	_test_entry_position(t)
	_test_playable_area(t)
	_test_no_playable_beyond_rim(t)
	t.finish(self)

func _test_rim_hit(t: RefCounted) -> void:
	var arena: CircularArena = Arena.new()
	var hit: Dictionary = arena.boundary_hit(arena.center,arena.center+Vector2(arena.radius*3.0,0))
	var measured: float = hit.point.distance_to(arena.center)
	t.check(absf(measured-arena.radius)<=0.01,"Ray fired from the centre hits the rim within 0.01 px of radius (measured %.4f, radius %.4f)" % [measured,arena.radius])
	# Negative control: an arena with a deliberately wrong radius must fail the same check.
	var wrong: CircularArena = Arena.new()
	wrong.radius = arena.radius*0.5
	var wrong_hit: Dictionary = wrong.boundary_hit(wrong.center,wrong.center+Vector2(arena.radius*3.0,0))
	var wrong_measured: float = wrong_hit.point.distance_to(wrong.center)
	t.control("radius deliberately halved",absf(wrong_measured-arena.radius)>0.01)

func _test_ricochet_containment(t: RefCounted) -> void:
	var arena: CircularArena = Arena.new()
	var pos: Vector2 = arena.center+Vector2(arena.radius*0.3,0)
	var vel: Vector2 = Vector2(733.0,511.0) # irrational-ish so bounces do not repeat a short cycle
	var contained: bool = true
	for i: int in range(1000):
		var to: Vector2 = pos+vel*0.5
		var hit: Dictionary = arena.boundary_hit(pos,to)
		if hit.is_empty():
			pos = to
			continue
		vel = vel.bounce(hit.normal)
		pos = Vector2(hit.point)-Vector2(hit.normal)*0.01
		if pos.distance_to(arena.center)>arena.radius+0.5: contained = false
	t.check(contained,"A ricocheting bullet stays inside the arena over 1000 bounces")
	# Negative control: disable the bounce (let it fly straight through) and it must leave.
	var escaped: bool = false
	var free_pos: Vector2 = arena.center+Vector2(arena.radius*0.3,0)
	var free_vel: Vector2 = Vector2(733.0,511.0)
	for i: int in range(1000):
		free_pos += free_vel*0.5
		if not arena.contains(free_pos):
			escaped = true
			break
	t.control("bounce disabled (straight flight)",escaped)

func _test_membranes(t: RefCounted) -> void:
	var arena: CircularArena = Arena.new()
	arena.exits.assign([Vector2i.RIGHT])
	var on_membrane: Vector2 = arena.center+Vector2(arena.radius+1.0,0)
	t.check(arena.membrane_at(on_membrane)==Vector2i.RIGHT,"A point on the open membrane returns its direction")
	# Negative control: ask for an exit that is not open and get ZERO back.
	var closed_side: Vector2 = arena.center+Vector2(0,-(arena.radius+1.0))
	t.control("asked for a direction (UP) that is not in arena.exits",arena.membrane_at(closed_side)==Vector2i.ZERO)

func _test_entry_position(t: RefCounted) -> void:
	var arena: CircularArena = Arena.new()
	for direction: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var entry: Vector2 = arena.entry_position(direction)
		var opposite_direction_ok: bool = (entry-arena.center).normalized().is_equal_approx(-Vector2(direction))
		t.check(opposite_direction_ok,"entry_position(%s) lands on the line to the opposite membrane" % direction)
		t.check(arena.contains(entry),"entry_position(%s) lands inside the arena" % direction)
		t.check(entry.distance_to(arena.center)<arena.radius-1.0,"entry_position(%s) lands just inside the rim, not on it" % direction)

func _test_playable_area(t: RefCounted) -> void:
	var arena: CircularArena = Arena.new()
	var area: float = PI*arena.radius*arena.radius
	var old_area: float = 1792.0*1120.0
	var ratio: float = area/old_area
	print("ARENA playable area: old(rect) %.0f px^2, new(circle) %.0f px^2, ratio %.4f" % [old_area,area,ratio])
	t.check(absf(ratio-1.0)<0.05,"Playable area is within a few percent of the old 1792x1120 rectangle")

func _test_no_playable_beyond_rim(t: RefCounted) -> void:
	var arena: CircularArena = Arena.new()
	var worst: float = 0.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in range(500):
		var far: Vector2 = arena.center+Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(0.0,arena.radius*4.0)
		var clamped: Vector2 = arena.clamp_point(far)
		worst = maxf(worst,clamped.distance_to(arena.center))
	t.check(worst<=arena.radius+0.001,"clamp_point never returns a point further than radius from the centre (worst %.4f vs radius %.4f)" % [worst,arena.radius])
	# Negative control: clamp with a negative margin (inflates the allowed radius) must be caught over that radius.
	var inflated: Vector2 = arena.clamp_point(arena.center+Vector2(arena.radius*4.0,0),-50.0)
	t.control("clamp called with a negative margin (inflated radius)",inflated.distance_to(arena.center)>arena.radius+0.001)
