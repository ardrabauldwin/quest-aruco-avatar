extends SceneTree
## Explicit network smoke test with synthetic content, not part of the offline suite.
## python3 tools/run_local.py --headless --xr-mode off --script tools/probe_runtime.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var api := NaretUniAPIClient.new()
	root.add_child(api)
	await process_frame
	if not api.is_available():
		printerr("No runtime API configuration. Use tools/run_local.py.")
		quit(1)
		return
	var report := {"engine": Engine.get_version_info().get("string", ""), "timeout_s": api.timeout_s, "checks": {}}
	for language in ["de", "pl"]:
		var phrase := "Ich bleibe ruhig." if language == "de" else "Zachowam spokój."
		var result: Dictionary = await api.synthesize(phrase)
		var valid_audio := false
		if result.get("ok", false):
			valid_audio = NaretUniAPIClient.decode_audio(result["body"]) != null
		report["checks"]["tts_" + language] = {"ok": result.get("ok", false), "latency_ms": result.get("latency_ms", -1), "decoded": valid_audio}
		var messages := NaretLLMOrchestrator.build_messages(phrase, {"state": "INTRO", "emotion": "anxious"}, language)
		var llm: Dictionary = await api.complete(messages)
		var valid_reply := false
		var choices: Array = llm.get("json", {}).get("choices", [])
		if not choices.is_empty():
			valid_reply = not NaretLLMOrchestrator.parse_response(str(choices[0].get("message", {}).get("content", "")), language).is_empty()
		report["checks"]["llm_" + language] = {"ok": llm.get("ok", false), "latency_ms": llm.get("latency_ms", -1), "parsed": valid_reply}
	var wav := FileAccess.get_file_as_bytes("res://assets/audio/tts_de/calm.wav")
	var asr: Dictionary = await api.transcribe(wav, "de")
	report["checks"]["asr"] = {"ok": asr.get("ok", false), "latency_ms": asr.get("latency_ms", -1), "has_transcript": not str(asr.get("json", {}).get("text", "")).is_empty()}
	var output := JSON.stringify(report, "  ")
	print(output)
	var file := FileAccess.open("res://docs/godot_api_probe.json", FileAccess.WRITE)
	if file != null:
		file.store_string(output + "\n")
	api.queue_free()
	await process_frame
	quit()
