class_name ShipCompiler
extends RefCounted
## Grammar -> parts (ship design spec §10: "positions are derived, never authored"). A rail hull
## stores only colours, a core depth, rails and slots; this derives the circle-and-line graph that
## ShipMesh, the outline shader, the ShipMotion rig, the broadphase and detachment already consume.
## Pure and deterministic: no RNG, no clock, no iteration over an unordered container, so the same
## grammar yields the same ids and bytes in every process (the golden trace depends on that).
##
## `parts` is emitted in PAINT order, because ShipMesh bakes a rail hull in part order:
##   rail rings -> spokes and pod links -> core stack -> passive rings -> nodes and pods -> hubs
##   -> set-piece lines -> set-piece circles          (the core dot is drawn last by the mesh)
## so counter-rotating spokes sweep UNDER the clusters they cross, and a set piece's lines draw
## over its hub's fill, as the reference shows. The rig orders circles itself (DFS from the core).
##
## Ids are positional: core, core_2, core_3, passive_<k>, r<rail>, r<rail>s<slot>, ...p<pod>,
## ...w<n>, core_w<n>, c<link>; lines end in _spoke, _link or l<n>.

const SPOKES_TO_CORE_THROUGH_RAIL: int = 2 # user decision 4: rails 1-2 spoke to the core rim

class Build extends RefCounted:
	var rings: Array[PartDefinition] = []
	var lines: Array[PartDefinition] = []
	var core: Array[PartDefinition] = []
	var passives: Array[PartDefinition] = []
	var small: Array[PartDefinition] = []
	var hubs: Array[PartDefinition] = []
	var piece_lines: Array[PartDefinition] = []
	var piece_circles: Array[PartDefinition] = []
	var cluster: int = 0

static func compile(ship: ShipDefinition) -> void:
	if not ship.is_rail_hull(): return
	var build: Build = Build.new()
	var chassis: String = ship.chassis_color
	var accent: String = ship.accent_color if ship.accent_color != "" else chassis
	_core(ship, build, chassis, accent)
	for rail_index: int in range(ship.rails.size()):
		_rail(ship, build, rail_index, chassis)
	_chain(ship, build, chassis)
	var parts: Array[PartDefinition] = []
	for group: Array in [build.rings, build.lines, build.core, build.passives, build.small, build.hubs, build.piece_lines, build.piece_circles]:
		for part: PartDefinition in group: parts.append(part)
	ship.parts = parts
	ship.groups = []
	ship.core_radius = float(ShipGrammar.LADDER.core_dot)
	ship.symmetry = "none"
	ship.is_player = ship.faction == "player"
	_loadout(ship)
	# Footprint: the diameter of the circle about the core that holds every solid circle at rest.
	var reach: float = 0.0
	for part: PartDefinition in parts:
		if part.shape == "circle" and part.solid: reach = maxf(reach, part.position.length() + part.radius)
	ship.footprint = reach * 2.0
	ship.compile_key = "%s#%d" % [ship.id, hash(grammar_signature(ship))]

## A core weapon always fires from the core. Its set piece is DRAWN only on a depth-2 core; deeper
## cores carry an accent inner ring that marks it instead (read from the reference image).
static func draws_core_piece(ship: ShipDefinition) -> bool:
	return ship.core_weapon != "" and SetPieceCatalog.has(ship.core_weapon) and ship.core_depth <= 2

## Everything that decides the compiled output, in a fixed order.
static func grammar_signature(ship: ShipDefinition) -> Array:
	var signature: Array = [ship.id, ship.faction, ship.tier, ship.chassis_color, ship.accent_color, ship.core_depth, ship.core_weapon, ship.archetype, ship.passives, ship.chain_mode]
	for rail: RailDefinition in ship.rails:
		signature.append([rail.radius, rail.order, rail.speed, rail.phase, rail.pump_phase, rail.pump_amp, rail.reach_ring, rail.offset])
		for slot: SlotDefinition in rail.slots: signature.append(_slot_signature(slot))
	for link: SlotDefinition in ship.chain_links: signature.append(_slot_signature(link))
	return signature

static func _slot_signature(slot: SlotDefinition) -> Array:
	return [slot.type, slot.node_radius, slot.pods, slot.set_piece, slot.mount, slot.hp, slot.feature, slot.bob_amp]

