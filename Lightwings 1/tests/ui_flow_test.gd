extends SceneTree
var failures: int = 0
var checks: int = 0
var app: Node

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	SaveService.storage_root = "user://ui-v2-test-%d" % Time.get_ticks_usec()
	app = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	await process_frame
	check(app.mode == "menu","Main menu starts")
	app._new_game(false)
	check(app.combat.hull_id == "player_seed" and app.combat.light_total == 40.0,"New campaign starts neutral seed at forty light")
	check(app.campaign.unlocked == [GameTuning.ELEMENTS[0]],"Campaign starts with only Lightning unlocked (spec §8)")
	check(app.combat.player_tier == 1 and app.combat.absorption.is_empty(),"No tutorial absorption is fabricated")
	app.combat.collect_light(20.0,"fire")
	app.combat.collect_light(20.0,"corruption")
	app.combat.collect_light(20.0,"plasma")
	app._show_evolution()
	# M12: evolution no longer pauses; it dilates the sim to 0.25 (tests/evolution_slowmo_test.gd
	# measures the rate, with its control).
	check(not paused and app.overlay_kind == "evolution" and is_equal_approx(app.combat.time_scale(),0.25),"Evolution dilates simulation to 0.25 instead of pausing")
	check(app.pending_offers.size() == 3,"Three complete preset hulls offered")
	# M12: each card groups its nodes, so the previews are the overlay's descendants, not children.
	var preview_count: int = 0
	for child: Node in app.overlay.find_children("*","ShipPreview",true,false):
		preview_count += 1
		check(child.renderer.definition.tier == 2,"Every preview is next tier")
	check(preview_count == 3,"Three live previews")
	var before_elapsed: float = app.combat.elapsed
	var before_light: float = app.combat.light_total
	var frames: int = 0
	for index: int in range(12):
		await physics_frame
		frames += 1
	var advanced: float = app.combat.elapsed-before_elapsed
	check(advanced > 0.0 and advanced <= (frames+1)*0.25/60.0+0.0001,"Evolution advances combat only at the dilated rate (%.4f s sim in %d physics frames)" % [advanced,frames])
	check(app.combat.light_total <= before_light,"Evolution does not heal")
	var offered: Array = app.pending_offers.duplicate()
	app._close_overlay()
	app._show_evolution()
	check(app.pending_offers == offered,"Closing evolution cannot reroll")
	var saved_serial: int = app.offer_serial
	var save_error: Error = SaveService.save_snapshot(app.campaign.to_dict(),{"combat":app.combat.snapshot(),"pending_offers":app.pending_offers,"previous_offers":app.previous_offers,"offer_serial":app.offer_serial},"campaign")
	check(save_error == OK,"Pending evolution writes to isolated save")
	app._continue_game("campaign")
	app._show_evolution()
	check(app.pending_offers == offered and app.offer_serial == saved_serial,"Save/resume preserves pending choices without reroll")
	var chosen: String = app.pending_offers[0]
	var definition: ShipDefinition = ShipCatalog.get_ship(chosen)
	before_light = app.combat.light_total # the dilated sim may have spent light while the cards were up
	app._choose_evolution(chosen)
	check(not paused and app.combat.hull_id == chosen,"Chosen hull is equipped")
	check(app.combat.light_total == before_light and app.combat.player_invulnerable >= 0.79,"Evolution preserves light and grants protection")
	check(app.combat.absorption.is_empty() and app.pending_offers.is_empty(),"Successful choice resets absorption and pending cards")
	check(app.combat.player.definition.primary == definition.primary if app.combat.player.has("definition") else app.combat.hull_id == definition.id,"Preset loadout belongs to selected hull")
	app._show_map()
	check(paused and app.overlay_kind == "map","Map pauses simulation")
	check(app._sector_description(Vector2i(3,3)).contains("Unexplored") and not app._sector_description(Vector2i(3,3)).contains("FIRE"),"Unknown map cells disclose no threat or element")
	check(not app._sector_known(Vector2i(1,0)),"Adjacent unexplored node remains unknown")
	# No panning: the whole level fits on screen at every radius (spec §11).
	var model: MinimapModel = MinimapModel.build(app.campaign)
	check(model.grid_size() == app.campaign.level_radius()*2+1,"Map grid spans the whole bounded level, no panning")
	check(model.bearing_direction != "NONE" and model.bearing_distance >= 0,"Boss bearing is present from the first tick")
	app._close_overlay()
	var destination: Vector2i = Vector2i(1,0)
	app._enter_sector(destination,app.combat.arena.entry_position(Vector2i.RIGHT),false)
	check(app.campaign.current_sector == destination and app._sector_known(destination),"Physical transition records discovery")
	var node: Dictionary = app.campaign.sector_at(destination)
	# Transition is now the warp (spec §12/plan P6), not an instant cut on
	# crossing the rim: press into the RIGHT membrane and hold long enough to
	# push past the 0.30s threshold and ride out the ~1.0s locked window.
	# `app.benchmark_mode` (main.gd's own guard) stops `_physics_process` from
	# overwriting `combat.command` every frame with live (empty) Input state,
	# while `combat` keeps ticking normally - it is not `combat.benchmark_mode`.
	app.combat.player_position = Vector2(app.combat.arena.center.x+app.combat.arena.radius-8.0,app.combat.arena.center.y)
	app.combat.command.movement = Vector2.RIGHT
	app.benchmark_mode = true
	await create_timer(1.4,true).timeout
	app.benchmark_mode = false
	app.combat.command.movement = Vector2.ZERO
	check(app.campaign.current_sector == Vector2i(2,0),"Uncleared encounter never locks exit (push-and-commit warp completes the transition)")
	app.compositor._update_camera()
	# M10: the camera trails the ship (camera_rig.gd), so the ship is no longer pinned to (640,400);
	# what must hold is that mouse aim inverts the camera's own (shake-free) transform, and that the
	# ship stays inside the 18% total clamp of the screen centre. M6 (restated in M12): the centre is
	# the compositor's own screen_center() - the middle of the visible rect, not a fixed (640,400) -
	# and the clamp is a fraction of the rig's fixed reference half-width.
	var ship_on_screen: Vector2 = app.compositor.world_to_screen(app.combat.player_position)
	var clamp_px: float = GameTuning.feel("cam.total_clamp")*CameraRig.HALF_WIDTH
	check(app.compositor.screen_to_world(ship_on_screen).is_equal_approx(app.combat.player_position) and ship_on_screen.distance_to(app.compositor.screen_center()) <= clamp_px+0.01,"Mouse aim and camera share world transform (ship %.1f px from the centre %s, clamp %.1f)" % [ship_on_screen.distance_to(app.compositor.screen_center()),app.compositor.screen_center(),clamp_px])
	check(app.compositor.background_viewport.canvas_transform.origin == app.compositor.foreground.position,"HDR and foreground camera transforms match")
	var snapshot: Dictionary = app.combat.snapshot()
	app.combat.restore(snapshot)
	check(app.combat.hull_id == chosen and app.combat.light_total == before_light,"Run restore preserves chosen fixed hull and total")
	app._new_game(true)
	# Approved preamble: the demo is redefined as campaign levels 1-2, no
	# tier cap (dropped v0.2's three-element/T3 cap outright).
	check(app.campaign.demo and app.combat.max_player_tier == GameTuning.MAX_TIER,"Demo has no tier cap (approved preamble)")
	check(app.campaign.unlocked == [GameTuning.ELEMENTS[0]],"Demo also starts with only Lightning unlocked (spec §8)")
	check(app.mode_config.level_cap() == 2 and app.mode_config.enemy_elements() == ["lightning","fire"],"Demo is levels 1-2, Lightning + Fire only")
	app.combat.setup_player("plasma",5,2000,[])
	app._show_evolution()
	check(app.overlay_kind == "evolution","Demo offers evolution past the old T3 boundary")
	app._close_overlay()
	check(InputMap.has_action("ability_tertiary"),"Third secondary is rebindable")
	await app._stop_audio()
	app.queue_free()
	await process_frame
	print("UI V2: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
