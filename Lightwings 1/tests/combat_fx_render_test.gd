extends SceneTree
## Real Vulkan pixels for P8 (spec §19). Headless has no renderer and a
## shader that fails to compile renders black (tasks/lessons.md), so every
## check here needs a real window. Each measurement carries its own negative
## control per house rule.

const Harness = preload("res://tests/support/harness.gd")
const FX = preload("res://scripts/combat/combat_fx.gd")

var failures: int = 0
var controls_caught: int = 0
var controls_total: int = 0
var scene: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# 1280x800 matches the project's base content-scale aspect ratio (1.6) so
	# `root.get_texture().get_image()` maps world/canvas coordinates 1:1 onto
	# image pixels - a mismatched aspect letterboxes/scales the viewport
	# texture, and EVERY sample silently reads background (confirmed: a bare
	# ColorRect at a size that did not match this ratio produced an entirely
	# blank capture, image.get_size() != root.size, same trap arena_render_test
	# avoids by using 1280x800 itself).
	root.size = Vector2i(1280, 800)
	scene = Node2D.new()
	root.add_child(scene)
	await _ring_radius_case()
	await _flare_case()
	await _collar_case()
	await _hue_gate_case()
	await _compositor_stage_case()
	print("Combat FX rendering: failures=%d, controls %d/%d" % [failures,controls_caught,controls_total])
	quit(1 if failures or controls_caught != controls_total else 0)

func _ring_radius_case() -> void:
	var canvas: Node2D = Node2D.new()
	scene.add_child(canvas)
	var fx: RefCounted = FX.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var center: Vector2 = Vector2(450, 350)
	fx.emit("wall_flash",center,Color.WHITE,rng,{"r0":50.0,"r1":50.0})
	canvas.draw.connect(func(): fx.draw_above(canvas,ThemeDB.fallback_font))
	canvas.queue_redraw()
	await _frame()
	var image: Image = root.get_texture().get_image()
	# M6 (aspect "expand"): the capture is the whole window, never a letterboxed part of it.
	_check(image.get_size() == root.size,"the capture is exactly root.size %s (got %s)" % [root.size,image.get_size()])
	var on_ring: bool = _bright_at(image,center+Vector2(50,0)) or _bright_at(image,center+Vector2(0,50))
	var off_ring: bool = _bright_at(image,center+Vector2(20,0))
	_check(on_ring,"a ring's pixels sit at its radius (+/- a couple of px)")
	_check(not off_ring,"nothing bright sits well inside the ring's radius")
	canvas.queue_free()
	await process_frame
	# Negative control: capture a frame BEFORE emit() - the ring must not be there yet.
	var pre_canvas: Node2D = Node2D.new()
	scene.add_child(pre_canvas)
	var pre_fx: RefCounted = FX.new()
	pre_canvas.draw.connect(func(): pre_fx.draw_above(pre_canvas,ThemeDB.fallback_font))
	pre_canvas.queue_redraw()
	await _frame()
	var pre_image: Image = root.get_texture().get_image()
	_control("captured before emit() (nothing spawned yet)",not _bright_at(pre_image,center+Vector2(50,0)))
	pre_canvas.queue_free()
	await process_frame

