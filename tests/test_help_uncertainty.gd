extends "res://tests/suite.gd"
## Help and uncertainty (18 Nov 2026): "I don't know" and similar reach the instructor in all
## three languages; reports and safety answers do not.

func run() -> Array[String]:
	failures.clear()
	for text in ["I don't know what to do.", "I'm not sure.", "Help me.", "No idea.",
			"Ich weiß nicht, was ich tun soll.", "Keine Ahnung.", "Ich bin nicht sicher.", "Hilf mir bitte.", "Was muss ich machen?",
			"Nie wiem, co robić.", "Nie jestem pewna.", "Pomóż mi.", "Co mam robić?"]:
		check(NaretTrainingCoach.asks_for_help(text), "'%s' asks the instructor for help" % text)
	for text in ["The environment is safe.", "Die Umgebung ist sicher.", "Er reagiert nicht.", "Osoba nie reaguje.", "Ich rufe die 112 an."]:
		check(not NaretTrainingCoach.asks_for_help(text), "'%s' is a report, not a request for help" % text)
	return failures
