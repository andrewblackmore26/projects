extends SceneTree
## M16: FeelDirector's one mapping from feel_event to rumble / post / FX, scaled by the settings,
## measured through a RECORDING rumble backend (no controller needed). Also the damage-number
## merge rule of CombatFX. Every line has its own negative control.

const Harness = preload("res://tests/support/harness.gd")
const FX = preload("res://scripts/combat/combat_fx.gd")

class FakeApp extends Node:
	var settings: Dictionary = {}
	var combat: CombatWorld
	var sound: Object
	var campaign: Object

class FakeSound extends RefCounted:
	var cues: Array[String] = []
	var params: Array[Dictionary] = []
	var low_light: Array[bool] = []
	func play_cue(cue: String, parameters: Dictionary) -> void:
		cues.append(cue)
		params.append(parameters)
	var stopped: Array[String] = []
	func set_low_light(on: bool) -> void: low_light.append(on)
	func stop_cue(cue: String) -> void: stopped.append(cue)
	func count(cue: String) -> int: return cues.count(cue)

var calls: Array = []

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var t: RefCounted = Harness.new("FEEL_DIRECTOR")
	_rumble(t)
	_routing(t)
	_damage_numbers(t)
	await _cue_map(t)
	_one_hurt(t)
	_slow_mo(t)
	_low_light(t)
	_boss_intro(t)
	_evolve_ready(t)
	await _ui_sounds(t)
	t.finish(self)

func _record(weak: float, strong: float, seconds: float) -> void:
	calls.append([weak, strong, seconds])

const EVENTS: Array[StringName] = [&"player_hit", &"enemy_kill", &"boss_kill", &"dash", &"regression", &"warp_snap"]

func _drive(setting: float) -> int:
	calls.clear()
	var app := FakeApp.new()
	app.settings = {"rumble": setting}
	var director := FeelDirector.new(app, _record)
	director.configure(app.settings)
	for kind: StringName in EVENTS: director.on_feel_event(kind, Vector2.ZERO, 1.0, 0)
	director.free()
	app.free()
	return calls.size()

func _rumble(t: RefCounted) -> void:
	var full: int = _drive(1.0)
	var strongest_full: float = 0.0
	for c: Array in calls: strongest_full = maxf(strongest_full, float(c[1]))
	var half: int = _drive(0.5)
	var strongest_half: float = 0.0
	for c: Array in calls: strongest_half = maxf(strongest_half, float(c[1]))
	var off: int = _drive(0.0)
	print("measure: rumble calls for %d events at setting 1.0/0.5/0.0 = %d/%d/%d; strongest motor %.2f/%.2f" % [EVENTS.size(), full, half, off, strongest_full, strongest_half])
	t.check(off == 0, "rumble setting 0 sends zero vibration calls (got %d)" % off)
	t.control("rumble setting 1 with the same events (%d calls)" % full, full > 0)
	t.check(is_equal_approx(strongest_half, strongest_full * 0.5), "rumble setting 0.5 halves the motor strength (%.2f vs %.2f)" % [strongest_half, strongest_full])
	var unscaled := Rumble.new(_record)
	unscaled.scale = 1.0
	calls.clear()
	unscaled.pulse(0.0, 0.0, 0.2)
	t.check(calls.is_empty(), "a zero-strength pulse sends nothing")
	unscaled.pulse(0.5, 0.5, 0.0)
	t.check(calls.is_empty(), "a zero-length pulse sends nothing")

