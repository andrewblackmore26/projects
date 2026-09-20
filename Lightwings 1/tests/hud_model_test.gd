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
	# scripts/main.gd no longer names evolution_button.visible at all.
	var source: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	var guard_start: int = source.find("func _draw_slot_icons")
	var guard_end: int = source.find("\nfunc ", guard_start + 1)
	var guard_body: String = source.substr(guard_start, guard_end - guard_start)
	h.check(not guard_body.contains("evolution_button.visible"), "_draw_slot_icons no longer early-returns on the evolve prompt")
	h.control("reintroducing the early-return text", guard_body.contains("return") and guard_body.contains("is_instance_valid(combat)"))

	h.finish(self)

func _check_bearing(h: Harness, campaign: CampaignState, model: MinimapModel, label: String) -> void:
	var delta: Vector2i = campaign.boss_coord() - campaign.current_sector
	var expected_distance: int = absi(delta.x) + absi(delta.y)
	h.check(model.bearing_distance == expected_distance, "Boss bearing distance is Manhattan steps (%s)" % label)
	h.check(model.bearing_direction != "NONE", "Boss bearing direction is present (%s)" % label)
	if delta.x == 0 and delta.y < 0: h.check(model.bearing_direction == "N", "Cardinal north bearing (%s)" % label)
	elif delta.x == 0 and delta.y > 0: h.check(model.bearing_direction == "S", "Cardinal south bearing (%s)" % label)
	elif delta.y == 0 and delta.x > 0: h.check(model.bearing_direction == "E", "Cardinal east bearing (%s)" % label)
	elif delta.y == 0 and delta.x < 0: h.check(model.bearing_direction == "W", "Cardinal west bearing (%s)" % label)
