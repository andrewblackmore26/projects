class_name ShipDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = "Seed"
@export var element: String = "corruption"
@export var tier: int = 1
@export var is_player: bool = false
## Spec v0.3 §17.4 / §22: player hulls are always bilaterally symmetric about the forward axis;
## enemies may be "radial", "bilateral" or "none". Stored rather than derived from `is_player`,
## because an enemy's symmetry is an authoring decision the archetypes differ on: a radial elite is
## built on N-fold rotation, an irregular elite is deliberately asymmetric.
@export var symmetry: String = "bilateral"
@export var breathes: bool = false
@export var core_radius: float = 3.0
@export var hull_radius: float = 0.0
@export var parts: Array[PartDefinition] = []
@export var groups: Array[GroupDefinition] = []
@export var abilities: Array[String] = []
@export var description: String = ""
@export var schema_version: int = 3
@export var faction: String = "player"
@export var role: String = "standard"
@export var family: String = "standard_a"
@export var footprint: float = 48.0
@export var magnet_radius: float = 100.0
@export var speed: float = 220.0
@export var turn_rate: float = 10.0
## Momentum model (spec v0.3 §13): `speed` is the TOP speed a full-input
## `accel` vs `drag` balance reaches (drag = accel/speed at authoring time, so
## a full-magnitude input approaches exactly `speed`, never overshoots).
@export var accel: float = 1200.0
@export var drag: float = 5.0
@export var hp_buffer: float = 1.0
@export var damage_multiplier: float = 1.0
@export var motion_signature: String = "smooth"
@export var primary: String = "pulse_cannon"
@export var secondaries: Array[String] = []
@export var passives: Array[String] = []
@export var tp_used: float = 0.0
@export var tp_max: float = 6.0

## --- Ship design spec (schema_version 4). These ARE the ship: `parts` is derived from them by
## `ShipCompiler` on load and is never saved (ShipCatalog.save_ship strips it). A schema-3 hull
## leaves them at their defaults and keeps authoring `parts` and `groups` directly.
@export var chassis_color: String = ""    # blue | red | yellow | green | violet | silver
@export var accent_color: String = ""     # one of the six, or "" for a mono-colour ship
## Depth of the core stack, counting the dot: 2 = [34, dot], 3 = [34, 22, dot], 4 = [34, 22, 13, dot].
@export var core_depth: int = 2
@export var core_weapon: String = ""      # enemies: a set piece mounted on the core
@export var archetype: String = ""        # "" (player) | drone | sentry | radial_elite | heavy_elite | irregular_elite | chain | boss
@export var rails: Array[RailDefinition] = []
@export var chain_links: Array[SlotDefinition] = [] # chain archetype only, head outward
@export var chain_mode: String = "sway"   # rigid | sway | whip (§9.6)
## Set by ShipCompiler: id + a hash of the grammar. The rig and mesh caches key on it.
var compile_key: String = ""

func is_rail_hull() -> bool:
	return schema_version >= 4

func mounted_components() -> Array[String]:
	var result: Array[String] = [primary]
	result.append_array(secondaries)
	result.append_array(passives)
	return result