func _routing(t: RefCounted) -> void:
	var app := FakeApp.new()
	var sound := FakeSound.new()
	app.sound = sound
	app.settings = {"flash_intensity": 1.0, "reduced_motion": false}
	var world := CombatWorld.new()
	app.combat = world
	var director := FeelDirector.new(app, _record)
	director.configure(app.settings)
	director.bind(world)
	world.feel_event.emit(&"player_hit", Vector2(10, 10), 1.0, 0)
	t.check(director.post.hurt_level > 0.9, "player_hit on the player (actor 0) raises the hurt state (%.2f)" % director.post.hurt_level)
	director.post.step(PostFx.HURT_SECONDS + 0.01)
	t.check(director.post.hurt_level == 0.0, "the hurt state is over after %.2f s" % PostFx.HURT_SECONDS)
	world.feel_event.emit(&"player_hit", Vector2(10, 10), 1.0, 7)
	t.control("player_hit reported for actor 7, not the player", director.post.hurt_level == 0.0)
	var before: int = world.fx.live_count()
	world.feel_event.emit(&"pickup_collect", Vector2(40, 40), 1.0, 0)
	t.check(world.fx.live_count() > before, "pickup_collect draws the collect sparkle (%d -> %d slots)" % [before, world.fx.live_count()])
	world.feel_event.emit(&"low_light_enter", Vector2.ZERO, 1.0, 0)
	t.check(director.post.low_light and sound.low_light == [true], "low_light_enter reaches post and Soundscape.set_low_light")
	world.feel_event.emit(&"boss_kill", Vector2.ZERO, 1.0, 0)
	t.check(sound.cues.has("boss_death"), "boss_kill reaches Soundscape.play_cue as its cue, boss_death (%s)" % [sound.cues])
	t.check(director.post.onset_count == 1, "boss_kill requests one flash (onsets %d)" % director.post.onset_count)
	world.feel_event.emit(&"warp_strain", Vector2.ZERO, 0.6, 0)
	world.feel_event.emit(&"warp_release", Vector2.ZERO, 0.6, 0)
	t.check(sound.params[-1].get("strain", -1.0) == 0.6 and sound.stopped == ["warp_strain"], "warp_strain carries its push depth and warp_release cuts it (%s)" % [sound.stopped])
	var unknown: int = director.event_counts.size()
	world.feel_event.emit(&"no_such_kind", Vector2.ZERO, 1.0, 0)
	t.check(director.event_counts.size() == unknown, "an unmapped kind is ignored")
	director.free()
	world.free()
	app.free()

func _damage_numbers(t: RefCounted) -> void:
	var rng := RandomNumberGenerator.new()
	var fx := FX.new()
	fx.emit("damage_number", Vector2(100, 100), Color.WHITE, rng, {"text": "12"})
	fx.update(0.1)
	fx.emit("damage_number", Vector2(104, 96), Color.WHITE, rng, {"text": "5"})
	t.check(fx.live_count() == 1 and fx.text[fx.active_indices[0]] == "17", "two hits 0.10 s apart on one target merge into one number (%d live, '%s')" % [fx.live_count(), fx.text[fx.active_indices[0]]])
	fx.update(0.16)
	fx.emit("damage_number", Vector2(100, 100), Color.WHITE, rng, {"text": "3"})
	t.control("a hit 0.16 s after the last merge (past the 0.15 s window)", fx.live_count() == 2)
	var far := FX.new()
	far.emit("damage_number", Vector2(100, 100), Color.WHITE, rng, {"text": "4"})
	far.emit("damage_number", Vector2(300, 100), Color.WHITE, rng, {"text": "4"})
	t.control("a simultaneous hit on a different target 200 px away", far.live_count() == 2)
	var keyed := FX.new()
	keyed.emit("damage_number", Vector2(100, 100), Color.WHITE, rng, {"text": "4", "target": 3})
	keyed.emit("damage_number", Vector2(100, 100), Color.WHITE, rng, {"text": "4", "target": 5})
	t.check(keyed.live_count() == 2, "an explicit target id keeps two actors' numbers apart even when they overlap")

# --- M16b / M17 wiring ------------------------------------------------------------------------

## A real CombatWorld (player set up, one sector) bound to a director that reports to `sound`.
func _rig(sound: FakeSound) -> Array:
	var app := FakeApp.new()
	app.sound = sound
	var world := CombatWorld.new()
	world.setup_player("neutral", 1, 40, [], GameTuning.ARENA_CENTER)
	world.sector = {"id": "a"}
	app.combat = world
	var director := FeelDirector.new(app, _record)
	director.bind(world)
	return [app, world, director]

func _free(rig: Array) -> void:
	rig[2].free()
	rig[1].free()
	rig[0].free()

## Every StringName literal on a line of scripts/ that emits a feel_event or names the kind it
## emits (`kill_kind`, `part_kind`), so a new emit site shows up here without editing this test.
func _emitted_kinds() -> Array:
	var pattern := RegEx.create_from_string("&\"([a-z_]+)\"")
	var kinds: Array = []
	for path: String in _scripts("res://scripts"):
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			if not ("feel_event.emit" in line or "_kind: StringName=" in line): continue
			for found: RegExMatch in pattern.search_all(line):
				if not StringName(found.get_string(1)) in kinds: kinds.append(StringName(found.get_string(1)))
	return kinds

