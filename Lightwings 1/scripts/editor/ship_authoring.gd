class_name ShipAuthoring
extends RefCounted
## Rail-hull JSON (ship design spec §10) and the editor's thumbnail helper. The v2/v3 legacy
## importers, mirror regeneration and `rebuild_loadout` retired with the v0.3 circle-authoring
## editor (S5): a rail hull's positions are derived, never authored, so there is nothing left to
## regenerate on import and no per-part JSON to emit on export.

## Emits the spec §10 shape with a FIXED key order and floats snapped to 0.0001, so
## export -> import -> export is byte-identical. Delegates parsing to `ShipGrammar.from_dict`,
## which is strict about unknown keys - the single source of truth for what a hull file may say.
static func to_json(ship: ShipDefinition) -> String:
	var doc: Dictionary = {}
	doc["schema_version"] = 4
	if ship.geometry_revision > 1: doc["geometry_revision"] = ship.geometry_revision
	if not ship.removed_part_map.is_empty(): doc["removed_part_map"] = ship.removed_part_map.duplicate()
	doc["id"] = ship.id
	doc["name"] = ship.display_name
	doc["faction"] = ship.faction
	if ship.archetype != "": doc["archetype"] = ship.archetype
	doc["tier"] = ship.tier
	doc["role"] = ship.role
	doc["family"] = ship.family
	doc["chassis_color"] = ship.chassis_color
	if ship.accent_color != "": doc["accent_color"] = ship.accent_color
	doc["core_depth"] = ship.core_depth
	if not ship.core_radii.is_empty(): doc["core_radii"] = Array(ship.core_radii)
	if ship.core_dot_radius != 5.0: doc["core_dot_radius"] = ship.core_dot_radius
	if ship.core_dot_color != "": doc["core_dot_color"] = ship.core_dot_color
	if ship.chain_head_lobes: doc["chain_head_lobes"] = true
	if ship.chain_spacing != 30.0: doc["chain_spacing"] = ship.chain_spacing
	if ship.chain_head_spacing >= 0.0: doc["chain_head_spacing"] = ship.chain_head_spacing
	if ship.core_weapon != "": doc["core_weapon"] = ship.core_weapon
	if not ship.passives.is_empty(): doc["passives"] = ship.passives.duplicate()
	var rails_out: Array = []
	for rail: RailDefinition in ship.rails: rails_out.append(_rail_to_dict(rail))
	doc["rails"] = rails_out
	if not ship.chain_links.is_empty():
		var chain_out: Array = []
		for link: SlotDefinition in ship.chain_links: chain_out.append(_slot_to_value(link))
		doc["chain"] = chain_out
	if ship.archetype == "chain": doc["chain_mode"] = ship.chain_mode
	if ship.description != "": doc["description"] = ship.description
	return JSON.stringify(doc, "\t")

static func _rail_to_dict(rail: RailDefinition) -> Dictionary:
	var d: Dictionary = {}
	d["radius"] = rail.radius
	d["order"] = rail.order
	d["speed"] = snappedf(rail.speed, 0.0001)
	d["phase"] = snappedf(rail.phase, 0.0001)
	d["pump_phase"] = snappedf(rail.pump_phase, 0.0001)
	if rail.pump_amp >= 0.0: d["pump_amp"] = snappedf(rail.pump_amp, 0.0001)
	if not rail.reach_ring: d["reach_ring"] = false
	if not rail.offset.is_zero_approx(): d["offset"] = [snappedf(rail.offset.x, 0.0001), snappedf(rail.offset.y, 0.0001)]
	var slots_out: Array = []
	for slot: SlotDefinition in rail.slots: slots_out.append(_slot_to_value(slot))
	d["slots"] = slots_out
	return d

## The "node"/"stub" string shorthand for a slot with nothing but its type: a node of radius 4, or
## any stub. Anything else (a hub, a node of radius 7, or one with hp/feature/bob_amp) is the full
## object form.
static func _slot_to_value(slot: SlotDefinition) -> Variant:
	var plain: bool = slot.hp == 0.0 and slot.hp_radius < 0.0 and slot.hp_fixed == 0.0 and slot.bob_amp < 0.0 and slot.feature == "" and slot.radius_override == 0.0 and slot.phase_offset == 0.0 and slot.mark_radius == 0.0 and slot.pod_hp_radius < 0.0
	if slot.type == "stub" and plain: return "stub"
	if slot.type == "node" and slot.node_radius == 4 and plain: return "node"
	var d: Dictionary = {"type": slot.type}
	for key: String in ["radius_override", "phase_offset", "mark_radius"]:
		if slot.get(key) != 0.0: d[key] = slot.get(key)
	if slot.pod_hp_radius >= 0.0: d["pod_hp_radius"] = slot.pod_hp_radius
	if slot.type == "node": d["radius"] = slot.node_radius
	if slot.type == "hub":
		d["pods"] = slot.pods
		if not is_equal_approx(slot.pod_spacing, ShipGrammar.POD_SPACING): d["pod_spacing"] = slot.pod_spacing
		if slot.set_piece != "": d["set_piece"] = slot.set_piece
		if slot.mount != "": d["mount"] = slot.mount
	if slot.hp != 0.0: d["hp"] = snappedf(slot.hp, 0.0001)
	if slot.hp_radius >= 0.0:
		d["hp_fixed"] = slot.hp_fixed
		d["hp_radius"] = slot.hp_radius
	if slot.feature != "": d["feature"] = slot.feature
	if slot.bob_amp >= 0.0: d["bob_amp"] = snappedf(slot.bob_amp, 0.0001)
	return d

