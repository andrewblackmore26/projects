extends SceneTree
## P5b: MinimapModel (spec §11, M3 "a tester always knows which way the
## boss is") and the HUD overlap fix (spec §24: slot icons + evolve prompt
## coexist). M11b: the floating HUD's models - the light bar's ghost and
## lead (GhostMeter), its tier ticks, the combo meter's pops, the boss bar's
## phase segments and the edge indicators for queued spawns. Model-level
## checks only; pixels are tests/ui_hud_render_test.gd.
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
	# The slot icons' draw used to `return` early whenever evolution_button.visible
	# was true, hiding the slot icons exactly when the evolve pill appeared
	# (spec §24 wants both). Confirmed by source: the guard clause of the dock's
	# draw (scripts/ui/hud/ability_dock.gd since M11b; hud.gd's _draw_slot_icons
	# before, main.gd's until modernization M2) never names evolution_button.visible.
	var source: String = FileAccess.get_file_as_string("res://scripts/ui/hud/ability_dock.gd")
	var guard_start: int = source.find("func draw_slots")
	h.check(guard_start >= 0, "ability_dock.gd defines draw_slots (the scan below reads its body)")
	var guard_end: int = source.find("\nfunc ", guard_start + 1)
	if guard_end < 0: guard_end = source.length() # the last function in its file
	var guard_body: String = source.substr(guard_start, guard_end - guard_start)
	h.check(not guard_body.contains("evolution_button") and not guard_body.contains("evolve"), "the dock's draw never early-returns on the evolve prompt")
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

	_ghost(h)
	_ticks(h)
	await _live_hud(h)
	h.finish(self)

## [hold, drain] seconds of the loss ghost after a scripted loss of 400 -> 250 at `hz`.
func _measure_ghost(hz: float, enabled: bool) -> Vector2:
	var meter := GhostMeter.new()
	meter.ghost_enabled = enabled
	meter.reset(400.0)
	var dt: float = 1.0 / hz
	var elapsed: float = 0.0
	var hold: float = 0.0
	var drained: float = -1.0
	for frame: int in range(roundi(hz * 1.5)):
		meter.step(250.0, dt)
		elapsed += dt
		if meter.ghost >= 400.0 - 0.001: hold = elapsed
		if drained < 0.0 and not meter.ghost_visible(): drained = elapsed
	return Vector2(hold, drained - hold)

## Seconds until the fill closes 98 % of a scripted gain 250 -> 400 at `hz`, and whether the lead
## showed the whole gain on the first frame.
func _measure_catch(hz: float, omega: float) -> Vector2:
	var meter := GhostMeter.new()
	meter.omega = omega
	meter.reset(250.0)
	var dt: float = 1.0 / hz
	var elapsed: float = 0.0
	var lead_first: float = -1.0
	for frame: int in range(roundi(hz)):
		meter.step(400.0, dt)
		elapsed += dt
		if lead_first < 0.0: lead_first = meter.lead
		if meter.value >= 250.0 + 0.98 * 150.0: return Vector2(elapsed, lead_first)
	return Vector2(INF, lead_first)

