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

func mounted_components() -> Array[String]:
	var result: Array[String] = [primary]
	result.append_array(secondaries)
	result.append_array(passives)
	return result