func _scripts(dir: String) -> Array[String]:
	var result: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"): result.append(dir + "/" + file)
	for sub: String in DirAccess.get_directories_at(dir): result.append_array(_scripts(dir + "/" + sub))
	return result

func _cue_map(t: RefCounted) -> void:
	var sound := Soundscape.new()
	root.add_child(sound)
	await process_frame
	var kinds: Array = _emitted_kinds()
	print("measure: %d feel_event kinds emitted under scripts/: %s" % [kinds.size(), kinds])
	t.check(kinds.size() >= 14 and kinds.has(&"boss_engage") and kinds.has(&"low_light_exit"), "the source scan finds the emit sites, boss_engage and the low-light pair included (%d kinds)" % kinds.size())
	var missing: Array = FeelDirector.unmapped(kinds)
	t.check(missing.is_empty(), "every kind the sim emits has a FeelDirector row (unmapped: %s)" % [missing])
	t.control("an emitted kind with no row (no_such_kind) is reported", FeelDirector.unmapped(kinds + [&"no_such_kind"]).has(&"no_such_kind"))
	var cues: Array[String] = [FeelDirector.EVOLVE_READY_CUE, "combo_tier", "ui_move", "ui_confirm", "ui_back", "ui_slider_tick"]
	var mapped: int = 0
	for kind: StringName in FeelDirector.MAP:
		if FeelDirector.cue_for(kind) != "":
			cues.append(FeelDirector.cue_for(kind))
			mapped += 1
	var silent: Array[String] = []
	for cue: String in cues:
		if sound.stream_for(cue, 0) == null: silent.append(cue)
	print("measure: %d of %d rows sound a cue; %d distinct cues checked against Soundscape.stream_for" % [mapped, FeelDirector.MAP.size(), cues.size()])
	t.check(silent.is_empty(), "every cue a row plays (and evolve_ready, combo_tier, the UI four) has a stream (silent: %s)" % [silent])
	t.control("the pre-wiring cue name boss_kill, a kind rather than a cue, has no stream", sound.stream_for("boss_kill", 0) == null)
	sound.shutdown()
	sound.free()

func _one_hurt(t: RefCounted) -> void:
	var sound := FakeSound.new()
	var rig: Array = _rig(sound)
	var world: CombatWorld = rig[1]
	world._damage_actor(world.player, 5.0, 99)
	var hits: int = int(rig[2].event_counts.get(&"player_hit", 0))
	var single: int = sound.count("hurt")
	t.check(hits == 1 and single == 1, "one player hit sounds exactly one hurt cue (%d hits, %d cues)" % [hits, single])
	_free(rig)
	# The only other place that ever played it: main.gd's per-frame "hp dropped" check.
	var pattern := RegEx.create_from_string("play(_cue|_at)?\\(\\s*\"hurt\"")
	var callers: Array[String] = []
	for path: String in _scripts("res://scripts"):
		if path.ends_with("soundscape.gd"): continue
		if pattern.search(FileAccess.get_file_as_string(path)) != null: callers.append(path)
	t.check(callers.is_empty(), "no script plays the hurt cue by name; FeelDirector's row is the one path (%s)" % [callers])
	t.control("the scan sees main.gd's removed line", pattern.search("\t\t\t\tsound.play(\"hurt\")") != null)
	# Control: main.gd's path restored beside the director gives two cues for the one hit.
	var doubled := FakeSound.new()
	var again: Array = _rig(doubled)
	var last_hp: float = again[1].player_hp
	again[1]._damage_actor(again[1].player, 5.0, 99)
	if again[1].player_hp < last_hp: doubled.play_cue("hurt", {})
	print("measure: hurt cues per hit = %d (control, main.gd's path restored: %d)" % [single, doubled.count("hurt")])
	t.control("main.gd's hp-drop hurt restored (%d cues)" % doubled.count("hurt"), doubled.count("hurt") == 2)
	_free(again)

