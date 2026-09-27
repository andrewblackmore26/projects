class_name RunController
extends RefCounted
## The run FLOW, extracted from scripts/main.gd (modernization plan M1): starting a run, entering a
## node, the warp's node swap, death and reboot, the boss-defeated flow and the save hooks. UI
## construction and the companion lines stay in main.gd (M2 moves the UI;
## tests/dialogue_coverage_test.gd scans main.gd for every line trigger); this calls back into
## `app` for both, and
## main.gd keeps one-line forwarders with the old names, because tests and package_validation.gd
## drive the game through `app._new_game`, `app._enter_sector`, `app._reboot` and friends
## (tests/facade_contract_test.gd keeps that honest).
##
## A RefCounted, not a Node: it has no per-frame work, so it has no business in the scene tree's
## process order or pause modes, and main.gd owns exactly one for its whole lifetime.
##
## Run STATE (campaign, combat, mode_config, slot, the offer bookkeeping) still lives on main.gd for
## now, since tests read and write it as `app.campaign`, `app.pending_offers`, ... This file holds
## only the state the flow itself owns: the next life prepared at death, and the save timings.

## Instrumented (plan P6 item 6): `save_timings_ms` is a rolling window a bot
## run / test can read p95/max off of. Saving itself only happens at calm
## moments now - warp commit (`on_warp_committed`), node clear
## (main.gd `_on_sector_clear`), level complete/boss defeat (`on_boss_defeated`),
## and pause/menu/quit - never on the old per-node-entry hot path.
const SAVE_TIMING_WINDOW: int = 500

var app: Node
var save_timings_ms: Array[float] = []
## --- Frictionless death (spec §7.4/§24, plan P7) -------------------------
## The next life is built the INSTANT the player dies (fresh hull, fresh
## sector descriptor, fresh seed already rolled by campaign.on_death()), so
## dismissing the card is just applying data already sitting here - no work
## happens on the dismiss path itself, which is what keeps it fast.
var death_stats: Dictionary = {}
var death_next_sector: Dictionary = {}

func _init(owner: Node) -> void:
	app = owner

func begin_at_level(mode_id: String, level: int) -> void:
	app._close_overlay()
	new_game_as(mode_id)
	if level > 1: travel_to_level(level)

func new_game_as(mode_id: String) -> void:
	app.mode_config = ModeConfig.from_id(mode_id)
	app.slot = app.mode_config.save_slot()
	app.campaign = CampaignState.new()
	app.campaign.configure_mode(mode_id)
	app.campaign.world_seed = randi() if not app.testing else 734927
	app.absorbed = {}
	app.pending_offers.clear()
	app.previous_offers.clear()
	app.offer_serial = 0
	app.dialogue_director.reset()
	app._start_game_view()
	app.combat.setup_player("neutral",1,40,[],GameTuning.ARENA_CENTER)
	app.combat.max_player_tier = app.mode_config.max_tier()
	app._queue_welcome_line()
	enter_sector(Vector2i.ZERO,GameTuning.ARENA_CENTER,false)

## Kept for the many call sites (and tests) that only ever asked the old
## binary demo/campaign question.
func new_game(is_demo: bool) -> void:
	new_game_as("demo" if (is_demo or OS.has_feature("demo")) else "campaign")

func travel_to_level(level: int) -> void:
	app.campaign.travel_to_level(level)
	enter_sector(Vector2i.ZERO,GameTuning.ARENA_CENTER,false)

