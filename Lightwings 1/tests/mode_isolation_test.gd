extends SceneTree
## P5b: ModeConfig rows (spec §4). A dev session must never touch the
## campaign save, must earn no achievements, and the dev console node must
## exist ONLY where console_enabled() says it should.
const Harness = preload("res://tests/support/harness.gd")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var h := Harness.new("MODE ISOLATION")
	SaveService.storage_root = "user://mode-isolation-%d" % Time.get_ticks_usec()

	var app: Node = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	await process_frame

	# --- A campaign save exists first, as a real player's save would ------
	app._new_game_as("campaign")
	SaveService.save_snapshot(app.campaign.to_dict(),{"combat":app.combat.snapshot()},"campaign")
	var campaign_path: String = SaveService.snapshot_path("campaign")
	var before: PackedByteArray = FileAccess.get_file_as_bytes(campaign_path)
	h.check(not before.is_empty(),"Campaign save exists before the dev session")

	# --- A dev session runs, plays, and saves to its OWN slot -------------
	app._new_game_as("dev")
	h.check(app.campaign.unlocked.size() == GameTuning.ELEMENTS.size(),"Dev mode unlocks every element from the start")
	h.check(is_instance_valid(app.dev_console),"Dev console node exists in dev mode")
	app.combat.collect_light(50.0,"fire")
	SaveService.save_snapshot(app.campaign.to_dict(),{"combat":app.combat.snapshot()},"dev")
	var dev_path: String = SaveService.snapshot_path("dev")
	h.check(dev_path != campaign_path,"Dev and campaign use distinct save paths")
	var after: PackedByteArray = FileAccess.get_file_as_bytes(campaign_path)
	h.check(after == before,"A dev session leaves campaign.json byte-identical")
	# Negative control: prove the byte-identical check can actually fail --
	# a deliberate extra write to the campaign slot must be caught.
	SaveService.save_snapshot(app.campaign.to_dict(),{"sabotage":true},"campaign")
	var sabotaged: PackedByteArray = FileAccess.get_file_as_bytes(campaign_path)
	h.control("a deliberate extra write to campaign.json", sabotaged != after)

	# --- Achievements: positive control (campaign) vs dev vs demo ---------
	app.platform.pending_achievements.clear()
	app._new_game_as("campaign")
	app._achieve("FIRST_RIVAL")
	h.check("FIRST_RIVAL" in app.platform.pending_achievements,"An achievement IS recorded in campaign (positive control)")

	app.platform.pending_achievements.clear()
	app._new_game_as("dev")
	h.check(is_instance_valid(app.dev_console),"Dev console node present in dev mode")
	app._achieve("FIRST_RIVAL")
	h.check(app.platform.pending_achievements.is_empty(),"No achievement is recorded in dev")

	app.platform.pending_achievements.clear()
	app._new_game_as("demo")
	h.check(not is_instance_valid(app.dev_console),"Dev console node absent in demo")
	app._achieve("FIRST_RIVAL")
	h.check(app.platform.pending_achievements.is_empty(),"No achievement is recorded in demo")

	app._new_game_as("campaign")
	h.check(not is_instance_valid(app.dev_console),"Dev console node absent in campaign")

	# Negative control: an achievement guard that always granted would pass
	# every check above by accident. Prove the guard itself can fail by
	# querying ModeConfig directly instead of going through _achieve.
	h.control("achievements_enabled() answering true for dev",
		not ModeConfig.from_id("dev").achievements_enabled())
	h.control("achievements_enabled() answering true for demo",
		not ModeConfig.from_id("demo").achievements_enabled())

	# --- Slot/mode mismatch is rejected ------------------------------------
	# Uses the untouched "demo" slot: "dev" already has a real backup from
	# the save above, and load_snapshot falls through primary -> .bak -> .tmp,
	# so reusing "dev" here would let a matching backup mask the very
	# mismatch this check exists to catch.
	var mismatched_campaign: Dictionary = app.campaign.to_dict()
	mismatched_campaign.mode = "campaign"
	var write_error: Error = SaveService.save_snapshot(mismatched_campaign,{},"demo")
	h.check(write_error == OK,"Setup: a campaign-mode profile can be written to the demo slot's bytes")
	SaveService.last_error = ""
	var loaded: Dictionary = SaveService.load_snapshot("demo")
	h.check(loaded.is_empty() and not SaveService.last_error.is_empty(),"A slot/mode mismatch is rejected, not silently loaded")
	h.control("mode/slot check disabled",
		SaveService._mode_matches_slot({"mode":"campaign"},"dev") == false)
	h.control("mode/slot check disabled the other way",
		SaveService._mode_matches_slot({"mode":"dev"},"dev") == true)

	# Spec §4: dev mode offers "all hulls available at every evolution", campaign the ranked three.
	# 20 cards do not fit on screen, so the screen groups them behind an element tab strip; assert
	# both the offer list and that only one element's four hulls are live at a time.
	var everything: Array[String] = EvolutionRules.all_offers(1)
	var elements_seen: Dictionary = {}
	for id: String in everything:
		var ship: ShipDefinition = ShipCatalog.get_ship(id)
		if ship != null: elements_seen[ship.element] = int(elements_seen.get(ship.element,0)) + 1
	h.check(everything.size() == GameTuning.ELEMENTS.size() * 4,"Dev offers every next-tier hull (%d)" % everything.size())
	h.check(elements_seen.size() == GameTuning.ELEMENTS.size(),"Dev offers span all %d elements: %s" % [GameTuning.ELEMENTS.size(),elements_seen])
	var repeated: Dictionary = {}
	var distinct: bool = true
	for id: String in everything:
		if repeated.has(id): distinct = false
		repeated[id] = true
	h.check(distinct,"Dev offer ids are distinct")
	h.control("all_offers at the terminal tier",EvolutionRules.all_offers(GameTuning.MAX_TIER).is_empty())
	app._new_game_as("dev")
	app.combat.collect_light(120.0,"lightning")
	app._show_evolution()
	h.check(app.overlay_kind == "evolution","Dev evolution screen opens")
	h.check(app.pending_offers.size() == everything.size(),"Dev pending offers hold every hull (%d)" % app.pending_offers.size())
	var previews: int = 0
	for child: Node in app.overlay.get_children():
		if child is ShipPreview: previews += 1
	h.check(previews > 0 and previews <= 4,"Only one element's hulls are previewed at a time (%d)" % previews)
	h.control("previews counted against the full 20-hull offer list",not (app.pending_offers.size() <= 4))
	app._close_overlay()

	await app._stop_audio()
	app.queue_free()
	await process_frame
	h.finish(self)