func _slow_mo(t: RefCounted) -> void:
	var rig: Array = _rig(FakeSound.new())
	var world: CombatWorld = rig[1]
	var director: FeelDirector = rig[2]
	world.visuals_enabled = false
	root.add_child(world) # stepped below: _ready wires the broadphase
	world.set_physics_process(false)
	# Review fix 5: the slow motion runs on the world's physics steps (60 Hz here), not on the render
	# step, so these times are counted in physics steps.
	world.feel_event.emit(&"elite_kill", Vector2.ZERO, 1.0, 5)
	var during: float = world.time_scale()
	_physics(world, director, 6)
	var held: float = world.time_scale()
	_physics(world, director, 9)
	var easing: float = world.time_scale()
	_physics(world, director, 7)
	var after: float = world.time_scale()
	print("measure: elite kill time scale %.3f -> %.3f at 0.10 s -> %.3f at 0.25 s -> %.3f at 0.37 s" % [during, held, easing, after])
	t.check(is_equal_approx(during, 0.35) and is_equal_approx(held, 0.35), "an elite kill slows the sim to 0.35 and holds it (%.3f, %.3f)" % [during, held])
	t.check(easing > 0.35 and easing < 1.0, "the last 40%% eases back toward 1 (%.3f at 0.25 s)" % easing)
	t.check(after == 1.0 and director.slow_mo_remaining == 0.0, "the request is released after 0.35 s of physics steps (%.3f)" % after)
	world.feel_event.emit(&"boss_kill", Vector2.ZERO, 1.0, 5)
	var boss: float = world.time_scale()
	_physics(world, director, 30)
	var boss_mid: float = world.time_scale()
	_physics(world, director, 19)
	t.check(is_equal_approx(boss, 0.25) and boss_mid < 1.0 and world.time_scale() == 1.0, "a boss kill runs longer and lower: %.2f, still %.3f at 0.5 s, released by 0.82 s" % [boss, boss_mid])
	world.feel_event.emit(&"boss_kill", Vector2.ZERO, 1.0, 5)
	world.player_died.emit()
	t.check(world.time_scale() == 1.0 and director.slow_mo_remaining == 0.0, "death releases a slow motion in progress (%.3f)" % world.time_scale())
	world.feel_event.emit(&"elite_kill", Vector2.ZERO, 1.0, 5)
	world.start_sector({"id": "b"})
	t.check(world.time_scale() == 1.0, "a sector change releases it (%.3f)" % world.time_scale())
	world.feel_event.emit(&"elite_kill", Vector2.ZERO, 1.0, 5)
	director.bind(null)
	t.check(world.time_scale() == 1.0, "letting go of the world releases it (%.3f)" % world.time_scale())
	director.bind(world)
	director.slow_mo_release_enabled = false
	world.feel_event.emit(&"elite_kill", Vector2.ZERO, 1.0, 5)
	_physics(world, director, 60)
	t.control("the timer's release removed: the scale stays at %.3f after 1 s" % world.time_scale(), world.time_scale() != 1.0)
	world._clear_encounter()
	_free(rig)

func _physics(world: CombatWorld, director: FeelDirector, steps: int) -> void:
	for i: int in range(steps): world._physics_process(1.0 / 60.0)
	director.step(0.0)

func _low_light(t: RefCounted) -> void:
	var fractions: Array[float] = [0.40, 0.14, 0.16, 0.14, 0.16, 0.14, 0.16, 0.40]
	var sound := FakeSound.new()
	var rig: Array = _rig(sound)
	var counts: Array[int] = _drive_light(rig[1], fractions)
	print("measure: light oscillating 14%%/16%% of capacity -> %d enters, %d exits (enter < %.2f, exit > %.2f)" % [counts[0], counts[1], rig[1].low_light_enter_fraction, rig[1].low_light_exit_fraction])
	t.check(counts == [1, 1], "hysteresis: one enter and one exit across three dips (%s)" % [counts])
	t.check(sound.low_light == [true, false] and not rig[2].post.low_light, "the pair reaches Soundscape.set_low_light and the post state (%s)" % [sound.low_light])
	_free(rig)
	var flicker: Array = _rig(FakeSound.new())
	flicker[1].low_light_exit_fraction = flicker[1].low_light_enter_fraction
	var flickered: Array[int] = _drive_light(flicker[1], fractions)
	t.control("hysteresis removed: %d enters for the same light" % flickered[0], flickered[0] > 1)
	_free(flicker)

func _drive_light(world: CombatWorld, fractions: Array[float]) -> Array[int]:
	var counts: Array[int] = [0, 0]
	world.feel_event.connect(func(kind: StringName, _at: Vector2, _magnitude: float, _id: int) -> void:
		if kind == &"low_light_enter": counts[0] += 1
		elif kind == &"low_light_exit": counts[1] += 1)
	for fraction: float in fractions:
		world.light_total = world.player_max_hp * fraction
		world._update_feel_states()
	return counts

