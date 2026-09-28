class_name Soundscape
extends Node
## Quiet, bounded feedback. Every request represents an activation, never a projectile.
## Levels live on the buses of default_bus_layout.tres: each slider sets one bus volume in dB, a
## player carries only its cue's own gain, and the Master limiter holds the sum at -1 dBFS.

const EFFECT_LIMIT: int = 8
const ENEMY_LIMIT: int = 4
const INTERFACE_LIMIT: int = 2
const PICKUP_INTERVAL: float = 0.25
const RATE: int = 44100
const VARIANTS: int = 4
const SILENT_DB: float = -80.0
## Setting key -> bus. The low-pass on SFX (effect 0) is bypassed except in the low-light state.
const BUSES: Dictionary = {"volume": "Master", "effects_volume": "SFX", "interface_volume": "UI", "ambience_volume": "Music"}
const CATEGORY_BUS: Dictionary = {"interface": &"UI", "effects": &"SFX"}
const LOW_LIGHT_EFFECT: int = 0
const KENNEY: String = "res://assets/audio/kenney/"
## name: source, gain, category, priority, pitch jitter. A source is "synth" (procedural, VARIANTS
## variants) or a curated Kenney CC0 sample, trimmed by its play window and pitch-varied per play.
const CUES: Dictionary = {
	"ui_move": [KENNEY + "interface/tick_002.ogg", 0.30, "interface", 40, 0.02],
	"ui_confirm": [KENNEY + "interface/select_002.ogg", 0.40, "interface", 50, 0.02],
	"ui_back": [KENNEY + "interface/back_002.ogg", 0.36, "interface", 50, 0.02],
	"ui_error": [KENNEY + "interface/error_004.ogg", 0.36, "interface", 60, 0.0],
	"ui_slider_tick": [KENNEY + "interface/tick_001.ogg", 0.26, "interface", 30, 0.03],
	"dash": ["synth", 0.34, "effects", 50, 0.04],
	"dash_ready": [KENNEY + "interface/glass_002.ogg", 0.24, "effects", 45, 0.02],
	"warp_strain": [KENNEY + "scifi/forceField_000.ogg", 0.26, "effects", 70, 0.0],
	"warp_snap": [KENNEY + "scifi/laserLarge_000.ogg", 0.34, "effects", 90, 0.03],
	"warp_rush": [KENNEY + "scifi/lowFrequency_explosion_001.ogg", 0.40, "effects", 90, 0.03],
	"warp_arrive": [KENNEY + "scifi/impactMetal_000.ogg", 0.42, "effects", 90, 0.03],
	"combo_step": [KENNEY + "interface/pluck_001.ogg", 0.26, "effects", 55, 0.0],
	"combo_tier": [KENNEY + "interface/confirmation_002.ogg", 0.30, "effects", 80, 0.0],
	"combo_break": [KENNEY + "impact/impactGlass_light_000.ogg", 0.34, "effects", 80, 0.03],
	"boss_engage": [KENNEY + "scifi/lowFrequency_explosion_000.ogg", 0.46, "effects", 100, 0.0],
	"boss_phase": [KENNEY + "impact/impactBell_heavy_000.ogg", 0.50, "effects", 100, 0.0],
	"boss_death": [KENNEY + "scifi/explosionCrunch_002.ogg", 0.46, "effects", 100, 0.0],
	"evolve_ready": [KENNEY + "interface/maximize_006.ogg", 0.30, "effects", 90, 0.0],
	"evolve_pick": [KENNEY + "interface/select_004.ogg", 0.32, "effects", 90, 0.0],
	"evolve_assemble": [KENNEY + "scifi/doorOpen_000.ogg", 0.36, "effects", 100, 0.0],
	"death": [KENNEY + "scifi/explosionCrunch_000.ogg", 0.40, "effects", 100, 0.02],
	"reboot": [KENNEY + "interface/maximize_003.ogg", 0.36, "effects", 90, 0.0],
	"level_complete": [KENNEY + "interface/confirmation_004.ogg", 0.34, "effects", 100, 0.0],
	"pickup": ["synth", 0.13, "effects", 5, 0.03],
	"hurt": ["synth", 0.46, "effects", 100, 0.03],
	"fire": ["synth", 0.30, "effects", 50, 0.03],
	"lightning": ["synth", 0.27, "effects", 50, 0.03],
	"void": ["synth", 0.32, "effects", 50, 0.03],
	"corruption": ["synth", 0.27, "effects", 50, 0.03],
	"plasma": ["synth", 0.28, "effects", 50, 0.03],
	"ability": ["synth", 0.33, "effects", 50, 0.03],
}
## Pre-M17 names keep working for every existing caller.
const ALIASES: Dictionary = {"click": "ui_confirm", "clear": "level_complete", "evolve": "evolve_assemble", "warp_bloom": "warp_arrive"}
## Procedural layers: body frequency, seconds, noise blend, ending pitch ratio, transient, tail.
const SYNTH: Dictionary = {
	"pickup": [620.0, 0.085, 0.04, 1.03, 0.25, 0.10],
	"hurt": [105.0, 0.20, 0.35, 0.82, 1.00, 0.70],
	"dash": [180.0, 0.24, 0.85, 1.60, 0.20, 0.30],
	"fire": [155.0, 0.12, 0.40, 0.90, 0.80, 0.80],
	"lightning": [290.0, 0.10, 0.45, 0.96, 1.00, 0.55],
	"void": [88.0, 0.16, 0.12, 0.88, 0.45, 0.40],
	"corruption": [180.0, 0.13, 0.30, 0.97, 0.60, 0.60],
	"plasma": [225.0, 0.12, 0.18, 1.12, 0.70, 0.35],
	"ability": [130.0, 0.20, 0.22, 1.05, 0.55, 0.50],
}
## Adaptive music: four bar-aligned stems in one AudioStreamSynchronized, rendered offline by
## tools/render_audio_audition.gd (-- --stems) and swappable for licensed stems of the same length.
const STEM_DIR: String = "res://assets/audio/music/"
const STEMS: Array[String] = ["pad", "bass", "drums", "lead"]
const MUSIC_BPM: float = 96.0
const MUSIC_BARS: int = 4
const MUSIC_FADE_BARS: float = 1.5
const INTENSITY_STEMS: Array = [[1.0, 0.0, 0.0, 0.0], [1.0, 1.0, 0.0, 0.0], [1.0, 1.0, 1.0, 0.0], [1.0, 1.0, 1.0, 1.0]]

