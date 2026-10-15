extends SceneTree
## Real recogniser test with a generated fixture, not a headset microphone test.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var api := NaretUniAPIClient.new()
	root.add_child(api)
	api.local_asr_url = "http://127.0.0.1:8767/inference"
	var result: Dictionary = await api.transcribe(FileAccess.get_file_as_bytes("res://build/local-asr-fixture.wav"), "en")
	var text := str(result.get("json", {}).get("text", ""))
	var grammar := load("res://scripts/scenario/spoken_observation.gd")
	var passed: bool = result.get("ok", false) and grammar.action_for(text) == "check_responsiveness"
	print("LOCAL_ASR_PASS: recorded fixture -> real recogniser -> observation grammar" if passed else "LOCAL_ASR_FAIL")
	api.queue_free()
	quit(0 if passed else 1)
