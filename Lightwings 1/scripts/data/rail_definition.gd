class_name RailDefinition
extends Resource
## One rail (ship design spec §4.2, §9.1, §9.3). `slots.size()` must equal `order`.
@export var radius: int = 52              # 52 | 96 | 140 | 184, always from the inside out
@export var order: int = 3                # 3..8 evenly spaced slots
@export var speed: float = 0.0            # rad/s, signed. Adjacent rails must differ in sign
@export var phase: float = 0.0            # rad from forward, clockwise
@export var pump_phase: float = 0.0       # rad; the spec steps it 0.9 per rail
@export var pump_amp: float = -1.0        # < 0 = the §9.3 default (3 %)
@export var reach_ring: bool = true       # §9.9: every rail draws its dashed ring
@export var offset: Vector2 = Vector2.ZERO # irregular elites only, length <= 12
@export var slots: Array[SlotDefinition] = []
