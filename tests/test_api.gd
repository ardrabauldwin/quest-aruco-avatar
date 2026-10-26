extends "res://tests/suite.gd"

func run() -> Array[String]:
	# People in the scene speak before a waiting instructor line, in their own order.
	var queue := [{"speaker": "marek"}, {"speaker": "instructor"}, {"speaker": "instructor"}]
	check(NaretAudioManager._queue_slot(queue, "anna") == 1, "a bystander line goes before waiting instructor lines")
	check(NaretAudioManager._queue_slot(queue, "instructor") == 3, "an instructor line waits at the end")
	failures.clear()
	var deadlines := NaretUniAPIClient.new()
	check(deadlines.service_timeout("asr") == 0.0, "cloud ASR can wait without an automatic deadline")
	check(deadlines.service_timeout("llm") == 2.0 and deadlines.service_timeout("tts") == 2.0, "speech deadline does not delay dialogue or voice fallbacks")
	deadlines.free()
	check(NaretLLMOrchestrator.parse_response('{"text":"Ich helfe.","action":"calm","language":"de"}', "de").get("action") == "calm", "valid JSON accepted")
	check(NaretLLMOrchestrator.parse_response('{"text":"X","action":"admin","language":"de"}', "de").is_empty(), "unknown actions rejected")
	check(NaretLLMOrchestrator.parse_response('{"text":"X","action":"calm","language":"pl"}', "de").is_empty(), "wrong language rejected")
	check(NaretLLMOrchestrator.parse_response('[1,2]', "de").is_empty(), "non-object JSON rejected")
	check(NaretLLMOrchestrator.parse_response('{"text":42,"action":"calm","language":"de"}', "de").is_empty(), "non-string text rejected")
	check(NaretLLMOrchestrator.parse_response('```json\n{"text":"Pomogę.","action":"fetch_aed","language":"pl"}\n```', "pl").get("clip_key") == "aed", "fenced JSON accepted safely")
	var safe := NaretLLMOrchestrator.parse_response('{"text":"Ich helfe.","action":"calm","language":"de","state":"RECOVERY","code":"execute()"}', "de")
	check(not safe.has("state") and not safe.has("code"), "clinical state and code dropped")
	check(NaretLLMOrchestrator.fallback_reply("Bitte hole den AED", "de")["action"] == "fetch_aed", "German AED request")
	check(NaretLLMOrchestrator.fallback_reply("Proszę przynieść defibrylator", "pl")["action"] == "fetch_aed", "Polish AED request")
	check(NaretLLMOrchestrator.fallback_reply("Bitte nicht den AED holen", "de")["action"] == "calm", "negated request stays calm")
	check(NaretLLMOrchestrator.fallback_reply("Zadzwoń pod 112", "pl")["action"] == "call_help", "Polish help request")
	var recording := AudioStreamWAV.new()
	recording.format = AudioStreamWAV.FORMAT_16_BITS
	recording.mix_rate = 16000
	recording.stereo = false
	recording.data = PackedByteArray([0, 0, 255, 127, 0, 128, 0, 0])
	var bytes := NaretUniAPIClient.encode_wav(recording)
	check(bytes.size() == 52 and bytes.decode_u32(40) == 8, "multipart input WAV has correct byte lengths")
	check(bytes.decode_u32(24) == 16000 and bytes.decode_u16(22) == 1, "WAV preserves rate and channel count")
	var decoded := NaretUniAPIClient.decode_audio(bytes)
	check(decoded is AudioStreamWAV, "runtime WAV decoder")
	check(NaretUniAPIClient.decode_audio('not audio data'.to_utf8_buffer()) == null, "invalid TTS bytes rejected")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/manifest.json"))
	check(manifest.get("clips", []).size() >= 20, "bilingual offline speech is bundled")
	for clip: Dictionary in manifest.get("clips", []):
		check(ResourceLoader.exists("res://assets/audio/" + clip["file"]), "offline clip exists: " + clip["file"])
	var audio_script: GDScript = load("res://scripts/ai/audio_manager.gd")
	check(audio_script.can_instantiate(), "audio manager compiles for runtime")
	await _check_cancellation()
	_check_recording_state()
	_check_voice_activation()
	var prefix := NaretAudioManager.encode_prefix(PackedVector2Array([Vector2(1.0, -1.0), Vector2(0.5, 0.5)]), true)
	check(prefix.size() == 8 and prefix.decode_s16(0) == 32767 and prefix.decode_s16(2) == -32767, "pre-roll preserves stereo PCM channels and signs")
	var mono := NaretAudioManager.encode_prefix(PackedVector2Array([Vector2(1.0, -1.0)]), false)
	check(mono.size() == 2 and mono.decode_s16(0) == 0, "mono pre-roll averages channels")
	return failures

