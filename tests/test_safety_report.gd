extends "res://tests/suite.gd"
## Scene-safety reports by meaning (scripts/scenario/safety_report.gd).

const Safety = preload("res://scripts/scenario/safety_report.gd")

const CASES := [
	# English: safe in many wordings, extra clauses allowed
	["en", "The scene is safe.", "safe"],
	["en", "It's safe.", "safe"],
	["en", "Safe", "safe"],
	["en", "Everything is safe here", "safe"],
	["en", "All clear, no danger", "safe"],
	["en", "The scene is safe, I'm going to him now.", "safe"],
	["en", "I checked for traffic and fire, the scene is safe.", "safe"],
	["en", "There is no danger", "safe"],
	["en", "Nothing dangerous here, I can approach", "safe"],
	["en", "Okay the area is secure", "safe"],
	# English: not safe
	["en", "The scene is not safe.", "unsafe"],
	["en", "It isn't safe", "unsafe"],
	["en", "This is dangerous", "unsafe"],
	["en", "There is a fire", "unsafe"],
	["en", "I smell gas", "unsafe"],
	# English: not a report
	["en", "Is the scene safe?", ""],
	["en", "Is it safe", ""],
	["en", "If it is safe I will go", ""],
	["en", "He is not responding", ""],
	# German
	["de", "Die Umgebung ist sicher.", "safe"],
	["de", "Alles sicher", "safe"],
	["de", "Es ist sicher, ich gehe jetzt zu ihm", "safe"],
	["de", "Keine Gefahr", "safe"],
	["de", "Hier ist es ungefährlich", "safe"],
	["de", "Ich habe auf Verkehr und Feuer geachtet, die Umgebung ist sicher", "safe"],
	["de", "Die Umgebung ist nicht sicher.", "unsafe"],
	["de", "Das ist gefährlich", "unsafe"],
	["de", "Es brennt", "unsafe"],
	["de", "Ist die Umgebung sicher?", ""],
	["de", "Wenn es sicher ist, gehe ich hin", ""],
	["de", "Er reagiert nicht", ""],
	# Polish
	["pl", "Miejsce jest bezpieczne.", "safe"],
	["pl", "Jest bezpiecznie", "safe"],
	["pl", "Wszystko bezpieczne, podchodzę do niego", "safe"],
	["pl", "Nie ma zagrożenia", "safe"],
	["pl", "Brak zagrożeń", "safe"],
	["pl", "Nie jest niebezpiecznie", "safe"],
	["pl", "Miejsce nie jest bezpieczne.", "unsafe"],
	["pl", "Jest niebezpiecznie", "unsafe"],
	["pl", "Jest pożar", "unsafe"],
	["pl", "Czy miejsce jest bezpieczne?", ""],
	["pl", "Jeśli jest bezpiecznie, podejdę", ""],
	["pl", "Pacjent nie reaguje", ""],
]


func run() -> Array[String]:
	failures.clear()
	for case: Array in CASES:
		var got: String = Safety.classify(case[1], case[0])
		check(got == case[2], "%s \"%s\" -> \"%s\" (expected \"%s\")" % [case[0], case[1], got, case[2]])
	for language in ["en", "de", "pl"]:
		check(not Safety.unsafe_reply(language).is_empty(), language + " has an unsafe-report reply")
	return failures