var music: AudioStreamPlayer
var heartbeat: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var positional_voices: Array[AudioStreamPlayer2D] = []
var sounds: Dictionary = {}
var enabled: bool = true
var volume: float = 0.7
var music_enabled: bool = true
var effects_volume: float = 0.55
var interface_volume: float = 0.45
var ambience_volume: float = 0.15
var pickup_cues: bool = false
var voice_index: int = 0
var music_intensity: int = 0
var low_light: bool = false
var _variants: Dictionary = {}
var _active: Array[Dictionary] = []
var _last_cue: Dictionary = {}
var _shutting_down: bool = false
var _retiring_audio: Array[WeakRef] = []
var _context: String = "menu"
var _ambient_gain: float = 0.0
var _ambient_target: float = 0.0
var _stem_gain: PackedFloat32Array = PackedFloat32Array([1.0, 0.0, 0.0, 0.0])
var _jitter := RandomNumberGenerator.new()

## Safe before add_child(): legacy volume/music keys remain authoritative.
func configure(settings: Dictionary) -> void:
	if _shutting_down: return
	volume = clampf(float(settings.get("volume", 0.7)), 0.0, 1.0)
	music_enabled = bool(settings.get("music", true))
	effects_volume = clampf(float(settings.get("effects_volume", 0.55)), 0.0, 1.0)
	interface_volume = clampf(float(settings.get("interface_volume", 0.45)), 0.0, 1.0)
	ambience_volume = clampf(float(settings.get("ambience_volume", 0.15)), 0.0, 1.0)
	pickup_cues = bool(settings.get("pickup_cues", false))
	apply_settings()