func continue_game(save_slot: String) -> void:
	var snapshot: Dictionary = SaveService.load_snapshot(save_slot)
	if snapshot.is_empty():
		if not SaveService.last_error.is_empty():
			app._toast("Save could not be restored: "+SaveService.last_error)
			return
		new_game(save_slot == "demo")
		return
	app.slot = save_slot
	app.campaign = CampaignState.new()
	app.campaign.from_dict(snapshot.get("profile",{}))
	app.mode_config = ModeConfig.from_id(app.campaign.mode)
	var run: Dictionary = snapshot.get("run",{})
	app.pending_offers.assign(run.get("pending_offers",[]))
	app.previous_offers.assign(run.get("previous_offers",[]))
	app.offer_serial = int(run.get("offer_serial",0))
	app.dialogue_director.restore(run.get("seen_lines",{}),run.get("line_queue",[]))
	app._start_game_view()
	app.combat.max_player_tier = app.mode_config.max_tier()
	if run.get("combat",{}).is_empty():
		app.combat.setup_player("neutral",1,40,[],GameTuning.ARENA_CENTER)
		enter_sector(Vector2i.ZERO,GameTuning.ARENA_CENTER,false)
	else:
		app.combat.restore(run.combat)
	app.absorbed = app.combat.absorption
	app._toast("Instance restored. Your light is still yours.")
	app.last_hp = app.combat.light_total
	app._refresh_hud()

func enter_sector(coord: Vector2i, spawn: Vector2, show_intro: bool = true) -> void:
	var combat = app.combat # untyped on purpose: it may be a freed instance, which is_instance_valid checks below
	var campaign: CampaignState = app.campaign
	if is_instance_valid(combat) and not combat.sector.is_empty():
		campaign.record_node_left(campaign.current_sector,combat.elapsed,float(combat.sector_energy_remaining))
	campaign.on_enter(coord)
	var sector: Dictionary = campaign.sector_at(coord,combat.elapsed if is_instance_valid(combat) else 0.0)
	combat.player_position = spawn
	combat.start_sector(sector)
	app._on_node_entered(sector,coord,show_intro)
	app._refresh_hud()
	save_game()

## Node-to-node transition is now the warp (spec §12/plan P6), not an instant
## cut: `combat` runs the push/commit/travel state machine itself and fires
## `warp_committed` the instant control locks. This handler does the sector
## swap SYNCHRONOUSLY (GDScript signal emission is synchronous), so it is
## done well before the travel phase ends and `confirm_warp_swap()` is
## always called in time - the "missing node swap springs back" case is a
## test-only scenario (nothing connects this signal), not something that can
## happen in play.
func on_warp_committed(direction: Vector2i) -> void:
	var combat = app.combat # untyped: see enter_sector
	var campaign: CampaignState = app.campaign
	if not is_instance_valid(combat) or campaign == null: return
	campaign.record_node_left(campaign.current_sector,combat.elapsed,float(combat.sector_energy_remaining))
	var destination: Vector2i = campaign.current_sector+direction
	campaign.on_enter(destination)
	var sector: Dictionary = campaign.sector_at(destination,combat.elapsed)
	combat.start_sector(sector)
	combat.confirm_warp_swap()
	app._on_node_entered(sector,destination,true)
	# Saves moved off the per-node-entry critical path (plan P6 item 6): this
	# fires once, here, inside the warp's own locked window - never on the
	# old instant-cut hot path.
	save_game()
	app._refresh_hud()

## Frictionless death (spec §7.4/§24): the non-UI half. No confirmation, no
## menu, no loading screen: the next life is built HERE, immediately, so
## `reboot` (fired by the timer, a fresh press, or a test/fixture calling it
## directly) does no work of its own beyond swapping to data that already
## exists. main.gd's `_on_death` plays the sound and builds the card.
func on_death() -> void:
	var combat = app.combat # untyped: see enter_sector
	var campaign: CampaignState = app.campaign
	var kills: int = combat.run_kills if is_instance_valid(combat) else 0
	var life_elapsed: float = combat.elapsed if is_instance_valid(combat) else 0.0
	var life_ring: int = campaign.ring_reached
	campaign.on_death() # spec §7.5: fresh seed the instant the player dies
	death_stats = {"ring_reached":life_ring,"best_ring":int(campaign.best_ring.get(campaign.level,0)),"kills":kills,"time":life_elapsed}
	death_next_sector = campaign.sector_at(Vector2i.ZERO,0.0)
	app.pending_offers.clear()
	if not app.testing:
		SaveService.save_snapshot(campaign.to_dict(),{"seen_lines":app.seen_lines,"previous_offers":app.previous_offers,"offer_serial":app.offer_serial},app.slot)