## Circle, line and set-piece counts without compiling: what the validator's 128 cap and the
## editor's readout use. `ship_compiler_test` holds it equal to the compiled counts.
static func budget(ship: ShipDefinition) -> Dictionary:
	var circles: int = maxi(1, ship.core_depth - 1) + ship.passives.size()
	var lines: int = 0
	var solid: int = 1
	var pieces: int = 0
	if ship.core_weapon != "":
		pieces += 1
		if draws_core_piece(ship):
			circles += (SetPieceCatalog.get_piece(ship.core_weapon).get("circles", []) as Array).size()
			lines += (SetPieceCatalog.get_piece(ship.core_weapon).get("lines", []) as Array).size()
	var slots: Array[SlotDefinition] = []
	for rail: RailDefinition in ship.rails:
		if rail.reach_ring: circles += 1
		for slot: SlotDefinition in rail.slots: slots.append(slot)
	for link: SlotDefinition in ship.chain_links: slots.append(link)
	for slot: SlotDefinition in slots:
		if not slot.is_occupied(): continue
		circles += 1
		lines += 1
		solid += 1
		if slot.type != "hub": continue
		circles += slot.pods
		lines += slot.pods
		solid += slot.pods
		if slot.feature == "shield_generator": circles += 2
		if slot.set_piece != "":
			pieces += 1
			circles += (SetPieceCatalog.get_piece(slot.set_piece).get("circles", []) as Array).size()
			lines += (SetPieceCatalog.get_piece(slot.set_piece).get("lines", []) as Array).size()
	return {"circles": circles, "lines": lines, "solid": solid, "set_pieces": pieces}

# ---------------------------------------------------------------- parts

static func _circle(id: String, parent: String, at: Vector2, radius: float, colour: String, filled: bool, solid: bool) -> PartDefinition:
	var part: PartDefinition = PartDefinition.new()
	part.id = id
	part.shape = "circle"
	part.parent_id = parent
	part.position = at
	part.radius = radius
	part.color_role = colour
	part.filled = filled
	part.solid = solid
	part.tp_cost = 0.0
	part.stat_id = "structure"
	return part

static func _line(id: String, from: String, to: String, colour: String, from_centre: bool = false) -> PartDefinition:
	var part: PartDefinition = PartDefinition.new()
	part.id = id
	part.shape = "line"
	part.from_id = from
	part.to_id = to
	part.color_role = colour
	part.radius = 1.0
	part.tp_cost = 0.0
	# style 6 on a LINE: it starts at its `from` circle's centre instead of that circle's rim.
	part.style = 6 if from_centre else -1
	return part

## §9.4: lap period by ladder radius; nothing starts in sync.
static func _shine(part: PartDefinition, part_index: int, cluster_index: int) -> void:
	var motion: Dictionary = ShipGrammar.MOTION
	part.light_period = ShipGrammar.shine_period(int(round(part.radius)))
	var laps: float = float(part_index) * float(motion.shine_phase_per_part) + float(cluster_index) * float(motion.shine_phase_per_cluster)
	part.light_phase = -fposmod(laps, 1.0) * part.light_period

## Forward is up (-y); angles run clockwise, which is what Vector2.rotated does on a y-down screen.
static func _direction(angle: float) -> Vector2:
	return Vector2(sin(angle), -cos(angle))

static func _core(ship: ShipDefinition, build: Build, chassis: String, accent: String) -> void:
	var rings: int = clampi(ship.core_depth - 1, 1, ShipGrammar.CORE_RADII.size())
	for i: int in range(rings):
		var innermost: bool = i == rings - 1 and i > 0
		# The reference's inner core ring is the accent colour and filled; otherwise alternate.
		var colour: String = accent if innermost and ship.faction != "player" else chassis
		var filled: bool = i % 2 == 0 or (innermost and ship.faction != "player")
		var part: PartDefinition = _circle("core" if i == 0 else "core_%d" % (i + 1), "" if i == 0 else "core", Vector2.ZERO, float(ShipGrammar.CORE_RADII[i]), colour, filled, i == 0)
		_shine(part, i, 0)
		build.core.append(part)
	# Passives are colourless: thin chassis rings on the two ladder radii the stack never uses.
	var passive_radii: Array[int] = [int(ShipGrammar.LADDER.hub), int(ShipGrammar.LADDER.pod)]
	for k: int in range(mini(ship.passives.size(), passive_radii.size())):
		var ring: PartDefinition = _circle("passive_%d" % k, "core", Vector2.ZERO, float(passive_radii[k]), chassis, false, false)
		ring.style = 4
		ring.ability_id = ship.passives[k]
		ring.mount_id = "passive_%d" % k
		build.passives.append(ring)
	if ship.core_weapon != "" and SetPieceCatalog.has(ship.core_weapon):
		build.core[0].ability_id = SetPieceCatalog.ability_of(ship.core_weapon)
		build.core[0].mount_id = "primary"
		# The reference's core is clean: its accent inner ring IS the core weapon's mark. Only a
		# depth-2 core (drone, sentry) has no such ring, so only there is the piece itself drawn,
		# at the core's forward rim (a piece is drawn for a r15 hub; the core is r34).
		if draws_core_piece(ship):
			var lift: float = float(ShipGrammar.CORE_RADII[0]) - float(ShipGrammar.LADDER.hub)
			_piece(build, ship.core_weapon, "core", "core_", Vector2(0, -lift), 0.0, false)
	build.cluster = 1

