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

class FakeSound extends RefCounted:
	var cues: Array[String] = []
	var low_light: Array[bool] = []
	func play_cue(cue: String, _params: Dictionary) -> void: cues.append(cue)
	func set_low_light(on: bool) -> void: low_light.append(on)

var calls: Array = []

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var t: RefCounted = Harness.new("FEEL_DIRECTOR")
	_rumble(t)
	_routing(t)
	_damage_numbers(t)
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
	t.check(sound.cues.has("boss_kill"), "an audio kind reaches Soundscape.play_cue (%s)" % [sound.cues])
	t.check(director.post.onset_count == 1, "boss_kill requests one flash (onsets %d)" % director.post.onset_count)
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
