extends SceneTree
## Geometry/serialization boundary checks for the production GPU surface.

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	for definition: ShipDefinition in ShipCatalog.all_forms():
		var builder: ShipMesh = ShipMesh.new()
		var mesh: ArrayMesh = builder.build(definition)
		_check(mesh.get_surface_count() == 1, definition.id + " uses one surface")
		var arrays: Array = mesh.surface_get_arrays(0)
		var points: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		_check(points.size() > 4 and indices.size() % 3 == 0, definition.id + " contains triangles")
		for index: int in indices:
			if index < 0 or index >= points.size():
				_check(false, definition.id + " references a missing vertex")
				break
		_check(builder.part_indices.size() == definition.parts.size(), definition.id + " retains every authored part")
		for part: PartDefinition in definition.parts:
			var parameters: Vector4 = builder.parameters[int(builder.part_indices[part.id])]
			_check(is_equal_approx(parameters.x, part.light_period) and is_equal_approx(parameters.y, part.light_phase), part.id + " keeps authored timing")
			_check(parameters.z > 0, part.id + " has an animated perimeter")
	print("Ship meshes: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
