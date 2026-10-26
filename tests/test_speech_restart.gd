extends "res://tests/suite.gd"
class SlowSpeech extends NaretUniAPIClient:
	signal first_done
	signal second_done
	var calls := 0
	func _ready() -> void: pass
	func transcribe(_wav: PackedByteArray, _language: String) -> Dictionary:
		calls += 1
		var number := calls
		if number == 1: await first_done
		else: await second_done
		return {"ok": true, "json": {"text": "old report" if number == 1 else "new report"}}
func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var api := SlowSpeech.new()
	tree.root.add_child(api)
	var manager := NaretAudioManager.new()
	manager.configure(api)
	tree.root.add_child(manager)
	var transcripts: Array[String] = []
	manager.transcript_ready.connect(func(text: String): transcripts.append(text))
	manager._transcribe_audio(PackedByteArray())
	manager.reset_training()
	manager._transcribe_audio(PackedByteArray())
	api.first_done.emit()
	check(transcripts.is_empty() and manager._transcribing, "old speech cannot advance a restarted exercise or clear its new request")
	api.second_done.emit()
	check(transcripts == ["new report"] and not manager._transcribing, "fresh speech still succeeds after restart")
	manager.free()
	api.free()
	return failures
