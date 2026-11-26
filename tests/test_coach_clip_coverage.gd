extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var manager := NaretAudioManager.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(manager)
	var guide: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/coach_steps.json"))
	for language: String in guide:
		for step: String in guide[language]:
			# The dispatcher's own wording (issue #1) is recorded in her voice.
			var speaker := "dispatcher" if step.begins_with("dispatcher_") else "instructor"
			# Same words as the dispatcher's line: only she says it (26 Nov 2026), no
			# second instructor recording.
			if speaker == "instructor" and str(guide[language].get("dispatcher_" + step, "")) == str(guide[language][step]): continue
			# A step without a spoken line ("setup" since 26 Nov 2026) needs no recording.
			if str(guide[language][step]).is_empty(): continue
			var key := language + ":" + speaker + ":" + str(guide[language][step])
			check(manager._coach_clips.get(key) is AudioStream, language + " " + step + " has bundled " + speaker + " audio")
	manager._voice_cache.clear()
	var breath_key := "en:instructor:" + NaretTrainingCoach.instruction("breaths", "en")
	check(manager._coach_clips.get(breath_key) is AudioStream, "clearing dynamic dialogue cannot remove the two-breath instruction")
	manager.queue_free()
	return failures
