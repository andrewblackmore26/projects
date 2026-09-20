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
		# Lines no longer occupy the shared 128-circle uniform slots (P2a-2):
		# only circles (plus any synthesized reach ring) get a `part_indices`
		# entry; a line's own period/phase now travels as per-vertex data.
		var authored_circles: int = 0
		var reach_rings: int = 0
		for part: PartDefinition in definition.parts:
			if part.shape == "circle": authored_circles += 1
		for group: GroupDefinition in definition.groups:
			if group.reach_ring: reach_rings += 1
		_check(builder.part_indices.size() == authored_circles + reach_rings, definition.id + " retains every authored circle (plus synthesized reach rings)")
		var custom0: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
		for part: PartDefinition in definition.parts:
			if part.shape == "circle":
				var parameters: Vector4 = builder.parameters[int(builder.part_indices[part.id])]
				_check(is_equal_approx(parameters.x, part.light_period) and is_equal_approx(parameters.y, part.light_phase), part.id + " keeps authored timing")
				_check(parameters.z > 0, part.id + " has an animated perimeter")
			else:
				var found: bool = false
				for i: int in range(0, custom0.size(), 4):
					if custom0[i + 3] > 0.5 and is_equal_approx(custom0[i], maxf(0.05, part.light_period)) and is_equal_approx(custom0[i + 1], part.light_phase):
						found = true
						break
				_check(found, part.id + " line keeps authored timing as per-vertex data")
	print("Ship meshes: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
