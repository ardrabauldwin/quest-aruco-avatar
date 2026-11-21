extends "res://tests/suite.gd"
## The exact wordings that lived in spoken_observation.gd until 11 Nov 2026, kept here so
## folding them into the pattern grammar never loses one. Each must still be accepted as a
## statement, and refused as a question or when quoted after "Do not say".
const Speech = preload("res://scripts/scenario/spoken_observation.gd")

const LEGACY := {
	"start": ["start exercise", "start the exercise", "übung starten", "rozpocznij ćwiczenie"],
	"begin_check": [
		"the scene is safe", "scene is safe", "die umgebung ist sicher", "miejsce jest bezpieczne",
		"it is safe to approach", "the surroundings are safe", "i checked the surroundings and the scene is safe",
		"die umgebung ist abgesichert", "ich kann mich sicher nähern", "ich habe die umgebung geprüft sie ist sicher",
		"można bezpiecznie podejść", "miejsce zdarzenia jest bezpieczne", "sprawdziłem otoczenie jest bezpieczne", "sprawdziłam otoczenie jest bezpieczne",
		"the area is safe", "the scene is clear"
	],
	"check_responsiveness": [
		"he is not responding", "the patient is not responding", "er reagiert nicht", "pacjent nie reaguje",
		"he did not respond", "he did not react", "there is no response", "he does not respond to my voice",
		"der patient reagiert nicht auf ansprechen", "er reagiert nicht auf meine ansprache", "ich habe ihn angesprochen er reagiert nicht",
		"pacjent nie reaguje na mój głos", "pacjent nie reaguje na wołanie", "nie ma reakcji",
		"he isn't responding", "the patient isn't responding", "no response", "he is unresponsive", "the patient is unresponsive"
	],
	"call_emergency": [
		"anna please call 112", "please call 112", "anna call 112", "bitte ruf 112 an", "anna ruf 112 an", "zadzwoń pod 112",
		"anna please phone 112", "anna please call an ambulance", "please call emergency services",
		"anna ruf bitte die 112 an", "anna ruf bitte den rettungsdienst an", "bitte wählen sie die 112",
		"anno zadzwoń proszę pod 112", "anno wezwij pogotowie", "proszę wezwać pogotowie",
		"anna please call one one two", "please call one one two", "anna call emergency services", "anna please call emergency services"
	],
	"check_breathing": [
		"he is not breathing normally", "the patient is not breathing normally", "er atmet nicht normal", "pacjent nie oddycha prawidłowo",
		"he is not breathing at all", "there is no normal breathing", "i checked his breathing it is not normal",
		"er atmet überhaupt nicht", "ich habe die atmung geprüft er atmet nicht normal", "es ist keine normale atmung vorhanden",
		"pacjent wcale nie oddycha", "nie ma prawidłowego oddechu", "sprawdziłem oddech pacjent nie oddycha prawidłowo", "sprawdziłam oddech pacjent nie oddycha prawidłowo",
		"he isn't breathing normally", "he is not breathing", "he isn't breathing", "the patient is not breathing", "no normal breathing"
	],
	"ventilation": [
		"i have given one rescue breath", "ich habe eine beatmung gegeben", "wykonałem jeden oddech ratowniczy", "wykonałam jeden oddech ratowniczy",
		"one rescue breath completed", "the first rescue breath is complete", "the second rescue breath is complete", "i have delivered one rescue breath",
		"ich habe die erste beatmung durchgeführt", "ich habe die zweite beatmung durchgeführt", "die erste beatmung ist durchgeführt", "die zweite beatmung ist durchgeführt",
		"pierwszy oddech ratowniczy wykonany", "drugi oddech ratowniczy wykonany", "pierwszy oddech wykonany", "drugi oddech wykonany",
		"i gave one rescue breath", "i have given a rescue breath", "i have given the first rescue breath", "i have given the second rescue breath",
		"i gave the first rescue breath", "i gave the second rescue breath", "i have given the first breath", "i have given the second breath",
		"i've given the first breath", "i've given the second breath", "i gave the first breath", "i gave the second breath",
		"we have given the first breath", "we have given the second breath"
	],
	"compression_only": [
		"use compression only mode", "nur herzdruckmassage", "tylko uciski klatki piersiowej",
		"select compression only mode", "choose compression only mode",
		"modus nur herzdruckmassage wählen", "nur herzdruckmassage auswählen",
		"wybieram tryb samych ucisków", "wybieram same uciski klatki piersiowej"
	],
	"handover": [
		"hand over the patient", "patienten übergeben", "przekaż pacjenta",
		"please hand over the patient", "hand the patient over to the ambulance crew",
		"bitte den patienten übergeben", "patienten an den rettungsdienst übergeben",
		"przekaż pacjenta ratownikom", "proszę przekazać pacjenta ratownikom"
	]
}

func run() -> Array[String]:
	failures.clear()
	for action: String in LEGACY:
		for phrase: String in LEGACY[action]:
			var got := Speech.action_for(phrase.capitalize() + ".")
			check(got == action, "legacy wording accepted: %s -> %s (got '%s')" % [phrase, action, got])
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
		var got := Speech.action_for(text)
		check(got.is_empty(), "opposite/intention/compound/spoken compression count rejected: %s (got '%s')" % [text, got])
	return failures
