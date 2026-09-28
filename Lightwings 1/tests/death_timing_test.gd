extends SceneTree
## Modernization M12: death is a beat and the reboot needs no press, through the real main.gd.
## - death -> playing (the banner gone, the world active, a live player, the swallowed tick spent)
##   is under 0.5 s at the median AND at the max over 20 seeds, with NO input at all. Control: the
##   reboot moved to 0.6 s (each line gets caught on its own);
## - the beat: the world keeps running (sim_q advances) at 0.3 for the first 0.25 s, then at full
##   speed; the killing hit plus the beat's own hitstop freeze it for a few ticks first;
## - the banner is non-modal: no backdrop, no pause, no escape;
## - after the reboot the life's stats stay up as a ~2 s toast;
## - the reboot's cost and its save's, measured apart: the save (over RunController's 8 ms budget
##   when it was synchronous) now runs on the next frame, and the reboot itself stays under budget.
## Frames are simulated at a fixed 1/60 s (main.gd's _process and _physics_process, then the world),
## so the timings are exact and independent of the machine.

const Harness = preload("res://tests/support/harness.gd")
const DT: float = 1.0 / 60.0
const SEEDS: int = 20
const LIMIT_S: float = 0.5

var t: RefCounted
var app: Node

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("DEATH TIMING")
	SaveService.storage_root = "user://death-timing-%d" % Time.get_ticks_usec()
	app = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	var times: Array[float] = []
	for seed_index: int in range(SEEDS): times.append(_death_to_playing(seed_index,RunController.DEATH_REBOOT_S,seed_index == 0))
	var median: float = _median(times)
	var worst: float = times.max()
	print("measure: death -> playing over %d seeds, no input: median %.0f ms, max %.0f ms (reboot at %.2f s)" % [SEEDS,median*1000.0,worst*1000.0,RunController.DEATH_REBOOT_S])
	t.check(median < LIMIT_S,"Median death -> playing is under 0.5 s (%.0f ms)" % (median*1000.0))
	t.check(worst < LIMIT_S,"Max death -> playing over %d seeds is under 0.5 s (%.0f ms)" % [SEEDS,worst*1000.0])
	# Control: the reboot at 0.6 s. Each line must notice on its own.
	var slow: Array[float] = []
	for seed_index: int in range(SEEDS): slow.append(_death_to_playing(seed_index,0.6,false))
	t.control("reboot at 0.6 s (median %.0f ms)" % (_median(slow)*1000.0),_median(slow) >= LIMIT_S)
	t.control("reboot at 0.6 s (max %.0f ms)" % (slow.max()*1000.0),slow.max() >= LIMIT_S)
	await _reboot_cost()
	await app._stop_audio()
	app.queue_free()
	await process_frame
	t.finish(self)

func _median(values: Array[float]) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	return sorted[n/2] if n % 2 == 1 else (sorted[n/2-1]+sorted[n/2])*0.5

## One frame the way the engine runs it: main.gd's idle step, its physics step, then the world's.
func _frame() -> void:
	app._process(DT)
	app._physics_process(DT)
	if is_instance_valid(app.combat): app.combat._physics_process(DT)

func _playing() -> bool:
	return app.overlay_kind != "death" and is_instance_valid(app.combat) and app.combat.active and not bool(app.combat.player.get("dead",false)) and int(app._input_swallow_frames) == 0

