extends SceneTree
## M10: the trailing camera (scripts/ships/camera_rig.gd), measured against
## docs/LIGHTSHIP_CAMERA_MOVEMENT_SPEC.md §6 with the ship's path given analytically, so nothing but
## the rig is under test. Every check has a control that sabotages the thing it measures:
## - lag: cruise lag equals v*tau (101.2 px at 460 px/s, tau 0.22) with the clamps opened;
## - clamp: with the defaults the ship rests ON the 14 % clamp (89.6 screen px), ahead of centre;
## - zoom: 1.00 at rest, 0.96 at top speed, 0.93 at dash peak, 95 % of the way in 0.40 s;
## - aim: 6 % of the half-width (38.4 px) toward the ship's aim;
## - total: lag + aim clamped to 18 % (115.2 px);
## - recentre: stopping dead settles to 5 % in 0.30 s with no single-tick jump;
## - rate: the same path at 30/60/120/144 Hz lands the camera in the same place.

const Harness = preload("res://tests/support/harness.gd")
const TOP: float = 460.0
var t: RefCounted

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	t = Harness.new("CAMERA RIG")
	_lag()
	_clamp()
	_zoom()
	_aim()
	_total_clamp()
	_recentre()
	_rate_independence()
	_cam_command()
	GameTuning.reset_feel()
	await process_frame
	t.finish(self)

func _tune(values: Dictionary) -> void:
	GameTuning.reset_feel()
	for key: String in values: GameTuning.set_feel(key, float(values[key]))

## Flies RIGHT at `speed` for `seconds` at `hz` with the given aim, from rest at the origin.
func _cruise(speed: float, seconds: float, aim: Vector2 = Vector2.ZERO, hz: int = 60, rig: CameraRig = null) -> CameraRig:
	if rig == null:
		rig = CameraRig.new()
		rig.reset(Vector2.ZERO)
	var dt: float = 1.0 / float(hz)
	var velocity: Vector2 = Vector2.RIGHT * speed
	var at: Vector2 = rig.ship
	for i: int in range(roundi(seconds * hz)):
		at += velocity * dt
		rig.step(dt, at, velocity, aim, TOP)
	return rig

## Ship minus lagging point, along the flight: how far the camera trails, in world px.
func _lag_px(rig: CameraRig) -> float: return rig.ship.x - rig.center.x

func _lag() -> void:
	_tune({"cam.lag_clamp": 1.0, "cam.total_clamp": 1.0, "cam.aim_on": 0.0, "cam.zoom_on": 0.0})
	var lag: float = _lag_px(_cruise(TOP, 2.0))
	print("measure: cruise lag %.2f px (v*tau = %.2f)" % [lag, TOP * 0.22])
	t.check(absf(lag - TOP * 0.22) < 0.5, "Unclamped cruise lag is v*tau = 101.2 px (measured %.2f)" % lag)
	_tune({"cam.lag_clamp": 1.0, "cam.total_clamp": 1.0, "cam.aim_on": 0.0, "cam.zoom_on": 0.0, "cam.lag_on": 0.0})
	t.control("the lag layer switched off", absf(_lag_px(_cruise(TOP, 2.0)) - TOP * 0.22) >= 0.5)

func _clamp() -> void:
	_tune({"cam.aim_on": 0.0})
	var rig: CameraRig = _cruise(TOP, 2.0)
	var screen: Vector2 = rig.ship_screen_offset()
	print("measure: cruise ship offset %.2f screen px ahead at zoom %.4f (clamp %.1f)" % [screen.x, rig.zoom, 0.14 * 640.0])
	t.check(absf(screen.x - 89.6) < 0.05 and absf(screen.y) < 0.001, "At cruise the ship rests on the 14%% clamp, 89.6 screen px AHEAD of centre (measured %.2f)" % screen.x)
	_tune({"cam.aim_on": 0.0, "cam.lag_clamp": 1.0})
	t.control("the lag clamp opened", absf(_cruise(TOP, 2.0).ship_screen_offset().x - 89.6) >= 0.05)

