extends SceneTree
## Saving is safe in every warp phase (plan P6 item 6; modernization M9 snapshot version 4).
##
## M9 put every warp phase on a sim_q deadline and put sim_q and those deadlines in the snapshot,
## so a restore resumes the SAME tick of the same phase (before M9 it restarted the phase). Three
## parts:
##
##   real save  a commit driven through main.gd with `testing=false`, so RunController really writes
##              the save from inside the commit handler, restored into a fresh main.gd: it arrives
##              on the committed exit's reflected entry point on the same tick an uninterrupted
##              warp does (control: `warp_swap_done` not restored - the P10 phantom-warp bug shape);
##   every phase  PUSH, BREAK, TRAVEL, ARRIVAL, FADE (both halves): snapshot -> bytes -> restore into
##              a new world, then both worlds run on and must match tick for tick (control: the
##              same with `warp_swap_done` dropped from the payload);
##   legacy     version-3 payloads in each old phase (2 ZOOM_IN, 3 TRAVEL, 4 ARRIVAL, 5 ZOOM_OUT,
##              6 FADE) map to TRAVEL / TRAVEL / ARRIVAL / NONE / FADE, finish without a spring-back
##              and never re-fire the swap (P10's no-double-swap rule; control: the swap flag
##              forced false on a mapped TRAVEL restore).
##
## `combat.set_physics_process(false)` on every instance: the test steps the sim itself, so the
## engine's own physics catch-up during an `await` never races it (two time sources, one bug).
const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")
const STEP: float = 1.0 / 60.0
const EXIT_OFFSET: float = 0.3

var h: RefCounted

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	h = Harness.new("WARP PERSISTENCE")
	GameTuning.reset_feel()
	await _real_save()
	_every_phase()
	_legacy()
	h.finish(self)

# --- Part 1: the real save written from inside the commit handler ---------------------------

## Steps `combat` until ARRIVAL begins; returns [ticks, position on that tick's start of ARRIVAL].
func _run_to_arrival(combat: CombatWorld) -> Array:
	var at: Array[Vector2] = [Vector2.INF]
	combat.warp_arrived.connect(func() -> void: at[0] = Vector2(combat.player.pos))
	var ticks: int = 0
	while combat.warp_phase != World.WARP_ARRIVAL and ticks < 200:
		combat._physics_process(STEP)
		ticks += 1
	return [ticks, at[0]]

func _continue(slot: String) -> Node:
	var app: Node = load("res://scripts/main.gd").new()
	app.testing = true # the fresh instance must not immediately re-save
	root.add_child(app)
	await process_frame
	app._continue_game(slot)
	app.combat.set_physics_process(false)
	return app