func _boss_intro(t: RefCounted) -> void:
	var sound := FakeSound.new()
	var rig: Array = _rig(sound)
	var world: CombatWorld = rig[1]
	var director: FeelDirector = rig[2]
	rig[0].campaign = CampaignState.new()
	# The sim's side: one boss_engage per rival, and only in range.
	var engages: Array[int] = [0]
	world.feel_event.connect(func(kind: StringName, _at: Vector2, _magnitude: float, _id: int) -> void:
		if kind == &"boss_engage": engages[0] += 1)
	var far: Dictionary = {"id": 8, "rival": true, "dead": false, "element": "void", "pos": world.player.pos + Vector2(CombatWorld.BOSS_ENGAGE_RANGE + 400.0, 0.0)}
	world.enemies.append(far)
	world._update_feel_states()
	t.control("a rival %.0f px beyond range does not engage (%d)" % [400.0, engages[0]], engages[0] == 0)
	var boss: Dictionary = {"id": 5, "rival": true, "dead": false, "element": "fire", "pos": world.player.pos + Vector2(300.0, 0.0)}
	world.enemies.append(boss)
	world.actors_by_id[5] = boss
	for index: int in range(3): world._update_feel_states()
	t.check(engages[0] == 1, "a rival 300 px away engages once over three ticks (%d)" % engages[0])
	boss.erase("engaged")
	world._update_feel_states()
	t.control("the per-actor engaged mark removed: it engages again (%d)" % engages[0], engages[0] == 2)
	world.enemies.clear()
	# The director's side: the card once per rival per campaign, the stinger with it.
	var shown: int = director.boss_intro.shown_count
	t.check(shown == 1 and director.boss_intro.rival_name == "PYRE" and director.boss_intro.active(), "the first engagement shows the card, PYRE for fire (%d shown)" % shown)
	t.check(sound.count("boss_engage") == 1, "the stinger plays with the card and not with the repeat (%d)" % sound.count("boss_engage"))
	t.check(bool(rig[0].campaign.story_flags.get("boss_intro_L1_fire", false)), "the shown flag is in the campaign's story_flags")
	world.actors_by_id[8] = far
	world.feel_event.emit(&"boss_engage", far.pos, 1.0, 8)
	t.check(director.boss_intro.shown_count == 2 and director.boss_intro.rival_name == "NOX", "another rival gets its own card (%d shown)" % director.boss_intro.shown_count)
	director.step(0.5)
	var held: bool = director.boss_intro.active()
	world.sector = {"id": "c"}
	director.step(0.0)
	t.check(held and not director.boss_intro.active(), "the card holds within its node and comes down when the run leaves it")
	var restored := CampaignState.new()
	restored.from_dict(rig[0].campaign.to_dict())
	var reloaded: Array = _rig(FakeSound.new())
	reloaded[0].campaign = restored
	reloaded[1].actors_by_id[5] = boss
	reloaded[1].feel_event.emit(&"boss_engage", Vector2.ZERO, 1.0, 5)
	t.check(reloaded[2].boss_intro.shown_count == 0, "after a save and load the same rival's card stays shown (%d)" % reloaded[2].boss_intro.shown_count)
	_free(reloaded)
	director.boss_intro_once = false
	world.feel_event.emit(&"boss_engage", Vector2.ZERO, 1.0, 5)
	t.control("the once-per-boss rule off: the card shows again (%d shown)" % director.boss_intro.shown_count, director.boss_intro.shown_count == 3)
	_free(rig)
	_boss_card_timeline(t)

