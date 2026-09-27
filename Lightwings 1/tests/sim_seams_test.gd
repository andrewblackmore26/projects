extends SceneTree
## Modernization M1: the sim seams, measured. Each seam is behaviour-neutral today (the golden trace
## proves that); this proves each one does what later phases will rely on, and that each check can
## fail:
## - `sim_q` is an exact integer clock at 30/60/120/144 Hz;
## - the time-scale broker takes the LOWEST request and scales the dt the sim integrates;
## - `request_hitstop` freezes the sim and caps grants at 8 ticks per rolling 60;
## - every invulnerability grant goes through `_grant_invulnerability`;
## - RunController's time-scale API forwards to the live world.

const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")
const STEP: float = 1.0 / 60.0
const SCANNED_SOURCES: Array[String] = [
	"res://scripts/combat/combat_world.gd",
	"res://scripts/combat/combat_persistence.gd",
	"res://scripts/editor/workshop_combat_preview.gd",
	"res://scripts/main.gd",
	"res://scripts/world/run_controller.gd"]
## Right-hand sides that may be assigned to `player_invulnerable` outside the choke point: resets,
## the per-step decay, the choke point's own max, and snapshot restore.
const ALLOWED_ASSIGNMENTS: Array[String] = [
	"0.0",
	"maxf(0.0,player_invulnerable-dt)",
	"maxf(player_invulnerable,seconds)",
	"float(data.get(\"player_invulnerable\",0.0))"]

## A stand-in for main.gd: RunController only needs `app.combat` for the time-scale API.
class FakeApp extends Node:
	var combat: Variant = null

## The wrong broker, for the control: it lets the HIGHEST request win.
class MaxBroker extends RefCounted:
	var requests: Dictionary = {}
	func request_time_scale(reason: StringName, scale: float) -> void: requests[reason] = scale
	func release_time_scale(reason: StringName) -> void: requests.erase(reason)
	func time_scale() -> float:
		var highest: float = 1.0 if requests.is_empty() else 0.0
		for reason: StringName in requests: highest = maxf(highest, float(requests[reason]))
		return highest

var t: RefCounted

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("SIM SEAMS")
	_sim_q_rates()
	_time_scale_broker()
	_time_scale_integrates()
	_hitstop_freezes()
	_hitstop_cap()
	_invulnerability_grants()
	_invulnerability_source_scan()
	_arena_set_exits()
	await process_frame
	t.finish(self)

func make_world() -> CombatWorld:
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 400, [], w.arena.center)
	w.arena.exits.clear() # no membrane can engage a warp mid-measurement
	return w

func release(w: CombatWorld) -> void:
	w._clear_encounter()
	w.free()

## Steps one simulated second at `hz` and reports whether every step advanced sim_q by exactly
## 720/hz, whether the second summed to exactly 720, and whether `tick` still counted steps.
func _sim_q_exact(hz: int) -> Dictionary:
	var w: CombatWorld = make_world()
	var per_step: int = CombatWorld.SIM_Q_PER_SECOND / hz
	var every_step_exact: bool = CombatWorld.SIM_Q_PER_SECOND % hz == 0
	for i: int in range(hz):
		var before: int = w.sim_q
		w._physics_process(1.0 / float(hz))
		if w.sim_q - before != per_step: every_step_exact = false
	var result: Dictionary = {"exact": every_step_exact and w.sim_q == CombatWorld.SIM_Q_PER_SECOND, "sim_q": w.sim_q, "tick": w.tick}
	release(w)
	return result

func _sim_q_rates() -> void:
	for hz: int in [30, 60, 120, 144]:
		var measured: Dictionary = _sim_q_exact(hz)
		print("measure: sim_q hz=%d after_1s=%d tick=%d" % [hz, int(measured.sim_q), int(measured.tick)])
		t.check(bool(measured.exact), "sim_q advances by exactly %d per step at %d Hz and sums to 720 in one second (got %d)" % [720 / hz, hz, int(measured.sim_q)])
		t.check(int(measured.tick) == hz, "tick still counts one per step at %d Hz (got %d)" % [hz, int(measured.tick)])
	# 1/50 s is 14.4 units: no integer step is exact, so one second must not read 720.
	var fifty: Dictionary = _sim_q_exact(50)
	print("measure: sim_q hz=50 after_1s=%d (control)" % int(fifty.sim_q))
	t.control("a 1/50 s step, which is not a whole number of 1/720 s units", not bool(fifty.exact))

## The broker contract: lowest active request wins; releasing restores the next lowest, then 1.0.
func _lowest_wins(broker: Object) -> bool:
	var ok: bool = is_equal_approx(broker.time_scale(), 1.0)
	broker.request_time_scale(&"evolution", 0.25)
	broker.request_time_scale(&"menu", 0.5)
	broker.request_time_scale(&"boss_intro", 0.8)
	ok = ok and is_equal_approx(broker.time_scale(), 0.25)
	broker.release_time_scale(&"evolution")
	ok = ok and is_equal_approx(broker.time_scale(), 0.5)
	broker.release_time_scale(&"menu")
	broker.release_time_scale(&"boss_intro")
	ok = ok and is_equal_approx(broker.time_scale(), 1.0)
	return ok

