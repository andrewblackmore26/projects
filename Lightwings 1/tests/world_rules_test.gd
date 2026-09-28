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
	for coord: Vector2i in [Vector2i(3, -2), Vector2i(-4, 1), Vector2i(0, 5), Vector2i.ZERO]:
		var descriptor: Dictionary = first.sector_at(coord)
		expect(descriptor == second.sector_at(coord), "Seed and coordinate determine node independent of exploration")
		expect(descriptor.tier >= 1 and descriptor.tier <= GameTuning.MAX_TIER, "Ring-derived tier stays within supported roster")
	expect(first.to_dict() == initial, "Reading procedural nodes does not inflate profile")
	expect(first.can_enter(Vector2i.ZERO, Vector2i.ONE, 0).allowed, "A diagonal neighbour is enterable (open 8-neighbour lattice)")
	expect(not first.can_enter(Vector2i.ZERO, Vector2i(2, 1), 0).allowed, "Travel requires Chebyshev adjacency (a knight's move is not a neighbour)")
	expect(not first.can_enter(Vector2i(6, 6), Vector2i(7, 7), 0).allowed, "The perimeter is sealed: no neighbour beyond the level radius")
	expect(first.sector_at(Vector2i(6, 0)).tier >= first.sector_at(Vector2i(1, 0)).tier, "Outward travel does not decrease difficulty tier")
	expect(not first.in_bounds(Vector2i(7, 0)) and first.in_bounds(Vector2i(6, 0)), "L1's bounded disc is exactly radius 6 (spec preamble)")
	expect(Campaign.valid_key("-10,24") and not Campaign.valid_key("01,0") and not Campaign.valid_key("garbage"), "Coordinate persistence uses canonical signed integer keys")
	expect(Campaign.ring(Vector2i(-4, 3)) == 4, "Ring is Chebyshev distance, not Euclidean")
	var boss: Vector2i = first.boss_coord()
	expect(Campaign.ring(boss) == first.level_radius(), "Boss sits on the level's perimeter ring")
	expect(first.neighbours_of(boss).size() == 5, "The boss node (perimeter, never a corner) opens onto its 5 in-bounds neighbours")

func _test_progression() -> void:
	var campaign: CampaignState = Campaign.new()
	expect(campaign.unlocked == [GameTuning.ELEMENTS[0]], "Campaign starts with only Lightning unlocked (spec §8)")
	expect(not campaign.unlock_element("fire", 0.0), "A zero-amount absorption never unlocks")
	expect(campaign.unlock_element("fire", 5.0) and "fire" in campaign.unlocked, "Absorbing an element's light unlocks its branch")
	expect(not campaign.unlock_element("fire", 5.0), "Re-absorbing an already-unlocked element reports no new unlock")
	expect(not campaign.unlock_element("not_an_element", 5.0), "An unknown element token never unlocks anything")
	var seed_value: int = campaign.world_seed
	var epoch_before: int = campaign.epoch
	campaign.on_death()
	expect(campaign.world_seed == seed_value and campaign.current_sector == Vector2i.ZERO and campaign.deaths == 1, "Reboot preserves seed and resets to origin")
	expect(campaign.epoch == epoch_before + 1, "Death advances the epoch, which changes level_seed (spec: a fresh seed every life)")
	expect("fire" in campaign.unlocked, "Reboot preserves earned unlocks")
	var travelled: CampaignState = Campaign.new()
	var epoch_travel: int = travelled.epoch
	travelled.travel_to_level(2)
	expect(travelled.level == 2 and travelled.epoch == epoch_travel + 1 and travelled.current_sector == Vector2i.ZERO, "Travelling to a level is also an epoch change (fresh layout, spec preamble)")
	var boss_campaign: CampaignState = Campaign.new()
	var boss: Vector2i = boss_campaign.boss_coord()
	boss_campaign.on_enter(boss)
	var result: Dictionary = boss_campaign.complete_level()
	expect(result.level_completed and result.revealed_element == "fire" and boss_campaign.is_level_complete(1), "Beating level 1's boss completes it and reveals Fire (spec §8 table)")
	var repeat: Dictionary = boss_campaign.complete_level()
	expect(not repeat.level_completed, "complete_level is idempotent")
	expect(boss_campaign.best_ring.get(1, 0) == Campaign.ring(boss), "Best ring records how far the run reached before the boss")
	expect(not boss_campaign.campaign_complete(), "One level does not finish the five-level campaign")
	var saved: Dictionary = boss_campaign.to_dict()
	var restored: CampaignState = Campaign.new()
	restored.from_dict(saved)
	expect(restored.to_dict() == saved, "New campaign round-trip preserves every serialized field")
	var malformed: CampaignState = Campaign.new()
	malformed.from_dict({"schema_version": 4, "unlocked": "bad", "discovered": ["bad", 4], "current_sector": "bad"})
	expect(malformed.current_sector == Vector2i.ZERO and malformed.discovered == ["0,0"], "Malformed collection records recover safely")
	var legacy: CampaignState = Campaign.new()
	legacy.from_dict({"schema_version": 3, "deaths": 7, "unlocked": ["fire", "void"], "story_flags": {"reboot_3": true, "first_evolution": true}})
	expect(legacy.deaths == 7 and legacy.unlocked == [GameTuning.ELEMENTS[0]] and legacy.story_flags.has("reboot_3") and not legacy.story_flags.has("first_evolution"), "Legacy (schema<4) saves keep deaths and reboot flags but reset unlocks to Lightning (approved preamble)")

