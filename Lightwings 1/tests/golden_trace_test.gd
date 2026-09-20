extends SceneTree
## Golden trace: one fixed-seed scripted life through the real main.gd, fingerprinted step by step.
## Its job is to prove that a refactor changed no behaviour: the fingerprints must equal the ones
## recorded in tests/fixtures/golden_trace.json. When a phase changes behaviour on purpose, re-record
## and say so in tasks/todo.md:
##   Godot --headless --path <project> --script res://tests/golden_trace_test.gd -- --record
##
## The route never awaits, and combat is stepped by hand at a fixed 1/60 s, so no engine frame
## (with its real, variable delta) can run in the middle of it.

const Harness = preload("res://tests/support/harness.gd")
const GOLDEN_PATH: String = "res://tests/fixtures/golden_trace.json"
const STEP: float = 1.0 / 60.0
var app: Node

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var t: RefCounted = Harness.new("GOLDEN TRACE")
	SaveService.storage_root = "user://golden-trace-%d" % Time.get_ticks_usec()
	app = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	await process_frame
	var first: Array = _route(false)
	await process_frame
	var second: Array = _route(false)
	await process_frame
	var sabotaged: Array = _route(true)
	t.check(_first_difference(first,second) == "","The same route fingerprints identically twice in one process (first difference: %s)" % _first_difference(first,second))
	t.control("one movement command reversed during the first fight",_first_difference(first,sabotaged) != "")
	if "--record" in OS.get_cmdline_user_args():
		var file: FileAccess = FileAccess.open(GOLDEN_PATH,FileAccess.WRITE)
		file.store_string(JSON.stringify({"note":"Recorded by tests/golden_trace_test.gd --record. Re-record only when behaviour changes on purpose.","steps":first},"\t"))
		file.close()
		print("golden trace recorded: %d steps, final %s" % [first.size(),first[-1].snapshot])
	else:
		var golden: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
		var steps: Array = golden.get("steps",[]) if golden is Dictionary else []
		if t.check(not steps.is_empty(),"A recorded golden trace exists at "+GOLDEN_PATH):
			# JSON reads integers back as floats; send the live trace through the same round trip to compare like with like.
			var difference: String = _first_difference(steps,JSON.parse_string(JSON.stringify(first)))
			t.check(difference == "","Behaviour matches the recorded trace (first difference: %s)" % difference)
	await app._stop_audio()
	app.queue_free()
	await process_frame
	t.finish(self)

func _route(sabotage: bool) -> Array:
	var steps: Array = []
	app._new_game(false)
	app.combat.set_physics_process(false)
	_record(steps,"new_game")
	_fly(Vector2.LEFT if sabotage else Vector2.RIGHT,Vector2.RIGHT,120)
	_record(steps,"origin_flown")
	app._enter_sector(Vector2i(1,0),app.combat.arena.entry_position(Vector2i.RIGHT),false)
	_record(steps,"entered_1_0")
	_fly(Vector2.UP,Vector2.RIGHT,180)
	_record(steps,"fought_1_0")
	app.combat.collect_light(40.0,"fire")
	app.combat.collect_light(40.0,"plasma")
	app._show_evolution()
	_record(steps,"evolution_offered")
	if not app.pending_offers.is_empty(): app._choose_evolution(app.pending_offers[0])
	_record(steps,"evolved")
	_fly(Vector2.DOWN,Vector2.LEFT,120)
	_record(steps,"fought_as_t2")
	app._show_map()
	_record(steps,"map_open")
	app._close_overlay()
	app._enter_sector(Vector2i(2,0),app.combat.arena.entry_position(Vector2i.RIGHT),false)
	_fly(Vector2.RIGHT,Vector2.UP,90)
	_record(steps,"fought_2_0")
	# Review finding 4: every hull on the route up to here is rigid (no
	# ShipMotion group), so `tick` -- the clock groups actually read, not
	# `elapsed` -- never affected a single fingerprinted field, and a
	# process-global `tick` that outlives a life could not be caught by the
	# "first run == second run in one process" check below. A corruption
	# chain hull always carries a `whip` group (ship_roster_test asserts
	# this for every corruption hull), so spawning one here and letting a
	# few frames run makes the check real.
	var motion_hull: String = ShipGenerator.hull_id("enemy","chain","corruption",4)
	app.combat._spawn_named_enemy(motion_hull,"corruption",4,app.combat.arena.center,false,false)
	_fly(Vector2.ZERO,Vector2.UP,30)
	_record(steps,"corruption_motion_group")
	app.combat.player_invulnerable = 0.0
	app.combat.player.invulnerable = 0.0
	app.combat._damage_actor(app.combat.player,1000000.0,1,1)
	_record(steps,"died")
	app._reboot()
	_fly(Vector2.RIGHT,Vector2.RIGHT,60)
	_record(steps,"rebooted")
	return steps

func _fly(movement: Vector2, aim: Vector2, frames: int) -> void:
	var command: ShipCommand = ShipCommand.new()
	command.movement = movement
	command.aim = aim
	command.fire = true
	command.ability_primary = true
	app.combat.set_command(command)
	for frame: int in range(frames): app.combat._physics_process(STEP)

func _record(steps: Array, name: String) -> void:
	steps.append({
		"step":name,"mode":app.mode,"overlay":app.overlay_kind,"paused":paused,
		"sector":str(app.campaign.current_sector),"hull":app.combat.hull_id,"tier":app.combat.player_tier,
		"light":snappedf(app.combat.light_total,0.0001),"enemies":app.combat.remaining_enemies(),"bullets":app.combat.bullets.count(),
		"offers":app.pending_offers.duplicate(),
		"profile":_digest(app.campaign.to_dict()),"snapshot":_digest(app.combat.snapshot()),
		"lines":_digest([app.seen_lines,app.line_queue])})

func _digest(value: Variant) -> String:
	return JSON.stringify(value,"",true,true).sha256_text().substr(0,16)

## Names the first step and field that differ, or "" when the traces are equal.
func _first_difference(expected: Array, actual: Array) -> String:
	for index: int in range(mini(expected.size(),actual.size())):
		for key: String in expected[index]:
			if str(expected[index][key]) != str(actual[index].get(key)):
				return "%s.%s expected %s got %s" % [expected[index].step,key,expected[index][key],actual[index].get(key)]
	if expected.size() != actual.size(): return "step count %d vs %d" % [expected.size(),actual.size()]
	return ""