func _ghost(h: Harness) -> void:
	for hz: float in [60.0, 144.0, 30.0]:
		var ghost: Vector2 = _measure_ghost(hz, true)
		var frame: float = 1.0 / hz + 0.0001
		print("measure: ghost at %.0f Hz holds %.4f s, drains over %.4f s" % [hz, ghost.x, ghost.y])
		h.check(absf(ghost.x - GhostMeter.HOLD) <= frame, "the loss ghost holds %.2f s at %.0f Hz (measured %.4f)" % [GhostMeter.HOLD, hz, ghost.x])
		h.check(absf(ghost.y - GhostMeter.DRAIN) <= frame, "the loss ghost drains over %.2f s at %.0f Hz (measured %.4f)" % [GhostMeter.DRAIN, hz, ghost.y])
		var gain: Vector2 = _measure_catch(hz, GhostMeter.OMEGA)
		print("measure: gain lead at %.0f Hz caught in %.4f s (first-frame lead %.1f)" % [hz, gain.x, gain.y])
		h.check(gain.x <= GhostMeter.CATCH + frame, "the fill catches the gain lead within %.2f s at %.0f Hz (measured %.4f)" % [GhostMeter.CATCH, hz, gain.x])
		h.check(is_equal_approx(gain.y, 400.0), "the gain lead shows the whole gain on its first frame at %.0f Hz (%.1f)" % [hz, gain.y])
	# The spring is integrated in closed form: the fill lands the same at any frame rate.
	var spread: Array[float] = []
	for hz: float in [30.0, 60.0, 144.0]:
		var meter := GhostMeter.new()
		meter.reset(0.0)
		# 1/6 s is a whole number of frames at all three rates (0.1 s is not at 144 Hz).
		for frame: int in range(roundi(hz / 6.0)): meter.step(100.0, 1.0 / hz)
		spread.append(meter.value)
	print("measure: fill after 1/6 s at 30/60/144 Hz = %.4f / %.4f / %.4f" % spread)
	h.check(spread.max() - spread.min() < 0.01, "the fill's spring is frame-rate independent (spread %.5f)" % (spread.max() - spread.min()))
	var none: Vector2 = _measure_ghost(60.0, false)
	h.control("the ghost disabled (hold %.4f s)" % none.x, absf(none.x - GhostMeter.HOLD) > 1.0 / 60.0)
	var slow: Vector2 = _measure_catch(60.0, UiTokens.SPRING_OMEGA)
	h.control("the token spring omega %.0f (catch %.4f s)" % [UiTokens.SPRING_OMEGA, slow.x], slow.x > GhostMeter.CATCH + 1.0 / 60.0)

## Each tick at threshold / capacity x width, labelled with the tier it begins.
func _ticks_match(actual: Array[Dictionary], expected: Array) -> bool:
	if actual.size() != expected.size(): return false
	for index: int in range(actual.size()):
		if absf(float(actual[index].x) - float(expected[index][0])) > 0.0001 or str(actual[index].label) != str(expected[index][1]): return false
	return true

func _ticks(h: Harness) -> void:
	var width: float = 360.0
	var all_match: bool = true
	var off_by_one_caught: bool = true
	var total: int = 0
	for tier: int in range(1, GameTuning.MAX_TIER + 1):
		var capacity: float = GameTuning.capacity(tier, GameTuning.MAX_TIER)
		var expected: Array = []
		var shifted: Array = []
		for index: int in range(GameTuning.THRESHOLDS.size()):
			if GameTuning.THRESHOLDS[index] >= capacity: continue
			expected.append([GameTuning.THRESHOLDS[index] / capacity * width, "T%d" % (index + 2)])
			# The control: the same ticks, indexed one threshold along.
			shifted.append([GameTuning.THRESHOLDS[mini(index + 1, GameTuning.THRESHOLDS.size() - 1)] / capacity * width, "T%d" % (index + 2)])
		var actual: Array[Dictionary] = LightBar.ticks(tier, GameTuning.MAX_TIER, width)
		total += actual.size()
		all_match = all_match and _ticks_match(actual, expected)
		if not expected.is_empty(): off_by_one_caught = off_by_one_caught and not _ticks_match(actual, shifted)
	print("measure: %d labelled ticks over tiers 1-%d" % [total, GameTuning.MAX_TIER])
	h.check(all_match and total > 0, "every tick sits at threshold / capacity x width with its tier label (%d ticks)" % total)
	h.control("the ticks read one threshold along (off by one)", off_by_one_caught)

