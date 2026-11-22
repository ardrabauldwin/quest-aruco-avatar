extends "res://tests/suite.gd"
## Early recognition: after 0.5 s of quiet the words so far are already sent; more words
## throw that answer away; a speaker who stays quiet gets it without a second request.

class Server extends NaretUniAPIClient:
	var calls := 0
	func transcribe(_wav: PackedByteArray, _language: String) -> Dictionary:
		calls += 1
		await (Engine.get_main_loop() as SceneTree).process_frame
		return {"ok": true, "json": {"text": "The scene is safe."}}

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var audio := NaretAudioManager.new()
	tree.root.add_child(audio)
	var server := Server.new()
	audio.add_child(server)
	audio._api = server
	var heard := []
	audio.transcript_ready.connect(func(text: String): heard.append(text))
	# One second of speech already in the recording (a 220 Hz tone).
	var frames := PackedVector2Array()
	var rate := int(AudioServer.get_mix_rate())
	for i in rate:
		var v := 0.3 * sin(TAU * 220.0 * i / rate)
		frames.append(Vector2(v, v))
	audio.recording = true
	audio._speech_seen = true
	audio._live_frames = frames
	var t := 10000
	audio.update_voice_activity(0.0, t)        # quiet starts
	audio.update_voice_activity(0.0, t + 300)
	check(server.calls == 0, "nothing is sent before 0.5 s of quiet")
	audio.update_voice_activity(0.0, t + 600)
	check(server.calls == 1, "after 0.5 s of quiet the words so far are sent")
	await tree.process_frame
	await tree.process_frame
	check(not audio._spec_result.is_empty(), "the early answer is kept while the speaker stays quiet")
	audio.update_voice_activity(0.5, t + 700)  # speaks again
	check(audio._spec_for == -1, "more words throw the early answer away")
	# Quiet again: a new early request, and the end of the utterance uses it.
	audio.update_voice_activity(0.0, t + 800)
	audio.update_voice_activity(0.0, t + 1400)
	check(server.calls == 2, "the new pause sends the longer utterance early")
	await tree.process_frame
	await tree.process_frame
	audio._finish_with_speculation(audio._spec_for, PackedByteArray())
	await tree.process_frame
	check(server.calls == 2 and heard == ["The scene is safe."], "the end of the utterance uses the early answer, no second request (%d calls, %s)" % [server.calls, str(heard)])
	audio.queue_free()
	return failures