func _zoom() -> void:
	_tune({})
	var rest: float = _cruise(0.0, 2.0).zoom
	var top: float = _cruise(TOP, 2.0).zoom
	var dash: float = _cruise(TOP * GameTuning.feel("dash.peak_ratio"), 2.0).zoom
	var eased: float = (1.0 - _cruise(TOP, 0.40).zoom) / (1.0 - GameTuning.feel("cam.zoom_top"))
	print("measure: zoom rest %.4f top %.4f dash %.4f; share of the top-speed step reached in 0.40 s %.3f" % [rest, top, dash, eased])
	t.check(absf(rest - 1.0) < 0.001, "Zoom is 1.00 at rest (measured %.4f)" % rest)
	t.check(absf(top - 0.96) < 0.001, "Zoom is 0.96 at top speed (measured %.4f)" % top)
	t.check(absf(dash - 0.93) < 0.001, "Zoom is 0.93 at dash peak (measured %.4f)" % dash)
	t.check(absf(eased - 0.95) < 0.01, "The zoom eases in over 0.40 s: 95%% of the step reached (measured %.3f)" % eased)
	_tune({"cam.zoom_on": 0.0})
	t.control("the zoom layer switched off", absf(_cruise(TOP * GameTuning.feel("dash.peak_ratio"), 2.0).zoom - 0.93) >= 0.001)
	_tune({"cam.zoom_in_s": 1.2})
	t.control("a 1.2 s ease in place of 0.40 s", absf((1.0 - _cruise(TOP, 0.40).zoom) / 0.04 - 0.95) >= 0.01)

func _aim() -> void:
	_tune({})
	var rig: CameraRig = _cruise(0.0, 2.0, Vector2.RIGHT)
	var offset: Vector2 = rig.focus - rig.ship
	print("measure: aim offset %.2f px at rest (6%% of 640 = 38.4)" % offset.x)
	t.check(absf(offset.x - 38.4) < 0.05 and absf(offset.y) < 0.001, "At rest the camera leads the ship's aim by 38.4 px (measured %.2f)" % offset.x)
	_tune({"cam.aim_on": 0.0})
	t.control("the aim layer switched off", absf((_cruise(0.0, 2.0, Vector2.RIGHT).focus.x) - 38.4) >= 0.05)

func _total_clamp() -> void:
	# Flying right while aiming left puts the lag (89.6 behind) and the aim (38.4 behind) on the same
	# side: 128 px, over the 18 % total clamp of 115.2.
	_tune({})
	var total: float = _cruise(TOP, 2.0, Vector2.LEFT).ship_screen_offset().length()
	print("measure: lag + aim %.2f screen px (total clamp 115.2)" % total)
	t.check(absf(total - 115.2) < 0.05, "Lag plus aim is clamped to 18%% of the half-width, 115.2 px (measured %.2f)" % total)
	_tune({"cam.total_clamp": 1.0})
	t.control("the total clamp opened", absf(_cruise(TOP, 2.0, Vector2.LEFT).ship_screen_offset().length() - 115.2) >= 0.05)

## Cruises, then stops dead; returns the share of the lag left after 0.30 s and the largest single
## tick of camera movement after the stop.
func _stop(values: Dictionary) -> Dictionary:
	_tune(values)
	var rig: CameraRig = _cruise(TOP, 2.0)
	var start: float = _lag_px(rig)
	var largest: float = 0.0
	var at_030: float = 0.0
	for i: int in range(60):
		var before: Vector2 = rig.focus
		rig.step(1.0 / 60.0, rig.ship, Vector2.ZERO, Vector2.ZERO, TOP)
		largest = maxf(largest, before.distance_to(rig.focus))
		if i == 17: at_030 = _lag_px(rig) / start
	return {"left": at_030, "largest": largest, "final": absf(_lag_px(rig))}

