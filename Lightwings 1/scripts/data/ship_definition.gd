class_name ShipDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = "Seed"
@export var element: String = "corruption"
@export var tier: int = 1
@export var is_player: bool = false
@export var breathes: bool = false
@export var core_radius: float = 3.0
@export var hull_radius: float = 0.0
@export var parts: Array[PartDefinition] = []
@export var abilities: Array[String] = []
@export var description: String = ""
@export var schema_version: int = 2
@export var faction: String = "player"
@export var role: String = "standard"
@export var family: String = "standard_a"
@export var footprint: float = 48.0
@export var magnet_radius: float = 100.0
@export var speed: float = 220.0
@export var turn_rate: float = 10.0
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
