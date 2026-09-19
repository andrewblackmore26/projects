extends SceneTree
func _initialize() -> void:
	var ship: ShipDefinition = ShipCatalog.get_ship("elite_plasma_t5")
	var started: int = Time.get_ticks_usec()
	for index: int in range(100):
		var builder: ShipMesh = ShipMesh.new()
		builder._build_geometry(ship)
	var uncached_ms: float = (Time.get_ticks_usec() - started) / 1000.0
	ShipMesh.clear_cache()
	started = Time.get_ticks_usec()
	for index: int in range(100):
		var builder: ShipMesh = ShipMesh.new()
		builder.build(ship)
	var cached_ms: float = (Time.get_ticks_usec() - started) / 1000.0
	print("Mesh profile: 100 elite hulls uncached=", uncached_ms, "ms cached=", cached_ms, "ms ", ShipMesh.cache_stats())
	quit()
