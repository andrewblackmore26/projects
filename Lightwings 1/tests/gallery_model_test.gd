extends SceneTree
## S6: GalleryModel is pure and headless-testable. Stages a temp root under user:// with the five
## rail fixtures, one deliberately invalid rail hull, and one non-ship file.
const Harness = preload("res://tests/support/harness.gd")

var h: Harness

func _initialize() -> void:
	h = Harness.new("gallery_model_test")
	_run()
	h.finish(self)

func _root() -> String:
	var path: String = "user://gallery_model_test_root"
	DirAccess.make_dir_recursive_absolute(path)
	return path

func _clear(root: String) -> void:
	var dir: DirAccess = DirAccess.open(root)
	if dir == null: return
	for file: String in dir.get_files(): dir.remove(file)

func _invalid_hull() -> ShipDefinition:
	# RAIL-ORDER-ADJ: two adjacent rails share an order.
	var ship: ShipDefinition = ShipDefinition.new()
	ship.schema_version = 4
	ship.id = "broken_hull"
	ship.display_name = "Broken"
	ship.faction = "enemy"
	ship.archetype = "sentry"
	ship.chassis_color = "yellow"
	ship.accent_color = "red"
	ship.core_depth = 2
	ship.core_weapon = "coil_pair"
	var rail_a: RailDefinition = RailDefinition.new()
	rail_a.radius = ShipGrammar.RAIL_RADII[0]
	rail_a.order = 4
	rail_a.speed = -0.95
	var rail_b: RailDefinition = RailDefinition.new()
	rail_b.radius = ShipGrammar.RAIL_RADII[1]
	rail_b.order = 4 # same order as rail_a: RAIL-ORDER-ADJ
	rail_b.speed = 0.42
	for rail: RailDefinition in [rail_a, rail_b]:
		var slots: Array[SlotDefinition] = []
		for i: int in range(rail.order):
			var slot: SlotDefinition = SlotDefinition.new()
			slot.type = "node"
			slot.node_radius = 7
			slots.append(slot)
		rail.slots = slots
	ship.rails = [rail_a, rail_b]
	return ship