func _flare_case() -> void:
	var world: CombatWorld = CombatWorld.new()
	scene.add_child(world)
	# The world must NOT run its own physics here. `_frame()` awaits two process frames, and with
	# `_physics_process` live those frames advance the tick, which decays the flare and re-runs
	# `_step_motion`/`_sync_visuals` between setting the flare and capturing the pixels. Measured
	# without this line: 2 failures in 5 runs on an idle machine, both reporting the flared and
	# unflared rim as the identical unflared value (1.407 vs 1.407) - the capture simply missed it.
	# The claim under test is "a flared rim is brighter", not "a flare survives N uncontrolled ticks",
	# so the test drives the tick itself.
	world.set_physics_process(false)
	world.setup_player("fire",1,40,[],Vector2(450,350))
	var enemy: Dictionary = world._spawn_enemy("fire",1,Vector2(650,350),false)
	world._sync_visuals()
	await _frame()
	var image_before: Image = root.get_texture().get_image()
	# Sample the RIM, not the centre: a flare brightens the circle's 1.5 px rim at radius r, and a
	# 7x7 patch on the centre never contains it. That is why this check used to pass only when the
	# enemy happened to DRIFT between the two captures (physics left running) so the patch caught
	# unrelated geometry - 3 passes in 5 for the wrong reason. `_rim_sample` takes the brightest
	# point on the circle itself.
	var rim_radius: float = (enemy.rig as ShipMotion.ShipRig).radius[0]
	var rim_before: float = _rim_sample(image_before,Vector2(enemy.pos),rim_radius)
	world._flare(enemy,0)
	world._last_dt = 1.0/60.0
	world._step_motion(enemy)
	world._sync_visuals()
	await _frame()
	var image_after: Image = root.get_texture().get_image()
	var rim_after: float = _rim_sample(image_after,Vector2(enemy.pos),rim_radius)
	_check(rim_after>1.0,"a flared rim's summed channel value pushes above 1.0 (measured %.3f)" % rim_after)
	_check(rim_after>rim_before,"flared rim is brighter than the same rim before the hit (%.3f vs %.3f)" % [rim_after,rim_before])
	# Negative control: never calling `_flare` leaves a fresh, same-element
	# core at its ordinary (unflared) brightness - close to `rim_before`, not
	# jumped up near `rim_after`. An absolute ">1.0" bar is the wrong test
	# here (every core is already boosted ~1.8x per spec §23 and can clear
	# 1.0 unflared), so this compares against the measured unflared baseline.
	var control_enemy: Dictionary = world._spawn_enemy("fire",1,Vector2(650,550),false)
	world._sync_visuals()
	await _frame()
	var control_image: Image = root.get_texture().get_image()
	var control_rim: float = _rim_sample(control_image,Vector2(control_enemy.pos),(control_enemy.rig as ShipMotion.ShipRig).radius[0])
	_control("no _flare() call on this circle",not (control_rim>rim_before*1.3))
	world.queue_free()
	await process_frame

func _collar_case() -> void:
	var canvas: Node2D = Node2D.new()
	scene.add_child(canvas)
	var fx: RefCounted = FX.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	var center: Vector2 = Vector2(450, 350)
	fx.emit("collar",center,Color.BLACK,rng,{"r1":24.0})
	fx.update(0.05) # off t=0, where the collar's own radius starts at 0 (nothing to sample yet)
	canvas.draw.connect(func():
		canvas.draw_rect(Rect2(center-Vector2(80,80),Vector2(160,160)),Color(0.30,0.30,0.30))
		fx.draw_below(canvas))
	canvas.queue_redraw()
	await _frame()
	var image: Image = root.get_texture().get_image()
	var playfield: float = _sample(image,center+Vector2(60,60))
	var collar: float = _sample(image,center)
	_check(collar<playfield,"the collar's mean sits below the surrounding playfield value (%.3f vs %.3f)" % [collar,playfield])
	canvas.queue_free()
	await process_frame
	# Negative control: an unconsumed (never-emitted) collar leaves the centre at the playfield value.
	var empty_canvas: Node2D = Node2D.new()
	scene.add_child(empty_canvas)
	var empty_fx: RefCounted = FX.new()
	empty_canvas.draw.connect(func():
		empty_canvas.draw_rect(Rect2(center-Vector2(80,80),Vector2(160,160)),Color(0.30,0.30,0.30))
		empty_fx.draw_below(empty_canvas))
	empty_canvas.queue_redraw()
	await _frame()
	var empty_image: Image = root.get_texture().get_image()
	var empty_center: float = _sample(empty_image,center)
	var empty_playfield: float = _sample(empty_image,center+Vector2(60,60))
	_control("collar never emitted",not (empty_center<empty_playfield))
	empty_canvas.queue_free()
	await process_frame