static func _rail(ship: ShipDefinition, build: Build, rail_index: int, chassis: String) -> void:
	var rail: RailDefinition = ship.rails[rail_index]
	var motion: Dictionary = ShipGrammar.MOTION
	var ring_id: String = "r%d" % (rail_index + 1)
	# The ring is a real circle: the clusters' parent (so they turn about the rail's own centre,
	# offset and all) and, for rails 3-4, the inner end of the next rail's spokes.
	var ring: PartDefinition = _circle(ring_id, "core", rail.offset, float(rail.radius), chassis, false, false)
	ring.style = 5
	build.rings.append(ring)
	var pump_amp: float = rail.pump_amp if rail.pump_amp >= 0.0 else float(motion.pump_amp)
	var spoke_from: String = "core" if rail_index < SPOKES_TO_CORE_THROUGH_RAIL else "r%d" % rail_index
	for j: int in range(rail.slots.size()):
		var slot: SlotDefinition = rail.slots[j]
		if not slot.is_occupied(): continue
		var angle: float = rail.phase + float(j) * TAU / float(maxi(1, rail.order))
		var id: String = "%ss%d" % [ring_id, j]
		var root: PartDefinition = _cluster(build, slot, id, ring_id, rail.offset + _direction(angle) * float(rail.radius), angle, chassis, j)
		root.spin_speed = rail.speed
		root.pump_amp = pump_amp
		root.pump_freq = float(motion.pump_freq)
		root.pump_phase = rail.pump_phase
		build.lines.append(_line(id + "_spoke", spoke_from, id, chassis))

## A hub with its pods and set piece, or a node. Returns the cluster's root circle.
static func _cluster(build: Build, slot: SlotDefinition, id: String, parent: String, at: Vector2, outward: float, chassis: String, slot_index: int) -> PartDefinition:
	var motion: Dictionary = ShipGrammar.MOTION
	var cluster: int = build.cluster
	build.cluster += 1
	if slot.type == "node":
		var node: PartDefinition = _circle(id, parent, at, float(slot.node_radius), chassis, true, true)
		node.bob_amp = slot.bob_amp if slot.bob_amp >= 0.0 else float(motion.node_bob_amp)
		node.bob_freq = float(motion.node_bob_freq)
		node.bob_phase = float(slot_index) * float(motion.node_bob_phase_step)
		node.hp = slot.hp
		_shine(node, 0, cluster)
		build.small.append(node)
		return node
	var hub: PartDefinition = _circle(id, parent, at, float(ShipGrammar.LADDER.hub), chassis, true, true)
	hub.hp = slot.hp
	if slot.feature != "": hub.stat_id = slot.feature
	_shine(hub, 0, cluster)
	build.hubs.append(hub)
	var fan: PackedFloat32Array = ShipGrammar.pod_angles(slot.pods)
	for m: int in range(fan.size()):
		var pod: PartDefinition = _circle("%sp%d" % [id, m], id, at + _direction(outward + fan[m]) * ShipGrammar.POD_DISTANCE, float(ShipGrammar.LADDER.pod), chassis, true, true)
		pod.bob_amp = slot.bob_amp if slot.bob_amp >= 0.0 else float(motion.pod_bob_amp)
		pod.bob_freq = float(motion.pod_bob_freq)
		pod.bob_phase = float(m) * float(motion.pod_bob_phase_step)
		_shine(pod, m + 1, cluster)
		build.small.append(pod)
		build.lines.append(_line("%sp%d_link" % [id, m], id, pod.id, chassis))
	if slot.feature == "shield_generator":
		# The boss's second core stack: [22, 13] inside the hub's slot, chassis colour, not solid.
		for k: int in range(2):
			build.passives.append(_circle("%sc%d" % [id, k], id, at, float(ShipGrammar.CORE_RADII[k + 1]), chassis, k == 1, false))
	if slot.set_piece != "" and SetPieceCatalog.has(slot.set_piece):
		hub.ability_id = SetPieceCatalog.ability_of(slot.set_piece)
		hub.mount_id = slot.mount if slot.mount != "" else id
		_piece(build, slot.set_piece, id, id, at, outward, true)
	return hub

