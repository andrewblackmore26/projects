extends SceneTree
## Modernization M14: the map and the minimap draw the open 8-way lattice.
##
## Instruments, each line with its own negative control:
## - RAILS: the map's drawn rail list gives every interior node 8 rails, every edge node 5 and every
##   corner 3, at all five level radii and in the real map screen (control: a 4-way lattice);
## - REVEAL: nodes appear in non-decreasing ring distance from the player, 20 ms per ring, from the
##   origin and from an off-centre node (control: the order reversed);
## - FOCUS: stepping focus along the 8 bearings from the current node reaches every in-bounds node
##   (control: a lattice with one orphaned node); a tap, a chord (diagonal) and a hold step as
##   designed (control: a hold shorter than the chord window read as a step); the detail panel
##   follows focus (control: the previous node's text);
## - VIEW: zoom stays within 0.75-2x (control: zoom forced to 3); a click picks the node under it
##   (control: a click between nodes);
## - CLIP: every primitive the minimap draws lies inside its circular clip, from every node of a
##   small and the largest level (control: primitives built for double the radius);
## - WORDS: _sector_description reads exactly as before M14 for sample nodes, through the static
##   and main.gd's forwarder (control: the same node once explored).
const Harness = preload("res://tests/support/harness.gd")

var h := Harness.new("MAP VIEW")

## A lattice that lost its diagonals (the 4-way map M14 replaces).
class FourWay extends CampaignState:
	func neighbour_offsets() -> Array[Vector2i]:
		return [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## A lattice with one node cut off from all of its neighbours.
class Orphan extends CampaignState:
	var orphan := Vector2i(2, 1)
	func neighbours_of(coord: Vector2i) -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		if coord == orphan: return result
		for dir: Vector2i in super(coord):
			if coord + dir != orphan: result.append(dir)
		return result

func _initialize() -> void: _run.call_deferred()

func _campaign(level: int, seed_value: int = 1414, source: CampaignState = null) -> CampaignState:
	var campaign: CampaignState = source if source != null else CampaignState.new()
	campaign.world_seed = seed_value
	campaign.level = level
	return campaign

func _view(campaign: CampaignState) -> MapScreen.MapView:
	var view := MapScreen.MapView.new()
	view.size = Vector2(900, 700)
	root.add_child(view)
	view.setup(MinimapModel.build(campaign), campaign)
	view.refit()
	return view

## Nodes whose drawn rail count differs from 8 inside / 5 on an edge / 3 at a corner.
func _rail_census(view: MapScreen.MapView, radius: int) -> Dictionary:
	var degree: Dictionary = {}
	for pair: Array in view.rails:
		degree[pair[0]] = int(degree.get(pair[0], 0)) + 1
		degree[pair[1]] = int(degree.get(pair[1], 0)) + 1
	var wrong: Array = []
	var counts: Dictionary = {3: 0, 5: 0, 8: 0}
	for y: int in range(-radius, radius + 1):
		for x: int in range(-radius, radius + 1):
			var coord := Vector2i(x, y)
			var edge_axes: int = int(absi(x) == radius) + int(absi(y) == radius)
			var expected: int = [8, 5, 3][edge_axes]
			var got: int = int(degree.get(coord, 0))
			if got != expected: wrong.append("%s:%d" % [coord, got])
			else: counts[expected] = int(counts[expected]) + 1
	return {"wrong": wrong, "counts": counts}

func _run() -> void:
	_rails()
	_reveal()
	_focus()
	_view_controls()
	_minimap_clip()
	await _screen()
	h.finish(self)

func _rails() -> void:
	for level: int in range(1, 6):
		var campaign := _campaign(level)
		var view := _view(campaign)
		var census: Dictionary = _rail_census(view, campaign.level_radius())
		h.check((census.wrong as Array).is_empty(), "level %d (R %d): every node draws 8/5/3 rails (census %s, wrong %s)" % [level, campaign.level_radius(), census.counts, (census.wrong as Array).slice(0, 4)])
		if level == 5: print("measure: R 12 draws %d rails for %d nodes (census %s)" % [view.rails.size(), view.reveal_at.size(), census.counts])
		view.free()
	var four := _view(_campaign(1, 1414, FourWay.new()))
	var four_census: Dictionary = _rail_census(four, 6)
	h.control("a 4-way lattice (%d nodes off the 8/5/3 census)" % (four_census.wrong as Array).size(), not (four_census.wrong as Array).is_empty())
	four.free()

## True when the nodes, taken in reveal order, never step back to a nearer ring and each appears
## exactly REVEAL_PER_RING per ring.
func _reveal_ok(order: Array, view: MapScreen.MapView) -> bool:
	var here: Vector2i = view.model.current_coord
	var last: int = -1
	for coord: Vector2i in order:
		var ring: int = CampaignState.ring(coord - here)
		if ring < last: return false
		if not is_equal_approx(float(view.reveal_at[coord]), 0.020 * ring): return false
		last = ring
	return true

func _reveal() -> void:
	for current: Vector2i in [Vector2i.ZERO, Vector2i(3, -2), Vector2i(-6, 6)]:
		var campaign := _campaign(1)
		campaign.current_sector = current
		var view := _view(campaign)
		var order: Array = view.reveal_at.keys()
		order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return float(view.reveal_at[a]) < float(view.reveal_at[b]))
		h.check(_reveal_ok(order, view), "from %s the reveal runs outward, 20 ms per ring (last node at %.0f ms)" % [current, view.reveal_end * 1000.0])
		h.check(_reveal_ok(view.model.reveal_order(), view), "from %s MinimapModel.reveal_order is nearest ring first" % current)
		if current == Vector2i(-6, 6):
			var reversed: Array = order.duplicate()
			reversed.reverse()
			h.control("the reveal order reversed", not _reveal_ok(reversed, view))
		view.free()

