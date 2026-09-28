class_name DeathCardScreen
extends UiScreen
## Frictionless death (spec §7.4/§24; moved from main.gd's `_on_death` in M2). M12: a non-modal
## banner over the live world, not a card. It takes no input, blocks nothing and does not pause;
## "SIGNAL LOST" slams in (BANNER_SLAM_SCALE -> 1 over BANNER_SLAM_SECONDS) for the death beat, and
## RunController reboots on its own timer (DEATH_REBOOT_S), when the life's stats follow as a toast
## (`stats_line`). args: {stats} (RunController.death_stats).

const BANNER_SLAM_SCALE: float = 1.15
const BANNER_SLAM_SECONDS: float = 0.09

const BANNER_Y: float = 236.0
const LINE_Y: float = 316.0

var banner: Label
var _line: Label

## M6 rule: the stats line sits under the banner however tall the text scale makes it.
func relayout() -> void:
	_line.position.y = maxf(LINE_Y,BANNER_Y+banner.get_minimum_size().y+2.0)

func build() -> void:
	var stats: Dictionary = args.stats
	# Above the ship (the camera centres it at y 400), clear of its burst.
	banner = centered_label(host,"SIGNAL LOST",Vector2(250,BANNER_Y),Vector2(780,78),56,WHITE)
	banner.theme_type_variation = UiTokens.DISPLAY_LABEL
	_line = centered_label(host,"RING %d · BEST %d" % [int(stats.ring_reached),int(stats.best_ring)],Vector2(250,LINE_Y),Vector2(780,32),UiTokens.TEXT_L,GOLD)
	_line.theme_type_variation = UiTokens.KICKER_LABEL
	for label: Label in [banner,_line]:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE

## The banner slams instead of rising: it is not a menu entering, it is the hit landing.
func motion_items() -> Array:
	var slam: Tween = UiMotion.tween(banner).set_parallel(true)
	banner.pivot_offset = banner.size*0.5
	banner.scale = Vector2.ONE*(1.0 if UiMotion.reduced else BANNER_SLAM_SCALE)
	banner.modulate.a = 0.0
	slam.tween_property(banner,"scale",Vector2.ONE,UiMotion.duration(BANNER_SLAM_SECONDS)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	slam.tween_property(banner,"modulate:a",1.0,UiMotion.duration(BANNER_SLAM_SECONDS,true))
	return super().filter(func(node: Node) -> bool: return node != banner)

## The toast the stats stay up as after the reboot.
static func stats_line(stats: Dictionary) -> String:
	return "SIGNAL LOST · RING %d · BEST %d · %d KILLS · %s" % [int(stats.get("ring_reached",0)),int(stats.get("best_ring",0)),int(stats.get("kills",0)),format_run_time(float(stats.get("time",0.0)))]

static func format_run_time(seconds: float) -> String:
	var total: int = maxi(0,roundi(seconds))
	return "%d:%02d" % [total/60,total%60]