func _ready() -> void:
	if _shutting_down: return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_jitter.seed = 1709
	for cue: String in CUES:
		var variants: Array[AudioStream] = []
		if CUES[cue][0] == "synth":
			for variant: int in range(VARIANTS): variants.append(make_clip(cue, variant))
		else:
			var stream: AudioStream = load(str(CUES[cue][0])) as AudioStream
			if stream != null: variants.append(stream)
		if variants.is_empty(): continue
		_variants[cue] = variants
		sounds[cue] = variants[0]
	for index: int in range(EFFECT_LIMIT + INTERFACE_LIMIT):
		var player := AudioStreamPlayer.new()
		add_child(player)
		voices.append(player)
	for index: int in range(EFFECT_LIMIT):
		var player := AudioStreamPlayer2D.new()
		player.max_distance = 1350.0
		player.attenuation = 1.5
		player.bus = CATEGORY_BUS.effects
		add_child(player)
		positional_voices.append(player)
	heartbeat = AudioStreamPlayer.new()
	heartbeat.stream = heartbeat_loop()
	heartbeat.bus = CATEGORY_BUS.effects
	heartbeat.volume_linear = 0.5
	add_child(heartbeat)
	music = AudioStreamPlayer.new()
	music.stream = music_stream()
	music.bus = &"Music"
	music.volume_linear = 0.0
	add_child(music)
	_apply_stem_gains()
	apply_settings()

func set_context(context: String) -> void:
	_context = context
	_ambient_target = _target_ambient_gain()

## The music player carries only the context fade; the Music bus carries the ambience slider.
func _target_ambient_gain() -> float:
	var context_gain: float = 0.65 if _context == "pause" else (0.85 if _context == "menu" else 1.0)
	return context_gain if enabled and music_enabled and volume > 0.0 and ambience_volume > 0.0 else 0.0

func _process(delta: float) -> void:
	if _shutting_down: return
	_prune()
	if is_instance_valid(music) and music.playing:
		_ambient_gain = move_toward(_ambient_gain, _ambient_target, delta * 0.5)
		music.volume_linear = _ambient_gain
	_step_stems(delta)

func _now_seconds() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0

func _prune() -> void:
	var now: float = _now_seconds()
	for index: int in range(_active.size() - 1, -1, -1):
		if float(_active[index].until) <= now:
			_active[index].player.stop()
			_active.remove_at(index)

func _player_gain(cue: String, source: String) -> float:
	return float(CUES[cue][1]) * (0.42 if source == "enemy" else 1.0)

## The level a listener hears before the master chain: sliders (bus volumes) times the player gain.
func _gain(category: String, source: String, cue: String) -> float:
	if not enabled: return 0.0
	var category_gain: float = interface_volume if category == "interface" else effects_volume
	return volume * category_gain * _player_gain(cue, source)

func apply_settings() -> void:
	if _shutting_down: return
	_apply_buses()
	for index: int in range(_active.size() - 1, -1, -1):
		var entry: Dictionary = _active[index]
		var gain: float = _gain(str(entry.category), str(entry.source), str(entry.cue))
		if gain <= 0.0 or (entry.cue == "pickup" and not pickup_cues):
			entry.player.stop()
			_active.remove_at(index)
	_ambient_target = _target_ambient_gain()
	_apply_heartbeat()
	if not is_instance_valid(music): return
	if _ambient_target <= 0.0 or music.stream == null:
		music.stop()
		music.volume_linear = 0.0
		_ambient_gain = 0.0
	else:
		# Mix changes land on the bus at once. Starting playback and menu/play/pause transitions
		# still fade the player; unrelated settings must not interrupt that fade.
		if not music.playing: _ambient_gain = 0.0
		music.volume_linear = _ambient_gain
		if not music.playing: music.play()

func _apply_buses() -> void:
	var levels: Dictionary = {"volume": volume if enabled else 0.0, "effects_volume": effects_volume, "interface_volume": interface_volume, "ambience_volume": ambience_volume if music_enabled else 0.0}
	for key: String in BUSES:
		var index: int = AudioServer.get_bus_index(BUSES[key])
		if index < 0: continue
		var linear: float = float(levels[key])
		AudioServer.set_bus_mute(index, linear <= 0.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(linear) if linear > 0.0 else SILENT_DB)