## Every in-bounds node focus can reach from the current one, stepping along the 8 bearings.
func _reachable(view: MapScreen.MapView) -> Dictionary:
	var seen: Dictionary = {view.model.current_coord: true}
	var frontier: Array[Vector2i] = [view.model.current_coord]
	while not frontier.is_empty():
		var coord: Vector2i = frontier.pop_back()
		for dir: Vector2i in CampaignState.NEIGHBOURS:
			var next: Vector2i = view.model.focus_step(coord, dir)
			if not seen.has(next):
				seen[next] = true
				frontier.append(next)
	return seen

func _focus() -> void:
	for level: int in [1, 5]:
		var view := _view(_campaign(level))
		var reached: Dictionary = _reachable(view)
		h.check(reached.size() == view.reveal_at.size(), "level %d: focus reaches all %d in-bounds nodes from the current one (reached %d)" % [level, view.reveal_at.size(), reached.size()])
		view.free()
	var orphaned := _view(_campaign(1, 1414, Orphan.new()))
	h.control("a lattice with an orphaned node (%d of %d reached)" % [_reachable(orphaned).size(), orphaned.reveal_at.size()], _reachable(orphaned).size() != orphaned.reveal_at.size())
	orphaned.free()
	# The input semantics: a tap steps on release, two keys inside the chord window make a
	# diagonal, and a hold repeats after the first-repeat delay.
	var view := _view(_campaign(1))
	var moves: Array[Vector2i] = []
	view.focus_moved.connect(func(coord: Vector2i, _audible: bool) -> void: moves.append(coord))
	view.navigate(Vector2i(1, 0), 0.016)
	view.navigate(Vector2i(1, 0), 0.016)
	view.navigate(Vector2i.ZERO, 0.016)
	h.check(moves == [Vector2i(1, 0)], "a 32 ms tap steps once, on release (%s)" % [moves])
	moves.clear()
	view.navigate(Vector2i(0, -1), 0.02)
	view.navigate(Vector2i(1, -1), 0.02)
	view.navigate(Vector2i(1, -1), 0.02)
	view.navigate(Vector2i.ZERO, 0.02)
	h.check(moves == [Vector2i(2, -1)], "up then right inside the chord window steps once, diagonally (%s)" % [moves])
	moves.clear()
	var held: float = 0.0
	# 10 ms frames: the chord step lands on the 5th or 6th (float), so leave a frame's slack.
	while held < 0.05 + 0.3 + 0.11 * 2 + 0.03:
		view.navigate(Vector2i(0, 1), 0.01)
		held += 0.01
	view.navigate(Vector2i.ZERO, 0.01)
	h.check(moves.size() == 4, "a %.0f ms hold steps 1 + 3 repeats (%d: %s)" % [held * 1000.0, moves.size(), moves])
	moves.clear()
	# The same two keys 60 ms apart, outside the chord window: two steps, not one diagonal.
	var from: Vector2i = view.focus
	view.navigate(Vector2i(0, -1), 0.06)
	view.navigate(Vector2i(1, -1), 0.02)
	view.navigate(Vector2i.ZERO, 0.02)
	h.control("up then right 60 ms apart (outside the chord window): %s" % [moves], moves != [from + Vector2i(1, -1)])
	Input.action_press("ui_up")
	Input.action_press("ui_right")
	var chord: Vector2i = MinimapModel.bearing_of(Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down", 0.3), 0.5)
	Input.action_release("ui_up")
	Input.action_release("ui_right")
	h.check(chord == Vector2i(1, -1), "up + right on the InputMap reads as the NE bearing (%s)" % chord)
	view.free()

func _view_controls() -> void:
	var view := _view(_campaign(5))
	view.zoom_at(100.0, view.size * 0.5)
	var high: float = view.zoom
	view.zoom_at(0.0001, view.size * 0.5)
	var low: float = view.zoom
	h.check(is_equal_approx(high, 2.0) and is_equal_approx(low, 0.75), "zoom is held to 0.75-2x (%.2f / %.2f)" % [low, high])
	view.zoom = 3.0
	h.control("zoom forced to 3x", not (view.zoom >= 0.75 and view.zoom <= 2.0))
	view.zoom = 1.0
	view.zoom_at(2.0, Vector2(100, 100))
	view.pan = view.clamp_pan(Vector2(99999, -99999))
	var extent: float = (view.model.radius + 0.5) * view.spacing()
	var field := Rect2(view.to_view(Vector2.ZERO) - Vector2(extent, extent), Vector2(extent, extent) * 2.0)
	h.check(field.intersection(Rect2(Vector2.ZERO, view.size)).get_area() > view.size.x * view.size.y * 0.3, "panned to the limit at 2x, the level still covers %.0f%% of the view" % (100.0 * field.intersection(Rect2(Vector2.ZERO, view.size)).get_area() / (view.size.x * view.size.y)))
	var picks_ok: bool = true
	for coord: Vector2i in [Vector2i.ZERO, Vector2i(3, -7), Vector2i(-12, 12)]:
		picks_ok = picks_ok and view.node_at(view.to_view(Vector2(coord))) == coord
	h.check(picks_ok, "a click on a node picks that node, at 2x after panning")
	h.control("a click halfway between two nodes read as a pick of the origin", view.node_at(view.to_view(Vector2(0.5, 0.5))) != Vector2i.ZERO)
	view.free()

## The primitives whose reach from the minimap's centre exceeds `radius`.
func _outside(primitives: Array, radius: float) -> Array:
	var result: Array = []
	for primitive: Dictionary in primitives:
		var reach: float = Minimap.reach_of(primitive)
		if reach > radius + 0.001: result.append("%s %.1f" % [primitive.kind, reach])
	return result

func _minimap_clip() -> void:
	var sampled: int = 0
	var escaped: Array = []
	var widest: float = 0.0
	var chevrons_missing: int = 0
	for level: int in [1, 5]:
		var campaign := _campaign(level, 2026)
		var radius: int = campaign.level_radius()
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if (x + y) % 2 == 0: campaign.discover(Vector2i(x, y))
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				campaign.current_sector = Vector2i(x, y)
				var primitives: Array = Minimap.primitives(campaign, Minimap.CLIP_RADIUS)
				sampled += primitives.size()
				escaped.append_array(_outside(primitives, Minimap.CLIP_RADIUS))
				for primitive: Dictionary in primitives: widest = maxf(widest, Minimap.reach_of(primitive))
				var chevron: bool = primitives.any(func(p: Dictionary) -> bool: return p.kind == "poly")
				if chevron != (campaign.current_sector != campaign.boss_coord()): chevrons_missing += 1
	print("measure: %d minimap primitives from every node of R 6 and R 12; widest reach %.2f px of %.0f" % [sampled, widest, Minimap.CLIP_RADIUS])
	h.check(escaped.is_empty(), "every minimap primitive stays inside the %.0f px circle (%d outside: %s)" % [Minimap.CLIP_RADIUS, escaped.size(), escaped.slice(0, 4)])
	h.check(chevrons_missing == 0, "the boss chevron is on the rim from every node but the boss's own (%d wrong)" % chevrons_missing)
	var control_campaign := _campaign(5, 2026)
	control_campaign.current_sector = Vector2i(3, 3)
	h.control("minimap primitives built for twice the clip radius", not _outside(Minimap.primitives(control_campaign, Minimap.CLIP_RADIUS * 2.0), Minimap.CLIP_RADIUS).is_empty())
	# The rails the minimap draws are the lattice's: 8 around a node deep inside the window.
	var rails_campaign := _campaign(5, 2026)
	var center_rails: int = 0
	for primitive: Dictionary in Minimap.primitives(rails_campaign, Minimap.CLIP_RADIUS):
		if primitive.kind == "line" and ((primitive.a as Vector2).distance_to(Minimap.CENTER) < 0.01 or (primitive.b as Vector2).distance_to(Minimap.CENTER) < 0.01): center_rails += 1
	h.check(center_rails == 8, "the minimap draws 8 rails from the centre node (%d)" % center_rails)
	# The per-frame replay: the batched list draws every line the primitives hold, in fewer calls.
	var raw: Array = Minimap.primitives(rails_campaign, Minimap.CLIP_RADIUS)
	var replay: Array = Minimap.batched(raw)
	var raw_lines: int = raw.filter(func(p: Dictionary) -> bool: return p.kind == "line").size()
	var batched_lines: int = 0
	for entry: Dictionary in replay:
		if entry.kind == "lines": batched_lines += (entry.colors as PackedColorArray).size()
	var started: int = Time.get_ticks_usec()
	for i: int in range(20): Minimap.primitives(rails_campaign, Minimap.CLIP_RADIUS)
	var rebuild_ms: float = float(Time.get_ticks_usec() - started) / 20000.0
	started = Time.get_ticks_usec()
	for i: int in range(20): MinimapModel.build(rails_campaign)
	print("measure: minimap draw calls per frame %d batched (from %d primitives, %d lines); a rebuild (only on a new node, discovery, life or tier) takes %.2f ms; a whole-level MinimapModel.build (which the pre-M14 minimap ran every frame, without rails) takes %.2f ms at R 12" % [replay.size(), raw.size(), raw_lines, rebuild_ms, float(Time.get_ticks_usec() - started) / 20000.0])
	h.check(batched_lines == raw_lines and replay.size() < raw.size(), "batching keeps all %d lines (%d) in %d draw calls instead of %d" % [raw_lines, batched_lines, replay.size(), raw.size()])

func _screen() -> void:
	root.size = Vector2i(1280, 800)
	SaveService.storage_root = "user://map-view-%d" % Time.get_ticks_usec()
	var app: Node = load("res://scripts/main.gd").new()
	app.testing = true
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	app._new_game(false)
	app.combat.set_physics_process(false)
	app.combat._physics_process(1.0 / 60.0)
	app._show_map()
	await process_frame
	var screen: MapScreen = app.screen_router.stack.back().screen
	h.check(screen != null and screen.view != null and screen.view.has_focus(), "the map screen opens with the lattice focused")
	var census: Dictionary = _rail_census(screen.view, app.campaign.level_radius())
	h.check((census.wrong as Array).is_empty(), "the live map screen draws 8/5/3 rails (%s)" % [census.counts])
	h.check(screen.view.get_global_rect().size.x > 700.0, "the lattice gets the room the window has (%s)" % screen.view.get_global_rect().size)
	var here: Vector2i = app.campaign.current_sector
	var before: String = screen.map_detail.text
	screen.view.navigate(Vector2i(1, 1), 0.1)
	var target: Vector2i = here + Vector2i(1, 1)
	h.check(screen.view.focus == target and screen.map_detail.text == MapScreen.sector_description(app.campaign, target), "focus steps SE and the detail panel follows ('%s')" % screen.map_detail.text.replace("\n", " | "))
	h.control("the detail panel left on the previous node", screen.map_detail.text != before)
	screen.view.navigate(Vector2i.ZERO, 0.1)
	# WORDS: the descriptions are the pre-M14 ones, through the static and the forwarder.
	var words := _campaign(1, 1414)
	words.current_sector = Vector2i.ZERO
	var samples: Dictionary = {
		Vector2i.ZERO: "NODE 0,0 · RING 0\n\nSAFE ORIGIN",
		Vector2i(3, 3): "NODE 3,3\n\nUnexplored space.",
		Vector2i(9, 0): "NODE 9,0\n\nSealed perimeter.",
	}
	var all_same: bool = true
	for coord: Vector2i in samples:
		all_same = all_same and MapScreen.sector_description(words, coord) == samples[coord]
	words.discover(Vector2i(-2, 1))
	var sector: Dictionary = words.sector_at(Vector2i(-2, 1))
	var explored: String = MapScreen.sector_description(words, Vector2i(-2, 1))
	var expected: String = "NODE -2,1 · RING 2\n\n%s · REGULAR\nThreat tier %d" % [str(sector.element).to_upper(), int(sector.tier)]
	h.check(all_same and explored == expected, "_sector_description is unchanged for the origin, an unexplored, an out-of-bounds and an explored node ('%s')" % explored.replace("\n", " | "))
	h.check(app._sector_description(Vector2i(3, 3)) == MapScreen.sector_description(app.campaign, Vector2i(3, 3)) and app._sector_known(Vector2i.ZERO), "main.gd's forwarders answer through MapScreen")
	words.discover(Vector2i(3, 3))
	h.control("the unexplored sample once explored", MapScreen.sector_description(words, Vector2i(3, 3)) != samples[Vector2i(3, 3)])
	app._close_overlay()
	await app._stop_audio()
	app.queue_free()
	await process_frame
