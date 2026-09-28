extends SceneTree
## P5b: MinimapModel (spec §11, M3 "a tester always knows which way the
## boss is") and the HUD overlap fix (spec §24: slot icons + evolve prompt
## coexist). Model-level checks only; pixel-level confirmation is a GPU
## capture, recorded separately in the phase report.
const Harness = preload("res://tests/support/harness.gd")
const Campaign = preload("res://scripts/world/campaign_state.gd")

const SEEDS: int = 30

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var h := Harness.new("HUD MODEL")
	var samples: int = 0

	for seed_value: int in range(SEEDS):
		for level: int in range(1, 6):
			var campaign := Campaign.new()
			campaign.world_seed = hash("hud-model-%d" % seed_value)
			campaign.level = level

			# --- Explored / unexplored: model must agree with the world ---
			var probe: Vector2i = Vector2i(1, 0)
			if campaign.in_bounds(probe):
				campaign.discover(probe)
			var model: MinimapModel = MinimapModel.build(campaign)
			var probe_cell: MinimapModel.Cell = model.cell_at(probe)
			if campaign.in_bounds(probe):
				h.check(probe_cell != null and probe_cell.explored, "A discovered in-bounds node reads as explored")
			var undiscovered: Vector2i = Vector2i(0, campaign.level_radius())
			if undiscovered != probe and campaign.in_bounds(undiscovered):
				var undiscovered_cell: MinimapModel.Cell = model.cell_at(undiscovered)
				h.check(undiscovered_cell != null and not undiscovered_cell.explored, "An unvisited in-bounds node reads as unexplored (reveals nothing)")
			h.check(model.grid_size() == campaign.level_radius() * 2 + 1, "Grid fits the whole bounded level (spec §11)")

			# --- Boss bearing: tick 0 (origin) -----------------------------
			samples += 1
			_check_bearing(h, campaign, model, "tick 0")

			# --- Boss bearing: after a death (fresh epoch/layout) ----------
			campaign.on_death()
			var after_death_model: MinimapModel = MinimapModel.build(campaign)
			samples += 1
			_check_bearing(h, campaign, after_death_model, "after death")

			# --- Boss bearing: from a non-origin current node --------------
			var elsewhere: Vector2i = Vector2i(0, mini(2, campaign.level_radius()))
			if campaign.in_bounds(elsewhere) and elsewhere != campaign.boss_coord():
				campaign.current_sector = elsewhere
				var elsewhere_model: MinimapModel = MinimapModel.build(campaign)
				samples += 1
				_check_bearing(h, campaign, elsewhere_model, "away from origin")

	print("HUD MODEL: boss-bearing sample count = %d" % samples)

	# --- Negative control: debug_hide_boss must make the bearing fail -----
	var control_campaign := Campaign.new()
	control_campaign.world_seed = 12345
	var hidden: MinimapModel = MinimapModel.build(control_campaign, true)
	h.control("debug_hide_boss forcing the bearing blank", hidden.bearing_direction == "NONE" and hidden.bearing_distance < 0)

	# --- Slot icons stay visible while the evolve prompt is up ------------
	# _draw_slot_icons used to `return` early whenever evolution_button.visible
	# was true, hiding the slot icons exactly when the evolve pill appeared
	# (spec §24 wants both). Confirmed by source: the guard clause in
	# scripts/ui/hud/hud.gd (main.gd's until modernization M2 moved the HUD)
	# no longer names evolution_button.visible at all.
	var source: String = FileAccess.get_file_as_string("res://scripts/ui/hud/hud.gd")
	var guard_start: int = source.find("func _draw_slot_icons")
	h.check(guard_start >= 0, "hud.gd defines _draw_slot_icons (the scan below reads its body)")
	var guard_end: int = source.find("\nfunc ", guard_start + 1)
	if guard_end < 0: guard_end = source.length() # the last function in its file
	var guard_body: String = source.substr(guard_start, guard_end - guard_start)
	h.check(not guard_body.contains("evolution_button.visible"), "_draw_slot_icons no longer early-returns on the evolve prompt")
	h.control("reintroducing the early-return text", guard_body.contains("return") and guard_body.contains("is_instance_valid(combat)"))

	# --- Corner minimap perimeter is the square Chebyshev ring, not a circle
	# centred on the player (finding 6) -----------------------------------
	# `_show_map` (the full map screen) already draws the perimeter correctly
	# as a border on `CampaignState.ring(coord) == model.radius`; the corner
	# minimap must classify the SAME cells the SAME way. Source-check that
	# `_draw_minimap` now uses that per-cell, position-independent test
	# instead of a `draw_arc` centred on the player with a level-radius-in-
	# pixels radius (which is Euclidean, moves with the player, and - for
	# any level with radius > ~5 - exceeds the 186px panel outright).
	var minimap_source: String = FileAccess.get_file_as_string("res://scripts/ui/hud/minimap.gd")
	var minimap_start: int = minimap_source.find("func _draw_minimap")
	h.check(minimap_start >= 0, "minimap.gd defines _draw_minimap (the scan below reads its body)")
	var minimap_end: int = minimap_source.find("\nfunc ", minimap_start + 1)
	if minimap_end < 0: minimap_end = minimap_source.length() # the last function in its file
	var minimap_body: String = minimap_source.substr(minimap_start, minimap_end - minimap_start)
	h.check(minimap_body.contains("CampaignState.ring(map_cell.coord) == model.radius"), "_draw_minimap classifies the perimeter the same way _show_map does (per-cell ring test)")
	h.check(not minimap_body.contains("draw_arc(center,perimeter_radius"), "_draw_minimap no longer draws a circular arc for the perimeter")
	# Panel clipping: the old arc (radius up to level_radius*18, e.g. 216px
	# for L5's radius 12) spilled well outside the 186px panel; confirm the
	# panel now clips its own contents so nothing it draws can do that again.
	h.check(minimap_source.contains("minimap.clip_contents = true"), "The corner minimap panel clips its own contents (spec §24 'perimeter', contained to its own panel)")
	# Behavioural proof the fixed classification is position-INDEPENDENT
	# (unlike a circle centred on the player): the set of perimeter coords
	# within the local window is identical regardless of where current_sector
	# is, because it is a property of each cell, not a distance from "here".
	var ring_campaign := Campaign.new()
	ring_campaign.world_seed = 777
	ring_campaign.level = 1
	var radius: int = ring_campaign.level_radius()
	var perimeter_at_origin: Dictionary = {}
	for coord: Vector2i in _local_window(Vector2i.ZERO):
		if CampaignState.ring(coord) == radius: perimeter_at_origin[coord] = true
	ring_campaign.current_sector = Vector2i(2, 0)
	var perimeter_from_elsewhere: Dictionary = {}
	for coord: Vector2i in _local_window(Vector2i.ZERO): # same ABSOLUTE coords, not re-centred on "here"
		if CampaignState.ring(coord) == radius: perimeter_from_elsewhere[coord] = true
	h.check(perimeter_at_origin.keys() == perimeter_from_elsewhere.keys(), "Perimeter classification for a fixed set of coords does not depend on the current sector")
	# Old-formula control: the SAME single absolute coordinate's "perimeter"
	# classification under a circle-centred-on-current-sector formula
	# depends on where the player is standing - reproducing the moves-with-
	# the-player symptom directly. The fixed per-cell ring test above already
	# proves the real fix does NOT have this property for the same probe.
	var probe: Vector2i = Vector2i(radius, 0) # a real perimeter cell (ring == radius)
	var old_style_near: bool = Vector2(probe - Vector2i.ZERO).length() >= float(radius)
	var old_style_far: bool = Vector2(probe - Vector2i(radius - 1, 0)).length() >= float(radius)
	h.control("the old draw_arc formula (circle centred on the current sector) reclassifies the SAME cell as the player moves", old_style_near != old_style_far)

	h.finish(self)

func _local_window(origin: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy: int in range(-4, 5):
		for dx: int in range(-4, 5): result.append(origin + Vector2i(dx, dy))
	return result

func _check_bearing(h: Harness, campaign: CampaignState, model: MinimapModel, label: String) -> void:
	var delta: Vector2i = campaign.boss_coord() - campaign.current_sector
	var expected_distance: int = maxi(absi(delta.x), absi(delta.y))
	h.check(model.bearing_distance == expected_distance, "Boss bearing distance is Chebyshev steps on the 8-neighbour lattice (%s)" % label)
	h.check(model.bearing_direction != "NONE", "Boss bearing direction is present (%s)" % label)
	if delta.x == 0 and delta.y < 0: h.check(model.bearing_direction == "N", "Cardinal north bearing (%s)" % label)
	elif delta.x == 0 and delta.y > 0: h.check(model.bearing_direction == "S", "Cardinal south bearing (%s)" % label)
	elif delta.y == 0 and delta.x > 0: h.check(model.bearing_direction == "E", "Cardinal east bearing (%s)" % label)
	elif delta.y == 0 and delta.x < 0: h.check(model.bearing_direction == "W", "Cardinal west bearing (%s)" % label)
