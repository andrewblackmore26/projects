class_name GroupDefinition
extends Resource
## A group owns the subtree rooted at `root_id` (found by walking `parent_id`
## on `PartDefinition`, stopping at any nested group's root). It describes how
## that subtree moves; `ShipMotion` is the only reader that turns this into
## positions. See docs/LIGHTSHIP_GAME_SPEC_V3.md §18, §22.

@export var root_id: String = ""
@export var orbit_radius: float = 0.0
## Radians/second. Signed: negative counter-rotates. Sibling groups at
## different radii should carry opposite signs or the hull reads as one
## spinning wheel (spec §18).
@export var orbit_speed: float = 0.0
@export var drift_amp: float = 0.0
@export var drift_freq: float = 0.0
@export var breathe_amp: float = 0.0
## "rigid" | "sway" | "whip"
@export var chain_mode: String = "rigid"
## When true, a dashed unfilled ring is synthesized at `orbit_radius` around
## the group's root, drawn under everything, with no collider and no hp.
@export var reach_ring: bool = false