## Expands a set piece onto `host`. Its first circle is the aim joint and the rest hang off it, so
## the whole piece turns to the aim while the hub underneath rides its rail (spec §9.7).
static func _piece(build: Build, piece_id: String, host: String, prefix: String, at: Vector2, outward: float, aims: bool) -> void:
	var piece: Dictionary = SetPieceCatalog.get_piece(piece_id)
	var colours: Array = piece.get("colours", [])
	var ids: Array[String] = []
	var circles: Array = piece.get("circles", [])
	for n: int in range(circles.size()):
		var spec: Array = circles[n]
		var id: String = "%sw%d" % [prefix, n]
		var circle: PartDefinition = _circle(id, host if n == 0 else ids[0], at + Vector2(float(spec[0]), float(spec[1])).rotated(outward), float(spec[2]), str(colours[int(spec[4])]), bool(spec[3]), false)
		circle.aim_joint = aims and n == 0
		circle.rest_heading = outward
		_shine(circle, n + 5, build.cluster - 1)
		ids.append(id)
		build.piece_circles.append(circle)
	var lines: Array = piece.get("lines", [])
	for n: int in range(lines.size()):
		var spec: Array = lines[n]
		var from_hub: bool = int(spec[0]) == SetPieceCatalog.HUB
		build.piece_lines.append(_line("%sl%d" % [prefix, n], host if from_hub else ids[int(spec[0])], ids[int(spec[1])], str(colours[int(spec[2])]), from_hub))

## Chain archetype: no rails. Links trail behind the core, 30 px apart, each the child of the one
## before, so severing a link detaches everything behind it.
static func _chain(ship: ShipDefinition, build: Build, chassis: String) -> void:
	var parent: String = "core"
	var at: Vector2 = Vector2.ZERO
	var rest: float = float(ShipGrammar.MOTION.chain_rest_length)
	for i: int in range(ship.chain_links.size()):
		var link: SlotDefinition = ship.chain_links[i]
		if not link.is_occupied(): continue
		at += Vector2(0, rest + (float(ShipGrammar.CORE_RADII[0]) if i == 0 else 0.0))
		var id: String = "c%d" % i
		var root: PartDefinition = _cluster(build, link, id, parent, at, PI, chassis, i)
		# §9.6's travelling wave, as a pure function of the tick: each link swings about the one
		# before it, 0.85 rad behind it. The swings ACCUMULATE down the chain, so the sideways
		# amplitude grows from nothing at the head to the mode's full value at the tip.
		# Link k's swing carries every link after it, 0.85 rad out of step with its neighbours, so the
		# tip's sideways amplitude is rest * swing * |sum over k of (N - k) e^(-i 0.85 k)|. Dividing by
		# that makes the TIP swing the mode's amplitude (6 px sway, 14 px whip). The first version
		# divided by rest * N and measured 10.7 and 24.9 px.
		var links: int = maxi(1, ship.chain_links.size())
		var sum: Vector2 = Vector2.ZERO
		for k: int in range(links): sum += Vector2.from_angle(-float(k) * float(ShipGrammar.MOTION.chain_phase_step)) * float(links - k)
		root.bob_amp = float((ShipGrammar.MOTION.chain_amplitude as Dictionary).get(ship.chain_mode, 0.0)) / (rest * maxf(0.001, sum.length()))
		root.bob_freq = float(ShipGrammar.MOTION.chain_wave_freq)
		root.bob_phase = -float(i) * float(ShipGrammar.MOTION.chain_phase_step)
		build.lines.append(_line(id + "_spoke", parent, id, chassis))
		parent = id

## primary / secondaries / abilities, read back from what is mounted.
static func _loadout(ship: ShipDefinition) -> void:
	var secondaries: Dictionary = {}
	var guns: Array[String] = []
	ship.primary = ""
	for part: PartDefinition in ship.parts:
		if part.shape != "circle" or part.ability_id == "" or part.mount_id.begins_with("passive_"): continue
		if part.mount_id == "primary": ship.primary = part.ability_id
		elif part.mount_id.begins_with("secondary_"): secondaries[part.mount_id] = part.ability_id
		elif not guns.has(part.ability_id): guns.append(part.ability_id)
	var listed: Array[String] = []
	for n: int in range(GameTuning.MAX_SECONDARY_SLOTS):
		if secondaries.has("secondary_%d" % n): listed.append(str(secondaries["secondary_%d" % n]))
	ship.secondaries = listed
	var abilities: Array[String] = []
	if ship.primary != "": abilities.append(ship.primary)
	for id: String in listed + guns + ship.passives:
		if not abilities.has(id): abilities.append(id)
	ship.abilities = abilities
