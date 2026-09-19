extends SceneTree

const Campaign = preload("res://scripts/world/campaign_state.gd")
const Rules = preload("res://scripts/world/evolution_rules.gd")
const Saves = preload("res://scripts/platform/save_service.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	_test_world()
	_test_progression()
	_test_evolution()
	_test_saves()
	print("WORLD RULES %s: %d assertions" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _test_world() -> void:
	var first: CampaignState = Campaign.new()
	var second: CampaignState = Campaign.new()
	var initial: Dictionary = first.to_dict()
	for coord: Vector2i in [Vector2i(10000, -2400), Vector2i(-31, 12), Vector2i(4, 17), Vector2i.ZERO]:
		var descriptor: Dictionary = first.sector_at(coord)
		expect(descriptor == second.sector_at(coord), "Seed and coordinate determine node independent of exploration")
		expect(descriptor.tier >= 1 and descriptor.tier <= 5, "Distance tier stays within supported roster")
		for direction: Vector2i in Campaign.DIRECTIONS:
			expect(first.can_enter(coord, coord + direction, 0).allowed and first.can_enter(coord + direction, coord, 0).allowed, "Every cardinal exit is reciprocal and has no resource gate")
	expect(first.to_dict() == initial, "Reading procedural nodes does not inflate profile")
	expect(not first.can_enter(Vector2i.ZERO, Vector2i.ONE, 1500).allowed, "Travel requires an actual neighboring exit")
	expect(first.sector_at(Vector2i(36,0)).tier == 5 and first.sector_at(Vector2i(36,0)).enemy_count > first.sector_at(Vector2i(1,0)).enemy_count, "Outward travel increases capped tier and population")
	var core_ids: Array = []
	for element: String in Campaign.ELEMENTS:
		var coord: Vector2i = first.core_coordinate(element)
		var node: Dictionary = first.sector_at(coord)
		core_ids.append(node.core_id)
		expect(node.kind == "core" and node.element == element and node.core_id == element, "Each core is placed within its own angular region")
		expect(absf(Campaign.distance_of(coord) - GameTuning.CORE_DISTANCES[Campaign.ELEMENTS.find(element)]) <= 0.71, "Core rounding stays within one cell of configured radius")
		expect(first.sector_at(coord + Vector2i.RIGHT).elite_heavy, "Elite-heavy neighborhood surrounds each core")
		expect(first.can_enter(coord, coord + Vector2i.UP, 0).allowed, "An undefeated core never traps the player")
	expect(core_ids.size() == 5, "Five distinct core objectives replace gates and finale")
	expect(first.radiation_icons(Vector2i.ZERO, 1).is_empty(), "Unknown node threat is not exposed by legacy radar")
	expect(Campaign.valid_key("-10,24") and not Campaign.valid_key("01,0") and not Campaign.valid_key("garbage"), "Coordinate persistence uses canonical signed integer keys")

func _test_progression() -> void:
	var campaign: CampaignState = Campaign.new()
	expect(campaign.unlocked == ["fire", "corruption", "plasma"], "Three launch elements are immediately eligible")
	for element: String in ["lightning", "void"]:
		var event: Dictionary = campaign.on_enter(campaign.core_coordinate(element))
		expect(event.unlocked == element and element in campaign.unlocked, "Entering a new region unlocks its element immediately")
		var repeat: Dictionary = campaign.on_enter(campaign.current_sector)
		expect(repeat.unlocked == "", "Returning to region cannot duplicate its unlock")
	campaign.configure(false)
	for x: int in range(1, 13):
		var event: Dictionary = campaign.on_enter(Vector2i(x,0))
		expect(bool(event.waypoint) == (x == 6 or x == 12), "Distance waypoints occur once per six-node milestone")
	expect(campaign.checkpoints["6,0"].tier == 2 and campaign.checkpoints["12,0"].tier == 3, "Waypoint requirement follows distance threat tier")
	expect(not campaign.can_teleport(Vector2i(6,0),5), "Waypoint jumping is only available from origin")
	var seed_value: int = campaign.world_seed
	campaign.on_death()
	expect(campaign.world_seed == seed_value and campaign.current_sector == Vector2i.ZERO and campaign.deaths == 1, "Reboot preserves seed and resets to origin")
	expect(not campaign.can_teleport(Vector2i(6,0),1) and campaign.can_teleport(Vector2i(6,0),2), "Waypoint tier requirement is enforced at equality without spending progress")
	for element: String in Campaign.ELEMENTS:
		var coord: Vector2i = campaign.core_coordinate(element)
		var event: Dictionary = campaign.clear_sector(coord)
		expect(event.core == element and event.waypoint and campaign.checkpoints.has(Campaign.coord_key(coord)), "Core victory awards persistent waypoint")
		expect(campaign.clear_sector(coord).core == "", "Repeated clear never repeats core reward")
	expect(campaign.completed and campaign.defeated_leaders.size() == 5, "Only all five cores finish the full campaign")
	var saved: Dictionary = campaign.to_dict()
	var restored: CampaignState = Campaign.new()
	restored.from_dict(saved)
	expect(restored.to_dict() == saved, "New campaign round-trip preserves every serialized field")
	var unfinished: CampaignState = Campaign.new()
	var fire_coord: Vector2i = unfinished.core_coordinate("fire")
	var victory: Dictionary = unfinished.defeat_core("fire")
	expect(victory.core == "fire" and unfinished.sector_at(fire_coord).core_defeated and not unfinished.sector_at(fire_coord).cleared,"Defeating a rival credits core before remaining enemies are cleared")
	var continued: CampaignState = Campaign.new()
	continued.from_dict(unfinished.to_dict())
	expect(continued.sector_at(fire_coord).core_defeated and not continued.sector_at(fire_coord).cleared,"Saving an unfinished core fight preserves objective and encounter distinction")
	expect(continued.clear_sector(fire_coord).core == "" and continued.sector_at(fire_coord).cleared,"Subsequent full clear does not repeat the objective reward")
	continued.on_death()
	expect(continued.sector_at(fire_coord).core_defeated and not continued.sector_at(fire_coord).cleared,"Reboot refreshes soldiers without resurrecting the beaten rival core")
	campaign.configure(true)
	expect(campaign.sector_at(Vector2i(1000,0)).tier == 3, "Demo remains explorable while limiting tier")
	for coord: Vector2i in [Vector2i(2,4),Vector2i(-12,-40),Vector2i(100,-9)]:
		expect(campaign.sector_at(coord).element in GameTuning.START_ELEMENTS, "Demo has only its three supported regions")
	campaign.clear_sector(campaign.core_coordinate("fire"))
	expect(campaign.demo_completed and not campaign.completed, "Demo finishes at Fire core at distance eight")
	restored.import_demo(campaign.to_dict())
	expect(not restored.demo and "fire" in restored.defeated_leaders and not restored.completed and restored.current_sector == Vector2i.ZERO, "Demo import credits Fire and starts safely on full map")
	var malformed: CampaignState = Campaign.new()
	malformed.from_dict({"schema_version":3,"unlocked":"bad","checkpoints":{"01,0":{},"1,0":40},"discovered":["bad",4],"current_sector":"bad"})
	expect(malformed.checkpoints.is_empty() and malformed.current_sector == Vector2i.ZERO and malformed.discovered == ["0,0"], "Malformed collection records recover safely")

func _test_evolution() -> void:
	expect([Rules.threshold(1),Rules.threshold(2),Rules.threshold(3),Rules.threshold(4),Rules.threshold(5)] == [100,250,500,900,-1], "Five-tier light thresholds use central tuning")
	var unlocked: Array = Array(GameTuning.ELEMENTS)
	var first: Array[String] = Rules.offers("neutral",1,{"void":50,"plasma":30,"fire":20},unlocked,[],42)
	expect(first.size() == 3 and ShipCatalog.get_ship(first[0]).element == "void" and ShipCatalog.get_ship(first[1]).element == "plasma" and ShipCatalog.get_ship(first[2]).element == "fire", "Seed evolution ranks three absorbed elements")
	expect(first == Rules.offers("neutral",1,{"void":50,"plasma":30,"fire":20},unlocked,[],42), "Offer seed is reproducible")
	var zero: Array[String] = Rules.offers("neutral",1,{},Array(GameTuning.START_ELEMENTS))
	expect(zero.size() == 3, "Zero-diet first evolution still has three distinct starting elements")
	var old: Array[String] = []
	for iteration: int in range(12):
		var options: Array[String] = Rules.offers("fire",2,{"fire":60,"void":40},unlocked,old,iteration)
		expect(options.size() == 3 and not Rules._same_set(options,old), "Later choice has three hulls and never repeats prior set")
		for id: String in options: expect(ShipCatalog.get_ship(id).element == "fire", "Exactly forty percent does not permit element switching")
		old = options
	var cross: Array[String] = Rules.offers("fire",2,{"fire":59,"void":41},unlocked,[],2)
	var void_count: int = 0
	for id: String in cross:
		if ShipCatalog.get_ship(id).element == "void": void_count += 1
	expect(void_count == 1, "More than forty percent replaces exactly one offer")
	expect(Rules.offers("fire",5,{},unlocked).is_empty(), "Terminal tier has no offer")

func _test_saves() -> void:
	var previous_root: String = Saves.storage_root
	Saves.storage_root = "user://world_v3_tests_%d" % Time.get_ticks_usec()
	var campaign: CampaignState = Campaign.new()
	var run: Dictionary = {"combat":{"version":2,"hull_id":"player_seed","light":65.0,"position":Vector2(40,50)},"previous_offers":["a","b","c"]}
	expect(Saves.save_snapshot(campaign.to_dict(),run) == OK, "Current atomic save writes")
	expect(Saves.load_snapshot().run == run, "Typed light, hull identity and offer history survive transport")
	var old_run: Dictionary = run.duplicate(true)
	run.combat.light = 90.0
	Saves.save_snapshot(campaign.to_dict(),run)
	var corrupt: FileAccess = FileAccess.open(Saves.snapshot_path("campaign"),FileAccess.WRITE)
	corrupt.store_string("corrupt")
	corrupt.close()
	expect(Saves.load_snapshot().run == old_run and Saves.last_load_source.ends_with(".bak"), "Corrupt primary recovers verified prior save")
	var legacy_profile: Dictionary = {"schema_version":2,"world_seed":33,"current_sector":"3,0","deaths":4,"unlocked":["fire","void"],"defeated_leaders":["void"],"completed":true,"story_flags":{"reboot_1":true,"veil_2_fire":true}}
	Saves.save_snapshot(legacy_profile,{"combat":{"version":1,"energy":500,"stolen":["laser"]}},"legacy")
	var original: PackedByteArray = FileAccess.get_file_as_bytes(Saves.snapshot_path("legacy"))
	var migrated: Dictionary = Saves.load_snapshot("legacy")
	expect(migrated.profile.schema_version == 3 and migrated.run.is_empty() and migrated.profile.current_sector == "0,0", "Legacy combat is reset to new origin run")
	expect(migrated.profile.deaths == 4 and "void" in migrated.profile.unlocked and migrated.profile.defeated_leaders.is_empty() and not migrated.profile.completed, "Compatible legacy meta survives but new cores remain unbeaten")
	expect(migrated.profile.story_flags.has("reboot_1") and not migrated.profile.story_flags.has("veil_2_fire") and migrated.profile.legacy_history.defeated_leaders == ["void"], "Story whitelist and historical victories remain distinct")
	expect(FileAccess.get_file_as_bytes(Saves.snapshot_path("legacy") + ".legacy-v2") == original and FileAccess.get_file_as_bytes(Saves.snapshot_path("legacy")) == original, "Migration preserves exact legacy bytes without rewriting source")
	Saves.save_snapshot(migrated.profile,migrated.run,"legacy")
	expect(FileAccess.get_file_as_bytes(Saves.snapshot_path("legacy") + ".legacy-v2") == original, "Subsequent autosave never alters legacy archive")
	expect(Saves.decode_snapshot('{"version":999,"profile":{},"run":{}}'.to_utf8_buffer()).is_empty(), "Future envelope rejects safely")
	var envelope: Dictionary = JSON.parse_string(Saves.encode_snapshot({"profile":{},"run":{}}).get_string_from_utf8())
	envelope.sha256 = "bad"
	expect(Saves.decode_snapshot(JSON.stringify(envelope).to_utf8_buffer()).is_empty(), "Payload corruption is rejected")
	expect(Saves.save_snapshot({}, {}, "../escape") == ERR_INVALID_PARAMETER, "Save slots cannot escape directory")
	var broken: FileAccess = FileAccess.open(Saves.snapshot_path("broken"),FileAccess.WRITE)
	broken.store_string("invalid")
	broken.close()
	expect(Saves.load_snapshot("broken").is_empty() and not Saves.last_error.is_empty(), "Corrupt existing save is distinguishable from an absent campaign")
	expect(Saves.load_snapshot("missing").is_empty() and Saves.last_error.is_empty(), "Missing save remains an ordinary new-game case")
	var demo: CampaignState = Campaign.new()
	demo.configure(true)
	demo.clear_sector(demo.core_coordinate("fire"))
	Saves.save_snapshot(demo.to_dict(),run,"demo")
	expect(Saves.import_demo("broken") == ERR_FILE_CORRUPT and FileAccess.get_file_as_string(Saves.snapshot_path("broken")) == "invalid", "Demo import never treats a corrupt existing campaign as an empty destination")
	expect(Saves.import_demo("imported") == OK and not Saves.load_snapshot("imported").profile.demo, "Demo import creates distinct full campaign")
	expect(Saves.import_demo("imported") == ERR_ALREADY_EXISTS, "Demo import cannot overwrite progress")
	var directory: DirAccess = DirAccess.open(Saves.storage_root)
	if directory != null:
		for filename: String in directory.get_files(): DirAccess.remove_absolute(Saves.storage_root.path_join(filename))
		DirAccess.remove_absolute(Saves.storage_root)
	Saves.storage_root = previous_root
