extends SceneTree

const Harness = preload("res://tests/support/harness.gd")
var suite = Harness.new("QUIET AUDIO")

## Every cue gameplay may request (M17). Each must resolve to a stream.
const CUE_LIST: Array[String] = ["ui_move", "ui_confirm", "ui_back", "ui_error", "ui_slider_tick", "dash", "dash_ready", "warp_strain", "warp_snap", "warp_rush", "warp_arrive", "combo_step", "combo_tier", "combo_break", "boss_engage", "boss_phase", "boss_death", "evolve_ready", "evolve_pick", "evolve_assemble", "death", "reboot", "level_complete", "pickup", "hurt", "fire", "lightning", "void", "corruption", "plasma", "ability"]
const CEILING: float = 0.8912509  # -1 dBFS
## Per-cue RMS band at the default mix, dBFS over the cue's own length. Measured M17: -40.6 .. -29.4
## (boss_phase lowest, level_complete highest); the band keeps ~5 dB either side and a +12 dB (x4)
## error must leave it.
const RMS_LOW_DB: float = -46.0
const RMS_HIGH_DB: float = -24.0
const WEAPONS: Array[String] = ["fire", "lightning", "void", "corruption", "plasma", "ability", "hurt", "dash"]

class ClockedSound extends Soundscape:
	var seconds: float = 10.0
	func _now_seconds() -> float: return seconds

func _initialize() -> void:
	_run.call_deferred()

func _bus_db(bus: String) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))

func _bus_matches(bus: String, linear: float) -> bool:
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0: return false
	if linear <= 0.0: return AudioServer.is_bus_mute(index)
	return not AudioServer.is_bus_mute(index) and absf(AudioServer.get_bus_volume_db(index) - linear_to_db(linear)) < 0.01

func _effect(bus: String, type: String) -> AudioEffect:
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0: return null
	for effect: int in range(AudioServer.get_bus_effect_count(index)):
		if AudioServer.get_bus_effect(index, effect).is_class(type): return AudioServer.get_bus_effect(index, effect)
	return null

func _peak(samples: PackedFloat32Array, gain: float) -> float:
	var peak: float = 0.0
	for value: float in samples: peak = maxf(peak, absf(value * gain))
	return peak

