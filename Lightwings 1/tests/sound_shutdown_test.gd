extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var sound: Soundscape = Soundscape.new()
	root.add_child(sound)
	sound.play("fire")
	await create_timer(0.05).timeout
	paused = true
	sound.shutdown()
	# Combat callbacks can arrive while the host drains the audio mixer.
	for tick: int in range(8):
		sound.play("lightning")
		sound.apply_settings()
		await create_timer(0.02,true).timeout
	var failures: int = 0
	for voice: AudioStreamPlayer in sound.voices:
		if voice.playing or voice.stream != null: failures += 1
	if sound.music.playing or sound.music.stream != null: failures += 1
	if not sound.sounds.is_empty(): failures += 1
	sound.shutdown()
	sound.queue_free()
	await process_frame
	await create_timer(0.25,true).timeout
	print("AUDIO SHUTDOWN: late cues and paused cleanup, ",failures," failures")
	quit(1 if failures else 0)