## Public API for gameplay: one call per activation. params: "position" (Vector2, relative to the
## player; positional), "source" ("player"/"enemy"), "priority", "strain" (0..1, warp_strain pitch)
## and "step" (combo_step, one semitone per step).
func play_cue(cue: String, params: Dictionary = {}) -> bool:
	cue = str(ALIASES.get(cue, cue))
	var pitch: float = 1.0
	if cue == "warp_strain":
		pitch = lerpf(0.8, 1.6, clampf(float(params.get("strain", 0.0)), 0.0, 1.0))
		# A held press re-requests every frame: bend the sounding voice rather than restart it.
		for entry: Dictionary in _active:
			if entry.cue == "warp_strain":
				entry.player.pitch_scale = pitch
				entry.pitch = pitch
				return true
	elif cue == "combo_step":
		pitch = pow(2.0, clampf(float(params.get("step", 0)), 0.0, 12.0) / 12.0)
	var source: String = str(params.get("source", "player"))
	var positional: bool = params.has("position")
	return _request(cue, params.get("position", Vector2.ZERO), positional, source, int(params.get("priority", -1)), pitch)

## Cuts a sounding cue (warp_strain when the press is released).
func stop_cue(cue: String) -> void:
	cue = str(ALIASES.get(cue, cue))
	for index: int in range(_active.size() - 1, -1, -1):
		if _active[index].cue == cue:
			_active[index].player.stop()
			_active.remove_at(index)

func play(cue: String, priority: int = -1, source: String = "player") -> bool:
	return _request(str(ALIASES.get(cue, cue)), Vector2.ZERO, false, source, priority)

func play_at(cue: String, relative_position: Vector2, source: String = "enemy", priority: int = -1) -> bool:
	cue = str(ALIASES.get(cue, cue))
	return _request(cue if CUES.has(cue) else "ability", relative_position, true, source, priority)

func _request(cue: String, position: Vector2, positional: bool, source: String, priority: int, pitch: float = 1.0) -> bool:
	if _shutting_down or not enabled or not sounds.has(cue): return false
	if cue == "pickup" and not pickup_cues: return false
	var category: String = str(CUES[cue][2])
	var gain: float = _gain(category, source, cue)
	if gain <= 0.0: return false
	if positional and source == "enemy" and position.length() >= 1350.0: return false
	var now: float = _now_seconds()
	var cooldown: float = PICKUP_INTERVAL if cue == "pickup" else (0.12 if cue == "hurt" else (0.075 if source == "enemy" else 0.035))
	var key: String = "pickup" if cue == "pickup" else source + ":" + cue
	if now - float(_last_cue.get(key, -1000.0)) < cooldown: return false
	_prune()
	if priority < 0: priority = 10 if source == "enemy" else int(CUES[cue][3])
	var candidates: Array[Dictionary] = []
	for entry: Dictionary in _active:
		if entry.category == category: candidates.append(entry)
	var limit: int = INTERFACE_LIMIT if category == "interface" else EFFECT_LIMIT
	var enemies: Array[Dictionary] = []
	if source == "enemy":
		for entry: Dictionary in candidates:
			if entry.source == "enemy": enemies.append(entry)
	var constrained: Array[Dictionary] = enemies if enemies.size() >= ENEMY_LIMIT else candidates
	if candidates.size() >= limit or enemies.size() >= ENEMY_LIMIT:
		var victim: Dictionary = {}
		for entry: Dictionary in constrained:
			if int(entry.priority) < priority and (victim.is_empty() or int(entry.priority) < int(victim.priority)):
				victim = entry
		if victim.is_empty(): return false
		victim.player.stop()
		_active.erase(victim)
	var player: Node = _free_player(positional)
	if player == null: return false
	var variants: Array = _variants[cue]
	var variant: int = voice_index % variants.size()
	voice_index += 1
	var stream: AudioStream = variants[variant]
	var scale: float = pitch * (1.0 + _jitter.randf_range(-1.0, 1.0) * float(CUES[cue][4]))
	player.stream = stream
	player.bus = CATEGORY_BUS[category]
	player.volume_linear = _player_gain(cue, source)
	player.pitch_scale = scale
	if positional: player.position = get_viewport().get_visible_rect().size * 0.5 + position
	player.play()
	_active.append({"player": player, "cue": cue, "source": source, "category": category, "priority": priority, "variant": variant, "pitch": scale, "started": now, "until": now + stream.get_length() / scale})
	_last_cue[key] = now
	return true

func _free_player(positional: bool) -> Node:
	var pool: Array = positional_voices if positional else voices
	for player: Node in pool:
		var used: bool = false
		for entry: Dictionary in _active:
			if entry.player == player:
				used = true
				break
		if not used: return player
	return null

