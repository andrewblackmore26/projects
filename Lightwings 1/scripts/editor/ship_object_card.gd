class_name ShipObjectCard
extends Button
var object_id: String = "circle"
var object_kind: String = "Body"
func _get_drag_data(_position: Vector2) -> Variant:
	var label: Label = Label.new()
	label.text = object_id.replace("_", " ").capitalize()
	set_drag_preview(label)
	return {"ship_object": object_id, "kind": object_kind}
