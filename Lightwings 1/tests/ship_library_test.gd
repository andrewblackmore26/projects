extends SceneTree
## The rail roster as a library (our own gate; spec v1's "every ship passes validation with no
## warnings"), and the colour language of spec §6.6 as checkable properties (acceptance 5's
## automated proxies: what a tester could read off an enemy's two colours must actually be true).
## Runs on the staging root until the cutover, then on `content/ships`.
const Harness = preload("res://tests/support/harness.gd")

func _initialize() -> void: _run.call_deferred()

func _root() -> String:
	return RailRoster.STAGING_ROOT if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(RailRoster.STAGING_ROOT)) else ShipCatalog.catalog_root

## What is wrong with the library at `root`, against the manifest. Empty means nothing.
func _audit(root: String) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var wanted: Dictionary = {}
	for entry: Dictionary in RailRoster.manifest(): wanted[str(entry.id)] = entry
	var found: Dictionary = {}
	var dir: DirAccess = DirAccess.open(root)
	if dir == null: return PackedStringArray(["no library at " + root])
	for file: String in dir.get_files():
		if file.ends_with(".tres"): found[file.get_basename()] = true
	for id: String in wanted:
		if not found.has(id): problems.append("MISSING: %s is in the manifest and not on disk" % id)
	for id: String in found:
		if not wanted.has(id): problems.append("ORPHAN: %s is on disk and not in the manifest" % id)
	for id: String in found:
		if not wanted.has(id): continue
		var ship: ShipDefinition = ResourceLoader.load(root.path_join(id + ".tres"), "", ResourceLoader.CACHE_MODE_IGNORE)
		if ship == null:
			problems.append("UNREADABLE: " + id)
			continue
		if not ship.parts.is_empty(): problems.append("PARTS: %s stores compiled parts" % id)
		for error: String in ShipCatalog.validate(ship): problems.append("INVALID: %s: %s" % [id, error])
		for warning: String in ShipCatalog.warnings(ship): problems.append("WARNING: %s: %s" % [id, warning])
		# A stale file cannot hide: what is on disk must be what the recipe builds today.
		var fresh: ShipDefinition = RailRoster.build(wanted[id])
		if var_to_bytes(ShipCompiler.grammar_signature(ship)) != var_to_bytes(ShipCompiler.grammar_signature(fresh)): problems.append("STALE: %s differs from a fresh build" % id)
		if int(ShipCompiler.budget(ship).circles) > ShipGrammar.MAX_CIRCLES: problems.append("BUDGET: %s has %d circles" % [id, int(ShipCompiler.budget(ship).circles)])
	return problems

## Spec §6.6 as rules about one enemy hull. Empty means its colours tell the truth.
func _colour_problems(ship: ShipDefinition) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if ship.chassis_color == "blue" or ship.accent_color == "blue": problems.append("blue on an enemy")
	if ship.accent_color != RailRoster.accent_for(ship.element, ship.archetype): problems.append("accent %s is not the pairing rule's %s" % [ship.accent_color, RailRoster.accent_for(ship.element, ship.archetype)])
	if Elements.color_key(ship.element) != ship.chassis_color: problems.append("chassis %s is not its element's colour" % ship.chassis_color)
	var shows_chassis: bool = false
	var shows_accent: bool = ship.accent_color == ""
	for piece: String in ShipGrammar.mounted_pieces(ship):
		var colours: Array = SetPieceCatalog.colours_of(piece)
		if colours.has(ship.chassis_color): shows_chassis = true
		if colours.has(ship.accent_color): shows_accent = true
	if not shows_chassis and not ShipGrammar.mounted_pieces(ship).is_empty(): problems.append("no weapon in its chassis colour")
	if not shows_accent: problems.append("an accent colour with no weapon in it: the colour promises something the ship cannot do")
	return problems

