class_name DeathCardScreen
extends UiScreen
## Frictionless death (spec §7.4/§24; moved from main.gd's `_on_death` in M2). M12: a non-modal
## banner over the live world, not a card. It takes no input, blocks nothing and does not pause;
## "SIGNAL LOST" slams in (BANNER_SLAM_SCALE -> 1 over BANNER_SLAM_SECONDS) for the death beat, and
## RunController reboots on its own timer (DEATH_REBOOT_S), when the life's stats follow as a toast
## (`stats_line`). args: {stats} (RunController.death_stats).
##
## M19 review: the stats are data, so neutral ink (gold is focus only), and a ring sweeps once
## round the ship's burst over the reboot timer, REBOOTING under it, so the reboot that follows with
## no press reads as intended rather than as a glitch. The ring reads RunController's own clock
## (`death_elapsed / death_reboot_s`) and sits on the ship's screen position (the canvas centre when
## there is no world).

const BANNER_SLAM_SCALE: float = 1.15
const BANNER_SLAM_SECONDS: float = 0.09

const BANNER_Y: float = 236.0
const LINE_Y: float = 316.0
const RING_SIZE: float = 84.0
const LABEL_GAP: float = 6.0

var banner: Label
var _line: Label
var _reboot: Control
var _ring: RebootRing
var _reboot_label: Label

## The reboot's progress round the burst: a faint track, and the player's blue sweeping clockwise
## from the top with a bright head.
class RebootRing extends Control:
	var progress: float = 0.0
	func _draw() -> void:
		var middle: Vector2 = size * 0.5
		var radius: float = size.x * 0.5 - 3.0
		draw_arc(middle, radius, 0.0, TAU, 64, Color(UiTokens.PLAYER, 0.18), 2.0, true)
		if progress <= 0.0: return
		var end: float = -PI * 0.5 + TAU * clampf(progress, 0.0, 1.0)
		draw_arc(middle, radius, -PI * 0.5, end, 64, UiTokens.PLAYER, 2.5, true)
		draw_circle(middle + Vector2.from_angle(end) * radius, 3.0, Color.WHITE)

## M6 rule: the stats line sits under the banner however tall the text scale makes it. The ring is
## centred on the ship, REBOOTING under it.
func relayout() -> void:
	_line.position.y = maxf(LINE_Y,BANNER_Y+banner.get_minimum_size().y+2.0)
	UiLayout.hug(_reboot_label)
	_reboot.size = Vector2(maxf(RING_SIZE,_reboot_label.size.x),RING_SIZE+LABEL_GAP+_reboot_label.size.y)
	_ring.position = Vector2((_reboot.size.x-RING_SIZE)*0.5,0.0)
	_reboot_label.position = Vector2((_reboot.size.x-_reboot_label.size.x)*0.5,RING_SIZE+LABEL_GAP)
	_place_reboot()

## The ring's centre on the ship (canvas px), or the canvas centre with no world on screen.
func _place_reboot() -> void:
	var at := Vector2(640.0,400.0)
	var compositor: CombatCompositor = app.get("compositor") as CombatCompositor if is_instance_valid(app) else null
	var combat: CombatWorld = app.get("combat") as CombatWorld if is_instance_valid(app) else null
	if is_instance_valid(compositor) and is_instance_valid(combat) and host.is_inside_tree():
		var screen: Vector2 = compositor.get_global_transform_with_canvas()*compositor.world_to_screen(combat.player_position)
		at = host.get_global_transform_with_canvas().affine_inverse()*screen
	_reboot.position = at-Vector2(_reboot.size.x*0.5,RING_SIZE*0.5)

func build() -> void:
	var stats: Dictionary = args.stats
	# Above the ship (the camera centres it at y 400), clear of its burst.
	banner = centered_label(host,"SIGNAL LOST",Vector2(250,BANNER_Y),Vector2(780,78),56,WHITE)
	banner.theme_type_variation = UiTokens.DISPLAY_LABEL
	_line = centered_label(host,ring_line(stats),Vector2(250,LINE_Y),Vector2(780,32),UiTokens.TEXT_L,UiTokens.INK_MUTED)
	_line.theme_type_variation = UiTokens.KICKER_LABEL
	for label: Label in [banner,_line]:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reboot = Control.new()
	_reboot.name = "Reboot"
	_reboot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_reboot)
	_ring = RebootRing.new()
	_ring.name = "RebootRing"
	_ring.size = Vector2(RING_SIZE,RING_SIZE)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reboot.add_child(_ring)
	_reboot_label = UiKit.label(_reboot,"REBOOTING",Vector2.ZERO,Vector2.ZERO,UiTokens.TEXT_XS,UiTokens.PLAYER)
	_reboot_label.theme_type_variation = UiTokens.KICKER_LABEL
	tick(0.0)

## "REACHED RING 2 · BEST 3" (the HUD's own ring numbering: the origin is ring 0).
static func ring_line(stats: Dictionary) -> String:
	return "REACHED RING %d  ·  BEST %d" % [int(stats.get("ring_reached",0)),int(stats.get("best_ring",0))]

## The ring follows the reboot timer (real time, ScreenRouter.tick).
func tick(_delta: float) -> void:
	var run: Object = app.get("run_controller") if is_instance_valid(app) else null
	if run == null or not is_instance_valid(_ring): return
	var elapsed: float = float(run.get("death_elapsed"))
	var total: float = maxf(0.001,float(run.get("death_reboot_s")))
	var progress: float = clampf(elapsed/total,0.0,1.0) if elapsed >= 0.0 else 0.0
	_place_reboot()
	if not is_equal_approx(progress,_ring.progress):
		_ring.progress = progress
		_ring.queue_redraw()

## The banner slams instead of rising: it is not a menu entering, it is the hit landing.
func motion_items() -> Array:
	var slam: Tween = UiMotion.tween(banner).set_parallel(true)
	banner.pivot_offset = banner.size*0.5
	banner.scale = Vector2.ONE*(1.0 if UiMotion.reduced else BANNER_SLAM_SCALE)
	banner.modulate.a = 0.0
	slam.tween_property(banner,"scale",Vector2.ONE,UiMotion.duration(BANNER_SLAM_SECONDS)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	slam.tween_property(banner,"modulate:a",1.0,UiMotion.duration(BANNER_SLAM_SECONDS,true))
	# The ring follows the ship every tick, so it fades in without the entrance's rise (whose tween
	# would hold it at the position it had when the screen was built).
	_reboot.modulate.a = 0.0
	UiMotion.tween(_reboot).tween_property(_reboot,"modulate:a",1.0,UiMotion.duration(UiTokens.FAST,true))
	return super().filter(func(node: Node) -> bool: return node != banner and node != _reboot)

## The toast the stats stay up as after the reboot.
static func stats_line(stats: Dictionary) -> String:
	return "SIGNAL LOST · RING %d · BEST %d · %d KILLS · %s" % [int(stats.get("ring_reached",0)),int(stats.get("best_ring",0)),int(stats.get("kills",0)),format_run_time(float(stats.get("time",0.0)))]

static func format_run_time(seconds: float) -> String:
	var total: int = maxi(0,roundi(seconds))
	return "%d:%02d" % [total/60,total%60]
