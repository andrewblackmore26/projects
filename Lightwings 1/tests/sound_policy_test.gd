extends SceneTree

const Harness = preload("res://tests/support/harness.gd")
var suite = Harness.new("QUIET AUDIO")

class ClockedSound extends Soundscape:
	var seconds: float = 10.0
	func _now_seconds() -> float: return seconds

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var sound := ClockedSound.new()
	sound.configure({"volume": 0.35, "music": false})
	root.add_child(sound)
	sound.set_process(false)
	suite.check(is_equal_approx(sound.volume, 0.35) and not sound.music_enabled, "Legacy master and music preferences survive")
	suite.check(is_equal_approx(sound.effects_volume, 0.55) and is_equal_approx(sound.interface_volume, 0.45) and is_equal_approx(sound.ambience_volume, 0.15), "Legacy settings receive quiet category defaults")
	suite.check(not sound.music.playing and sound.music.volume_linear == 0.0, "Saved music mute is honored before startup")
	var preferences: Dictionary = {"volume":0.4,"music":false,"effects_volume":0.2,"interface_volume":0.3,"ambience_volume":0.1,"pickup_cues":true}
	var config := ConfigFile.new()
	for key: String in preferences: config.set_value("device", key, preferences[key])
	var restored := ConfigFile.new()
	suite.check(restored.parse(config.encode_to_text()) == OK, "Device audio settings serialize")
	var loaded: Dictionary = {}
	for key: String in restored.get_section_keys("device"): loaded[key] = restored.get_value("device", key)
	sound.configure(loaded)
	suite.check(is_equal_approx(sound.volume, 0.4) and is_equal_approx(sound.effects_volume, 0.2) and is_equal_approx(sound.interface_volume, 0.3) and is_equal_approx(sound.ambience_volume, 0.1) and sound.pickup_cues and not sound.music_enabled, "All new and legacy audio settings round-trip")
	sound.configure({"volume":0.35,"music":false})
	suite.check(not sound.play("pickup"), "Routine pickups are silent by default")
	sound.configure({"music": false, "pickup_cues": true})
	suite.check(sound.play("pickup"), "Optional pickup feedback starts")
	sound.seconds += 0.1
	suite.check(not sound.play("pickup"), "Collection burst is aggregated")
	sound.seconds = 10.249
	suite.check(not sound.play("pickup"), "Pickup remains limited before 250ms")
	sound.seconds = 10.25
	suite.check(sound.play("pickup"), "Pickup can play at 250ms")

	sound.seconds = 20.0
	sound.mix_snapshot()
	for cue: String in ["fire", "lightning", "void", "corruption"]:
		suite.check(sound.play_at(cue, Vector2.ZERO, "enemy"), "Enemy activation accepted: " + cue)
	suite.check(not sound.play_at("plasma", Vector2.ZERO, "enemy"), "Enemy fire cannot exceed four voices")
	for cue: String in ["fire", "plasma", "ability", "void"]:
		suite.check(sound.play(cue), "Player activation accepted: " + cue)
	suite.check(sound.mix_snapshot().size() == 8, "Combined positional/nonpositional effects share eight slots")
	suite.check(not sound.play("lightning", 10), "Equal-priority excess fire is dropped")
	suite.check(sound.play("hurt"), "Damage preempts lower-priority fire")
	var snapshot: Array[Dictionary] = sound.mix_snapshot()
	var enemy_count: int = 0
	var hurt_count: int = 0
	for entry: Dictionary in snapshot:
		if entry.source == "enemy": enemy_count += 1
		if entry.cue == "hurt": hurt_count += 1
	suite.check(snapshot.size() == 8 and enemy_count == 3 and hurt_count == 1, "Priority preemption preserves total cap and critical cue")
	suite.check(sound.play("click"), "Interface feedback has a separate bounded category")
	suite.check(not sound.play("click"), "Duplicate activation in a frame is suppressed")
	suite.check(not sound.play_at("plasma", Vector2(1400, 0), "enemy"), "Inaudible distant fire does not consume voices")

	sound.seconds = 30.0
	sound.mix_snapshot()
	suite.check(sound.play("clear"), "Long cue available to test active gain")
	sound.configure({"volume": 0.2, "music": false, "effects_volume": 0.1})
	snapshot = sound.mix_snapshot()
	suite.check(snapshot.size() == 1 and is_equal_approx(float(snapshot[0].gain), 0.0064), "Changing gain immediately updates an active cue")
	sound.effects_volume = 0.0
	sound.apply_settings()
	suite.check(sound.mix_snapshot().is_empty() and not sound.play("hurt"), "Category zero is true silence")
	sound.configure({"volume": 0.0, "music": true})
	suite.check(not sound.music.playing and not sound.play("click") and not sound.play_at("fire", Vector2.ZERO, "player"), "Master zero silences all categories")
	sound.configure({"volume": 0.7, "music": false})
	suite.check(sound.mix_snapshot().is_empty(), "Unmuting cannot replay discarded cues")
	sound.configure({"volume":0.5,"music":true,"ambience_volume":0.1})
	suite.check(sound.music.playing and sound.music.volume_linear == 0.0, "New ambience playback begins silently")
	sound._process(2.0)
	suite.check(is_equal_approx(sound.music.volume_linear, 0.0425), "Startup fade reaches the saved ambience mix")
	sound.configure({"volume":0.5,"music":true,"ambience_volume":0.4})
	suite.check(is_equal_approx(sound.music.volume_linear, 0.17), "Raising ambience applies to active playback immediately")
	sound.configure({"volume":0.8,"music":true,"ambience_volume":0.4})
	suite.check(is_equal_approx(sound.music.volume_linear, 0.272), "Raising master applies to active ambience immediately")
	sound.configure({"volume":0.5,"music":true,"ambience_volume":0.1})
	suite.check(is_equal_approx(sound.music.volume_linear, 0.0425), "Lowering the mix applies to active ambience immediately")
	sound.set_context("pause")
	sound.apply_settings()
	suite.check(is_equal_approx(sound.music.volume_linear, 0.0425), "Context changes and unrelated settings preserve the intentional transition fade")
	sound._process(1.0)
	suite.check(is_equal_approx(sound.music.volume_linear, 0.0325), "Pause ambience reaches its quieter context level")
	sound.configure({"volume":0.5,"music":true,"ambience_volume":0.0})
	suite.check(not sound.music.playing and sound.music.volume_linear == 0.0, "Ambience zero stops active playback immediately")

	var previous: PackedByteArray = Soundscape.make_clip("fire", 0).data
	suite.check(previous != Soundscape.make_clip("fire", 1).data, "Repeated feedback has deterministic variation")
	for cue: String in Soundscape.CUES:
		var bytes: PackedByteArray = Soundscape.make_clip(cue).data
		var peak: int = 0
		var jump: int = 0
		for offset: int in range(0, bytes.size(), 2):
			peak = maxi(peak, absi(bytes.decode_s16(offset)))
			if offset > 0: jump = maxi(jump, absi(bytes.decode_s16(offset) - bytes.decode_s16(offset - 2)))
		suite.check(bytes.decode_s16(0) == 0 and bytes.decode_s16(bytes.size() - 2) == 0 and peak < 24000 and jump < 4000, cue + " has headroom and rounded, continuous endpoints")
	var ambient: PackedByteArray = Soundscape.ambient().data
	var silent: int = 0
	for offset: int in range(0, ambient.size(), 2):
		if ambient.decode_s16(offset) == 0: silent += 1
	suite.check(silent > ambient.size() / 4 and ambient.decode_s16(0) == 0 and ambient.decode_s16(ambient.size() - 2) == 0, "Ambient loop has long silent spaces and seamless endpoints")
	sound.shutdown()
	sound.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	suite.finish(self)
