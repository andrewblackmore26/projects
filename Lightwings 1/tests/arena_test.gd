extends SceneTree
## CircularArena geometry (spec v3 §11): analytic rim hit, ricochet containment,
## whole-rim exit arcs (M3), mirrored entry placement, playable area, and
## the rule that nothing playable sits beyond the rim. Every measurement below
## carries its own negative control (house rule: a gate that cannot fail is not a gate).

const Harness = preload("res://tests/support/harness.gd")
const Arena = preload("res://scripts/combat/circular_arena.gd")

func _initialize() -> void:
	var t: RefCounted = Harness.new("ARENA")
	_test_rim_hit(t)
	_test_ricochet_containment(t)
	_test_arcs(t)
	_test_entry_round_trip(t)
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

## Modernization M3 (retires the membrane_at checks): the whole rim exits, each angle to the
## nearest exit bearing; only `sealed` closes it.
func _test_arcs(t: RefCounted) -> void:
	var arena: CircularArena = Arena.new()
	arena.set_exits(CampaignState.NEIGHBOURS)
	var own_ok: bool = true
	for direction: Vector2i in CampaignState.NEIGHBOURS:
		for nudge: float in [-0.39, 0.0, 0.39]: # just inside +/-22.5 deg
			if arena.arc_of(arena.direction_angle(direction)+nudge)!=direction: own_ok = false
	t.check(own_ok,"On an interior node every rim angle within 22.5 deg of a bearing leads to that bearing")
	t.check(arena.arcs.size()==8,"An interior node's arc table has 8 arcs (measured %d)" % arena.arcs.size())
	arena.set_exits([Vector2i.RIGHT,Vector2i.LEFT])
	var up: float = arena.direction_angle(Vector2i.UP)
	var folded: Vector2i = arena.arc_of(up+0.01)
	t.check(folded==Vector2i.RIGHT and arena.arc_of(up-0.01)==Vector2i.LEFT,"A missing bearing's arc folds into its nearest neighbours (RIGHT/LEFT either side of UP)")
	# Negative control: the same angle asked of a node whose exits DO include UP answers UP.
	arena.set_exits([Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP])
	t.control("UP restored to the exits (the fold is caused by its absence)",arena.arc_of(up+0.01)!=folded)
	arena.sealed = true
	var sealed_ok: bool = true
	for i: int in range(72):
		if arena.arc_of(TAU*i/72.0)!=Vector2i.ZERO: sealed_ok = false
	t.check(sealed_ok,"A sealed rim leads nowhere at any angle")
	arena.sealed = false
	t.control("the same rim unsealed",arena.arc_of(0.0)!=Vector2i.ZERO)

## Modernization M3: an exit at bearing+u enters at the opposite bearing-u, 44 px in, and flying
## straight back out through the same geometry lands where you started with the velocity you had.
func _test_entry_round_trip(t: RefCounted) -> void:
	var arena: CircularArena = Arena.new()
	var worst: float = 0.0
	var worst_velocity: float = 0.0
	var worst_control: float = 0.0
	var mirrored_ok: bool = true
	var inside_ok: bool = true
	for direction: Vector2i in CampaignState.NEIGHBOURS:
		var bearing: float = arena.direction_angle(direction)
		for i: int in range(360):
			var u: float = -PI*0.25+PI*0.5*(float(i)+0.5)/360.0
			var start: Vector2 = arena.center+Vector2.from_angle(bearing+u)*arena.radius
			var velocity: Vector2 = Vector2.from_angle(bearing+u)*320.0
			var entry: Vector2 = arena.entry_point(direction,start)
			var arrive_v: Vector2 = arena.entry_velocity(direction,velocity)
			if absf(angle_difference((entry-arena.center).angle(),bearing+PI-u))>1e-4: mirrored_ok = false
			if not arena.contains(entry,arena.ENTRY_INSET-0.5): inside_ok = false
			var back_exit: Vector2 = arena.center+(entry-arena.center).normalized()*arena.radius
			var home: Vector2 = arena.entry_point(-direction,back_exit)
			var home_v: Vector2 = -arena.entry_velocity(-direction,-arrive_v)
			var expected: Vector2 = arena.center+Vector2.from_angle(bearing+u)*(arena.radius-arena.ENTRY_INSET)
			worst = maxf(worst,home.distance_to(expected))
			worst_velocity = maxf(worst_velocity,home_v.distance_to(velocity))
			# Negative control: the offset discarded (arrive at entry_position, as before M3).
			var flat_home: Vector2 = arena.entry_position(-direction)
			worst_control = maxf(worst_control,flat_home.distance_to(expected))
	t.check(mirrored_ok,"An exit at bearing+u enters at the opposite bearing-u (360 angles x 8 directions)")
	t.check(inside_ok,"Every arrival lands inside the arena, ENTRY_INSET px in")
	t.check(worst<=0.01,"Round trip exit -> neighbour -> back lands within 0.01 px of the start (worst %.5f px)" % worst)
	t.check(worst_velocity<=0.01,"Round trip keeps the velocity (worst %.5f px/s)" % worst_velocity)
	t.control("offset discarded - arrival at entry_position (worst %.1f px)" % worst_control,worst_control>0.01)
	# Velocity cone: more than 60 deg off the travel bearing is rotated onto the cone, magnitude kept.
	var sideways: Vector2 = Vector2(0,-300) # straight N while travelling E
	var turned: Vector2 = arena.entry_velocity(Vector2i.RIGHT,sideways)
	var off_deg: float = rad_to_deg(absf(angle_difference(0.0,turned.angle())))
	t.check(absf(off_deg-60.0)<1e-3 and absf(turned.length()-300.0)<1e-3,"A heading 90 deg off the travel bearing is turned to 60 deg, speed kept (measured %.4f deg, %.4f px/s)" % [off_deg,turned.length()])
	t.control("heading passed through unrotated (90 deg off)",absf(rad_to_deg(absf(angle_difference(0.0,sideways.angle())))-60.0)>=1e-3)
	# Clamp: a folded corner arc can be far wider than 45 deg; the arrival stays within 45 deg of the
	# opposite bearing.
	var wide: Vector2 = arena.center+Vector2.from_angle(PI*0.5)*arena.radius # 90 deg off an E exit
	var clamped_deg: float = rad_to_deg(absf(angle_difference(PI,(arena.entry_point(Vector2i.RIGHT,wide)-arena.center).angle())))
	t.check(absf(clamped_deg-45.0)<1e-3,"An exit 90 deg off its bearing arrives clamped to 45 deg off the opposite bearing (measured %.4f deg)" % clamped_deg)

func _test_entry_position(t: RefCounted) -> void:
	var arena: CircularArena = Arena.new()
	for direction: Vector2i in CampaignState.NEIGHBOURS:
		var entry: Vector2 = arena.entry_position(direction)
		var opposite_direction_ok: bool = (entry-arena.center).normalized().is_equal_approx(-Vector2(direction).normalized())
		t.check(opposite_direction_ok,"entry_position(%s) lands on the line to the opposite bearing" % direction)
		var zero_offset: Vector2 = arena.entry_point(direction,arena.center+Vector2(direction).normalized()*arena.radius)
		t.check(zero_offset.distance_to(entry)<0.01,"entry_point with a zero offset is entry_position(%s)" % direction)
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