## Intensity 0..3 from enemies, combo and boss state; stems cross-fade over MUSIC_FADE_BARS bars.
func set_music_intensity(intensity: int) -> void:
	music_intensity = clampi(intensity, 0, INTENSITY_STEMS.size() - 1)

func stem_targets() -> Array:
	return INTENSITY_STEMS[music_intensity]

func stem_gains() -> PackedFloat32Array:
	return _stem_gain.duplicate()

func _step_stems(delta: float) -> void:
	var rate: float = delta / (MUSIC_FADE_BARS * bar_seconds())
	var targets: Array = stem_targets()
	var changed: bool = false
	for index: int in range(_stem_gain.size()):
		var next: float = move_toward(_stem_gain[index], float(targets[index]), rate)
		changed = changed or next != _stem_gain[index]
		_stem_gain[index] = next
	if changed: _apply_stem_gains()

func _apply_stem_gains() -> void:
	if not is_instance_valid(music) or not (music.stream is AudioStreamSynchronized): return
	var synced: AudioStreamSynchronized = music.stream
	for index: int in range(mini(_stem_gain.size(), synced.stream_count)):
		synced.set_sync_stream_volume(index, linear_to_db(_stem_gain[index]) if _stem_gain[index] > 0.0 else SILENT_DB)

## Low light: the SFX low-pass engages and a heartbeat loops until light returns.
func set_low_light(on: bool) -> void:
	if _shutting_down: return
	low_light = on
	var index: int = AudioServer.get_bus_index(&"SFX")
	if index >= 0: AudioServer.set_bus_effect_enabled(index, LOW_LIGHT_EFFECT, on)
	_apply_heartbeat()

func _apply_heartbeat() -> void:
	if not is_instance_valid(heartbeat): return
	if low_light and enabled and volume > 0.0 and effects_volume > 0.0:
		if not heartbeat.playing: heartbeat.play()
	elif heartbeat.playing: heartbeat.stop()

## Small diagnostics surface for policy tests and the offline listening reel.
func mix_snapshot() -> Array[Dictionary]:
	_prune()
	var result: Array[Dictionary] = []
	for entry: Dictionary in _active:
		result.append({"cue": entry.cue, "source": entry.source, "category": entry.category, "priority": entry.priority, "variant": entry.variant, "pitch": entry.pitch, "started": entry.started, "until": entry.until, "gain": _gain(str(entry.category), str(entry.source), str(entry.cue))})
	return result

## The stream a snapshot entry plays, for the offline reel. Holding it past shutdown pins it.
func stream_for(cue: String, variant: int) -> AudioStream:
	return _variants[cue][variant] if _variants.has(cue) else null

func _exit_tree() -> void:
	shutdown()

func audio_retired() -> bool:
	if not _shutting_down: return false
	for reference: WeakRef in _retiring_audio:
		if reference.get_ref() != null: return false
	return true

func shutdown() -> void:
	if _shutting_down: return
	_shutting_down = true
	enabled = false
	music_enabled = false
	var low_pass: int = AudioServer.get_bus_index(&"SFX")
	if low_pass >= 0: AudioServer.set_bus_effect_enabled(low_pass, LOW_LIGHT_EFFECT, false)
	for variants: Array in _variants.values():
		for stream: AudioStream in variants: _retiring_audio.append(weakref(stream))
	var players: Array = []
	players.append_array(voices)
	players.append_array(positional_voices)
	if is_instance_valid(heartbeat): players.append(heartbeat)
	if is_instance_valid(music): players.append(music)
	for player: Node in players:
		if not is_instance_valid(player): continue
		if player.stream != null: _retiring_audio.append(weakref(player.stream))
		if player.has_stream_playback(): _retiring_audio.append(weakref(player.get_stream_playback()))
		player.stop()
		player.stream = null
	_active.clear()
	_last_cue.clear()
	_variants.clear()
	sounds.clear()

static func bar_seconds() -> float:
	return 240.0 / MUSIC_BPM

