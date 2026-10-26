extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var controls: Node = load("res://scripts/main.gd").new()
	controls.scenario = NaretScenario.new()
	controls.audio_manager = NaretAudioManager.new()
	controls.llm = NaretLLMOrchestrator.new()
	for language in ["en", "de", "pl"]:
		controls._set_language(language)
		for mode in ["own", "neighbour"]:
			controls._set_mode(mode)
			check(controls.audio_manager.language == language,
				"recognition must retain trainee language %s in %s mode" % [language, mode])
	controls.audio_manager.free()
	controls.llm.free()
	controls.scenario.free()
	controls.free()
	return failures
