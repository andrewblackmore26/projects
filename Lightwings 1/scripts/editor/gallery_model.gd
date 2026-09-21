class_name GalleryModel
extends RefCounted
## Pure, headless-testable scan/filter/sort/coverage/scheduler for the S6 gallery (spec §12).
## No nodes, no rendering: `gallery.gd` and its views are the only things that touch the tree.

## Every `.tres` in `root`, INCLUDING invalid ones and anything that is not a ship at all. Loaded
## directly with `ResourceLoader.load(.., "", CACHE_MODE_IGNORE)`, never through
## `ShipCatalog._template` (which silently drops an invalid hull).
static func scan(root: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(root) and not root.begins_with("res://"):
		return entries
	var files: PackedStringArray = DirAccess.get_files_at(root)
	for id: String in ShipCatalog.ids_from_files(files):
		entries.append(_scan_one(root, id))
	return entries

static func _scan_one(root: String, id: String) -> Dictionary:
	var path: String = root.path_join(id + ".tres")
	var physical: String = path if FileAccess.file_exists(path) else path + ".remap"
	var modified: int = FileAccess.get_modified_time(physical) if FileAccess.file_exists(physical) else 0
	var entry: Dictionary = {
		"id": id, "path": path, "modified": modified, "name": id, "faction": "", "tier": 0,
		"archetype": "", "chassis": "", "accent": "", "element": "", "schema": 0, "circles": 0,
		"lines": 0, "rails": 0, "footprint": 0.0, "set_pieces": [] as Array[String],
		"errors": PackedStringArray(), "warnings": PackedStringArray(), "status": "invalid", "ship": null,
	}
	if not ResourceLoader.exists(path):
		entry.errors = PackedStringArray(["File does not resolve to a resource."])
		return entry
	var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not resource is ShipDefinition:
		entry.errors = PackedStringArray(["Not a ship definition."])
		return entry
	var ship: ShipDefinition = resource
	var errors: PackedStringArray
	var warnings: PackedStringArray
	var circles: int = 0
	var lines: int = 0
	var rails: int = 0
	var set_pieces: Array[String] = []
	var compiled: ShipDefinition = ship.duplicate(true)
	if ship.is_rail_hull():
		errors = ShipGrammar.validate(ship)
		warnings = ShipGrammar.warnings(ship)
		var budget: Dictionary = ShipCompiler.budget(ship)
		circles = int(budget.circles)
		lines = int(budget.lines)
		rails = ship.rails.size()
		set_pieces = ShipGrammar.mounted_pieces(ship)
		if errors.is_empty(): ShipCompiler.compile(compiled)
	else:
		errors = ShipCatalog.validate(ship)
		warnings = ShipCatalog.warnings(ship)
		for part: PartDefinition in ship.parts:
			if part.shape == "circle": circles += 1
			elif part.shape == "line": lines += 1
		if errors.is_empty(): ShipCatalog.recalculate(compiled)
	var status: String = "invalid" if not errors.is_empty() else ("warnings" if not warnings.is_empty() else "valid")
	entry.name = ship.display_name
	entry.faction = ship.faction
	entry.tier = ship.tier
	entry.archetype = ship.archetype
	entry.chassis = ship.chassis_color
	entry.accent = ship.accent_color
	entry.element = ship.element
	entry.schema = ship.schema_version
	entry.circles = circles
	entry.lines = lines
	entry.rails = rails
	# From the COMPILED copy: a rail hull is saved without parts, so the raw file's `footprint` is
	# the resource default (48). Reading it made every rail hull say "48px" and draw far too large
	# for its tile - seen in the first staging contact sheet, where only cores fitted.
	entry.footprint = compiled.footprint if errors.is_empty() else ship.footprint
	entry.set_pieces = set_pieces
	entry.errors = errors
	entry.warnings = warnings
	entry.status = status
	entry.ship = compiled if errors.is_empty() else ship
	return entry

## §12.3. `criteria` keys are all optional: faction, chassis, accent ("none" for no accent), pair
## ({chassis, accent} exact), tier, archetype, rail_count, set_piece, status, search.
static func filter(entries: Array[Dictionary], criteria: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if criteria.has("faction") and str(criteria.faction) != "" and str(entry.faction) != str(criteria.faction): continue
		if criteria.has("chassis") and str(criteria.chassis) != "" and str(entry.chassis) != str(criteria.chassis): continue
		if criteria.has("accent") and str(criteria.accent) != "":
			var wanted: String = str(criteria.accent)
			if wanted == "none":
				if str(entry.accent) != "": continue
			elif str(entry.accent) != wanted: continue
		if criteria.has("pair"):
			var pair: Dictionary = criteria.pair
			if str(entry.chassis) != str(pair.get("chassis", "")) or str(entry.accent) != str(pair.get("accent", "")): continue
		if criteria.has("tier") and int(criteria.tier) > 0 and int(entry.tier) != int(criteria.tier): continue
		if criteria.has("archetype") and str(criteria.archetype) != "" and str(entry.archetype) != str(criteria.archetype): continue
		if criteria.has("rail_count") and int(criteria.rail_count) >= 0 and int(entry.rails) != int(criteria.rail_count): continue
		if criteria.has("set_piece") and str(criteria.set_piece) != "":
			var pieces: Array = entry.set_pieces
			if not pieces.has(str(criteria.set_piece)): continue
		if criteria.has("status") and str(criteria.status) != "" and str(entry.status) != str(criteria.status): continue
		if criteria.has("search") and str(criteria.search).strip_edges() != "":
			var needle: String = str(criteria.search).to_lower()
			if not str(entry.name).to_lower().contains(needle) and not str(entry.id).to_lower().contains(needle): continue
		result.append(entry)
	return result

## `key` in tier | footprint | circles | name | modified.
static func sort(entries: Array[Dictionary], key: String, descending: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = entries.duplicate()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var va: Variant = a.get(key, 0)
		var vb: Variant = b.get(key, 0)
		var less: bool = (str(va) < str(vb)) if key == "name" else (float(va) < float(vb))
		return not less if descending else less)
	return result

## §12.6: an element x tier grid built from `ShipGenerator.roster_manifest()`, filled/empty counts,
## and (for an empty cell) the manifest's own suggested slot.
static func coverage(entries: Array[Dictionary], manifest: Array[Dictionary]) -> Dictionary:
	var counts: Dictionary = {}
	for entry: Dictionary in entries:
		var key: String = "%s|%d" % [str(entry.get("element", "")), int(entry.get("tier", 0))]
		counts[key] = int(counts.get(key, 0)) + 1
	var elements: Array[String] = []
	for slot: Dictionary in manifest:
		var element: String = str(slot.get("element", ""))
		if not elements.has(element): elements.append(element)
	var max_tier: int = GameTuning.MAX_TIER
	var cells: Array[Dictionary] = []
	for element: String in elements:
		for tier: int in range(1, max_tier + 1):
			var key: String = "%s|%d" % [element, tier]
			var count: int = int(counts.get(key, 0))
			var suggestion: Dictionary = {}
			if count == 0:
				for slot: Dictionary in manifest:
					if str(slot.get("element", "")) == element and int(slot.get("tier", 0)) == tier:
						suggestion = slot
						break
			cells.append({"element": element, "tier": tier, "count": count, "filled": count > 0, "suggestion": suggestion})
	return {"cells": cells, "elements": elements, "max_tier": max_tier}

## The "≤ 24 animating, nearest-to-centre, off-screen frozen" scheduler, as a pure function:
## `tile_rects[i]` intersecting `visible_rect`, nearest-centre-first, at most `cap`.
static func animating(visible_rect: Rect2, tile_rects: Array[Rect2], cap: int = 24) -> PackedInt32Array:
	var center: Vector2 = visible_rect.get_center()
	var candidates: Array[Dictionary] = []
	for i: int in range(tile_rects.size()):
		if visible_rect.intersects(tile_rects[i]):
			candidates.append({"i": i, "d": tile_rects[i].get_center().distance_squared_to(center)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.d) < float(b.d))
	var result: PackedInt32Array = PackedInt32Array()
	for i: int in range(mini(cap, candidates.size())): result.append(int(candidates[i].i))
	return result

## A cheap signature of the directory's contents (names + mtimes) for the gallery's live-reload
## poll: unequal whenever a file is added, removed or resaved.
static func signature(root: String) -> int:
	var files: PackedStringArray = DirAccess.get_files_at(root)
	var parts: Array = []
	for file: String in files:
		if file.ends_with(".tres"):
			parts.append([file, FileAccess.get_modified_time(root.path_join(file))])
	parts.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
	return hash(parts)
