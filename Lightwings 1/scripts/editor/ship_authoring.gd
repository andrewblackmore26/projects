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
	var plain: bool = slot.hp == 0.0 and slot.bob_amp < 0.0 and slot.feature == ""
	if slot.type == "stub" and plain: return "stub"
	if slot.type == "node" and slot.node_radius == 4 and plain: return "node"
	var d: Dictionary = {"type": slot.type}
	if slot.type == "node": d["radius"] = slot.node_radius
	if slot.type == "hub":
		d["pods"] = slot.pods
		if slot.set_piece != "": d["set_piece"] = slot.set_piece
		if slot.mount != "": d["mount"] = slot.mount
	if slot.hp != 0.0: d["hp"] = snappedf(slot.hp, 0.0001)
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
static func from_description(_text: String) -> Dictionary:
	return {"errors": PackedStringArray(["generation moves to ShipRecipe in S9"])}

## A 64x64 SVG icon for the library/gallery, from the ship's already-compiled parts.
static func thumbnail(ship: ShipDefinition) -> Texture2D:
	var scale: float = 48.0 / maxf(48.0, ship.footprint)
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="#050507"/>'
	for part: PartDefinition in ship.parts:
		if part.shape == "line": continue
		var color: Color = ShipCatalog.get_color(("player" if ship.is_player else ship.element) if part.color_role == "chassis" else part.color_role)
		var point: Vector2 = Vector2(32, 32) + part.position * scale
		svg += '<circle cx="%f" cy="%f" r="%f" fill="%s" stroke="#%s" stroke-width="1"/>' % [point.x, point.y, part.radius * scale, "none" if not part.filled else "#07111a", color.to_html(false)]
	svg += '</svg>'
	var image: Image = Image.new()
	image.load_svg_from_string(svg)
	return ImageTexture.create_from_image(image)