## Strict: an unknown key or a malformed shape is a JSON-level error, not a silently ignored one.
## `ShipGrammar.validate`'s own errors (an empty rail, a colour outside the pair, ...) are returned
## alongside a ship that DID parse, so the editor can show them without refusing to load the file.
static func from_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary: return {"errors": PackedStringArray(["JSON: not a ship object"])}
	var parse_errors: PackedStringArray = PackedStringArray()
	var ship: ShipDefinition = ShipGrammar.from_dict(parsed, parse_errors)
	if not parse_errors.is_empty(): return {"errors": parse_errors}
	return {"ship": ship, "errors": ShipGrammar.validate(ship)}

## Generation moves to `ShipRecipe` in a later phase (S9); the editor's description box stays wired
## to this so the affordance survives, but it does nothing yet.
## Free text -> the spec §13.1 template -> a ship, through the same ShipRecipe the roster is built
## with. Returns {ship, params, warnings (words it could not use), errors (style check)}.
static func from_description(text: String, seed: int = 1) -> Dictionary:
	var parsed: Dictionary = ShipRecipe.from_description(text, seed)
	var ship: ShipDefinition = ShipRecipe.generate(parsed.params)
	var warnings: PackedStringArray = PackedStringArray()
	for word: String in parsed.unknown: warnings.append("not understood: " + word)
	return {"ship": ship, "params": parsed.params, "warnings": warnings, "errors": ShipRecipe.style_check(ship)}

## A 64x64 SVG icon for the library/gallery, from the ship's already-compiled parts.
static func thumbnail(ship: ShipDefinition) -> Texture2D:
	if ship == null: return null
	var scale: float = 26.0 / maxf(26.0, ShipPreview.animated_radius(ship))
	var circles: Dictionary = {}
	for part: PartDefinition in ship.parts:
		if part.shape == "circle": circles[part.id] = part
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="#%s"/>' % VisualStyle.BG.to_html(false)
	for part: PartDefinition in ship.parts:
		var role: String = ("player" if ship.is_player else ship.element) if part.color_role == "chassis" else part.color_role
		var color: Color = ShipCatalog.get_color(role)
		if part.shape == "line":
			if not circles.has(part.from_id) or not circles.has(part.to_id): continue
			var from: PartDefinition = circles[part.from_id]
			var to: PartDefinition = circles[part.to_id]
			var from_radius: float = 0.0 if part.style == 6 else from.radius
			var points: PackedVector2Array = ShipGeometry.clipped_line({"position":from.position,"radius":from_radius},{"position":to.position,"radius":to.radius})
			if points.size() != 2: continue
			var a: Vector2 = Vector2(32,32) + points[0]*scale
			var b: Vector2 = Vector2(32,32) + points[1]*scale
			svg += '<line x1="%f" y1="%f" x2="%f" y2="%f" stroke="#%s" stroke-width="%f" opacity="%f"/>' % [a.x,a.y,b.x,b.y,color.to_html(false),VisualStyle.CONNECTOR_WIDTH,VisualStyle.CONNECTOR_OPACITY]
			continue
		var point: Vector2 = Vector2(32, 32) + part.position * scale
		var guide: bool = part.style == 5 or part.dashed or part.layer == 0
		var fill: String = "#" + (ShipCatalog.FILLS.get(role,VisualStyle.BG) as Color).to_html(false) if part.filled and not guide and part.style < 4 else "none"
		var width: float = VisualStyle.GUIDE_WIDTH if guide else 1.0 if part.style == 4 else VisualStyle.STROKE_WIDTH
		var guide_style: String = ' stroke-dasharray="%f %f" stroke-opacity="%f"' % [VisualStyle.GUIDE_DASH,VisualStyle.GUIDE_PERIOD-VisualStyle.GUIDE_DASH,VisualStyle.GUIDE_OPACITY] if guide else ""
		svg += '<circle cx="%f" cy="%f" r="%f" fill="%s" stroke="#%s" stroke-width="%f"%s/>' % [point.x,point.y,part.radius*scale,fill,color.to_html(false),width,guide_style]
		if not guide and part.style != 4:
			var circumference: float = TAU * part.radius * scale
			var phase: float = fposmod(part.light_phase / maxf(0.01, part.light_period), 1.0)
			var light: Color = ShipCatalog.LIGHTS.get(role, Color.WHITE)
			svg += '<circle cx="%f" cy="%f" r="%f" fill="none" stroke="#%s" stroke-width="%f" stroke-linecap="round" stroke-dasharray="%f %f" stroke-dashoffset="%f"/>' % [point.x,point.y,part.radius*scale,light.to_html(false),VisualStyle.LIGHT_WIDTH,circumference*VisualStyle.LIGHT_FRACTION,circumference*(1.0-VisualStyle.LIGHT_FRACTION),-phase*circumference]
	var core_color: Color = Color.WHITE if ship.is_player else ShipCatalog.get_color(ship.accent_color if ship.is_rail_hull() and ship.accent_color != "" else ship.chassis_color if ship.is_rail_hull() else ship.element)
	if ship.core_dot_color == "white": core_color = Color.WHITE
	svg += '<circle cx="32" cy="32" r="%f" fill="#%s"/>' % [clampf(ship.core_radius*scale,1.0,2.0),core_color.to_html(false)]
	svg += '</svg>'
	var image: Image = Image.new()
	if image.load_svg_from_string(svg) != OK: return null
	return ImageTexture.create_from_image(image)
