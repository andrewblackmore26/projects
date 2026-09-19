class_name EditorShipPreview
extends ShipPreview
## Resizable authoring wrapper around the production HDR preview.
var zoom: float = 1.0

func _ready() -> void:
	var right: float = anchor_right
	var bottom: float = anchor_bottom
	anchor_right = anchor_left
	anchor_bottom = anchor_top
	initialize(ShipCatalog.make_ship("corruption", 1, true), Vector2(maxf(1, size.x), maxf(1, size.y)), zoom)
	anchor_right = right
	anchor_bottom = bottom
	stretch = true
	preview_viewport.transparent_bg = false
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if renderer != null:
		renderer.position = size * 0.5
		renderer.visual_scale = zoom

func set_ship(ship: ShipDefinition, animate: bool = false) -> void:
	if renderer == null:
		return
	renderer.set_ship(ship, animate)

func set_zoom(value: float) -> void:
	zoom = value
	_layout()
