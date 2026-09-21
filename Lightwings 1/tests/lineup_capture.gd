extends SceneTree
## Acceptance 8, the human half: "a designer cannot pick the generated ones out of a line-up with
## the hand-authored ones". Writes 12 roster elites and bosses and 12 freshly generated ones, under
## neutral shuffled names, into artifacts/lineup/ with an answer key beside them. Look at it with:
##   tools\godot.ps1 -Arguments '"res://scenes/gallery.tscn" -- --catalog-root=res://artifacts/lineup --gallery-export=<png>'
## Not a test. Headless is fine: it only writes files.

func _initialize() -> void:
	var root: String = "res://artifacts/lineup"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var dir: DirAccess = DirAccess.open(root)
	for file: String in dir.get_files(): dir.remove(file)
	var ships: Array = []
	for entry: Dictionary in RailRoster.manifest():
		if str(entry.faction) == "elite" and ships.size() < 12: ships.append(["roster " + str(entry.id), RailRoster.build(entry)])
	var pairs: Array = [["yellow", "silver"], ["red", "violet"], ["green", "yellow"], ["silver", "red"], ["violet", "green"], ["red", "yellow"]]
	var archetypes: Array[String] = ["radial_elite", "heavy_elite", "irregular_elite"]
	for n: int in range(12):
		var pair: Array = pairs[n % pairs.size()]
		var params: Dictionary = {"id": "x", "faction": "elite", "archetype": archetypes[n % 3], "tier": 3 + n % 3, "chassis_color": pair[0], "accent_color": pair[1], "element": Elements.ELEMENT_OF_COLOR[pair[0]], "role": "heavy", "family": "heavy", "seed": 9000 + n * 37}
		ships.append(["generated seed %d" % int(params.seed), ShipRecipe.generate(params)])
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 424242
	for i: int in range(ships.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Array = ships[i]
		ships[i] = ships[j]
		ships[j] = swap
	var key: PackedStringArray = PackedStringArray()
	var failures: int = 0
	for n: int in range(ships.size()):
		var ship: ShipDefinition = ships[n][1]
		ship.id = "lineup_%02d" % (n + 1)
		ship.display_name = "Line-up %02d" % (n + 1)
		if not ShipRecipe.style_check(ship).is_empty(): failures += 1
		ShipCatalog.save_ship(ship, root.path_join(ship.id + ".tres"))
		key.append("%s = %s" % [ship.id, ships[n][0]])
	var file: FileAccess = FileAccess.open(root.path_join("ANSWER_KEY.txt"), FileAccess.WRITE)
	file.store_string("\n".join(key) + "\n")
	print("lineup checks: %d written, %d failures" % [ships.size(), failures])
	quit(1 if failures > 0 else 0)
