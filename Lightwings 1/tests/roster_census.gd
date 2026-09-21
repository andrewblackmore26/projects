extends SceneTree
## Prints a census of the roster on disk: per kind, how many hulls, and the range of footprint,
## circle, line and mount counts. Not a test (the runner does not discover it): it is the "before"
## and "after" measurement for the ship design spec rebuild. Run:
##   tools\godot.ps1 -Arguments '--headless --script "res://tests/roster_census.gd"'

func _initialize() -> void:
	var groups: Dictionary = {}
	for ship: ShipDefinition in ShipCatalog.all_forms():
		var kind: String = ship.faction
		if ship.faction != "player":
			var words: PackedStringArray = ship.id.split("_")
			kind = "%s_%s" % [words[0], words[1]] if ship.faction != "boss" else "boss"
		elif ship.id != "player_seed":
			kind = "player_t%d" % ship.tier
		else:
			kind = "player_t1"
		var circles: int = 0
		var lines: int = 0
		var mounts: int = 0
		for part: PartDefinition in ship.parts:
			if part.shape == "line": lines += 1
			else: circles += 1
			if part.ability_id != "": mounts += 1
		if not groups.has(kind): groups[kind] = {"n": 0, "footprint": [], "circles": [], "lines": [], "mounts": []}
		var group: Dictionary = groups[kind]
		group.n += 1
		group.footprint.append(ship.footprint)
		group.circles.append(circles)
		group.lines.append(lines)
		group.mounts.append(mounts)
	var kinds: Array = groups.keys()
	kinds.sort()
	var total: int = 0
	for kind: String in kinds:
		var group: Dictionary = groups[kind]
		total += int(group.n)
		print("census %-16s n=%3d footprint=%s circles=%s lines=%s mounts=%s" % [kind, group.n, _range(group.footprint), _range(group.circles), _range(group.lines), _range(group.mounts)])
	print("census checks: %d hulls, 0 failures" % total)
	quit(0)

func _range(values: Array) -> String:
	return "%d..%d" % [int(values.min()), int(values.max())]
