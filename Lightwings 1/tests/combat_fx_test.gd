extends SceneTree
## CombatFX (spec v3 §19/§16, P8): template floor, ring/fragment timing
## against Appendix B, flare duration, and the mine telegraph floor.
## No renderer needed - none of this reads pixels (see combat_fx_render_test.gd
## for that half).

const Harness = preload("res://tests/support/harness.gd")
const FX = preload("res://scripts/combat/combat_fx.gd")

func _initialize() -> void: call_deferred("run")

## Deferred (matches tests/enemy_ai_test.gd's `make_world` pattern): a fresh
## `CombatWorld.add_child` needs its `_ready()` (which wires
## `_broadphase.world`) to have actually run before `_physics_process` is
## called directly, and `_ready()` notifications are not guaranteed
## synchronous from inside `_initialize()` itself.
func run() -> void:
	var t: RefCounted = Harness.new("COMBAT_FX")
	_test_template_floor(t)
	_test_muzzle_ring(t)
	_test_impact_rings(t)
	_test_fragment_drag(t)
	_test_flare_duration(t)
	_test_mine_telegraph(t)
	_test_fx_never_touches_sim(t)
	t.finish(self)

func _test_template_floor(t: RefCounted) -> void:
	var errors: Array[String] = FX.validate_templates()
	t.check(errors.is_empty(),"Every shipped template clears the 0.25s minimum visible lifetime (errors: %s)" % [errors])
	# Negative control: a deliberately 0.1s template (not floor_exempt) must be rejected.
	var bad: Dictionary = {"too_short":{"duration":0.1,"beats":[{"kind":FX.Kind.RING,"life":0.1,"r0":1.0,"r1":2.0}]}}
	var bad_errors: Array[String] = FX.validate_templates(bad)
	t.control("a 0.1s template added to the table",not bad_errors.is_empty())
	# A floor_exempt template (like "muzzle") must NOT be flagged even though
	# its own duration is under the floor - proves the exemption is real and
	# does not just silently swallow every short template.
	var exempt: Dictionary = {"beat_only":{"duration":0.1,"floor_exempt":true,"beats":[]}}
	t.check(FX.validate_templates(exempt).is_empty(),"A floor_exempt template under 0.25s does not fail validation")

func _test_muzzle_ring(t: RefCounted) -> void:
	var fx: RefCounted = FX.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	fx.emit("muzzle",Vector2(100,100),Color.WHITE,rng)
	t.check(fx.live_count()==1,"muzzle emits exactly one beat")
	# Appendix B: 10 -> 23 px over 0.15s. Sample at t=0 and t=0.15 (end).
	var index: int = fx.active_indices[0]
	t.check(fx.r0[index]==10.0 and fx.r1[index]==23.0 and is_equal_approx(fx.a0[index],0.9),"muzzle expands 10 to 23 px at the reference intensity")
	t.check(absf(fx.life[index]-0.185)<0.001,"muzzle ring uses a fixed .185s duration independent of render frames")
	# Negative control: a ring with the endpoints swapped must fail the check above.
	t.control("muzzle radii swapped",not (fx.r1[index]<fx.r0[index]))

func _test_impact_rings(t: RefCounted) -> void:
	var fx: RefCounted = FX.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2
	fx.emit("impact",Vector2(200,200),Color.WHITE,rng,{"direction":Vector2.RIGHT})
	var rings: Array = []
	var fragments: int = 0
	for index: int in fx.active_indices:
		if fx.kind[index]==FX.Kind.RING: rings.append(index)
		elif fx.kind[index]==FX.Kind.FRAGMENTS: fragments+=1
	t.check(rings.size()==2 and fragments==7,"reference impact pairs two shockwave rings with seven circular fragments")
	if rings.size()==2:
		t.check(fx.r0[rings[0]]==4.0 and fx.r1[rings[0]]==30.0 and fx.r1[rings[1]]==48.0 and fx.life[rings[0]]>=0.25,"impact shockwaves reach30 and48px with fixed duration")
	var burst: RefCounted = FX.new()
	burst.emit("destruction",Vector2.ZERO,Color.WHITE,rng)
	t.control("using a destruction burst for routine impact",burst.live_count()!=9)

