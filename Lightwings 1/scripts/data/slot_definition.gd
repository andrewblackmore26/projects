class_name SlotDefinition
extends Resource
## One slot on a rail, or one link of a chain (ship design spec §4.4). Nothing here is a position:
## where the cluster sits is derived from its rail, its index and the tick.
@export var type: String = "stub"        # hub | node | stub
@export var node_radius: int = 4          # node only: 4 (micro) or 7 (pod)
@export var pods: int = 0                 # hub only: 1..4, fanned 0.78 rad apart about outward
@export var pod_spacing: float = 0.78     # wider paired arms distinguish heavy hulls without extra circles
@export var radius_override: float = 0.0
@export var phase_offset: float = 0.0
@export var mark_radius: float = 0.0
@export var pod_hp_radius: float = -1.0
@export var set_piece: String = ""        # hub only: a SetPieceCatalog id, at most one
@export var mount: String = ""            # player: primary | secondary_N. Empty on enemies (a gun)
@export var hp: float = 0.0               # 0 = derived from radius and tier, as v0.3 did
## Explicit armour budget after merging pods: fixed + radius * (4 + 3 * spawn tier).
## A negative radius retains the original hp/radius rule for existing custom hulls.
@export var hp_fixed: float = 0.0
@export var hp_radius: float = -1.0
@export var feature: String = ""          # "" | shield_generator (the boss's second core stack)
@export var bob_amp: float = -1.0         # < 0 = the §9.2 default

func is_occupied() -> bool:
	return type == "hub" or type == "node"