func _boss_card_timeline(t: RefCounted) -> void:
	var card := BossIntro.new()
	card.present("PYRE", "RIVAL SIGNAL", "FIRE DIALECT", Color.RED)
	var full: float = roundf(800.0 * BossIntro.BAR_FRACTION)
	card.step(0.10)
	var sliding: float = card.top_bar.offset_bottom
	card.step(0.20)
	var closed: float = card.top_bar.offset_bottom
	var first_letters: int = card.name_label.visible_characters
	card.step(0.40)
	var typed: int = card.name_label.visible_characters
	var filled: float = card.bar_fill.size.x
	card.step(2.0)
	var leaving: float = card.top_bar.offset_bottom
	card.step(0.5)
	print("measure: boss card bars %.1f/%.1f/%.1f px at 0.1/0.3/2.7 s (full %.0f); letters %d at 0.3 s, %d at 0.7 s; fill %.0f px" % [sliding, closed, leaving, full, first_letters, typed, filled])
	t.check(sliding > 0.0 and sliding < full and is_equal_approx(closed, full), "the letterbox closes over %.2f s (%.1f then %.1f px)" % [BossIntro.BARS_IN, sliding, closed])
	t.check(first_letters >= 1 and first_letters < 4 and typed == 4, "the name types in (%d letters at 0.3 s, %d at 0.7 s)" % [first_letters, typed])
	t.check(leaving < full and not card.active() and not card.visible, "it clears and hides itself after %.2f s" % BossIntro.DURATION)
	var still := BossIntro.new()
	still.reduced_motion = true
	still.present("PYRE", "RIVAL SIGNAL", "FIRE DIALECT", Color.RED)
	still.step(0.05)
	t.check(is_equal_approx(still.top_bar.offset_bottom, full) and still.name_label.visible_characters == 4 and is_equal_approx(still.root.modulate.a, 0.25), "reduced motion: no slide, no typing, a fade only (alpha %.2f)" % still.root.modulate.a)
	t.control("the same moment with motion on slides and types (%.1f px, %d letters)" % [sliding, 0], not is_equal_approx(sliding, full))
	card.free()
	still.free()

func _evolve_ready(t: RefCounted) -> void:
	var sound := FakeSound.new()
	var rig: Array = _rig(sound)
	var world: CombatWorld = rig[1]
	var director: FeelDirector = rig[2]
	var threshold: float = float(EvolutionRules.threshold(world.player_tier))
	for light: float in [threshold - 1.0, threshold + 1.0, threshold + 5.0, threshold + 9.0]:
		world.light_total = light
		director.step(0.016)
	t.check(sound.count("evolve_ready") == 1, "crossing the evolution threshold sounds evolve_ready once over three frames above it (%d)" % sound.count("evolve_ready"))
	world.light_total = threshold - 1.0
	director.step(0.016)
	world.light_total = threshold + 1.0
	director.step(0.016)
	t.check(sound.count("evolve_ready") == 2, "falling back and crossing again re-arms it (%d)" % sound.count("evolve_ready"))
	for index: int in range(3):
		director._evolve_ready = false
		director.step(0.016)
	t.control("the edge memory cleared every frame: %d cues" % sound.count("evolve_ready"), sound.count("evolve_ready") > 2)
	_free(rig)

## UiScreen.wire_sounds: focus moves sound ui_move (not the focus a screen grabs as it opens), and a
## dragged slider ticks at most once per SLIDER_TICK_SECONDS.
func _ui_sounds(t: RefCounted) -> void:
	var app := FakeApp.new()
	var sound := FakeSound.new()
	app.sound = sound
	root.add_child(app)
	var host := Control.new()
	app.add_child(host)
	var first := Button.new()
	var second := Button.new()
	var slider := HSlider.new()
	slider.max_value = 100.0
	for control: Control in [first, second, slider]: host.add_child(control)
	UiScreen.wire_sounds(host, app)
	UiScreen.wire_sounds(host, app)
	first.grab_focus()
	var opening: int = sound.count("ui_move")
	await process_frame
	second.grab_focus()
	var moved: int = sound.count("ui_move")
	for value: float in [10.0, 11.0, 12.0]: slider.value = value
	var burst: int = sound.count("ui_slider_tick")
	var waited: int = Time.get_ticks_msec() + int(UiScreen.SLIDER_TICK_SECONDS * 1000.0) + 10
	while Time.get_ticks_msec() < waited: await process_frame
	slider.value = 20.0
	var later: int = sound.count("ui_slider_tick")
	print("measure: ui_move on open %d, after a move %d; slider ticks for a 3-step burst %d, after %.2f s %d" % [opening, moved, burst, UiScreen.SLIDER_TICK_SECONDS, later])
	t.check(opening == 0 and moved == 1, "the opening focus is silent and a focus move sounds ui_move once, though wired twice (%d, %d)" % [opening, moved])
	t.check(burst == 1 and later == 2, "a slider burst ticks once, and again after the throttle window (%d, %d)" % [burst, later])
	var loud := Button.new()
	host.add_child(loud)
	UiScreen.wire_sounds(loud, app)
	await process_frame
	var before: int = sound.count("ui_move")
	loud.grab_focus()
	first.grab_focus()
	t.control("a control wired a frame earlier is not treated as opening (%d moves)" % (sound.count("ui_move") - before), sound.count("ui_move") - before == 2)
	app.queue_free()