## Loads the four stems, loops each over its bar-aligned length, and starts at intensity 0.
## Godot 4.7's WAV playback sounds the loop_end frame itself before jumping to loop_begin + 1
## (measured: loop_end = length inserts one zero frame, a click). So every stem carries one guard
## frame equal to its first, and loop_end points at it; a swapped-in stem must do the same.
static func music_stream() -> AudioStreamSynchronized:
	var synced := AudioStreamSynchronized.new()
	synced.stream_count = STEMS.size()
	for index: int in range(STEMS.size()):
		var path: String = STEM_DIR + STEMS[index] + ".wav"
		var stem: AudioStreamWAV = load(path) as AudioStreamWAV if ResourceLoader.exists(path) else null
		if stem == null: return null
		stem.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stem.loop_begin = 0
		stem.loop_end = roundi(stem.get_length() * stem.mix_rate) - 1
		synced.set_sync_stream(index, stem)
		synced.set_sync_stream_volume(index, 0.0 if index == 0 else SILENT_DB)
	return synced

## Procedural weapon/feedback cue at 44.1 kHz: a bright transient, a gliding harmonic body and a
## dull noise tail, peak-normalised to 0.7 so the table's gain alone sets the level.
static func make_clip(cue: String, variant: int = 0) -> AudioStreamWAV:
	var profile: Array = SYNTH.get(cue, SYNTH.ability)
	var random := RandomNumberGenerator.new()
	random.seed = absi(cue.hash()) + variant * 173
	var frequency: float = float(profile[0]) * (1.0 + (float(variant) - 1.5) * 0.02)
	var duration: float = float(profile[1]) * random.randf_range(0.94, 1.06)
	var count: int = int(duration * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase: float = 0.0
	var low: float = 0.0
	var band: float = 0.0
	var peak: float = 0.0
	for index: int in range(count):
		var seconds: float = float(index) / RATE
		var t: float = float(index) / maxf(1.0, count - 1.0)
		phase += TAU * frequency * lerpf(1.0, float(profile[3]), t) / RATE
		var white: float = random.randf_range(-1.0, 1.0)
		low = lerpf(low, white, 0.06)
		var transient: float = (white - low) * exp(-seconds * 380.0) * float(profile[4])
		var body: float = (sin(phase) + 0.32 * sin(2.0 * phase + 0.4) + 0.12 * sin(3.0 * phase)) * pow(1.0 - t, 1.3)
		if cue == "dash":
			# A band of noise swept upward: the whoosh of a burn.
			band = lerpf(band, white, lerpf(0.02, 0.35, t))
			body = lerpf(body, (band - low) * 4.0, float(profile[2])) * sin(PI * t)
		else:
			body = lerpf(body, low * 3.0, float(profile[2]))
		var tail: float = low * 3.0 * t * pow(1.0 - t, 2.0) * float(profile[5])
		var sample: float = (transient + body * 0.8 + tail) * smoothstep(0.0, 0.0015, seconds) * smoothstep(0.0, 0.006, duration - seconds)
		samples[index] = sample
		peak = maxf(peak, absf(sample))
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var scale: float = 0.7 / maxf(peak, 0.0001)
	for index: int in range(count): bytes.encode_s16(index * 2, int(clampf(samples[index] * scale, -1.0, 1.0) * 32767.0))
	return _wav(bytes)

static func _wav(bytes: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream

## A seamless one-second "lub-dub" at 60 bpm for the low-light state.
static func heartbeat_loop() -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(RATE * 2)
	for index: int in range(RATE):
		var seconds: float = float(index) / RATE
		var sample: float = 0.0
		for beat: Vector3 in [Vector3(0.02, 62.0, 0.8), Vector3(0.30, 50.0, 0.55)]:
			var local: float = seconds - beat.x
			if local > 0.0 and local < 0.22:
				sample += sin(TAU * beat.y * local * (1.0 - local)) * smoothstep(0.0, 0.008, local) * exp(-local * 22.0) * beat.z
		bytes.encode_s16(index * 2, int(clampf(sample * 0.7, -1.0, 1.0) * 32767.0))
	var stream: AudioStreamWAV = _wav(bytes)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = RATE
	return stream

## Offline mono decode of any stream through its own playback, for the policy test and the reel.
static func render_stream(stream: AudioStream, pitch: float = 1.0, max_seconds: float = 30.0) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if stream == null: return result
	var playback: AudioStreamPlayback = stream.instantiate_playback()
	playback.start(0.0)
	var frames: PackedVector2Array = playback.mix_audio(pitch, int(minf(stream.get_length() / pitch, max_seconds) * RATE))
	playback.stop()
	result.resize(frames.size())
	for index: int in range(frames.size()): result[index] = (frames[index].x + frames[index].y) * 0.5
	return result