func _time_scale_broker() -> void:
	var w: CombatWorld = make_world()
	t.check(_lowest_wins(w), "CombatWorld's broker: the lowest request wins and releases restore 1.0")
	var app: FakeApp = FakeApp.new()
	var run: RunController = RunController.new(app)
	t.check(is_equal_approx(run.time_scale(), 1.0), "RunController reads 1.0 with no world")
	app.combat = w
	run.request_time_scale(&"test", 0.4)
	t.check(is_equal_approx(w.time_scale(), 0.4) and is_equal_approx(run.time_scale(), 0.4), "RunController forwards a request to the live world")
	run.release_time_scale(&"test")
	t.check(is_equal_approx(w.time_scale(), 1.0), "RunController forwards a release to the live world")
	t.check(_lowest_wins(run), "RunController's broker API passes the same contract")
	t.control("a broker that lets the highest request win", not _lowest_wins(MaxBroker.new()))
	app.free()
	release(w)

## At 0.5 the sim integrates half the time: elapsed and sim_q both advance half as far.
func _half_speed_second(scaled: bool) -> Dictionary:
	var w: CombatWorld = make_world()
	if scaled: w.request_time_scale(&"test", 0.5)
	for i: int in range(60): w._physics_process(STEP)
	var result: Dictionary = {"elapsed": w.elapsed, "sim_q": w.sim_q, "ok": absf(w.elapsed - 0.5) < 1e-6 and w.sim_q == 360}
	release(w)
	return result

func _time_scale_integrates() -> void:
	var half: Dictionary = _half_speed_second(true)
	print("measure: time_scale=0.5 elapsed=%.6f sim_q=%d" % [float(half.elapsed), int(half.sim_q)])
	t.check(bool(half.ok), "At time scale 0.5, 60 steps of 1/60 s integrate 0.5 s (elapsed %.6f, sim_q %d)" % [float(half.elapsed), int(half.sim_q)])
	t.control("no time-scale request, so the half-speed check sees a full second", not bool(_half_speed_second(false).ok))

## Gets the player moving, requests `ticks` of hitstop, and reports whether the next `ticks` steps
## left position, tick and sim_q untouched and the step after that moved again.
func _hitstop_run(ticks: int) -> Dictionary:
	var w: CombatWorld = make_world()
	w.command.movement = Vector2.RIGHT
	for i: int in range(20): w._physics_process(STEP)
	var granted: int = w.request_hitstop(ticks, &"test")
	var at: Vector2 = Vector2(w.player.pos)
	var tick_before: int = w.tick
	var q_before: int = w.sim_q
	for i: int in range(5): w._physics_process(STEP)
	var frozen: bool = Vector2(w.player.pos) == at and w.tick == tick_before and w.sim_q == q_before
	w._physics_process(STEP)
	var resumed: bool = Vector2(w.player.pos).x > at.x and w.tick == tick_before + 1
	var result: Dictionary = {"granted": granted, "frozen": frozen, "resumed": resumed, "moved_px": Vector2(w.player.pos).x - at.x}
	release(w)
	return result

func _hitstop_freezes() -> void:
	var run: Dictionary = _hitstop_run(5)
	print("measure: hitstop ticks=5 granted=%d frozen=%s resumed=%s moved_after=%.2fpx" % [int(run.granted), str(run.frozen), str(run.resumed), float(run.moved_px)])
	t.check(int(run.granted) == 5 and bool(run.frozen), "5 ticks of hitstop freeze a moving player's position, tick and sim_q for 5 steps")
	t.check(bool(run.resumed), "The sim resumes on the step after the hitstop runs out")
	t.control("no hitstop requested, so the player keeps moving", not bool(_hitstop_run(0).frozen))

## Requests 20 ticks, then 5 more straight after, then 5 more once the window has rolled past.
func _hitstop_grants(cap_disabled: bool) -> Array[int]:
	var w: CombatWorld = make_world()
	w.hitstop_cap_disabled = cap_disabled
	var grants: Array[int] = []
	grants.append(w.request_hitstop(20, &"test"))
	while w.hitstop_remaining > 0: w._physics_process(STEP)
	grants.append(w.request_hitstop(5, &"test"))
	while w.hitstop_remaining > 0: w._physics_process(STEP)
	for i: int in range(CombatWorld.HITSTOP_WINDOW_TICKS): w._physics_process(STEP)
	grants.append(w.request_hitstop(5, &"test"))
	release(w)
	return grants

