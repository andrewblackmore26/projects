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
	check(app.campaign.unlocked == ["fire","corruption","plasma"],"Three starting elements")
	check(app.combat.player_tier == 1 and app.combat.absorption.is_empty(),"No tutorial absorption is fabricated")
	app.combat.collect_light(20.0,"fire")
	app.combat.collect_light(20.0,"corruption")
	app.combat.collect_light(20.0,"plasma")
	app._show_evolution()
	check(paused and app.overlay_kind == "evolution","Evolution pauses simulation")
	check(app.pending_offers.size() == 3,"Three complete preset hulls offered")
	var preview_count: int = 0
	for child: Node in app.overlay.get_children():
		if child is ShipPreview:
			preview_count += 1
			check(child.renderer.definition.tier == 2,"Every preview is next tier")
	check(preview_count == 3,"Three live previews")
	var frozen: float = app.combat.elapsed
	var before_light: float = app.combat.light_total
	await create_timer(0.15,true).timeout
	check(app.combat.elapsed == frozen and app.combat.light_total == before_light,"Evolution does not advance combat or heal")
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
	app._choose_evolution(chosen)
	check(not paused and app.combat.hull_id == chosen,"Chosen hull is equipped")
	check(app.combat.light_total == before_light and app.combat.player_invulnerable >= 0.79,"Evolution preserves light and grants protection")
	check(app.combat.absorption.is_empty() and app.pending_offers.is_empty(),"Successful choice resets absorption and pending cards")
	check(app.combat.player.definition.primary == definition.primary if app.combat.player.has("definition") else app.combat.hull_id == definition.id,"Preset loadout belongs to selected hull")
	app._show_map()
	check(paused and app.overlay_kind == "map","Map pauses simulation")
	check(app._sector_description(Vector2i(50,50)).contains("Unexplored") and not app._sector_description(Vector2i(50,50)).contains("FIRE"),"Unknown map cells disclose no threat or element")
	check(not app._sector_known(Vector2i(1,0)),"Adjacent unexplored node remains unknown")
	app._pan_map(Vector2i(100,-100))
	check(app.map_center == Vector2i(100,-100),"Map pans beyond former fixed boundary")
	app._close_overlay()
	var destination: Vector2i = Vector2i(1,0)
	app._enter_sector(destination,app.combat.arena.entry_position(Vector2i.RIGHT),false)
	check(app.campaign.current_sector == destination and app._sector_known(destination),"Physical transition records discovery")
	var node: Dictionary = app.campaign.sector_at(destination)
	app.combat.player_position = Vector2(app.combat.bounds.end.x+3,app.combat.bounds.get_center().y)
	app._attempt_exit()
	check(app.campaign.current_sector == Vector2i(2,0),"Uncleared encounter never locks exit")
	app.compositor._update_camera()
	check(app.compositor.screen_to_world(Vector2(640,400)).is_equal_approx(app.combat.player_position),"Mouse aim and camera share world transform")
	check(app.compositor.background_viewport.canvas_transform.origin == app.compositor.foreground.position,"HDR and foreground camera transforms match")
	var snapshot: Dictionary = app.combat.snapshot()
	app.combat.restore(snapshot)
	check(app.combat.hull_id == chosen and app.combat.light_total == before_light,"Run restore preserves chosen fixed hull and total")
	app._new_game(true)
	check(app.campaign.demo and app.combat.max_player_tier == 3,"Demo tier limit reaches simulation")
	check(app.campaign.unlocked == ["fire","corruption","plasma"],"Demo uses same three starting elements")
	app.combat.setup_player("plasma",3,500,[])
	app._show_evolution()
	check(app.overlay_kind != "evolution","Demo maximum does not offer T4")
	check(GameTuning.capacity(3,3) == 500.0,"Demo uses T3 capacity, not T5 survivability")
	check(InputMap.has_action("ability_tertiary"),"Third secondary is rebindable")
	await app._stop_audio()
	app.queue_free()
	await process_frame
	print("UI V2: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