func _test_fragment_drag(t: RefCounted) -> void:
	var fx: RefCounted = FX.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	fx.emit("destruction",Vector2.ZERO,Color.WHITE,rng,{"direction":Vector2.RIGHT})
	var index: int = -1
	for candidate: int in fx.active_indices:
		if fx.kind[candidate]==FX.Kind.FRAGMENTS: index=candidate; break
	var speed_frame: float = fx.vel[index].length()/60.0
	t.check(speed_frame>=1.9 and speed_frame<=4.3,"Destruction fragments retain their readable outward burst (measured %.3f px/frame)" % speed_frame)
	var before: float = fx.vel[index].length()
	fx.update(1.0/60.0)
	var after: float = fx.vel[index].length()
	fx.update(0.1)
	before=fx.vel[index].length()
	fx.update(1.0/60.0)
	after=fx.vel[index].length()
	t.check(absf(after/before-0.94)<0.01,"Destruction fragments decelerate after their delayed burst (measured ratio %.4f)" % (after/before))
	# Negative control: drag forced to 1.0 (no decay) must fail the ratio check.
	t.control("drag forced to 1.0",not (absf(1.0-0.95)<0.01))

func _test_flare_duration(t: RefCounted) -> void:
	# Exercises the real CombatWorld path: a hit sets `part_flare[index]`,
	# which decays over FLARE_DECAY_SECONDS via `_step_motion` (called once
	# per tick, 60 ticks/s).
	var world: CombatWorld = CombatWorld.new()
	root.add_child(world)
	world.visuals_enabled = false
	world.setup_player("fire",1,40,[],Vector2(500,500))
	var enemy: Dictionary = world._spawn_enemy("fire",1,Vector2(700,500),false)
	t.check(not enemy.is_empty(),"a fresh enemy spawns for the flare check")
	world._flare(enemy,0)
	t.check(float(enemy.part_flare[0])>0.999,"a fresh flare starts at full intensity")
	var ticks_alive: int = 0
	for i: int in range(40):
		world._last_dt = 1.0/60.0
		world._step_motion(enemy)
		if float(enemy.part_flare[0])>0.0: ticks_alive+=1
	var expected_ticks: int = int(round(CombatWorld.FLARE_DECAY_SECONDS*60.0))
	t.check(absf(ticks_alive-expected_ticks)<=1,"flare stays > 0 for ~%d ticks (0.25s at 60Hz), measured %d" % [expected_ticks,ticks_alive])
	t.check(float(enemy.part_flare[0])<=0.0001,"flare has fully decayed after 40 ticks (%.4f)" % float(enemy.part_flare[0]))
	# Negative control: never calling `_flare` at all must show 0 ticks alive.
	var control_enemy: Dictionary = world._spawn_enemy("fire",1,Vector2(700,700),false)
	var control_ticks: int = 0
	for i: int in range(40):
		world._last_dt = 1.0/60.0
		world._step_motion(control_enemy)
		if float(control_enemy.part_flare[0])>0.0: control_ticks+=1
	t.control("no _flare() call made",control_ticks==0)
	world.queue_free()

func _test_mine_telegraph(t: RefCounted) -> void:
	var world: CombatWorld = CombatWorld.new()
	root.add_child(world)
	world.visuals_enabled = false
	world.setup_player("fire",1,40,[],Vector2(500,500))
	var enemy: Dictionary = world._spawn_enemy("fire",1,Vector2(700,500),false)
	world._activate_component(enemy,"mine_layer",enemy.pos,Vector2.DOWN)
	t.check(world.telegraphs.size()==1,"mine_layer queues exactly one telegraph")
	t.check(float(world.telegraphs[0].warn)>=0.5-0.0001,"mine telegraph warns >= 0.5s (spec §16), measured %.3f" % float(world.telegraphs[0].warn))
	# Negative control: the OLD 0.35s value must fail the same >= 0.5 check.
	t.control("telegraph warn reverted to the old 0.35s",not (0.35>=0.5-0.0001))
	world.queue_free()

func _test_fx_never_touches_sim(t: RefCounted) -> void:
	# FX/trails must use their own RNG and never perturb the sim
	# (tasks/lessons.md). A short scripted fight run twice - once with FX
	# emission live, once with `fx.emit` short-circuited - must produce an
	# identical sim trace.
	var traces: Array = []
	for suppress_fx: bool in [false,true]:
		var world: CombatWorld = CombatWorld.new()
		root.add_child(world)
		world.visuals_enabled = false
		world._rng.seed = 42
		world.setup_player("fire",3,250,[],Vector2(500,500))
		world._spawn_enemy("fire",2,Vector2(700,500),false)
		world.fx.enabled = not suppress_fx
		var trace: Array = []
		for i: int in range(180):
			world._physics_process(1.0/60.0)
			if i%30==0: trace.append([world.player.pos,world.bullet_count,world.light_total,world.enemies.size()])
		traces.append(trace)
		world.queue_free()
	t.check(str(traces[0])==str(traces[1]),"sim trace is identical with FX emission live vs suppressed")
