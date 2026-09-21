class_name PartDefinition
extends Resource
@export var id: String = ""
@export var shape: String = "circle"
@export var position: Vector2 = Vector2.ZERO
@export var radius: float = 5.0
@export var filled: bool = true
@export var parent_id: String = ""
@export var color_role: String = "chassis"
@export var layer: int = 3
@export var light_period: float = 2.0
@export var light_phase: float = 0.0
@export var ability_id: String = ""
@export var from_id: String = ""
@export var to_id: String = ""
@export var mirror_id: String = ""
@export var mount_id: String = ""
@export var stat_id: String = ""
@export var tp_cost: float = 1.0
@export var hp: float = 0.0
@export var dashed: bool = false
@export var stat_value: float = 0.0

## --- Ship design spec (schema 4). `ShipCompiler` writes these; nobody authors them, and a schema-3
## hull leaves every one at its default, which is what keeps the legacy evaluator's path untouched.
## They are @export only so `duplicate(true)` carries them: compiled parts are never saved.
##
## Motion is forward kinematics down the parent chain (ShipMotion._step_fk). A part's own angle is
## `spin_speed * t + bob_amp * sin(bob_freq * t + bob_phase)`, added to its parent's angle, and its
## offset from its parent is scaled by `1 + pump_amp * sin(pump_freq * t + pump_phase)`. That one
## rule gives spec §9.1 (a rail's clusters spin), §9.2 (pods and nodes bob) and §9.3 (arms pump the
## RADIUS - nothing in this model can change a circle's size).
@export var spin_speed: float = 0.0   # rad/s, signed
@export var bob_amp: float = 0.0      # rad
@export var bob_freq: float = 0.0     # rad/s
@export var bob_phase: float = 0.0    # rad
@export var pump_amp: float = 0.0     # fraction of the offset from the parent
@export var pump_freq: float = 0.0    # rad/s
@export var pump_phase: float = 0.0   # rad
## A set piece's root: it ignores its parent's angle and takes the aim it is given (spec §9.7),
## or points outward when it is given none.
@export var aim_joint: bool = false
## Aim joints only: the heading (rad clockwise from the hull's forward) the piece has at rest, i.e.
## its slot's outward direction. An aim is a HEADING, so the joint turns by `aim - rest_heading`.
@export var rest_heading: float = 0.0
## False for rail rings, inner core rings, passive rings and set-piece circles: drawn, but no HP,
## no collider, no reward share and no TP.
@export var solid: bool = true
## -1 derives the draw style from `filled` / `dashed` / `layer` as v0.3 did. 4 = thin passive ring,
## 5 = rail dash (2 on / 5 off at 28 %, no running light).
@export var style: int = -1