func _check_cancellation() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var api := DelayedAPI.new()
	tree.root.add_child(api)
	var orchestrator := NaretLLMOrchestrator.new()
	tree.root.add_child(orchestrator)
	orchestrator.configure(api)
	var replies: Array[Dictionary] = []
	orchestrator.reply_ready.connect(func(reply: Dictionary) -> void: replies.append(reply))
	orchestrator.enqueue_transcript("Erste Anfrage", {"language": "de"})
	orchestrator.enqueue_transcript("Veraltete Warteschlange", {"language": "de"})
	orchestrator.cancel_pending()
	orchestrator.enqueue_transcript("Nowa prośba", {"language": "pl"})
	# The orchestrator only guarantees the second call *starts* after 500 ms, so a
	# fixed 0.65 s wait raced with it on a busy machine. Wait for the outcome.
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline and (replies.is_empty() or api.call_times.size() < 2):
		await tree.process_frame
	# Settle briefly so a stale reply that should have been cancelled would show up.
	await tree.create_timer(0.2).timeout
	check(replies.size() == 1, "language change cancels queued and in-flight stale replies")
	if not replies.is_empty():
		check(replies[0]["language"] == "pl", "only new language response is emitted")
	check(api.call_times.size() == 2, "cancelled queued item never reaches API")
	if api.call_times.size() == 2:
		check(api.call_times[1] - api.call_times[0] >= 500, "LLM requests are at least 500 ms apart")
	orchestrator.queue_free()
	api.queue_free()
	await tree.process_frame

func _check_recording_state() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var manager := NaretAudioManager.new()
	tree.root.add_child(manager)
	var states: Array[bool] = []
	manager.recording_changed.connect(func(active: bool) -> void: states.append(active))
	var input_enabled: bool = ProjectSettings.get_setting("audio/driver/enable_input", false)
	ProjectSettings.set_setting("audio/driver/enable_input", false)
	manager.begin_recording()
	ProjectSettings.set_setting("audio/driver/enable_input", input_enabled)
	check(states == [false] and not manager.recording, "unavailable microphone resets UI recording state")
	manager.queue_free()

func _check_voice_activation() -> void:
	## The trainee's hands are on the chest, so the microphone must arm itself.
	var tree: SceneTree = Engine.get_main_loop()
	var manager := NaretAudioManager.new()
	tree.root.add_child(manager)
	manager.set_listening(true)
	check(manager.listening, "voice activation arms the microphone")
	manager.set_input_focus(false)
	manager.begin_recording()
	check(manager.listening and not manager.recording and manager._microphone.playing, "Quest menu blocks recording while retaining the existing input stream")
	manager.set_input_focus(true)
	check(manager.listening and manager._microphone.playing, "returning to app retains microphone stream")
	manager.begin_recording()
	manager.set_input_focus(false)
	check(not manager.recording and not manager._transcribing, "interrupted recording is discarded rather than submitted as a failure")
	manager.set_input_focus(true)
	var start := Time.get_ticks_msec()
	manager.update_voice_activity(0.0, start)
	check(not manager.recording, "silence alone records nothing")
	manager.update_voice_activity(NaretAudioManager.VAD_THRESHOLD * 2.0, start)
	check(manager.recording, "speech starts the recording without a button")
	manager.update_voice_activity(NaretAudioManager.VAD_THRESHOLD * 2.0, start + 600)
	manager.update_voice_activity(0.0, start + 700)
	manager.update_voice_activity(0.0, start + 1500)
	check(manager.recording, "a pause inside a sentence does not cut it off")
	manager.update_voice_activity(0.0, start + 2100)
	check(not manager.recording, "trailing silence ends the utterance")
	check(manager.listening, "the microphone stays armed for the next utterance")
	# Speaking bystanders would otherwise record the app talking to itself.
	manager.set("_playing", true)
	manager.update_voice_activity(NaretAudioManager.VAD_THRESHOLD * 5.0, start + 3000)
	check(not manager.recording, "the app's own speech does not retrigger the microphone")
	manager.set("_playing", false)
	manager.set_listening(false)
	check(not manager.listening and not manager.recording, "disarming stops listening and recording")
	manager.queue_free()

class DelayedAPI extends NaretUniAPIClient:
	var call_times: Array[int] = []

	func _ready() -> void:
		pass

	func is_available(_model: String = "") -> bool:
		return true

	func request_json(_service: String, _endpoint: String, payload: Dictionary, _method: HTTPClient.Method = HTTPClient.METHOD_POST) -> Dictionary:
		call_times.append(Time.get_ticks_msec())
		var lang := "pl" if "Polnisch" in payload["messages"][0]["content"] else "de"
		await get_tree().create_timer(0.02).timeout
		var content := JSON.stringify({"text": "Pomogę." if lang == "pl" else "Ich helfe.", "action": "calm", "language": lang})
		return {"ok": true, "json": {"choices": [{"message": {"content": content}}]}}
