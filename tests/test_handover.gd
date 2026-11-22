extends "res://tests/suite.gd"
## Handover to the ambulance crew (issue #1, 8.).

func run() -> Array[String]:
	failures.clear()
	var de := NaretHandover.facts("Die Person reagiert nicht. Die Person atmet nicht normal. Ich habe gedrückt. Der AED hat einen Schock abgegeben.", "de")
	check(de == ["no_response", "not_breathing", "compressions", "aed", "shock"], "the issue's example handover (%s)" % str(de))
	check(NaretHandover.complete(de), "complete with response, breathing and compressions")
	var pl := NaretHandover.facts("Osoba nie reaguje, nie oddycha. Wykonałam masaż serca.", "pl")
	check(NaretHandover.complete(pl), "Polish, female form (%s)" % str(pl))
	var en := NaretHandover.facts("He is not breathing and I did CPR.", "en")
	check(not NaretHandover.complete(en) and "not_breathing" in en and "compressions" in en, "a handover without the response is not complete yet")
	check(not NaretHandover.crew_line("arrive", "de").is_empty() and "Sie" in NaretHandover.crew_line("arrive", "de"), "the crew speaks in the Sie-form")
	return failures