func _rms_db(samples: PackedFloat32Array, gain: float) -> float:
	var energy: float = 0.0
	for value: float in samples: energy += value * value
	return linear_to_db(maxf(sqrt(energy / maxf(1.0, samples.size())) * gain, 0.0000001))

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

	# Buses (default_bus_layout.tres) and the slider -> bus dB mapping.
	for bus: String in ["Master", "Music", "SFX", "UI"]:
		suite.check(AudioServer.get_bus_index(bus) >= 0, "Bus exists: " + bus)
	for bus: String in ["Music", "SFX", "UI"]:
		suite.check(AudioServer.get_bus_send(AudioServer.get_bus_index(bus)) == &"Master", bus + " sends to Master")
	var limiter := _effect("Master", "AudioEffectHardLimiter") as AudioEffectHardLimiter
	suite.check(limiter != null and is_equal_approx(limiter.ceiling_db, -1.0), "Master ends in a -1 dB hard limiter")
	var last_master: int = AudioServer.get_bus_effect_count(0) - 1
	suite.check(last_master >= 0 and AudioServer.get_bus_effect(0, last_master) is AudioEffectHardLimiter and _effect("Master", "AudioEffectCompressor") != null, "Master compressor precedes the limiter")
	var duck := _effect("Music", "AudioEffectCompressor") as AudioEffectCompressor
	suite.check(duck != null and duck.sidechain == &"SFX", "Music is ducked by an SFX sidechain")
	var sfx: int = AudioServer.get_bus_index("SFX")
	suite.check(_effect("SFX", "AudioEffectLowPassFilter") != null and not AudioServer.is_bus_effect_enabled(sfx, Soundscape.LOW_LIGHT_EFFECT), "SFX low-pass is bypassed outside low light")
	sound.configure({"volume":0.5,"music":true,"effects_volume":0.25,"interface_volume":0.8,"ambience_volume":0.1})
	var mapped: Dictionary = {"Master":0.5,"SFX":0.25,"UI":0.8,"Music":0.1}
	for bus: String in mapped:
		suite.check(_bus_matches(bus, mapped[bus]), "%s slider maps to %.2f dB on its bus (read %.2f)" % [bus, linear_to_db(mapped[bus]), _bus_db(bus)])
		suite.control("%s bus read against another slider's value" % bus, not _bus_matches(bus, 0.33))
	sound.configure({"volume":0.5,"music":true,"effects_volume":0.0})
	suite.check(_bus_matches("SFX", 0.0) and _bus_matches("Master", 0.5), "A zero slider mutes its bus only")
	sound.configure({"volume":0.5,"music":false,"ambience_volume":0.4})
	suite.check(_bus_matches("Music", 0.0), "Music off mutes the Music bus")
	sound.set_low_light(true)
	suite.check(AudioServer.is_bus_effect_enabled(sfx, Soundscape.LOW_LIGHT_EFFECT) and sound.heartbeat.playing, "Low light engages the SFX low-pass and the heartbeat")
	sound.set_low_light(false)
	suite.check(not AudioServer.is_bus_effect_enabled(sfx, Soundscape.LOW_LIGHT_EFFECT) and not sound.heartbeat.playing, "Light returning bypasses the low-pass and stops the heartbeat")

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
	suite.check(sound.play_cue("boss_phase"), "A new cue through play_cue obeys the same cap by preempting fire")
	suite.check(sound.mix_snapshot().size() == 8, "The effect cap still holds after play_cue")
	suite.check(sound.play("click"), "Interface feedback has a separate bounded category")
	suite.check(not sound.play("click"), "Duplicate activation in a frame is suppressed")
	sound.play_cue("ui_move")
	sound.play_cue("ui_back")
	var interface_count: int = 0
	for entry: Dictionary in sound.mix_snapshot():
		if entry.category == "interface": interface_count += 1
	suite.check(interface_count == Soundscape.INTERFACE_LIMIT, "Interface voices cap at two (%d)" % interface_count)
	suite.check(not sound.play_at("plasma", Vector2(1400, 0), "enemy"), "Inaudible distant fire does not consume voices")

	sound.seconds = 30.0
	sound.mix_snapshot()
	suite.check(sound.play("clear"), "Long cue available to test active gain")
	sound.configure({"volume": 0.2, "music": false, "effects_volume": 0.1})
	snapshot = sound.mix_snapshot()
	suite.check(snapshot.size() == 1 and is_equal_approx(float(snapshot[0].gain), 0.2 * 0.1 * float(Soundscape.CUES.level_complete[1])), "Changing gain immediately updates an active cue")
	sound.effects_volume = 0.0
	sound.apply_settings()
	suite.check(sound.mix_snapshot().is_empty() and not sound.play("hurt"), "Category zero is true silence")
	sound.configure({"volume": 0.0, "music": true})
	suite.check(not sound.music.playing and not sound.play("click") and not sound.play_at("fire", Vector2.ZERO, "player") and _bus_matches("Master", 0.0), "Master zero silences all categories")
	sound.configure({"volume": 0.7, "music": false})
	suite.check(sound.mix_snapshot().is_empty(), "Unmuting cannot replay discarded cues")

	# Parameterised cues.
	sound.seconds = 40.0
	sound.mix_snapshot()
	suite.check(sound.play_cue("warp_strain", {"strain": 0.0}), "Warp strain starts")
	var strain_low: float = float(sound.mix_snapshot()[0].pitch)
	sound.seconds = 40.1
	suite.check(sound.play_cue("warp_strain", {"strain": 1.0}) and sound.mix_snapshot().size() == 1, "A held strain bends one voice instead of stacking")
	var strain_high: float = float(sound.mix_snapshot()[0].pitch)
	suite.check(strain_high > strain_low * 1.9, "Warp strain pitch rises with its parameter (%.2f -> %.2f)" % [strain_low, strain_high])
	sound.stop_cue("warp_strain")
	suite.check(sound.mix_snapshot().is_empty(), "Releasing the press cuts the strain")
	var steps: Array[float] = []
	for step: int in [0, 4, 8]:
		sound.seconds += 0.2
		sound.play_cue("combo_step", {"step": step})
		for entry: Dictionary in sound.mix_snapshot():
			if entry.cue == "combo_step" and is_equal_approx(float(entry.started), sound.seconds): steps.append(float(entry.pitch))
	suite.check(steps.size() == 3 and steps[0] < steps[1] and steps[1] < steps[2], "Combo step pitch climbs with the step %s" % str(steps))

	# Music: bar-aligned loopable stems, a synchronized stream and an intensity cross-fade.
	suite.check(sound.music.stream is AudioStreamSynchronized and (sound.music.stream as AudioStreamSynchronized).stream_count == 4, "Music is four synchronized stems")
	var loop_frames: int = roundi(Soundscape.bar_seconds() * Soundscape.RATE) * Soundscape.MUSIC_BARS
	var music_sum := PackedFloat32Array()
	music_sum.resize(loop_frames)
	for stem: int in range(Soundscape.STEMS.size()):
		var stream: AudioStreamWAV = (sound.music.stream as AudioStreamSynchronized).get_sync_stream(stem)
		var frames: int = roundi(stream.get_length() * stream.mix_rate)
		suite.check(frames == loop_frames + 1 and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end == loop_frames, "%s stem loops over exactly %d bars (%d frames + 1 guard)" % [Soundscape.STEMS[stem], Soundscape.MUSIC_BARS, loop_frames])
		# Two passes through the engine's own looping playback. Seamless: the largest step across the
		# loop point is no bigger than the largest step inside the loop.
		var playback: AudioStreamPlayback = stream.instantiate_playback()
		playback.start(0.0)
		var mixed: PackedVector2Array = playback.mix_audio(1.0, loop_frames * 2)
		playback.stop()
		playback = null
		var steepest: float = 0.0
		var loudest_frame: int = 64
		for index: int in range(64, loop_frames - 4):
			steepest = maxf(steepest, absf(mixed[index].x - mixed[index - 1].x))
			if absf(mixed[index].x) > absf(mixed[loudest_frame].x): loudest_frame = index
		var seam: float = 0.0
		for index: int in range(loop_frames - 3, loop_frames + 4): seam = maxf(seam, absf(mixed[index].x - mixed[index - 1].x))
		suite.check(mixed.size() == loop_frames * 2 and seam <= steepest, "%s stem loops seamlessly (step across the loop point %.4f, steepest inside %.4f)" % [Soundscape.STEMS[stem], seam, steepest])
		# Control: a loop point spliced at the stem's loudest frame must read as a click.
		suite.control("%s loop spliced at its loudest frame" % Soundscape.STEMS[stem], absf(mixed[loudest_frame].x - mixed[loop_frames].x) > steepest)
		for index: int in range(loop_frames): music_sum[index] += mixed[loop_frames + index].x
		stream = null  # A block-scoped local outlives its loop and would pin the stem past shutdown.
	suite.check(_peak(music_sum, 1.0) <= CEILING, "All four stems together peak at or below -1 dBFS (%.2f dBFS)" % linear_to_db(_peak(music_sum, 1.0)))
	suite.control("stem sum at gain x4", _peak(music_sum, 4.0) > CEILING)
	suite.check(sound.stem_gains() == PackedFloat32Array([1.0, 0.0, 0.0, 0.0]), "Music starts at intensity 0 (pad only)")
	sound.set_music_intensity(3)
	sound._step_stems(Soundscape.bar_seconds() * 0.5)
	var partial: PackedFloat32Array = sound.stem_gains()
	suite.check(partial[1] > 0.0 and partial[1] < 1.0 and partial[3] < 1.0, "Intensity changes cross-fade rather than cut %s" % str(partial))
	sound._step_stems(Soundscape.bar_seconds() * Soundscape.MUSIC_FADE_BARS)
	suite.check(sound.stem_gains() == PackedFloat32Array([1.0, 1.0, 1.0, 1.0]), "Intensity 3 brings in every stem within %.1f bars" % Soundscape.MUSIC_FADE_BARS)
	sound.set_music_intensity(1)
	sound._step_stems(Soundscape.bar_seconds() * Soundscape.MUSIC_FADE_BARS)
	suite.check(sound.stem_gains() == PackedFloat32Array([1.0, 1.0, 0.0, 0.0]), "Intensity 1 leaves pad and bass")

	# Every cue resolves; offline level per cue.
	var rms_line: Array[String] = []
	var peak_fail_x4: bool = false
	var rms_fail_x4: bool = false
	var loudest: Array[float] = []
	for cue: String in CUE_LIST:
		var stream: AudioStream = sound.sounds.get(cue)
		suite.check(stream != null and stream.get_length() > 0.0, "Cue resolves to a stream: " + cue)
		if stream == null: continue
		var decoded: PackedFloat32Array = Soundscape.render_stream(stream)
		var category: String = str(Soundscape.CUES[cue][2])
		var gain: float = float(Soundscape.CUES[cue][1])
		var default_gain: float = 0.7 * (0.45 if category == "interface" else 0.55) * gain
		# Peak with every slider at maximum; RMS at the default mix.
		var peak: float = _peak(decoded, gain)
		var rms: float = _rms_db(decoded, default_gain)
		suite.check(peak <= CEILING, "%s peaks at or below -1 dBFS at full sliders (%.2f dBFS)" % [cue, linear_to_db(peak)])
		suite.check(rms >= RMS_LOW_DB and rms <= RMS_HIGH_DB, "%s RMS in band at the default mix (%.1f dBFS)" % [cue, rms])
		peak_fail_x4 = peak_fail_x4 or _peak(decoded, gain * 4.0) > CEILING
		rms_fail_x4 = rms_fail_x4 or _rms_db(decoded, default_gain * 4.0) > RMS_HIGH_DB
		rms_line.append("%s=%.1f/%.1f" % [cue, rms, linear_to_db(peak)])
		if cue in WEAPONS: loudest.append(_peak(decoded, default_gain))
		stream = null
	suite.control("per-cue gain x4 clips", peak_fail_x4)
	suite.control("per-cue gain x4 leaves the RMS band", rms_fail_x4)
	print("CUE LEVELS (rms at default mix / peak at full sliders, dBFS): ", " ".join(rms_line))
	# A firefight's stack: the eight loudest weapon/impact voices start on the same sample at the
	# default mix. (Rarer stacks of boss and evolution cues are left to the Master limiter.)
	loudest.sort()
	var stacked: float = 0.0
	for index: int in range(maxi(0, loudest.size() - Soundscape.EFFECT_LIMIT), loudest.size()): stacked += loudest[index]
	suite.check(stacked <= CEILING, "Eight weapon voices aligned stay at or below -1 dBFS at the default mix (%.2f dBFS)" % linear_to_db(stacked))
	suite.control("aligned voices at gain x4", stacked * 4.0 > CEILING)

	var previous: PackedByteArray = Soundscape.make_clip("fire", 0).data
	suite.check(previous != Soundscape.make_clip("fire", 1).data, "Repeated feedback has deterministic variation")
	for cue: String in Soundscape.SYNTH:
		var clip: AudioStreamWAV = Soundscape.make_clip(cue)
		var bytes: PackedByteArray = clip.data
		var peak: int = 0
		for offset: int in range(0, bytes.size(), 2): peak = maxi(peak, absi(bytes.decode_s16(offset)))
		suite.check(clip.mix_rate == 44100 and sound._variants[cue].size() == Soundscape.VARIANTS and bytes.decode_s16(0) == 0 and absi(bytes.decode_s16(bytes.size() - 2)) < 200 and peak < 24000, cue + " is 44.1 kHz, %d variants, with headroom and rounded endpoints" % Soundscape.VARIANTS)
	var beat: PackedByteArray = Soundscape.heartbeat_loop().data
	suite.check(beat.decode_s16(0) == 0 and beat.decode_s16(beat.size() - 2) == 0, "Heartbeat loop has seamless endpoints")

	# Ambience fade: the player carries only the context fade; the Music bus carries the slider.
	sound.set_context("play")
	sound.configure({"volume":0.5,"music":true,"ambience_volume":0.1})
	suite.check(sound.music.playing and sound.music.volume_linear == 0.0, "New ambience playback begins silently")
	sound._process(2.0)
	suite.check(is_equal_approx(sound.music.volume_linear, 1.0) and _bus_matches("Music", 0.1), "Startup fade reaches full context level on a bus at the saved ambience")
	sound.configure({"volume":0.5,"music":true,"ambience_volume":0.4})
	suite.check(_bus_matches("Music", 0.4) and is_equal_approx(sound.music.volume_linear, 1.0), "Raising ambience applies to active playback immediately")
	sound.configure({"volume":0.8,"music":true,"ambience_volume":0.4})
	suite.check(_bus_matches("Master", 0.8), "Raising master applies immediately")
	sound.set_context("pause")
	sound.apply_settings()
	suite.check(is_equal_approx(sound.music.volume_linear, 1.0), "Context changes and unrelated settings preserve the intentional transition fade")
	sound._process(1.0)
	suite.check(is_equal_approx(sound.music.volume_linear, 0.65), "Pause ambience reaches its quieter context level")
	sound.configure({"volume":0.5,"music":true,"ambience_volume":0.0})
	suite.check(not sound.music.playing and sound.music.volume_linear == 0.0, "Ambience zero stops active playback immediately")
	sound.shutdown()
	suite.check(not AudioServer.is_bus_effect_enabled(sfx, Soundscape.LOW_LIGHT_EFFECT), "Shutdown leaves the low-pass bypassed")
	sound.queue_free()
	# The packaged quit path waits on audio_retired(): a live instance playing stems, the heartbeat,
	# samples and procedural cues must release every stream and playback after shutdown.
	var live := Soundscape.new()
	live.configure({"volume":0.5,"music":true,"ambience_volume":0.3,"pickup_cues":true})
	root.add_child(live)
	live.set_low_light(true)
	live.set_music_intensity(3)
	for cue: String in ["fire", "boss_phase", "ui_move", "pickup"]: live.play_cue(cue)
	live.play_at("void", Vector2(40, 0), "enemy")
	await create_timer(0.2).timeout
	live.shutdown()
	var deadline: int = Time.get_ticks_msec() + 1500
	while not live.audio_retired() and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	var alive: Array[String] = []
	for reference: WeakRef in live._retiring_audio:
		if reference.get_ref() != null: alive.append("%s %s" % [reference.get_ref().get_class(), reference.get_ref().resource_path.get_file()])
	suite.check(live.audio_retired(), "Stopped stems, heartbeat, samples and synth cues release their playback references %s" % str(alive))
	live.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	suite.finish(self)