## A run that has explored `seed_index % 4` nodes, killed; returns the real seconds until playing.
## `observe` also checks the beat itself on the way.
func _death_to_playing(seed_index: int, reboot_s: float, observe: bool) -> float:
	app._new_game(false)
	app.campaign.world_seed = 5000+seed_index
	app.combat.set_physics_process(false)
	for k: int in range(seed_index % 4):
		var dirs: Array[Vector2i] = app.campaign.neighbours_of(app.campaign.current_sector)
		if dirs.is_empty(): break
		app._enter_sector(app.campaign.current_sector+dirs[k % dirs.size()],app.combat.arena.entry_position(dirs[k % dirs.size()]),false)
	for frame: int in range(seed_index % 7): _frame()
	app.run_controller.death_reboot_s = reboot_s
	app.combat.player_invulnerable = 0.0
	app.combat.player.invulnerable = 0.0
	app.combat._damage_actor(app.combat.player,1000000.0,1,1) # fires _on_death synchronously
	var world: CombatWorld = app.combat
	if observe:
		t.check(app.overlay_kind == "death" and not paused and app.overlay.find_child("Backdrop",true,false) == null,"The death banner is up, non-modal: no backdrop and no pause")
		t.check(world.active and world.hitstop_remaining >= RunController.DEATH_HITSTOP_TICKS,"The world runs on through the beat, frozen first by %d hitstop tick(s)" % world.hitstop_remaining)
		t.check(is_equal_approx(world.time_scale(),RunController.DEATH_SLOWMO_SCALE),"The beat slows the world to %.1f (got %.2f)" % [RunController.DEATH_SLOWMO_SCALE,world.time_scale()])
	var seconds: float = 0.0
	var q_at_start: int = world.sim_q
	var scale_late: float = -1.0
	while seconds < 3.0 and not _playing():
		_frame()
		seconds += DT
		if observe and scale_late < 0.0 and seconds > RunController.DEATH_SLOWMO_SECONDS+DT and app.overlay_kind == "death": scale_late = world.time_scale()
	if observe:
		t.check(scale_late == 1.0,"After %.2f s the beat's slow motion is released (scale %.2f)" % [RunController.DEATH_SLOWMO_SECONDS,scale_late])
		t.check(world.sim_q > q_at_start or world != app.combat,"The world advanced during the beat")
		t.check(app.toast_stack.label.text.begins_with("SIGNAL LOST") and absf(app.toast_stack.remaining-RunController.DEATH_TOAST_SECONDS) <= 2.0*DT,"The life's stats stay up as a %.0f s toast: '%s'" % [RunController.DEATH_TOAST_SECONDS,app.toast_stack.label.text])
		t.check(app.combat.player_tier == 1 and app.campaign.current_sector == Vector2i.ZERO,"The next life starts at the origin as the seed hull")
	return seconds

## The reboot and its save for real (testing off, into this test's own storage root), measured
## apart: the reboot's own frame, then the save on the frame after it.
func _reboot_cost() -> void:
	var costs: Array[float] = []
	var saves: Array[float] = []
	for index: int in range(7):
		app._new_game(false)
		app.combat.set_physics_process(false)
		for frame: int in range(30): _frame()
		app.testing = false
		app.combat.player_invulnerable = 0.0
		app.combat.player.invulnerable = 0.0
		app.combat._damage_actor(app.combat.player,1000000.0,1,1)
		var saved_before: int = app.run_controller.save_timings_ms.size()
		app._reboot()
		var saved_in_reboot: bool = app.run_controller.save_timings_ms.size() != saved_before
		await process_frame
		app.testing = true
		costs.append(app.run_controller.last_reboot_ms)
		t.check(not saved_in_reboot and app.run_controller.save_timings_ms.size() == saved_before+1,"Reboot %d leaves its save to the next frame, which makes it" % index)
		if app.run_controller.save_timings_ms.size() > saved_before: saves.append(app.run_controller.save_timings_ms[-1])
	print("measure: reboot frame %.2f ms median, %.2f ms max; its save on the next frame %.2f ms median, %.2f ms max (budget %.0f ms)" % [_median(costs),costs.max(),_median(saves) if not saves.is_empty() else -1.0,saves.max() if not saves.is_empty() else -1.0,RunController.REBOOT_SAVE_BUDGET_MS])
	t.check(_median(costs) < RunController.REBOOT_SAVE_BUDGET_MS,"The reboot itself, its save deferred, costs under %.0f ms (median %.2f ms)" % [RunController.REBOOT_SAVE_BUDGET_MS,_median(costs)])