func _recentre() -> void:
	var run: Dictionary = _stop({"cam.aim_on": 0.0})
	print("measure: stop dead: %.1f%% of the lag left at 0.30 s, largest tick move %.2f px, %.3f px left at 1 s" % [float(run.left) * 100.0, float(run.largest), float(run.final)])
	t.check(float(run.left) <= 0.055, "Stopping dead recentres to 5%% in 0.30 s (measured %.1f%%)" % (float(run.left) * 100.0))
	t.check(float(run.largest) <= 16.0 and float(run.final) < 0.5, "The recentre never jumps more than 16 px in a tick (measured %.2f) and settles" % float(run.largest))
	t.control("a 0.001 s recentre, which snaps", float(_stop({"cam.aim_on": 0.0, "cam.recentre_s": 0.001}).largest) > 16.0)

## An accelerate / cruise / dash-turn / stop path sampled at 1.5 s, 1/6 s into the recentre, where
## the lag is unclamped and still moving; `wrong_dt` passes a 60 Hz dt at any rate.
func _path_camera(hz: int, wrong_dt: bool = false) -> Dictionary:
	_tune({})
	var rig: CameraRig = CameraRig.new()
	rig.reset(Vector2.ZERO)
	var dt: float = 1.0 / float(hz)
	var at: Vector2 = Vector2.ZERO
	# Every phase boundary is a multiple of 1/6 s, so it falls on a step at 30, 60, 120 AND 144 Hz: the
	# path is the same path at every rate and only the camera's own maths can differ.
	for i: int in range(roundi(1.5 * hz)):
		var time: float = float(i + 1) * dt - 0.000001
		var velocity: Vector2 = Vector2.ZERO
		if time <= 2.0 / 6.0: velocity = Vector2.RIGHT * TOP * (float(i) + 0.5) * dt / (2.0 / 6.0)
		elif time <= 1.0: velocity = Vector2.RIGHT * TOP
		elif time <= 8.0 / 6.0: velocity = Vector2.DOWN * TOP * 2.5
		at += velocity * dt
		rig.step(1.0 / 60.0 if wrong_dt else dt, at, velocity, Vector2.UP, TOP)
	return {"offset": rig.ship_screen_offset(), "zoom": rig.zoom}

func _rate_independence() -> void:
	var reference: Dictionary = _path_camera(60)
	var worst: float = 0.0
	var worst_zoom: float = 0.0
	for hz: int in [30, 120, 144]:
		var run: Dictionary = _path_camera(hz)
		worst = maxf(worst, Vector2(run.offset).distance_to(reference.offset))
		worst_zoom = maxf(worst_zoom, absf(float(run.zoom) - float(reference.zoom)))
	print("measure: 30/120/144 Hz against 60 Hz: ship screen offset differs by at most %.3f px, zoom by %.5f" % [worst, worst_zoom])
	t.check(worst < 1.0 and worst_zoom < 0.001, "The camera lands in the same place at 30, 60, 120 and 144 Hz (%.3f px, zoom %.5f)" % [worst, worst_zoom])
	var wrong: Dictionary = _path_camera(144, true)
	t.control("a 60 Hz dt used at 144 Hz", Vector2(wrong.offset).distance_to(reference.offset) >= 1.0)

## `cam` is the console's camera shorthand for `tune`: it must resolve to a real GameTuning key.
func _cam_command() -> void:
	var off: Dictionary = DevConsole.parse("cam lag off")
	var get_tau: Dictionary = DevConsole.parse("cam lag_tau")
	var set_hit: Dictionary = DevConsole.parse("cam shake.hit.px 2")
	t.check(off.ok and off.command == "tune" and off.args.key == "cam.lag_on" and float(off.args.value) == 0.0, "cam lag off sets cam.lag_on to 0")
	t.check(get_tau.ok and get_tau.args.action == "get" and get_tau.args.key == "cam.lag_tau", "cam lag_tau reads cam.lag_tau")
	t.check(set_hit.ok and set_hit.args.key == "shake.hit.px" and float(set_hit.args.value) == 2.0, "cam shake.hit.px 2 sets a shake row")
	t.control("an unknown camera key", DevConsole.parse("cam wobble 3").ok == false)
