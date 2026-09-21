extends SceneTree
## P5b: DevConsole.parse is a pure static function, testable headlessly with
## no Control/scene-tree instantiation (spec §4 dev console).
const Harness = preload("res://tests/support/harness.gd")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var h := Harness.new("DEV CONSOLE")

	var tier: Dictionary = DevConsole.parse("tier 3 fire")
	h.check(tier.ok and tier.command == "tier" and tier.args.tier == 3 and tier.args.element == "fire", "tier <n> <element> parses")

	var tier_no_element: Dictionary = DevConsole.parse("tier 5")
	h.check(tier_no_element.ok and tier_no_element.args.element == "", "tier <n> with no element parses")

	var level: Dictionary = DevConsole.parse("level 4")
	h.check(level.ok and level.command == "level" and level.args.level == 4, "level <n> parses")

	var light: Dictionary = DevConsole.parse("light 250")
	h.check(light.ok and light.command == "light" and is_equal_approx(float(light.args.amount), 250.0), "light <n> parses")

	var help: Dictionary = DevConsole.parse("help")
	h.check(help.ok and help.command == "help", "help parses")
	h.check(not DevConsole.parse("help now").ok, "help rejects extra arguments")

	# --- Rejections ---------------------------------------------------------
	h.check(not DevConsole.parse("").ok, "Empty input is rejected")
	h.check(not DevConsole.parse("   ").ok, "Whitespace-only input is rejected")
	h.check(not DevConsole.parse("fly to the moon").ok, "Unknown command is rejected")
	h.check(not DevConsole.parse("tier 7").ok, "tier 7 is refused (above MAX_TIER)")
	h.check(not DevConsole.parse("tier 0").ok, "tier 0 is refused (below range)")
	h.check(not DevConsole.parse("tier abc").ok, "Non-integer tier is rejected")
	h.check(not DevConsole.parse("tier 3 nonsense_element").ok, "Unknown element is rejected")
	h.check(not DevConsole.parse("level 9").ok, "level 9 is refused (above the five levels)")
	h.check(not DevConsole.parse("level 0").ok, "level 0 is refused (below range)")
	h.check(not DevConsole.parse("light -5").ok, "Negative light is rejected")
	h.check(not DevConsole.parse("light abc").ok, "Non-numeric light is rejected")
	h.check(not DevConsole.parse("tier").ok, "tier with no argument is rejected")
	h.check(not DevConsole.parse("level").ok, "level with no argument is rejected")

	# Negative controls: prove each rejection line can actually be satisfied
	# (that the acceptance path is reachable at all, not just permanently ok).
	h.control("tier 6 (the legal boundary) refused", DevConsole.parse("tier 6").ok)
	h.control("level 5 (the legal boundary) refused", DevConsole.parse("level 5").ok)
	h.control("light 0 (the legal boundary) refused", DevConsole.parse("light 0").ok)

	# --- tune (camera and movement spec, P11a) -------------------------------
	var tune_set: Dictionary = DevConsole.parse("tune player_top_speed 500")
	h.check(tune_set.ok and tune_set.command == "tune" and tune_set.args.action == "set" and tune_set.args.key == "player_top_speed" and is_equal_approx(float(tune_set.args.value), 500.0), "tune <key> <value> parses")
	var tune_get: Dictionary = DevConsole.parse("tune cam.lag_tau")
	h.check(tune_get.ok and tune_get.args.action == "get" and tune_get.args.key == "cam.lag_tau", "tune <key> reads a value")
	h.check(DevConsole.parse("tune reset").ok and DevConsole.parse("tune reset").args.action == "reset", "tune reset parses")
	h.check(DevConsole.parse("tune dump").ok and DevConsole.parse("tune dump").args.action == "dump", "tune dump parses")
	h.check(DevConsole.parse("tune enemy_ratio.drone -0.1").ok, "a negative value is a number: the parser passes it (range is the sim's business)")
	h.check(not DevConsole.parse("tune").ok, "tune with no argument is rejected")
	h.check(not DevConsole.parse("tune player_top_sped 500").ok, "A misspelt key is rejected when setting")
	h.check(not DevConsole.parse("tune player_top_sped").ok, "A misspelt key is rejected when reading")
	h.check(not DevConsole.parse("tune player_top_speed fast").ok, "A non-numeric value is rejected")
	h.check(not DevConsole.parse("tune player_top_speed 500 now").ok, "tune rejects a fourth word")
	# The parser cannot know every key by luck: EVERY key in the table must parse, so a key added
	# to GameTuning is reachable from the console without touching the parser.
	var unreachable: Array[String] = []
	for key: String in GameTuning.FEEL_DEFAULTS:
		if not DevConsole.parse("tune %s 1" % key).ok: unreachable.append(key)
	h.check(unreachable.is_empty(), "Every FEEL_DEFAULTS key is settable from the console (unreachable: %s)" % str(unreachable))
	h.control("a real key with a real number refused", DevConsole.parse("tune dash.cooldown_s 1.1").ok)

	h.finish(self)
