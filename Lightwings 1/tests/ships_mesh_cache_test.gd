extends SceneTree
var failures: int = 0
func _initialize() -> void:
	ShipMesh.clear_cache()
	var ship: ShipDefinition = ShipCatalog.get_ship("elite_plasma_t5")
	var first: ShipMesh = ShipMesh.new()
	var first_mesh: ArrayMesh = first.build(ship)
	var second: ShipMesh = ShipMesh.new()
	var second_mesh: ArrayMesh = second.build(ship.duplicate(true))
	_check(first_mesh == second_mesh, "Equivalent definitions share immutable mesh")
	_check(ShipMesh.cache_stats().hits == 1 and ShipMesh.cache_stats().misses == 1, "Only first build triangulates")
	var saved_center: Vector2 = first.centers[0]
	first.centers[0] = Vector2(999, 999)
	first.part_indices.clear()
	var third: ShipMesh = ShipMesh.new()
	third.build(ship)
	_check(third.centers[0] == saved_center and not third.part_indices.is_empty(), "Mutable builder metadata cannot corrupt cached metadata")
	var draft: ShipDefinition = ship.duplicate(true)
	draft.parts[0].radius += 1
	_check(ShipMesh.new().build(draft) != first_mesh, "Editing geometry with same hull ID gets a new mesh")
	draft = ship.duplicate(true)
	draft.parts[0].light_phase += 0.1
	_check(ShipMesh.new().build(draft) != first_mesh, "Edited running-light metadata gets a new mesh")
	draft = ship.duplicate(true)
	draft.parts[0].color_role = "red"
	_check(ShipMesh.new().build(draft) != first_mesh, "Edited colors get a new mesh")
	draft = ship.duplicate(true)
	draft.parts.reverse()
	_check(ShipMesh.new().build(draft) != first_mesh, "Authoring order participates in geometry identity")
	draft = ship.duplicate(true)
	draft.parts[0].stat_value += 1
	_check(ShipMesh.new().build(draft) == first_mesh, "Unbaked gameplay stats do not rebuild geometry")
	draft = ship.duplicate(true)
	draft.parts[1].parent_id = "not_a_real_circle"
	_check(ShipMesh.new().build(draft) == first_mesh, "The authoring parent graph does not affect geometry identity")
	var actor_a: ShipRenderer = ShipRenderer.new()
	var actor_b: ShipRenderer = ShipRenderer.new()
	root.add_child(actor_a)
	root.add_child(actor_b)
	actor_a.set_ship(ship)
	actor_b.set_ship(ship)
	actor_a.hidden_part_ids.append(ship.parts[0].id)
	actor_a.part_position_overrides[ship.parts[1].id] = Vector2(50, 10)
	actor_a._sync_part_offsets()
	actor_b._sync_part_offsets()
	_check(actor_a._mesh_instance.mesh == actor_b._mesh_instance.mesh, "Actors share geometry")
	_check(actor_a._mesh_material != actor_b._mesh_material and actor_a._mesh_offsets != actor_b._mesh_offsets, "Hidden parts and moving gun offsets remain per actor")
	actor_a.free()
	actor_b.free()
	# A small synthetic hull tests bounded eviction without expensive scene work.
	var simple: ShipDefinition = ShipCatalog.get_ship("player_seed")
	for index: int in range(ShipMesh.MAX_CACHE_ENTRIES + 8):
		simple.parts[0].radius = 10 + index * 0.1
		ShipMesh.new().build(simple)
	var statistics: Dictionary = ShipMesh.cache_stats()
	_check(statistics.entries <= ShipMesh.MAX_CACHE_ENTRIES and statistics.estimated_bytes <= ShipMesh.MAX_CACHE_BYTES, "Cache stays bounded across edited drafts")
	_check(first_mesh.get_surface_count() == 1, "Eviction leaves existing renderer resources valid")
	ShipMesh.clear_cache()
	_check(ShipMesh.cache_stats().entries == 0, "Explicit cache clear releases cache ownership")
	print("Ship mesh cache: ", failures, " failures")
	quit(1 if failures else 0)
func _check(condition: bool, label: String) -> void:
	if not condition: failures += 1; push_error(label)
