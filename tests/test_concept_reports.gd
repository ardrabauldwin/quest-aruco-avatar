extends "res://tests/suite.gd"
const Speech = preload("res://scripts/scenario/spoken_observation.gd")

func run() -> Array[String]:
	failures.clear()
	var accepted := {
		"This patient does not respond.": "check_responsiveness",
		"Der Patient reagiert überhaupt nicht auf Ansprache.": "check_responsiveness",
		"Ten pacjent nadal nie reaguje na dotyk.": "check_responsiveness",
		"This patient isn't breathing at all.": "check_breathing",
		"Der Patient atmet leider nicht normal.": "check_breathing",
		"Ten pacjent nadal nie oddycha prawidłowo.": "check_breathing",
		"The surroundings are now safe.": "begin_check",
		"Die Einsatzstelle ist jetzt sicher.": "begin_check",
		"Otoczenie jest już bezpieczne.": "begin_check",
		"I have just given him the first rescue breath.": "ventilation",
		"Ich habe gerade dem Patienten eine Atemspende gegeben.": "ventilation",
		"Właśnie wykonałam pacjentowi drugi oddech ratowniczy.": "ventilation"
	}
	for phrase: String in accepted:
		check(Speech.action_for(phrase) == accepted[phrase], "completed multilingual report: " + phrase)
	for phrase in [
		"This patient is responding.", "Der Patient reagiert normal.", "Ten pacjent oddycha prawidłowo.",
		"This patient is not responding?", "Czy ten pacjent nie oddycha prawidłowo", "Atmet der Patient nicht normal",
		"I will give him one rescue breath", "Ich werde eine Beatmung geben", "Będę wykonywać jeden oddech ratowniczy",
		"I have not given him one rescue breath", "Ich habe keine Beatmung gegeben", "Nie wykonałem jednego oddechu",
		"I am not sure this patient is responding", "Vielleicht reagiert der Patient nicht", "Chyba pacjent nie reaguje",
		"He is not responding and he is breathing normally", "Er reagiert nicht aber er atmet normal",
		"He said he is not responding", "I deny that he is not responding", "If he is not responding",
		"I gave him two rescue breaths", "Ich habe drei Beatmungen gegeben", "Wykonałem dwa oddechy",
		"This patient isn't not responding", "Not true the surroundings are now safe",
		"I gave a rescue bread", "helicopter not responding", "The patient is not breathing because he is talking"
	]:
		check(Speech.action_for(phrase).is_empty(), "ambiguous/contrary/compound report rejected: " + phrase)
	return failures