## The HTML reference identifies projectile types by hue. Factions retain the
## same hue; the friendly centre pip is tested independently in the range fixture.
func _hue_gate_case() -> void:
	const BulletCanvas = preload("res://scripts/combat/combat_canvas.gd")
	const Pool = preload("res://scripts/combat/bullet_pool.gd")
	var pool: LightBulletPool = Pool.new()
	var canvas: BulletCanvas = BulletCanvas.new()
	scene.add_child(canvas)
	var at: Vector2 = Vector2(450,350)
	var colours: Array[Vector3] = []
	for flag: int in [0,Pool.HOMING,Pool.ROCKET,Pool.RICOCHET]:
		pool.clear()
		pool.add(at,Vector2.RIGHT*100,-1,10,3,-1,1,0,flag,9)
		pool.add(at+Vector2(0,160),Vector2.RIGHT*100,-1,10,3,-1,0,4,flag,9)
		canvas.sync_pool(pool)
		await _frame()
		await _frame()
		var pixels: Image = root.get_texture().get_image()
		# Only the outer-right rim: a centre pip is an ownership cue, not a hue change.
		var enemy_colour: Vector3 = _patch_colour(pixels,at+Vector2(9,0),2)
		var friendly_colour: Vector3 = _patch_colour(pixels,at+Vector2(9,160),2)
		_check(enemy_colour!=Vector3.ZERO and enemy_colour.distance_to(friendly_colour)<0.05,"weapon type %d preserves its colour across factions" % flag)
		colours.append(enemy_colour)
	for i: int in range(colours.size()):
		for j: int in range(i):
			_check(colours[i].distance_to(colours[j])>0.2,"types %d and %d remain visibly distinct" % [i,j])
	_control("all bodies accidentally use the first type hue",not (colours[0].distance_to(colours[0])>0.2))
	_control("sampling an empty patch",_patch_colour(root.get_texture().get_image(),Vector2(200,100),10) == Vector3.ZERO)
	canvas.queue_free()
	await process_frame

## Mean colour of the lit pixels in a patch, divided by its largest channel, so brightness and HDR
## emission drop out and only hue and saturation remain. ZERO when nothing in the patch is lit.
func _patch_colour(image: Image, at: Vector2, radius: int) -> Vector3:
	var total: Vector3 = Vector3.ZERO
	for y: int in range(int(at.y)-radius,int(at.y)+radius):
		for x: int in range(int(at.x)-radius,int(at.x)+radius):
			if x<0 or y<0 or x>=image.get_width() or y>=image.get_height(): continue
			var pixel: Color = image.get_pixel(x,y)
			if pixel.r+pixel.g+pixel.b>0.3: total += Vector3(pixel.r,pixel.g,pixel.b)
	var top: float = maxf(total.x,maxf(total.y,total.z))
	return total/top if top>0.0 else Vector3.ZERO