func _run() -> void:
	var h := Harness.new("SHIP LIBRARY")
	var root: String = _root()
	var manifest: Array[Dictionary] = RailRoster.manifest()
	var census: Dictionary = {}
	for entry: Dictionary in manifest: census[str(entry.faction)] = int(census.get(str(entry.faction), 0)) + 1
	h.check(manifest.size() == 146 and int(census.player) == 101 and int(census.enemy) == 25 and int(census.elite) == 15 and int(census.boss) == 5, "The manifest is 101 player + 25 regular + 15 elite + 5 boss = 146 (%s)" % str(census))
	var problems: PackedStringArray = _audit(root)
	h.check(problems.is_empty(), "%s: every hull is on disk, valid, without warnings, part-free, fresh and within 128 circles (%d problems: %s)" % [root, problems.size(), "; ".join(problems.slice(0, 4))])

	var liars: PackedStringArray = PackedStringArray()
	var mounted: Dictionary = {}
	var most_circles: int = 0
	var biggest: String = ""
	for entry: Dictionary in manifest:
		var ship: ShipDefinition = RailRoster.build(entry)
		for piece: String in ShipGrammar.mounted_pieces(ship): mounted[piece] = true
		var circles: int = int(ShipCompiler.budget(ship).circles)
		if circles > most_circles:
			most_circles = circles
			biggest = ship.id
		if ship.faction == "player": continue
		for problem: String in _colour_problems(ship): liars.append("%s: %s" % [ship.id, problem])
		if ship.faction == "enemy" and ship.accent_color != "": liars.append("%s: a regular with two colours" % ship.id)
		if ship.faction != "enemy" and ship.accent_color == "": liars.append("%s: an elite or boss with one colour" % ship.id)
	h.check(liars.is_empty(), "Every enemy's colours tell the truth: regulars mono, elites and bosses paired by the ring rule, a weapon in each colour shown (%s)" % "; ".join(liars.slice(0, 4)))
	print("library: largest hull is %s with %d circles" % [biggest, most_circles])
	h.check(most_circles <= ShipGrammar.MAX_CIRCLES, "The largest hull (%s, %d circles) fits the shader's 128" % [biggest, most_circles])
	var unmounted: Array[String] = []
	for id: String in SetPieceCatalog.ids():
		if not mounted.has(id): unmounted.append(id)
	print("library: set pieces mounted by no hull (%d): %s" % [unmounted.size(), ", ".join(unmounted)])
	h.check(unmounted.is_empty(), "Every one of the 33 set pieces is mounted by some hull (unmounted: %s)" % ", ".join(unmounted))

	# Controls: a scratch copy of three hulls, each sabotaged one way.
	var scratch: String = "user://library_controls_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch))
	for entry: Dictionary in manifest: ShipCatalog.save_ship(RailRoster.build(entry), scratch.path_join(str(entry.id) + ".tres"))
	h.check(_audit(scratch).is_empty(), "A freshly written scratch library audits clean (the controls' precondition)")
	DirAccess.open(scratch).remove("boss_fire.tres")
	h.control("a manifest hull deleted from disk", _has(_audit(scratch), "MISSING"))
	ShipCatalog.save_ship(RailRoster.build(manifest[-1]), scratch.path_join("boss_fire.tres"))
	var stray: ShipDefinition = RailRoster.build(manifest[5])
	stray.id = "not_in_the_manifest"
	ShipCatalog.save_ship(stray, scratch.path_join("not_in_the_manifest.tres"))
	h.control("a hull on disk that the manifest does not name", _has(_audit(scratch), "ORPHAN"))
	DirAccess.open(scratch).remove("not_in_the_manifest.tres")
	var stale: ShipDefinition = RailRoster.build(manifest[120])
	stale.rails[0].phase += 0.01
	ShipCatalog.save_ship(stale, scratch.path_join(stale.id + ".tres"))
	h.control("a hull on disk that is not what the recipe builds today", _has(_audit(scratch), "STALE"))
	var recoloured: ShipDefinition = RailRoster.build(manifest[130])
	recoloured.accent_color = "green" if recoloured.accent_color != "green" else "red"
	h.control("an elite's accent changed (%s)" % recoloured.id, not _colour_problems(recoloured).is_empty())
	var dir: DirAccess = DirAccess.open(scratch)
	for file: String in dir.get_files(): dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	h.finish(self)

func _has(problems: PackedStringArray, code: String) -> bool:
	for problem: String in problems:
		if problem.begins_with(code): return true
	return false
