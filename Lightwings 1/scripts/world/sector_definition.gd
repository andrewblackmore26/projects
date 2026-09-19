class_name SectorDefinition
extends Resource
## Optional descriptor for tooling. Runtime nodes are generated from coordinates.
@export var sector_id: String = ""
@export var coordinate: Vector2i = Vector2i.ZERO
@export var sector_kind: String = "regular"
@export var native_element: String = "fire"
@export var encounter_tier: int = 1
@export var core_id: String = ""
@export var elite_probability: float = 0.04
