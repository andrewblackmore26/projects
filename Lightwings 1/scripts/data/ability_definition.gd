class_name AbilityDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var trigger: String = "passive"
@export var cooldown: float = 1.0
@export var damage: float = 10.0
@export var range_pixels: float = 180.0
@export var slot_kind: String = "primary"
@export var minimum_tier: int = 1
@export var tp_cost: float = 2.0
@export var visual_color: String = "red"
@export var allowed_factions: Array[String] = ["player", "enemy", "elite", "boss"]
@export var duration: float = 0.0