func _real_save() -> void:
	SaveService.storage_root = "user://warp-persist-test-%d" % Time.get_ticks_usec()
	var app: Node = load("res://scripts/main.gd").new()
	app.testing = false # the point: exercise the real save path
	root.add_child(app)
	await process_frame
	app._new_game(false)
	var combat: CombatWorld = app.combat
	combat.set_physics_process(false)
	# Press 0.3 rad off the east bearing (still the east arc), so the arrival's reflected offset is
	# something a restore that lost the exit point would visibly miss.
	var outward: Vector2 = Vector2.from_angle(EXIT_OFFSET)
	combat.player_position = combat.arena.center + outward * (combat.arena.radius - 4.0)
	combat.player.vel = outward * 200.0
	combat.command.movement = outward
	combat.command.aim = outward
	var pre_commit_sector: Vector2i = app.campaign.current_sector
	var ticks: int = 0
	while not combat.warp_locked() and ticks < 200:
		combat._physics_process(STEP)
		ticks += 1
	h.check(app.campaign.current_sector != pre_commit_sector, "The sector swapped synchronously at commit")
	h.check(combat.warp_phase == World.WARP_BREAK, "The commit landed in BREAK")
	var saved: Dictionary = SaveService.load_snapshot("campaign").get("run", {}).get("combat", {})
	h.check(int(saved.get("version", 0)) == 4 and int(saved.get("warp_phase", -1)) == World.WARP_BREAK and bool(saved.get("warp_swap_done", false)), "The on-disk save is version 4, in BREAK, with the swap recorded as done (version %d, phase %d)" % [int(saved.get("version", 0)), int(saved.get("warp_phase", -1))])
	h.check(int(saved.get("sim_q", -1)) == combat.sim_q and int(saved.get("warp_deadline_q", -1)) == combat.warp_deadline_q, "The save carries sim_q and the phase deadline (%d, %d)" % [int(saved.get("sim_q", -1)), int(saved.get("warp_deadline_q", -1))])
	var direction: Vector2i = combat.warp_direction
	var expected_entry: Vector2 = combat.arena.entry_point(direction, combat.warp_exit_point)
	var uninterrupted: Array = _run_to_arrival(combat)

	var restored: Node = await _continue("campaign")
	h.check(restored.combat.warp_phase == World.WARP_BREAK and restored.combat.warp_direction == Vector2i.RIGHT, "Restore resumes BREAK toward the east arc (%s)" % restored.combat.warp_direction)
	restored.combat.command.movement = Vector2.ZERO
	var resumed: Array = _run_to_arrival(restored.combat)
	var error: float = Vector2(resumed[1]).distance_to(expected_entry)
	print("warp persistence: uninterrupted arrival after %d ticks, restored after %d, entry error %.3f px" % [int(uninterrupted[0]), int(resumed[0]), error])
	h.check(int(resumed[0]) == int(uninterrupted[0]), "The restored warp arrives on the same tick as the uninterrupted one (%d vs %d)" % [int(resumed[0]), int(uninterrupted[0])])
	h.check(error < 0.01, "It arrives exactly on the committed exit's reflected entry point (error %.3f px)" % error)
	h.check(restored.combat.player_invulnerable > 0.0, "It is still invulnerable at the start of ARRIVAL (%.3f s)" % restored.combat.player_invulnerable)

	# Control: the same save restored WITHOUT the swap flag springs back and never arrives.
	var sabotaged: Node = await _continue("campaign")
	sabotaged.combat._warp_swap_done = false
	sabotaged.combat.command.movement = Vector2.ZERO
	var lost: Array = _run_to_arrival(sabotaged.combat)
	h.control("warp_swap_done not restored (arrived: %s)" % str(Vector2(lost[1]) != Vector2.INF), Vector2(lost[1]) == Vector2.INF)
	for node: Node in [app, restored, sabotaged]: node.queue_free()
	await process_frame

# --- Part 2: every phase, in memory ----------------------------------------------------------

func make_world() -> CombatWorld:
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 400, [], Vector2.ZERO)
	w.warp_committed.connect(func(_direction: Vector2i) -> void: w.confirm_warp_swap())
	return w

func release(w: CombatWorld) -> void:
	w._clear_encounter()
	w.free()

## The save's own path: var_to_bytes and back (SaveService stores Godot variants).
func round_trip(data: Dictionary) -> Dictionary:
	return bytes_to_var(var_to_bytes(data))

func state(w: CombatWorld) -> Array:
	return [w.warp_phase, w.sim_q, w.player_position.snapped(Vector2(0.001, 0.001)), Vector2(w.player.vel).snapped(Vector2(0.001, 0.001)), w.warp_locked()]

## Runs a warp until the `ordinal`-th tick spent in `phase` (and, for FADE, the right half), saves
## there, restores into a fresh world, runs both 60 more ticks. Returns [the tick the two first
## disagree on (-1 = never), ticks the source had spent, whether the source was in `phase`].
func resume_matches(phase: int, reduced: bool, ordinal: int, drop_swap: bool = false) -> Array:
	var a: CombatWorld = make_world()
	a.warp_reduced = reduced
	var outward: Vector2 = Vector2.from_angle(0.2)
	a.player_position = a.arena.center + outward * (a.arena.radius - 120.0)
	a.player.vel = outward * 300.0
	a.command.movement = outward
	var seen: int = 0
	var ticks: int = 0
	while ticks < 200:
		a._physics_process(STEP)
		ticks += 1
		if a.warp_phase == phase:
			seen += 1
			if seen == ordinal: break
	var found: bool = a.warp_phase == phase
	var data: Dictionary = round_trip(a.snapshot())
	if drop_swap: data.erase("warp_swap_done")
	var b: CombatWorld = make_world()
	b.restore(data)
	b.command.movement = a.command.movement
	var diverged: int = -1
	for i: int in range(60):
		a._physics_process(STEP)
		b._physics_process(STEP)
		if diverged < 0 and state(a) != state(b): diverged = i + 1
	release(a)
	release(b)
	return [diverged, ticks, found]

