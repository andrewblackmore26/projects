extends SceneTree
## Every player root-to-root next-tier route must preserve stable IDs, remove
## outgoing parts, grow incoming parts from the core and restore the GPU surface.

var failures: int = 0
var checks: int = 0
var routes: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for element: String in ShipCatalog.ELEMENTS:
		for tier: int in range(1, 5):
			for target_element: String in ShipCatalog.ELEMENTS:
				var renderer: ShipRenderer = ShipRenderer.new()
				root.add_child(renderer)
				renderer.set_process(false)
				var source: ShipDefinition = ShipCatalog.make_ship(element, tier, true)
				var target: ShipDefinition = ShipCatalog.make_ship(target_element, tier + 1, true)
				renderer.set_ship(source)
				renderer.set_ship(target, true)
				var route: String = source.id + " -> " + target.id
				_check(is_equal_approx(renderer.reshape_remaining, 0.8), route + " starts 0.8-second reshape")
				_check(not renderer._mesh_instance.visible, route + " uses interpolated geometry during reshape")
				renderer._process(0.4)
				for part: PartDefinition in renderer._display_parts:
					var before: PartDefinition = renderer._find(source, part.id)
					var after: PartDefinition = renderer._find(target, part.id)
					var expected_position: Vector2
					var expected_radius: float
					if before != null and after != null:
						expected_position = before.position.lerp(after.position, 0.5)
						expected_radius = lerpf(before.radius, after.radius, 0.5)
					elif after != null:
						expected_position = after.position * 0.5
						expected_radius = after.radius * 0.5
					else:
						expected_position = before.position * 0.5
						expected_radius = before.radius * 0.5
					var data: Dictionary = renderer._morph(part)
					_check(Vector2(data.position).is_equal_approx(expected_position), route + " midpoint position " + part.id)
					_check(is_equal_approx(float(data.radius), expected_radius), route + " midpoint radius " + part.id)
				renderer._process(0.4)
				_check(renderer.reshape_remaining == 0 and renderer._mesh_instance.visible, route + " returns to the cached surface")
				_check(renderer._display_parts.size() == target.parts.size(), route + " removes outgoing parts")
				for part: PartDefinition in renderer._display_parts:
					_check(renderer._find(target, part.id) != null, route + " retains only target IDs")
				routes += 1
				renderer.free()
	print("Ship reshapes: ", routes, " routes, ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
