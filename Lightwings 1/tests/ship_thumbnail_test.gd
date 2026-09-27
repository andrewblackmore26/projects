extends SceneTree
## CPU SVG pixels: the synchronous fallback must preserve the ship's visible connection graph.
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	var ship := ShipDefinition.new()
	ship.is_player = true
	ship.element = "lightning"
	ship.core_radius = 3.0
	var guide := _circle("guide",Vector2.ZERO,40.0)
	guide.style = 5
	guide.filled = false
	guide.parent_id = "core"
	var core := _circle("core",Vector2.ZERO,12.0)
	var pod := _circle("pod",Vector2(40,0),5.0)
	pod.parent_id = "core"
	var line := PartDefinition.new()
	line.id = "arm"
	line.shape = "line"
	line.from_id = "core"
	line.to_id = "pod"
	line.color_role = "blue"
	ship.parts.assign([guide,line,core,pod])
	var image: Image = ShipAuthoring.thumbnail(ship).get_image()
	_check(image.get_size() == Vector2i(64,64),"Thumbnail retains its 64px interface")
	_check(image.get_pixel(0,0).is_equal_approx(VisualStyle.BG),"Thumbnail uses the shared charcoal background")
	_check(image.get_pixel(32,32).r > 0.8,"Player thumbnail has a visible white core")
	var scale: float = 26.0 / maxf(26.0,ShipPreview.animated_radius(ship))
	var midpoint := Vector2i(Vector2(32,32)+Vector2(24,0)*scale)
	var connected: float = _peak(image,midpoint)
	_check(connected > 0.6,"Explicit arm is visible between separated circles")
	ship.parts.erase(line)
	var disconnected: Image = ShipAuthoring.thumbnail(ship).get_image()
	_check(_peak(disconnected,midpoint) < connected*0.5,"Removing the arm changes its own connector pixels")
	# The tiny core's interior is mostly its eye and restored 2.6px rim light.
	# Sample the empty pod centre so this checks fill rather than either highlight.
	var pod_center := Vector2i((Vector2(32,32)+Vector2(40,0)*scale).floor())
	var fill: Color = image.get_pixelv(pod_center)
	var expected_fill: Color = VisualStyle.FILLS.blue
	_check(absf(fill.r-expected_fill.r)<0.02 and absf(fill.g-expected_fill.g)<0.02 and absf(fill.b-expected_fill.b)<0.02,"Body interior matches the shared dark tinted fill")
	var guide_peak: float = 0.0
	for y: int in range(8,24):
		for x: int in range(8,24): guide_peak=maxf(guide_peak,_sum(image.get_pixel(x,y)))
	_check(guide_peak > _sum(VisualStyle.BG) and guide_peak < connected*0.4,"Dotted guide is present but subordinate to structure")
	print("Ship thumbnail: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _circle(id: String, at: Vector2, radius: float) -> PartDefinition:
	var part := PartDefinition.new()
	part.id=id
	part.position=at
	part.radius=radius
	part.color_role="blue"
	return part

func _sum(pixel: Color) -> float: return pixel.r+pixel.g+pixel.b

func _peak(image: Image, at: Vector2i) -> float:
	var peak: float = 0.0
	for y: int in range(at.y-1,at.y+2):
		for x: int in range(at.x-1,at.x+2): peak=maxf(peak,_sum(image.get_pixel(x,y)))
	return peak

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
