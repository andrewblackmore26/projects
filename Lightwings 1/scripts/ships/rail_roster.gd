class_name RailRoster
extends RefCounted
## The ship design spec's roster, as ShipRecipe inputs: 101 player hulls, 25 mono-colour regulars,
## 15 two-colour elites and 5 bosses. Hull ids are the v0.3 ids (saves, campaign descriptors and
## `ShipGenerator.hull_id` keep working), plus `elite_heavy_<element>_t<hi>` for the new archetype.
##
## The colour pairing is a rule a player can learn (spec §6.6), read off the campaign's reveal ring
## lightning -> fire -> corruption -> void -> plasma -> lightning:
##   regulars (drone, sentry, chain)  chassis only - "mono-colour enemies are the weak ones"
##   radial elite                     accent = the NEXT element on the ring
##   irregular elite                  accent = the PREVIOUS element
##   heavy elite                      accent = TWO AHEAD
##   boss                             accent = TWO BACK
## which puts all ten blue-free hybrids on some hull. The lightning radial elite is the spec's own
## yellow + red example.

const STAGING_ROOT: String = "res://content/ships_next"
const RING: Array[String] = ["lightning", "fire", "corruption", "void", "plasma"]

static func accent_for(element: String, archetype: String) -> String:
	var steps: int = {"radial_elite": 1, "irregular_elite": -1, "heavy_elite": 2, "boss": -2}.get(archetype, 0)
	if steps == 0: return ""
	return Elements.color_key(RING[posmod(RING.find(element) + steps, RING.size())])

## One recipe input per hull, in a fixed order.
static func manifest() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	entries.append(_player("neutral", 1, "standard_a"))
	for element: String in Elements.INDEX_ORDER:
		for tier: int in range(2, GameTuning.MAX_TIER + 1):
			for family: String in ShipCatalog.FAMILIES: entries.append(_player(element, tier, family))
	for element: String in Elements.INDEX_ORDER:
		var band: Dictionary = ShipGenerator.ELEMENT_TIER_BAND[element]
		var lo: int = int(band.lo)
		var hi: int = int(band.hi)
		entries.append(_enemy("enemy_drone_%s_t%d" % [element, lo], "enemy", "drone", element, lo))
		entries.append(_enemy("enemy_drone_%s_t%d" % [element, hi], "enemy", "drone", element, hi))
		entries.append(_enemy("enemy_sentry_%s_t%d" % [element, lo], "enemy", "sentry", element, lo))
		entries.append(_enemy("enemy_sentry_%s_t%d" % [element, hi], "enemy", "sentry", element, hi))
		entries.append(_enemy("enemy_chain_%s_t%d" % [element, hi], "enemy", "chain", element, hi))
		entries.append(_enemy("elite_radial_%s_t%d" % [element, hi], "elite", "radial_elite", element, hi))
		entries.append(_enemy("elite_irregular_%s_t%d" % [element, hi], "elite", "irregular_elite", element, hi))
		entries.append(_enemy("elite_heavy_%s_t%d" % [element, hi], "elite", "heavy_elite", element, hi))
		entries.append(_enemy("boss_%s" % element, "boss", "boss", element, hi))
	return entries

static func _player(element: String, tier: int, family: String) -> Dictionary:
	var id: String = "player_seed" if tier == 1 else "player_%s_t%d_%s" % [element, tier, family]
	var label: String = "Lumen" if tier == 1 else "%s T%d %s" % [element.capitalize(), tier, family.replace("_", " ").capitalize()]
	return {"id": id, "name": label, "faction": "player", "element": element, "tier": tier, "family": family, "role": ShipCatalog.role_for_family(family), "seed": _seed(id)}

static func _enemy(id: String, faction: String, archetype: String, element: String, tier: int) -> Dictionary:
	var label: String = "%s %s T%d" % [element.capitalize(), archetype.replace("_", " ").capitalize(), tier]
	return {"id": id, "name": label, "faction": faction, "archetype": archetype, "element": element, "tier": tier, "role": "standard" if faction == "enemy" else "heavy",
		"family": "standard_a" if faction == "enemy" else "heavy", "chassis_color": Elements.color_key(element), "accent_color": accent_for(element, archetype), "seed": _seed(id)}

## A hull's seed is a function of its id, so rebuilding the roster never reshuffles it.
static func _seed(id: String) -> int:
	return int(id.hash() % 1000000) + 1

static func build(entry: Dictionary) -> ShipDefinition:
	return ShipRecipe.generate(entry)

## Writes every hull into `root` as its grammar alone, and deletes `.tres` files the manifest does
## not name. Returns {written, removed, failures}.
static func write_all(root: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var wanted: Dictionary = {}
	var failures: PackedStringArray = PackedStringArray()
	var written: int = 0
	for entry: Dictionary in manifest():
		var ship: ShipDefinition = build(entry)
		wanted[ship.id + ".tres"] = true
		var problems: PackedStringArray = ShipRecipe.style_check(ship)
		if not problems.is_empty():
			failures.append("%s: %s" % [ship.id, "; ".join(problems)])
			continue
		if ShipCatalog.save_ship(ship, root.path_join(ship.id + ".tres")) == OK: written += 1
		else: failures.append("%s: could not be saved" % ship.id)
	var removed: int = 0
	var dir: DirAccess = DirAccess.open(root)
	if dir != null:
		for file: String in dir.get_files():
			if file.ends_with(".tres") and not wanted.has(file):
				dir.remove(file)
				removed += 1
	return {"written": written, "removed": removed, "failures": failures}