func _test_evolution() -> void:
	expect([Rules.threshold(1),Rules.threshold(2),Rules.threshold(3),Rules.threshold(4),Rules.threshold(5),Rules.threshold(6)] == [100,250,500,900,1500,-1], "Six-tier light thresholds use central tuning")
	var unlocked: Array = Array(GameTuning.ELEMENTS)
	var first: Array[String] = Rules.offers("neutral",1,{"void":50,"plasma":30,"fire":20},unlocked,[],42)
	expect(first.size() == 3 and ShipCatalog.get_ship(first[0]).element == "void" and ShipCatalog.get_ship(first[1]).element == "plasma" and ShipCatalog.get_ship(first[2]).element == "fire", "Seed evolution ranks three absorbed elements")
	expect(first == Rules.offers("neutral",1,{"void":50,"plasma":30,"fire":20},unlocked,[],42), "Offer seed is reproducible")
	var zero: Array[String] = Rules.offers("neutral",1,{},[GameTuning.ELEMENTS[0]])
	expect(zero.size() == 3, "Zero-diet first evolution still has three distinct starting-element hulls")
	# Fill rule (spec §8): fewer than three unlocked elements still offers three DISTINCT hulls.
	for unlocked_count: int in [1,2,3,5]:
		var pool: Array[String] = Array(GameTuning.ELEMENTS).slice(0, unlocked_count)
		var diet: Dictionary = {}
		for index: int in range(pool.size()): diet[pool[index]] = 100 - index
		var filled: Array[String] = Rules.offers("neutral",1,diet,pool,[],7)
		var distinct: Dictionary = {}
		for id: String in filled: distinct[id] = true
		expect(filled.size() == 3 and distinct.size() == 3, "First evolution with %d unlocked element(s) fills to three distinct hulls" % unlocked_count)
	# The neutral T1 seed as "current" has no roster; fill must fall back to
	# the highest-ranked unlocked element rather than staying short.
	var neutral_current: Array[String] = Rules.offers("neutral",1,{"fire":10},["fire"],[],3)
	expect(neutral_current.size() == 3, "Neutral-seed current element falls back to the ranked unlocked element for fill")
	for id: String in neutral_current: expect(ShipCatalog.get_ship(id).element == "fire", "Fill with a single unlocked element only draws from that element's roster")
	# Negative control: a roster lookup for a nonexistent element must return
	# no candidates, proving the fill loop can actually come up short.
	expect(Rules._roster_ids("nonexistent_element", 2).is_empty(), "CONTROL: an unknown element has no roster to fill from")
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
	expect(Rules.offers("fire",GameTuning.MAX_TIER,{},unlocked).is_empty(), "Terminal tier has no offer")

func _test_saves() -> void:
	# Note (P5a): full save schema-4 migration (SaveService's own envelope/
	# legacy-archive behaviour) is unaffected by the CampaignState schema
	# change - CampaignState.to_dict()/from_dict() are opaque Dictionaries to
	# SaveService. This section keeps the generic envelope/atomicity/cloud
	# behaviour and drops the v0.2-schema-specific migration assertions
	# (checkpoints/core distances no longer exist to migrate); the real
	# v3->v4 profile-migration test suite is P5b's "Save schema 4" item.
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
	var directory: DirAccess = DirAccess.open(Saves.storage_root)
	if directory != null:
		for filename: String in directory.get_files(): DirAccess.remove_absolute(Saves.storage_root.path_join(filename))
		DirAccess.remove_absolute(Saves.storage_root)
	Saves.storage_root = previous_root