func _run() -> void:
	var root: String = _root()
	_clear(root)
	ShipCatalog.catalog_root = root

	var fixture_ids: PackedStringArray = PackedStringArray(["boss", "drone", "irregular", "player_t3", "radial_elite"])
	for name: String in fixture_ids:
		var errors: PackedStringArray = []
		var ship: ShipDefinition = ShipGrammar.load_json("res://tests/fixtures/ships_v4/%s.json" % name, errors)
		h.check(ship != null and errors.is_empty(), "Fixture %s parses" % name)
		ship.id = name
		h.check(ShipCatalog.save_ship(ship, root.path_join(name + ".tres")) == OK, "Fixture %s saves" % name)

	h.check(ShipCatalog.save_ship(_invalid_hull(), root.path_join("broken_hull.tres")) == OK, "Invalid hull saves")

	var not_a_ship: Resource = Resource.new()
	h.check(ResourceSaver.save(not_a_ship, root.path_join("not_a_ship.tres")) == OK, "Non-ship resource saves")

	ShipCatalog.invalidate()
	var entries: Array[Dictionary] = GalleryModel.scan(root)
	var ids: Array = []
	for entry: Dictionary in entries: ids.append(str(entry.id))

	# --- every file is listed, including the invalid one and the non-ship -----------------------
	h.check(ids.size() == 7, "Every .tres in the root is listed (7), got %d" % ids.size())
	h.check(ids.has("broken_hull") and ids.has("not_a_ship"), "Invalid hull and non-ship file both listed")
	var catalog_ids: Array[String] = ShipCatalog.ids_from_files(DirAccess.get_files_at(root))
	var catalog_valid: Array = []
	for id: String in catalog_ids:
		if ShipCatalog.get_ship(id) != null: catalog_valid.append(id)
	h.control("scanning through ShipCatalog instead would drop the invalid ones", ids.size() > catalog_valid.size())

	# --- invalid status and first error code -------------------------------------------------
	var broken: Dictionary = {}
	var not_ship: Dictionary = {}
	for entry: Dictionary in entries:
		if entry.id == "broken_hull": broken = entry
		if entry.id == "not_a_ship": not_ship = entry
	h.check(broken.status == "invalid", "Broken hull is flagged invalid")
	h.check(String(broken.errors[0]).begins_with("RAIL-ORDER-ADJ"), "Broken hull's first error is RAIL-ORDER-ADJ, got: %s" % (broken.errors[0] if broken.errors.size() > 0 else "<none>"))
	h.check(not_ship.status == "invalid" and not_ship.errors.size() > 0, "Non-ship file is flagged invalid with an error")
	var valid_count: int = 0
	for entry: Dictionary in entries:
		if entry.status != "invalid": valid_count += 1
	h.control("a status check that always reports 'invalid' would also pass the previous line", valid_count > 0)

	# --- filters, one check + one control each -------------------------------------------------
	var valid_entries: Array[Dictionary] = GalleryModel.filter(entries, {"status": "valid"})
	# radial_elite fixture -> elite/yellow/red/tier2/radial_elite/2 rails
	var by_faction: Array[Dictionary] = GalleryModel.filter(valid_entries, {"faction": "elite"})
	h.check(by_faction.size() == 2, "Faction filter narrows to the two elites (radial_elite, irregular), got %d" % by_faction.size())
	h.control("faction 'player' matches a different set", GalleryModel.filter(valid_entries, {"faction": "player"}).size() != by_faction.size())

	var by_chassis: Array[Dictionary] = GalleryModel.filter(valid_entries, {"chassis": "yellow"})
	h.check(by_chassis.size() == 2, "Chassis filter narrows to yellow hulls (radial_elite, drone), got %d" % by_chassis.size())
	h.control("wrong chassis value matches nothing", GalleryModel.filter(valid_entries, {"chassis": "violet"}).size() == 0)

	var by_no_accent: Array[Dictionary] = GalleryModel.filter(valid_entries, {"accent": "none"})
	var expect_no_accent: int = 0
	for entry: Dictionary in valid_entries:
		if str(entry.accent) == "": expect_no_accent += 1
	h.check(by_no_accent.size() == expect_no_accent and expect_no_accent > 0, "Accent 'none' filter matches mono-colour hulls (%d)" % expect_no_accent)
	h.control("asking for a real accent colour instead would not match the mono hulls", GalleryModel.filter(valid_entries, {"accent": "red"}).size() != by_no_accent.size())

	var by_pair: Array[Dictionary] = GalleryModel.filter(valid_entries, {"pair": {"chassis": "yellow", "accent": "red"}})
	h.check(by_pair.size() == 2, "Exact pair filter (yellow/red) matches drone and radial_elite, got %d" % by_pair.size())
	h.control("a mismatched pair matches nothing", GalleryModel.filter(valid_entries, {"pair": {"chassis": "yellow", "accent": "violet"}}).size() == 0)

	var by_tier: Array[Dictionary] = GalleryModel.filter(valid_entries, {"tier": 2})
	h.check(by_tier.size() >= 1, "Tier filter matches at least one hull")
	h.control("a tier with no hulls matches none", GalleryModel.filter(valid_entries, {"tier": 99}).size() == 0)

	var by_archetype: Array[Dictionary] = GalleryModel.filter(valid_entries, {"archetype": "radial_elite"})
	h.check(by_archetype.size() == 1 and by_archetype[0].id == "radial_elite", "Archetype filter narrows to radial_elite")
	h.control("an archetype nothing carries matches none", GalleryModel.filter(valid_entries, {"archetype": "chain"}).size() == 0)

	var by_rails: Array[Dictionary] = GalleryModel.filter(valid_entries, {"rail_count": 2})
	h.check(by_rails.size() == 2, "Rail-count filter (2) narrows to radial_elite and player_t3, got %d" % by_rails.size())
	h.control("a rail count nothing has matches none", GalleryModel.filter(valid_entries, {"rail_count": 99}).size() == 0)

	var by_piece: Array[Dictionary] = GalleryModel.filter(valid_entries, {"set_piece": "v_rack"})
	h.check(by_piece.size() == 3, "Set-piece filter narrows to the hulls carrying v_rack (radial_elite, irregular, boss), got %d" % by_piece.size())
	h.control("a set piece nothing carries matches none", GalleryModel.filter(valid_entries, {"set_piece": "storm_crown"}).size() == 0)

	var by_status: Array[Dictionary] = GalleryModel.filter(entries, {"status": "invalid"})
	h.check(by_status.size() == 2, "Status filter narrows to the two invalid entries")
	h.control("status 'valid' would exclude them", GalleryModel.filter(entries, {"status": "valid"}).size() < entries.size())

	var by_search: Array[Dictionary] = GalleryModel.filter(entries, {"search": "triskel"})
	h.check(by_search.size() == 1 and by_search[0].id == "radial_elite", "Free-text search matches the fixture's display name")
	h.control("a nonsense query matches nothing", GalleryModel.filter(entries, {"search": "zzz_no_such_ship"}).size() == 0)

	# --- sorting ---------------------------------------------------------------------------------
	var by_tier_asc: Array[Dictionary] = GalleryModel.sort(valid_entries, "tier", false)
	var ascending: bool = true
	for i: int in range(1, by_tier_asc.size()):
		if int(by_tier_asc[i].tier) < int(by_tier_asc[i - 1].tier): ascending = false
	h.check(ascending, "Sort by tier ascending is non-decreasing")
	var by_tier_desc: Array[Dictionary] = GalleryModel.sort(valid_entries, "tier", true)
	h.control("reversed flag reverses the order", by_tier_desc[0].id != by_tier_asc[0].id or by_tier_asc.size() <= 1)

	var by_name: Array[Dictionary] = GalleryModel.sort(valid_entries, "name", false)
	var name_ok: bool = true
	for i: int in range(1, by_name.size()):
		if str(by_name[i].name) < str(by_name[i - 1].name): name_ok = false
	h.check(name_ok, "Sort by name is alphabetical")

	# --- counts equal ShipCompiler.budget -------------------------------------------------------
	var radial: Dictionary = {}
	for entry: Dictionary in valid_entries:
		if entry.id == "radial_elite": radial = entry
	var expected_budget: Dictionary = ShipCompiler.budget(radial.ship)
	h.check(int(radial.circles) == int(expected_budget.circles) and int(radial.lines) == int(expected_budget.lines), "Rail hull counts equal ShipCompiler.budget")

	# --- coverage ----------------------------------------------------------------------------
	var manifest: Array[Dictionary] = ShipGenerator.roster_manifest()
	var coverage: Dictionary = GalleryModel.coverage(entries, manifest)
	var filled_seen: bool = false
	var empty_seen: bool = false
	for cell: Dictionary in coverage.cells:
		if cell.filled: filled_seen = true
		else: empty_seen = true
	h.check(filled_seen, "Coverage marks at least one filled cell")
	h.check(empty_seen, "Coverage marks at least one empty cell (this tiny staged root cannot fill the whole roster)")
	var empty_with_suggestion: bool = false
	for cell: Dictionary in coverage.cells:
		if not cell.filled and not cell.suggestion.is_empty(): empty_with_suggestion = true
	h.check(empty_with_suggestion, "An empty cell carries a manifest suggestion")

	# --- scheduler -----------------------------------------------------------------------------
	var visible: Rect2 = Rect2(Vector2.ZERO, Vector2(400, 300))
	var tiles: Array[Rect2] = []
	for i: int in range(40):
		tiles.append(Rect2(Vector2(i * 10.0, 0), Vector2(50, 50))) # all overlap the visible rect
	var scheduled: PackedInt32Array = GalleryModel.animating(visible, tiles, 24)
	h.check(scheduled.size() == 24, "Scheduler caps at 24 with 40 visible tiles")
	h.control("40 visible tiles without the cap would all come back", scheduled.size() < tiles.size())

	var far_tiles: Array[Rect2] = [Rect2(Vector2(200, 150), Vector2(10, 10)), Rect2(Vector2(5000, 5000), Vector2(10, 10))]
	var far_scheduled: PackedInt32Array = GalleryModel.animating(visible, far_tiles, 24)
	h.check(far_scheduled.size() == 1 and far_scheduled[0] == 0, "An off-screen tile is never scheduled")
	h.control("a tile outside the rect being scheduled would size the result 2, not 1", far_scheduled.size() != far_tiles.size())

	var centered: PackedInt32Array = GalleryModel.animating(Rect2(Vector2(0, 0), Vector2(100, 100)), tiles, 3)
	var shifted: PackedInt32Array = GalleryModel.animating(Rect2(Vector2(300, 0), Vector2(100, 100)), tiles, 3)
	h.check(centered[0] != shifted[0] or centered != shifted, "Moving the visible rect changes the scheduled set")
	h.control("using the same rect twice would not change anything", centered == GalleryModel.animating(Rect2(Vector2(0, 0), Vector2(100, 100)), tiles, 3))

	# --- signature -------------------------------------------------------------------------------
	var before_sig: int = GalleryModel.signature(root)
	var extra: ShipDefinition = ShipGrammar.load_json("res://tests/fixtures/ships_v4/drone.json", [])
	extra.id = "another_drone"
	ShipCatalog.save_ship(extra, root.path_join("another_drone.tres"))
	var after_sig: int = GalleryModel.signature(root)
	h.check(before_sig != after_sig, "Signature changes when a file is added")
	h.control("re-checking the same unchanged root would not move it", GalleryModel.signature(root) == after_sig)

	_clear(root)
	ShipCatalog.invalidate()