func _every_phase() -> void:
	var cases: Array = [
		["PUSH", World.WARP_PUSH, false, 6],
		["BREAK (commit tick)", World.WARP_BREAK, false, 1],
		["BREAK", World.WARP_BREAK, false, 3],
		["TRAVEL", World.WARP_TRAVEL, false, 9],
		["ARRIVAL", World.WARP_ARRIVAL, false, 5],
		["FADE first half", World.WARP_FADE, true, 3],
		["FADE second half", World.WARP_FADE, true, 9],
	]
	for entry: Array in cases:
		var result: Array = resume_matches(int(entry[1]), bool(entry[2]), int(entry[3]))
		h.check(bool(result[2]) and int(result[0]) == -1, "Saved in %s (tick %d of the run), the restore runs on identical to the original for 60 ticks (first difference: %d)" % [entry[0], int(result[1]), int(result[0])])
	var control: Array = resume_matches(World.WARP_BREAK, false, 3, true)
	h.control("warp_swap_done dropped from a BREAK save (first difference at tick %d)" % int(control[0]), int(control[0]) > 0)

# --- Part 3: version-3 saves -----------------------------------------------------------------

## A version-3 payload in old phase `legacy`, built from a v4 save taken mid-TRAVEL (the ship's
## node, position and velocity are real), rewritten to the old keys.
func legacy_payload(legacy: int) -> Dictionary:
	var a: CombatWorld = make_world()
	a.player_position = a.arena.center + Vector2.RIGHT * (a.arena.radius - 4.0)
	a.player.vel = Vector2.RIGHT * 200.0
	a.command.movement = Vector2.RIGHT
	for i: int in range(20): a._physics_process(STEP)
	var data: Dictionary = round_trip(a.snapshot())
	release(a)
	for key: String in ["sim_q", "warp_push_q", "warp_commit_q", "warp_phase_start_q", "warp_deadline_q", "warp_invulnerable_q", "warp_contact_angle", "warp_approach", "warp_teleported", "warp_swap_done"]: data.erase(key)
	data.version = 3
	data.warp_phase = legacy
	data.warp_commit_speed = 88.0
	data.warp_exit_velocity = [88.0, 0.0]
	data.warp_reduced = legacy == 6
	return data

## Restores `data`, runs to the end of the warp. Returns [mapped phase, reached ARRIVAL, sprang
## back, swaps re-fired, ended in NONE].
func legacy_run(data: Dictionary, drop_swap: bool = false) -> Array:
	var b: CombatWorld = make_world()
	var fired: Array[int] = [0]
	b.warp_committed.connect(func(_direction: Vector2i) -> void: fired[0] += 1)
	var arrived: Array[bool] = [false]
	b.warp_arrived.connect(func() -> void: arrived[0] = true)
	var released: Array[bool] = [false]
	b.feel_event.connect(func(kind: StringName, _at: Vector2, _magnitude: float, _actor: int) -> void:
		if kind == &"warp_release": released[0] = true)
	b.restore(data)
	var mapped: int = b.warp_phase
	if drop_swap: b._warp_swap_done = false
	b.command.movement = Vector2.ZERO
	for i: int in range(90): b._physics_process(STEP)
	var result: Array = [mapped, arrived[0] or mapped == World.WARP_ARRIVAL, released[0], fired[0], b.warp_phase == World.WARP_NONE]
	release(b)
	return result

func _legacy() -> void:
	var expected: Dictionary = {2: World.WARP_TRAVEL, 3: World.WARP_TRAVEL, 4: World.WARP_ARRIVAL, 5: World.WARP_NONE, 6: World.WARP_FADE}
	for legacy: int in [2, 3, 4, 5, 6]:
		var result: Array = legacy_run(legacy_payload(legacy))
		var finishes: bool = legacy == 5 or (bool(result[1]) and not bool(result[2]))
		h.check(int(result[0]) == int(expected[legacy]) and finishes and int(result[3]) == 0 and bool(result[4]), "Version-3 phase %d restores as phase %d, %s, re-fires no swap (%d) and ends in NONE" % [legacy, int(result[0]), "no warp to finish" if legacy == 5 else ("arrives without a spring-back" if finishes else "DID NOT ARRIVE"), int(result[3])])
	var control: Array = legacy_run(legacy_payload(3), true)
	h.control("the swap flag forced false on a mapped TRAVEL restore (arrived %s, sprang back %s)" % [str(control[1]), str(control[2])], bool(control[2]) or not bool(control[1]))
