extends SceneTree
## Review finding 3 (spec §12): a save taken inside the warp's own locked
## window used to restore into a phantom warp. `CombatPersistence.restore`
## derived `_warp_swap_done` from `warp_phase` alone, backwards, so any save
## landing at WARP_ZOOM_IN (exactly where `_on_warp_committed` always saves
## -- main.gd:812, deliberately inside the lock) restored with the swap
## marked NOT done, and nothing ever re-fires `confirm_warp_swap()` on
## restore. `_update_warp`'s own TRAVEL-phase guard then sprang the player
## back (after shoving them `warp_commit_speed * 0.55s` along the exit
## direction) instead of ever reaching `_warp_arrive()`.
##
## Drives a REAL commit through main.gd (not combat_world directly) with
## `testing=false` against an isolated SaveService.storage_root, so
## `_save_game()` actually executes on disk -- every other test in this
## suite sets `testing=true`, which is exactly how the bug shipped unseen.
## `combat.set_physics_process(false)` on every instance the instant it
## exists, so the engine's own real-time physics catch-up (which fires
## during any `await process_frame`, independent of `benchmark_mode`) never
## races the test's own manually-stepped ticks -- two time sources, one bug.
##
## Measured (why "inside the arena" alone is not the right assertion): after
## a spring-back, the normal (non-locked) movement clamp that runs later in
## the SAME tick pulls the overshot position back to the near rim it pushed
## OUT from, which still reads as "inside" the circle. The real symptom is
## resuming on the WRONG side: spec §12 places arrival "just inside the
## OPPOSITE membrane" (`arena.entry_position(direction)`, the far rim), so
## the assertion compares final position against that point directly.
const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")
const STEP: float = 1.0 / 60.0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var h := Harness.new("WARP PERSISTENCE")
	SaveService.storage_root = "user://warp-persist-test-%d" % Time.get_ticks_usec()

	var app: Node = load("res://scripts/main.gd").new()
	app.testing = false # the point: exercise the real _save_game() path
	root.add_child(app)
	await process_frame
	app._new_game(false)
	app.combat.set_physics_process(false)
	app.combat.player.pos = app.combat.arena.center + Vector2(app.combat.arena.radius - 4.0, 0.0)
	app.combat.player.vel = Vector2(200.0, 0.0)
	app.combat.command.movement = Vector2.RIGHT
	app.combat.command.aim = Vector2.RIGHT
	var pre_commit_sector: Vector2i = app.campaign.current_sector
	var ticks: int = 0
	while (app.combat.warp_phase == World.WARP_NONE or app.combat.warp_phase == World.WARP_PUSH) and ticks < 200:
		app.combat._update_player(STEP)
		ticks += 1
	# `_warp_commit()` emits `warp_committed` synchronously from inside
	# `_update_player` -> `_on_warp_committed` has already run by here:
	# sector swapped, `confirm_warp_swap()` called, and (testing=false,
	# mode=="play") `_save_game()` has already written the save to disk.
	h.check(app.combat.warp_commit_speed > 20.0, "Commit speed is a real, non-degenerate value (%.1f)" % app.combat.warp_commit_speed)
	h.check(app.campaign.current_sector != pre_commit_sector, "The sector already swapped synchronously at commit")
	h.check(app.combat.warp_phase == World.WARP_ZOOM_IN, "The commit landed exactly at WARP_ZOOM_IN, the warp's own locked window")
	var saved: Dictionary = SaveService.load_snapshot("campaign")
	h.check(int(saved.get("run", {}).get("combat", {}).get("warp_phase", -1)) == World.WARP_ZOOM_IN, "The on-disk save really captured the mid-warp phase")

	# --- Continue into a FRESH main.gd instance from that on-disk save ---
	var restored: Node = load("res://scripts/main.gd").new()
	restored.testing = true # the fresh instance must not immediately re-save
	root.add_child(restored)
	await process_frame
	restored._continue_game("campaign")
	restored.combat.set_physics_process(false)
	h.check(restored.combat.warp_phase == World.WARP_ZOOM_IN, "Restore resumes the same phase from its start (spec P6 item 6)")
	var direction: Vector2i = restored.combat.warp_direction
	var expected_entry: Vector2 = restored.combat.arena.entry_position(direction)
	restored.combat.command.movement = Vector2.ZERO
	var arrive_ticks: int = 0
	while restored.combat.warp_phase != World.WARP_NONE and arrive_ticks < 200:
		restored.combat._update_player(STEP)
		arrive_ticks += 1
	var restored_error: float = Vector2(restored.combat.player.pos).distance_to(expected_entry)
	# `_warp_arrive()` sets position to exactly `expected_entry`, but ARRIVAL
	# + ZOOM_OUT (0.35s combined) then carry the ship forward at
	# `warp_commit_speed` by design (spec §12: "momentum carries through") -
	# measured drift here is commit_speed*0.35s (~31px at this test's ~88
	# px/s commit speed). The budget below is that measured drift plus
	# headroom, not a guess.
	var expected_drift: float = app.combat.warp_commit_speed * (World.WARP_ARRIVAL_SECONDS + World.WARP_ZOOM_OUT_SECONDS)
	h.check(restored.combat.warp_phase == World.WARP_NONE, "Control returns: the restored warp reaches WARP_NONE (%d ticks), not a permanent lock" % arrive_ticks)
	h.check(restored.combat.warp_locked_measured > 0.9, "The restored warp completed its full locked window via real arrival, not a spring-back (%.3f)" % restored.combat.warp_locked_measured)
	h.check(restored_error < expected_drift + 20.0, "The player lands within the expected post-arrival drift of the opposite membrane's entry point (spec §12), not pushed out toward a phantom node (error %.1f px, budget %.1f px)" % [restored_error, expected_drift + 20.0])

	# --- Negative control: replay the OLD (backwards) restore behaviour on
	# an otherwise-identical fresh continue of the SAME on-disk save, and
	# show the assertion above would have failed exactly as it did in
	# production. This sabotages the runtime STATE the checks above read
	# (`_warp_swap_done`), not a literal, so it exercises the real bug path.
	var sabotaged: Node = load("res://scripts/main.gd").new()
	sabotaged.testing = true
	root.add_child(sabotaged)
	await process_frame
	sabotaged._continue_game("campaign")
	sabotaged.combat.set_physics_process(false)
	sabotaged.combat._warp_swap_done = false # the old restore's own (buggy) derivation for WARP_ZOOM_IN
	sabotaged.combat.command.movement = Vector2.ZERO
	var sabotage_ticks: int = 0
	while sabotaged.combat.warp_phase != World.WARP_NONE and sabotage_ticks < 200:
		sabotaged.combat._update_player(STEP)
		sabotage_ticks += 1
	var sabotaged_error: float = Vector2(sabotaged.combat.player.pos).distance_to(expected_entry)
	h.control("restoring with the old warp_phase-only _warp_swap_done derivation (false at WARP_ZOOM_IN)", sabotaged_error > 500.0)

	h.finish(self)