## Review finding 5 (spec §19 "impact... plus the target rim"): P9's FX
## batching (`fx_canvas.gd`) reparents only `_bullet_canvas`/`_trail_canvas`
## into the compositor's `foreground`; `_fx_canvas` (which owns the "above"
## MultiMesh pass, z_index 41, the finding's own comment says "above the
## bullet canvas at 40") stayed a child of `world`, which lives INSIDE
## `background_viewport` - a separate render target composited as one flat
## texture at the background stage, entirely outside `foreground`'s own
## z-ordering. So an impact ring on the player composited UNDER the opaque
## player hull. This goes through the REAL `CombatCompositor`, not a bare
## FX+canvas fixture (this file's other cases explicitly do NOT, per the
## header comment), and samples the SAME screen point before/after the ring
## is emitted: an occluded ring leaves that point statistically unchanged
## (painted into a separate texture, then fully covered by the opaque hull
## drawn on top); a visible ring measurably brightens it.
func _compositor_stage_case() -> void:
	var world: CombatWorld = CombatWorld.new()
	scene.add_child(world)
	world.set_physics_process(false)
	world.setup_player("neutral",1,40,[],Vector2(896,560))
	var compositor: CombatCompositor = CombatCompositor.new()
	scene.add_child(compositor)
	compositor.attach(world)
	world._sync_visuals()
	world.queue_redraw()
	await _frame()
	var screen_center: Vector2 = Vector2(640,400) # compositor always centres the player here
	# r=8 sits well inside the seed hull's solid core fill (radius 15,
	# filled regardless of angle) so the sample point is guaranteed to be
	# covered by the OPAQUE hull, not a gap between its circles.
	var ring_point: Vector2 = screen_center+Vector2(8,0)
	var image_before: Image = root.get_texture().get_image()
	var before: float = _sample(image_before,ring_point)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 19
	world.fx.emit("impact",world.player_position,Color.WHITE,rng,{"r0":8.0,"r1":8.0})
	world.queue_redraw()
	await _frame()
	var image_after: Image = root.get_texture().get_image()
	var after: float = _sample(image_after,ring_point)
	_check(after>before+0.15,"an impact ring on the player is visible ON TOP of the player hull (before %.3f, after %.3f)" % [before,after])

	# Negative control: undo exactly the fix (reparent `_fx_canvas` back under
	# `world`, inside the background stage) and repeat the same before/after
	# measurement - the ring must now fail to brighten the point, reproducing
	# the actual shipped bug through the real reparenting code path.
	world.fx.clear()
	# `CombatCompositor._process()` re-applies this exact reparent every
	# frame (process_mode ALWAYS, unconditional on `get_parent() != foreground`),
	# so it must be paused or it would silently undo the sabotage before the
	# next capture - proving the fix is what holds the stage, not a one-time
	# accident of setup order.
	compositor.set_process(false)
	world._fx_canvas.reparent(world,false)
	world._fx_canvas.z_index = 0
	world.queue_redraw()
	await _frame()
	var control_before_image: Image = root.get_texture().get_image()
	var control_before: float = _sample(control_before_image,ring_point)
	world.fx.emit("impact",world.player_position,Color.WHITE,rng,{"r0":8.0,"r1":8.0})
	world.queue_redraw()
	await _frame()
	var control_after_image: Image = root.get_texture().get_image()
	var control_after: float = _sample(control_after_image,ring_point)
	_control("_fx_canvas reparented back under world (the pre-fix stage)",not (control_after>control_before+0.15))

	compositor.queue_free()
	world.queue_free()
	await process_frame

func _bright_at(image: Image, at: Vector2) -> bool:
	return _sample(image,at)>0.05

func _sample(image: Image, at: Vector2) -> float:
	var total: float = 0.0
	var count: int = 0
	for y: int in range(int(at.y)-3,int(at.y)+4):
		for x: int in range(int(at.x)-3,int(at.x)+4):
			if x<0 or y<0 or x>=image.get_width() or y>=image.get_height(): continue
			var pixel: Color = image.get_pixel(x,y)
			total += pixel.r+pixel.g+pixel.b
			count += 1
	return total/maxf(1.0,float(count))

func _frame() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

## Brightest point on a circle's rim: 64 samples around radius `radius`, each a small patch so a
## 1.5 px stroke cannot fall between pixels. A flare boosts the rim, so the maximum is the signal;
## an average around the ring would be dominated by the dark gaps between strokes.
func _rim_sample(image: Image, centre: Vector2, radius: float) -> float:
	var best: float = 0.0
	for step: int in range(64):
		var angle: float = TAU * float(step) / 64.0
		var at: Vector2 = centre + Vector2.from_angle(angle) * radius
		var local: float = 0.0
		for y: int in range(int(at.y) - 1, int(at.y) + 2):
			for x: int in range(int(at.x) - 1, int(at.x) + 2):
				if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
				var pixel: Color = image.get_pixel(x, y)
				local = maxf(local, pixel.r + pixel.g + pixel.b)
		best = maxf(best, local)
	return best

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
	else:
		print("ok: "+label)

func _control(what_was_sabotaged: String, instrument_noticed: bool) -> void:
	controls_total += 1
	if instrument_noticed: controls_caught += 1
	else: push_error("Negative control not caught: "+what_was_sabotaged)