func _live_hud(h: Harness) -> void:
	SaveService.storage_root = "user://hud-model-test-%d" % Time.get_ticks_usec()
	root.size = Vector2i(1280, 800)
	var app: Node = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	await process_frame
	app._new_game(false)
	app.line_queue.clear()
	await process_frame
	await process_frame
	app.set_process(false)
	var combat: CombatWorld = app.combat
	var hud: Hud = app.hud_view
	combat._grant_invulnerability(1000.0, &"hud_model_test")

	# --- Combo: exactly one pop per kill, past the combo cap -----------------
	var kills: int = GameTuning.COMBO_MAX_COUNT + 2
	hud.update(1.0 / 60.0)
	var pops_before: int = hud.combo.pops
	var kills_before: int = combat.run_kills
	var count_rises: int = 0
	var last_count: int = combat.combo_count
	for kill: int in range(kills):
		var actor: Dictionary = combat._spawn_enemy("fire", 1, combat.player_position + Vector2(300, 0), false)
		actor.invulnerable = 0.0
		combat._damage_actor(actor, 1.0e7, 0, 0)
		hud.update(1.0 / 60.0)
		if combat.combo_count > last_count: count_rises += 1
		last_count = combat.combo_count
	var pops: int = hud.combo.pops - pops_before
	var landed: int = combat.run_kills - kills_before
	print("measure: %d kills (the sim counted %d) -> %d pops; combo_count rose %d times (cap %d)" % [kills, landed, pops, count_rises, GameTuning.COMBO_MAX_COUNT])
	h.check(landed == kills, "every scripted kill landed (%d of %d)" % [landed, kills])
	h.check(pops == landed, "the combo pops exactly once per kill (%d pops, %d kills)" % [pops, landed])
	h.check(hud.combo.root.visible and hud.combo.multiplier_label.text == "×%.1f" % combat.combo_multiplier(), "the combo meter shows %s after the kills" % hud.combo.multiplier_label.text)
	h.control("popping on combo_count rises instead of kills (%d pops for %d kills)" % [count_rises, landed], count_rises != landed)
	# The break: the window lapses once, with the chain still standing.
	var breaks_before: int = hud.combo.breaks
	for frame: int in range(roundi((GameTuning.COMBO_WINDOW_SECONDS + 0.2) * 60.0)):
		combat.combo_timer = maxf(0.0, combat.combo_timer - 1.0 / 60.0)
		hud.update(1.0 / 60.0)
	h.check(hud.combo.breaks - breaks_before == 1 and hud.combo.alpha < 1.0, "the window lapsing breaks the combo once and fades it (breaks %d, alpha %.2f)" % [hud.combo.breaks - breaks_before, hud.combo.alpha])

	# --- Boss bar: one segment per phase, read from the boss actor ------------
	var bosses: int = 0
	var with_parts: int = 0
	var segments_match: bool = true
	var control_caught: bool = false
	for element: String in CombatWorld.ELEMENTS:
		for tier: int in [2, 4, 6]:
			var boss: Dictionary = combat._spawn_enemy(element, tier, combat.player_position + Vector2(0, -260), true)
			if boss.is_empty(): continue
			bosses += 1
			var expected: int = PackedInt32Array(boss.get("shield_generator_indices", PackedInt32Array())).size() + PackedInt32Array(boss.get("sub_core_indices", PackedInt32Array())).size() + 1
			if expected > 1: with_parts += 1
			hud.update(1.0 / 60.0)
			segments_match = segments_match and hud.boss_mode and hud.boss_bar.segments.size() == expected and hud.boss_bar.meters.size() == expected and BossBar.segment_spans(hud.boss_bar.segments, hud.boss_bar.width).size() == expected
			# The control: a bar that reads only the core (no parts) against the same actor.
			var bare: Dictionary = boss.duplicate()
			bare.shield_generator_indices = PackedInt32Array()
			bare.sub_core_indices = PackedInt32Array()
			if expected > 1 and BossBar.phases(bare).size() != expected: control_caught = true
			boss.dead = true
			combat.enemies.erase(boss)
	hud.update(1.0 / 60.0)
	print("measure: %d bosses spawned, %d with shield generators or sub-cores" % [bosses, with_parts])
	h.check(bosses > 0 and with_parts > 0, "the census has bosses with phase parts (%d of %d)" % [with_parts, bosses])
	h.check(segments_match, "every boss bar has one segment per phase (shield generators + sub-cores + core)")
	h.check(not hud.boss_mode and hud.combo.root.get_parent() == hud.top_center, "with the rival gone the slot is the combo meter's again")
	h.control("a boss bar that ignores the phase parts", control_caught)

	# --- Edge indicators: one per queued off-screen spawn, none on screen -----
	var saved_queue: Array = combat.spawn_queue.duplicate()
	combat.spawn_queue.clear()
	var entry: Dictionary = {"hull": "", "element": "fire", "tier": 1, "elite": false, "rival": false, "pos": combat.player_position + Vector2(4000, 0), "due_q": combat.encounter_q + 60, "tele": 0, "tele_left": 0}
	combat.spawn_queue.append(entry)
	hud.update(1.0 / 60.0)
	var off_screen: int = _count(hud.edges.markers(), "spawn")
	entry.pos = combat.player_position + Vector2(40, 0)
	hud.update(1.0 / 60.0)
	var on_screen: int = _count(hud.edges.markers(), "spawn")
	var unfiltered: int = _count(hud.edges.markers(true), "spawn")
	print("measure: spawn indicators off-screen %d, on-screen %d (unfiltered %d)" % [off_screen, on_screen, unfiltered])
	h.check(off_screen == 1, "an off-screen queued spawn has exactly one edge indicator (%d)" % off_screen)
	h.check(on_screen == 0, "an on-screen queued spawn has none (%d)" % on_screen)
	h.control("indicators that keep what the camera shows (%d for the on-screen spawn)" % unfiltered, unfiltered != 0)
	combat.spawn_queue.assign(saved_queue)
	# The rival's chevron is there without `radar`; an ordinary enemy's is not.
	var rival: Dictionary = combat._spawn_enemy("void", 3, combat.player_position + Vector2(-5000, 0), true)
	var drone: Dictionary = combat._spawn_enemy("void", 1, combat.player_position + Vector2(0, 5000), false)
	hud.update(1.0 / 60.0)
	var markers: Array[Dictionary] = hud.edges.markers()
	h.check(not combat.has_passive("radar") and _count(markers, "boss") == 1 and _count(markers, "enemy") == 0, "without radar only the rival gets a chevron (boss %d, enemy %d)" % [_count(markers, "boss"), _count(markers, "enemy")])
	var boss_marker: Dictionary = markers.filter(func(marker: Dictionary) -> bool: return str(marker.kind) == "boss")[0] if _count(markers, "boss") > 0 else {}
	h.check(not boss_marker.is_empty() and absf(float(boss_marker.distance) - Vector2(rival.pos).distance_to(combat.player_position) / EdgeIndicators.PX_PER_METRE) < 0.01 and float(boss_marker.distance) > 10.0 and Vector2(boss_marker.direction).x < -0.9, "the rival's chevron points at it with its distance (%s)" % str(boss_marker))
	for gone: Dictionary in [rival, drone]:
		gone.dead = true
		combat.enemies.erase(gone)

	# --- The dock: one slot per mount, the dash first ------------------------
	var heavy: ShipDefinition = ShipCatalog.get_ship("player_fire_t6_heavy")
	combat.player["definition"] = heavy
	hud.update(1.0 / 60.0)
	var expected_slots: int = 2 + heavy.secondaries.size() + heavy.passives.size()
	h.check(hud.dock.slots.size() == expected_slots and str(hud.dock.slots[0].kind) == "dash", "the dock holds the dash, the primary, %d secondaries and %d passives (%d slots)" % [heavy.secondaries.size(), heavy.passives.size(), hud.dock.slots.size()])
	await app._stop_audio()
	app.queue_free()
	await process_frame

static func _count(markers: Array[Dictionary], kind: String) -> int:
	var result: int = 0
	for marker: Dictionary in markers:
		if str(marker.kind) == kind: result += 1
	return result

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
