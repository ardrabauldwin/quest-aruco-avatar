extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var manager := NaretAudioManager.new()
	tree.root.add_child(manager)
	manager.set_listening(true)
	var clip := AudioStreamWAV.new()
	clip.mix_rate = 16000
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	var pcm := PackedByteArray()
	pcm.resize(32000)
	clip.data = pcm
	var player: AudioStreamPlayer = manager._players[0]
	player.stream = clip
	player.play()
	manager._playing = true
	manager._reconcile_playback()
	check(manager._playing, "active instructor audio remains protected from microphone echo")
	manager._on_playback_finished()
	check(manager._playing, "late completion from the other buffer cannot stop an active speaker's animation")
	# stop() does not emit finished. This previously left _playing true forever.
	player.stop()
	manager._reconcile_playback()
	check(not manager._playing, "an interrupted voice releases the microphone gate")
	manager.update_voice_activity(NaretAudioManager.VAD_THRESHOLD * 2.0, Time.get_ticks_msec())
	check(manager.recording, "the next breathing report starts recording after interrupted playback")
	manager.set_input_focus(false)
	check(not manager.recording and not manager._transcribing, "focus loss discards interrupted audio without submitting a report")
	manager.set_input_focus(true)
	check(manager.listening and manager._microphone.playing, "microphone remains armed after focus returns")
	manager.queue_free()
	return failures