func reboot() -> void:
	var combat: CombatWorld = app.combat
	var campaign: CampaignState = app.campaign
	app._close_overlay()
	combat.setup_player("neutral",1,40,[],GameTuning.ARENA_CENTER)
	campaign.on_enter(Vector2i.ZERO)
	combat.player_position = GameTuning.ARENA_CENTER
	combat.start_sector(death_next_sector if not death_next_sector.is_empty() else campaign.sector_at(Vector2i.ZERO,0.0))
	app.dialogue.visible = false
	app.dialogue_remaining = 0.0
	app._input_swallow_frames = 1 # spec §7.4: swallow the dismissing press for one tick
	app._queue_reboot_line()
	app._refresh_hud()
	save_game()

func on_boss_defeated(element: String) -> void:
	if element.is_empty(): return
	var campaign: CampaignState = app.campaign
	# CampaignState.complete_level() is itself idempotent (tasks/todo.md:
	# "call it every time a boss dies; it only fires level_completed... the
	# first time"), so this handler needs no separate guard of its own.
	var result: Dictionary = campaign.complete_level()
	app._queue_defeat_line(element)
	app._achieve("FIRST_RIVAL")
	if bool(result.get("level_completed",false)):
		if campaign.campaign_complete():
			app._achieve("CAMPAIGN_COMPLETE")
			# CampaignState.campaign_complete() is now mode-aware (ModeConfig.level_cap):
			# for the demo this is true the instant level 2's boss dies, so this is
			# exactly the demo ending trigger spec §4/preamble asks for -- "on beating
			# the level-2 boss", not the old wedge-world "Fire core".
			app._show_ending(app.mode_config.id == "demo")
		else:
			app._show_level_complete(result)
	save_game()

func save_game() -> void:
	var combat = app.combat # untyped: see enter_sector
	var campaign: CampaignState = app.campaign
	if app.mode != "play" or campaign == null or not is_instance_valid(combat) or app.benchmark_mode or app.testing: return
	var began: int = Time.get_ticks_usec()
	var run: Dictionary = {"combat":combat.snapshot(),"pending_offers":app.pending_offers,"previous_offers":app.previous_offers,"offer_serial":app.offer_serial,"seen_lines":app.seen_lines,"line_queue":app.line_queue}
	if combat.light_total <= 0.0: run = {"seen_lines":app.seen_lines,"previous_offers":app.previous_offers,"offer_serial":app.offer_serial}
	var error: Error = SaveService.save_snapshot(campaign.to_dict(),run,app.slot)
	save_timings_ms.append(float(Time.get_ticks_usec()-began)/1000.0)
	if save_timings_ms.size() > SAVE_TIMING_WINDOW: save_timings_ms.remove_at(0)
	if error != OK: app._toast("Save failed: "+error_string(error))
	elif app.platform.online and app.cloud_sync_ready and app.mode_config.cloud_enabled():
		app.platform.save_cloud(SaveService.encode_snapshot({"profile":campaign.to_dict(),"run":run}),app.slot)

## p95/max over the rolling timing window (plan P6 item 6's own reporting
## requirement) - a bot run or test calls this after driving many warps.
func save_timing_stats() -> Dictionary:
	if save_timings_ms.is_empty(): return {"count":0,"p95":0.0,"max":0.0}
	var sorted: Array[float] = save_timings_ms.duplicate()
	sorted.sort()
	var p95_index: int = clampi(ceili(0.95*sorted.size())-1,0,sorted.size()-1)
	return {"count":sorted.size(),"p95":sorted[p95_index],"max":sorted[sorted.size()-1]}

## Time-scale broker (plan M1; M2's screen router and M12's slow-motion evolution are its callers).
## The broker itself lives on CombatWorld, next to the dt it scales; these forward to the live
## world, so a run-level caller never has to know which world instance is current. Without a
## world there is nothing to scale, and time_scale() reads 1.0.
func request_time_scale(reason: StringName, scale: float) -> void:
	if is_instance_valid(app.combat): app.combat.request_time_scale(reason,scale)

func release_time_scale(reason: StringName) -> void:
	if is_instance_valid(app.combat): app.combat.release_time_scale(reason)

func time_scale() -> float:
	return app.combat.time_scale() if is_instance_valid(app.combat) else 1.0
