class_name DeathCardScreen
extends UiScreen
## Frictionless death's card (spec §7.4/§24; moved from main.gd's `_on_death` in M2). It neither
## pauses nor takes Escape; main.gd dismisses it on a fresh press or its auto-close timer, both
## read from ScreenRouter's "death" policy. args: {stats} (RunController.death_stats).

func build() -> void:
	var stats: Dictionary = args.stats
	centered_label(host,"SIGNAL LOST",Vector2(250,193),Vector2(780,78),56,WHITE)
	centered_label(host,"RING REACHED %d · BEST %d" % [int(stats.ring_reached),int(stats.best_ring)],Vector2(250,290),Vector2(780,42),28,GOLD)
	centered_label(host,"KILLS %d · TIME %s" % [int(stats.kills),format_run_time(float(stats.time))],Vector2(250,340),Vector2(780,32),18,MUTED)

static func format_run_time(seconds: float) -> String:
	var total: int = maxi(0,roundi(seconds))
	return "%d:%02d" % [total/60,total%60]