func _hitstop_cap() -> void:
	var grants: Array[int] = _hitstop_grants(false)
	print("measure: hitstop requests 20,5,(+60 ticks)5 granted=%s" % str(grants))
	t.check(grants[0] == 8, "A 20-tick request is clipped to the cap of 8 (granted %d)" % grants[0])
	t.check(grants[1] == 0, "Nothing more is granted inside the same 60-tick window (granted %d)" % grants[1])
	t.check(grants[2] == 5, "Once the window rolls past, a new request is granted in full (granted %d)" % grants[2])
	t.control("the hitstop cap disabled", _hitstop_grants(true)[0] != 8)

func _grants(w: CombatWorld, reason: StringName) -> int:
	return int(w.invulnerability_grants.get(reason, 0))

func _invulnerability_grants() -> void:
	var w: CombatWorld = make_world()
	w.setup_player("neutral", 1, 40, [], w.arena.center)
	w.collect_light(80.0, "fire")
	var reshape_before: int = _grants(w, &"reshape")
	t.check(w.evolve_hull("player_fire_t2_standard_a") and _grants(w, &"reshape") == reshape_before + 1 and is_equal_approx(w.player_invulnerable, 0.8), "Evolution's reshape grant goes through the choke point (0.8 s)")
	w.player_invulnerable = 0.0
	w.player.invulnerable = 0.0
	w._damage_actor(w.player, 15.1, 1)
	t.check(w.player_tier == 1 and _grants(w, &"regression") == 1 and is_equal_approx(w.player_invulnerable, 1.8), "The regression grant goes through the choke point and still gives 1.8 s")
	# Warp commit: hold into an open membrane past the 0.30 s threshold.
	w.player_invulnerable = 0.0
	w.arena.exits.assign([Vector2i.RIGHT])
	w.player.pos = w.arena.center + Vector2(w.arena.radius - 4.0, 0.0)
	w.player.vel = Vector2(200.0, 0.0)
	w.command.movement = Vector2.RIGHT
	for i: int in range(floori(0.30 / STEP) + 2): w._update_player(STEP)
	t.check(w.warp_locked() and _grants(w, &"warp") == 1 and w.player_invulnerable > 1.0, "The warp commit grant goes through the choke point (%.2f s)" % w.player_invulnerable)
	# The choke point keeps the max: a shorter grant cannot shorten a longer one.
	var held: float = w.player_invulnerable
	w._grant_invulnerability(0.1, &"test")
	t.check(is_equal_approx(w.player_invulnerable, held), "A shorter grant does not shorten a longer one")
	release(w)
	var bench: CombatWorld = make_world()
	bench.benchmark(10)
	t.check(_grants(bench, &"benchmark") == 1 and bench.player_invulnerable >= 1000000.0, "The benchmark grant goes through the choke point")
	release(bench)

## Structural half: no source assigns `player_invulnerable` anything but a reset, the decay, the
## choke point's own max or a snapshot restore. Returns the offending lines.
func _bypasses(source: String, path: String) -> Array[String]:
	var pattern: RegEx = RegEx.new()
	pattern.compile("\\bplayer_invulnerable\\s*=(?!=)\\s*([^#]*)")
	var found: Array[String] = []
	var lines: PackedStringArray = source.split("\n")
	for index: int in range(lines.size()):
		var hit: RegExMatch = pattern.search(lines[index])
		if hit == null: continue
		if hit.get_string(1).strip_edges() not in ALLOWED_ASSIGNMENTS: found.append("%s:%d %s" % [path, index + 1, lines[index].strip_edges()])
	return found

func _invulnerability_source_scan() -> void:
	var offenders: Array[String] = []
	var world_source: String = ""
	for path: String in SCANNED_SOURCES:
		var source: String = FileAccess.get_file_as_string(path)
		if not t.check(not source.is_empty(), "Source can be read: " + path): continue
		if path.ends_with("combat_world.gd"): world_source = source
		offenders.append_array(_bypasses(source, path))
	t.check(offenders.is_empty(), "No source grants invulnerability outside _grant_invulnerability (%s)" % str(offenders))
	var choke_line: String = "_grant_invulnerability(GameTuning.RESHAPE_SECONDS+GameTuning.REGRESSION_GRACE,&\"regression\")"
	t.check(world_source.contains(choke_line), "The regression grant site the control reverts exists")
	var reverted: String = world_source.replace(choke_line, "player_invulnerable=GameTuning.RESHAPE_SECONDS+GameTuning.REGRESSION_GRACE")
	t.control("the regression site reverted to a direct write", _bypasses(reverted, "reverted").size() == 1)

func _arena_set_exits() -> void:
	var arena: CircularArena = CircularArena.new()
	var same: Array[Vector2i] = arena.exits
	arena.set_exits([Vector2i.UP, [1, 0], "junk", [2]])
	t.check(arena.exits.size() == 2 and arena.exits[0] == Vector2i.UP and arena.exits[1] == Vector2i.RIGHT and is_same(arena.exits, same),"set_exits reads Vector2i and [x, y] entries, skips the rest, and refills the same array")
	t.check(not arena.sealed, "A new arena is not sealed")
