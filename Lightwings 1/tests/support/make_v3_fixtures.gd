extends SceneTree
## One-off tool: writes genuine v0.2 (schema 3) saves to tests/fixtures/ through the real game code.
## Run at the v0.2 baseline only. The fixtures are what the v3 -> v4 migration is tested against,
## so they must come from the build that players actually saved with, not from a hand-written dict.
##
##   Godot --headless --path <project> --script res://tests/support/make_v3_fixtures.gd

const STEP: float = 1.0 / 60.0
var app: Node

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var scratch: String = "user://fixture-gen-%d" % Time.get_ticks_usec()
	SaveService.storage_root = scratch
	app = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/fixtures"))
	var written: int = 0
	for is_demo: bool in [false, true]:
		_play(is_demo)
		var slot: String = "demo" if is_demo else "campaign"
		# The same run dictionary main.gd:_save_game builds; `testing` makes that function return early.
		var run: Dictionary = {"combat":app.combat.snapshot(),"pending_offers":app.pending_offers,"previous_offers":app.previous_offers,"offer_serial":app.offer_serial,"seen_lines":app.seen_lines,"line_queue":app.line_queue}
		var error: Error = SaveService.save_snapshot(app.campaign.to_dict(),run,slot)
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.snapshot_path(slot))
		var target: String = "res://tests/fixtures/%s_v3.json" % slot
		var file: FileAccess = FileAccess.open(target,FileAccess.WRITE)
		if error != OK or bytes.is_empty() or file == null:
			push_error("Fixture %s was not written (save error %d, %d bytes)" % [slot,error,bytes.size()])
			continue
		file.store_buffer(bytes)
		file.close()
		var decoded: Dictionary = SaveService.decode_snapshot(bytes)
		var profile: Dictionary = decoded.get("profile",{})
		print("fixture %s: %d bytes, schema=%s demo=%s deaths=%s unlocked=%s checkpoints=%d hull=%s tier=%d light=%s" % [target,bytes.size(),profile.get("schema_version"),profile.get("demo"),profile.get("deaths"),profile.get("unlocked"),profile.get("checkpoints",{}).size(),app.combat.hull_id,app.combat.player_tier,app.combat.light_total])
		written += 1
	await app._stop_audio()
	app.queue_free()
	await process_frame
	var dir: DirAccess = DirAccess.open(scratch)
	if dir != null:
		for name: String in dir.get_files(): dir.remove(name)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	print("FIXTURES: 2 checks, %d failures" % (2 - written))
	quit(0 if written == 2 else 1)

## A short but representative life: one death, one evolution, a few nodes, a waypoint, a live fight.
func _play(is_demo: bool) -> void:
	app._new_game(is_demo)
	app._enter_sector(Vector2i(1,0),app.combat.arena.entry_position(Vector2i.RIGHT),false)
	# Killing the player emits player_died, so main's own death path runs (it calls campaign.on_death itself).
	app.combat.player_invulnerable = 0.0
	app.combat._damage_actor(app.combat.player,1000000.0,1,1)
	app._reboot()
	app.combat.collect_light(30.0,"fire")
	app.combat.collect_light(30.0,"corruption")
	app._show_evolution()
	if not app.pending_offers.is_empty(): app._choose_evolution(app.pending_offers[0])
	# Headroom above the 85 % regression floor, so the fight below leaves a T2 hull in the save.
	app.combat.collect_light(110.0,"plasma")
	for coord: Vector2i in [Vector2i(1,0),Vector2i(2,0),Vector2i(2,1)]:
		app._enter_sector(coord,app.combat.arena.entry_position(Vector2i.RIGHT),false)
	app._enter_sector(Vector2i(6,0),app.combat.arena.entry_position(Vector2i.RIGHT),false)
	var command: ShipCommand = ShipCommand.new()
	command.aim = Vector2.RIGHT
	command.fire = true
	app.combat.set_command(command)
	for frame: int in range(90): app.combat._physics_process(STEP)
