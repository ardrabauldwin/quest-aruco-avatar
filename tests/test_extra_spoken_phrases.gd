extends "res://tests/suite.gd"
const Speech = preload("res://scripts/scenario/spoken_observation.gd")

func run() -> Array[String]:
	failures.clear()
	for action: String in Speech.EXTRA_PHRASES:
		for phrase: String in Speech.EXTRA_PHRASES[action]:
			check(Speech.action_for(phrase.capitalize() + ".") == action, "natural complete report/request accepted: " + phrase)
			check(Speech.action_for(phrase + "?").is_empty(), "question cannot become completed report: " + phrase)
			check(Speech.action_for("Do not say " + phrase).is_empty(), "quoted/negated instruction cannot become report: " + phrase)
	for text in [
		"I checked his breathing it is normal", "he did respond", "he is breathing at all", "I will deliver one rescue breath",
		"I have not delivered one rescue breath", "the first rescue breath is not complete", "one rescue bread completed",
		"Die Umgebung ist nicht abgesichert", "Ich werde die erste Beatmung durchführen", "Die erste Beatmung ist nicht durchgeführt",
		"Er reagiert auf meine Ansprache", "Es ist normale Atmung vorhanden", "Anna ruf bitte nicht die 112 an",
		"Miejsce zdarzenia nie jest bezpieczne", "Pacjent reaguje na mój głos", "Pacjent oddycha prawidłowo",
		"Pierwszy oddech nie został wykonany", "Anno nie wzywaj pogotowia", "Wykonam pierwszy oddech ratowniczy",
		"I have done thirty compressions", "Ich habe dreißig Kompressionen gemacht", "Wykonałem trzydzieści ucisków",
		"He did not react but he is breathing normally", "Er reagiert nicht auf Ansprechen aber er atmet normal"
	]:
		check(Speech.action_for(text).is_empty(), "opposite/intention/compound/spoken compression count rejected: " + text)
	return failures
