class_name Soundscape
extends Node

var music: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var positional_voices: Array[AudioStreamPlayer2D] = []
var sounds: Dictionary = {}
var enabled: bool = true
var volume: float = 0.7
var music_enabled: bool = true
var voice_index: int = 0
var _shutting_down: bool = false
var _retiring_audio: Array[WeakRef] = []

func _ready() -> void:
	if _shutting_down:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i: int in range(8):
		var player := AudioStreamPlayer.new()
		add_child(player)
		voices.append(player)
	sounds["pickup"] = tone(780.0, 0.09, 1.4)
	sounds["evolve"] = tone(220.0, 0.8, 4.0)
	sounds["hurt"] = tone(170.0, 0.16, 0.4)
	sounds["clear"] = tone(440.0, 0.6, 2.0)
	sounds["click"] = tone(550.0, 0.045, 0.8)
	sounds["death"] = tone(260.0, 0.8, 0.18)
	sounds["fire"] = tone(210.0, 0.10, 0.35)
	sounds["lightning"] = tone(1050.0, 0.07, 0.45)
	sounds["void"] = tone(125.0, 0.20, 0.55)
	sounds["corruption"] = tone(460.0, 0.12, 1.65)
	sounds["plasma"] = tone(650.0, 0.12, 0.65)
	for i: int in range(16):
		var positional := AudioStreamPlayer2D.new()
		positional.max_distance = 1700.0
		positional.attenuation = 0.6
		add_child(positional)
		positional_voices.append(positional)
	sounds["ability"] = tone(140.0, 0.30, 3.3)
	music = AudioStreamPlayer.new()
	music.stream = ambient()
	add_child(music)
	music.play()
	apply_settings()

func play(cue: String) -> void:
	if _shutting_down or not enabled or voices.is_empty() or not sounds.has(cue):
		return
	var voice: AudioStreamPlayer = voices[voice_index % voices.size()]
	voice_index += 1
	voice.stream = sounds[cue]
	voice.volume_db = linear_to_db(maxf(0.001, volume * 0.20))
	voice.play()

func apply_settings() -> void:
	if not _shutting_down and is_instance_valid(music):
		music.volume_db = linear_to_db(maxf(0.001, volume * 0.085)) if music_enabled else -80.0

func play_at(cue: String, relative_position: Vector2) -> void:
	if _shutting_down or not enabled or positional_voices.is_empty(): return
	var voice: AudioStreamPlayer2D = positional_voices[voice_index % positional_voices.size()]
	voice_index += 1
	voice.position = Vector2(640,400)+relative_position
	voice.stream = sounds.get(cue,sounds.get("ability"))
	voice.volume_db = linear_to_db(maxf(0.001,volume*0.10))
	voice.play()

func _exit_tree() -> void:
	shutdown()

func audio_retired() -> bool:
	if not _shutting_down:
		return false
	for reference: WeakRef in _retiring_audio:
		if reference.get_ref() != null:
			return false
	return true

func shutdown() -> void:
	if _shutting_down:
		return
	# Keep only weak references: AudioServer owns playback until its mixer
	# and update threads retire it, which can outlast a fixed exit delay.
	for stream: AudioStream in sounds.values():
		_retiring_audio.append(weakref(stream))
	var players: Array = voices.duplicate()
	if is_instance_valid(music): players.append(music)
	for player: AudioStreamPlayer in players:
		if not is_instance_valid(player): continue
		if player.stream != null: _retiring_audio.append(weakref(player.stream))
		if player.has_stream_playback(): _retiring_audio.append(weakref(player.get_stream_playback()))
	# Stop accepting cues before the host waits for AudioServer's mixer to
	# retire playback. Combat callbacks can still run during that drain window.
	_shutting_down = true
	enabled = false
	music_enabled = false
	if is_instance_valid(music):
		music.stop()
		music.stream = null
	for voice: AudioStreamPlayer in voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	sounds.clear()
	for voice: AudioStreamPlayer2D in positional_voices:
		if voice.has_stream_playback(): _retiring_audio.append(weakref(voice.get_stream_playback()))
		voice.stop()
		voice.stream = null

static func tone(frequency: float, duration: float, pitch_end: float) -> AudioStreamWAV:
	const RATE: int = 22050
	var count: int = int(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / count
		phase += TAU * frequency * lerpf(1.0, pitch_end, t) / RATE
		var envelope: float = minf(t * 50.0, 1.0) * pow(1.0 - t, 2.0)
		var value: int = int((sin(phase) + 0.2 * sin(phase * 2.0)) * envelope * 20000.0)
		bytes.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream

static func ambient() -> AudioStreamWAV:
	const RATE: int = 22050
	const DURATION: int = 12
	var bytes := PackedByteArray()
	bytes.resize(RATE * DURATION * 2)
	for i: int in range(RATE * DURATION):
		var t: float = float(i) / RATE
		var envelope: float = 0.6 + 0.4 * sin(t * TAU / DURATION)
		var sample: float = sin(t * TAU * 110.0) * 0.30 + sin(t * TAU * 165.0) * 0.15 + sin(t * TAU * 220.0) * 0.1
		bytes.encode_s16(i * 2, int(sample * envelope * 20000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = RATE * DURATION
	return stream
