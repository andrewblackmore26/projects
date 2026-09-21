class_name GalleryDetachOverlay
extends Node2D
## Detach preview (spec §12.4, acceptance 7): a red overlay drawn from the SAME rig/pose data the
## sim's own detachment uses (`ShipMotion.get_rig(ship).subtree_size`), not a shader change. Add as
## a CHILD of the `ShipRenderer` it previews, so it shares the renderer's origin; it reads the
## renderer's own `visual_scale` and pose each frame rather than keeping a stale copy.

var target: ShipRenderer
var highlighted_index: int = -1

func _init() -> void:
	# Always on top of the renderer's own mesh, regardless of add_child order.
	z_index = 10
	z_as_relative = true

func _process(_delta: float) -> void:
	queue_redraw()

func highlight(index: int) -> void:
	highlighted_index = index
	queue_redraw()

func clear() -> void:
	highlighted_index = -1
	queue_redraw()

func _draw() -> void:
	if target == null or target.rig == null or highlighted_index < 0: return
	var rig: ShipMotion.ShipRig = target.rig
	if highlighted_index >= rig.subtree_size.size(): return
	var pose: ShipMotion.ShipPose = target._drawn_pose()
	if pose == null: return
	var factor: float = target.visual_scale
	var last: int = highlighted_index + rig.subtree_size[highlighted_index]
	var color: Color = Color(1.0, 0.15, 0.15, 0.55)
	for i: int in range(highlighted_index, last):
		if i >= pose.local.size(): continue
		var radius: float = rig.radius[i] * factor * 1.2
		draw_circle(pose.local[i] * factor, maxf(radius, 2.0), color, true, -1, true)
