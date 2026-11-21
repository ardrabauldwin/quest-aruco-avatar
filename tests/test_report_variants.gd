extends "res://tests/suite.gd"
## Natural wordings of the BLS reports in English, German and Polish (11 Nov 2026).
## The headset logs of 3 and 9 Nov had correct transcripts that no rule accepted; every
## sentence here must now be understood by the grammar alone, without the cloud model.
## The second table lists sentences that must never be taken as a completed finding.
const Speech = preload("res://scripts/scenario/spoken_observation.gd")

func run() -> Array[String]:
	failures.clear()
	var accepted := {
		# transcripts from the headset logs
		"He's not breathing at all.": "check_breathing",
		"He's not breathing.": "check_breathing",
		"He is not breathing at all.": "check_breathing",
		"No, he doesn't, responds.": "",
		"Anna, please call 112 and put the call on speaker.": "call_emergency",
		"Anna, please call 112.": "call_emergency",
		"Ana, please call 112.": "",
		# English breathing
		"He isn't breathing normally.": "check_breathing",
		"She is not breathing properly.": "check_breathing",
		"The patient is no longer breathing.": "check_breathing",
		"He has stopped breathing.": "check_breathing",
		"He is only gasping.": "check_breathing",
		"There is no normal breathing.": "check_breathing",
		"His breathing is not normal.": "check_breathing",
		"Not breathing at all.": "check_breathing",
		"The patient's not breathing.": "check_breathing",
		# English responsiveness
		"He's not responding at all.": "check_responsiveness",
		"She does not react to my voice.": "check_responsiveness",
		"The patient is unresponsive.": "check_responsiveness",
		"He is unconscious.": "check_responsiveness",
		"There is no response at all.": "check_responsiveness",
		"He did not respond to shaking.": "check_responsiveness",
		"No reaction.": "check_responsiveness",
		# English call
		"Please call an ambulance.": "call_emergency",
		"Anna, ring 112 now.": "call_emergency",
		"Call 112 and use the speaker.": "call_emergency",
		# German breathing
		"Er atmet nicht.": "check_breathing",
		"Er atmet überhaupt nicht.": "check_breathing",
		"Er atmet gar nicht mehr.": "check_breathing",
		"Sie atmet nicht normal.": "check_breathing",
		"Der Patient atmet nicht mehr richtig.": "check_breathing",
		"Er hat aufgehört zu atmen.": "check_breathing",
		"Er hat Schnappatmung.": "check_breathing",
		"Er schnappt nur nach Luft.": "check_breathing",
		"Keine Atmung vorhanden.": "check_breathing",
		"Die Atmung ist nicht normal.": "check_breathing",
		"Ich sehe keine normale Atmung.": "check_breathing",
		# German responsiveness
		"Er reagiert nicht.": "check_responsiveness",
		"Er reagiert gar nicht auf Ansprache.": "check_responsiveness",
		"Sie reagiert nicht auf Rütteln.": "check_responsiveness",
		"Der Mann ist bewusstlos.": "check_responsiveness",
		"Die Person ist nicht ansprechbar.": "check_responsiveness",
		"Er antwortet nicht.": "check_responsiveness",
		"Er wacht nicht auf.": "check_responsiveness",
		"Keine Reaktion auf Ansprache.": "check_responsiveness",
		# German call
		"Anna, ruf bitte die 112 an.": "call_emergency",
		"Ruf den Rettungsdienst an und stell auf Lautsprecher.": "call_emergency",
		"Bitte wähle den Notruf.": "call_emergency",
		# Polish breathing
		"On nie oddycha.": "check_breathing",
		"Pacjent nie oddycha w ogóle.": "check_breathing",
		"Ona wcale nie oddycha.": "check_breathing",
		"Pacjent nie oddycha normalnie.": "check_breathing",
		"Mężczyzna nie oddycha prawidłowo.": "check_breathing",
		"On przestał oddychać.": "check_breathing",
		"Pacjent ma oddech agonalny.": "check_breathing",
		"Nie ma oddechu.": "check_breathing",
		"Brak prawidłowego oddechu.": "check_breathing",
		"Oddech jest nieprawidłowy.": "check_breathing",
		"Nie oddycha prawidłowo.": "check_breathing",
		# Polish responsiveness
		"On nie reaguje.": "check_responsiveness",
		"Pacjent w ogóle nie reaguje.": "check_responsiveness",
		"Ona nie reaguje na dotyk.": "check_responsiveness",
		"Pacjent nie odpowiada na głos.": "check_responsiveness",
		"Poszkodowany jest nieprzytomny.": "check_responsiveness",
		"Pacjent nie jest przytomny.": "check_responsiveness",
		"Nie ma reakcji.": "check_responsiveness",
		"Brak reakcji na wołanie.": "check_responsiveness",
		# Polish call
		"Anno, zadzwoń pod 112.": "call_emergency",
		"Proszę wezwij pogotowie.": "call_emergency",
		"Zadzwoń na 112 i włącz głośnomówiący.": "call_emergency",
	}
	for text: String in accepted:
		var got := Speech.action_for(text)
		check(got == accepted[text], "report %s -> expected '%s', got '%s'" % [text, accepted[text], got])
	for text in [
		# positive findings
		"He is breathing normally.", "He's breathing.", "He is responding.", "She is conscious.",
		"Er atmet normal.", "Er reagiert.", "Er ist ansprechbar.", "Die Atmung ist normal.",
		"Pacjent oddycha prawidłowo.", "On reaguje.", "Pacjent jest przytomny.", "Oddech jest prawidłowy.",
		# questions, plans, doubts, conditionals
		"Is he breathing at all?", "Atmet er überhaupt nicht?", "Czy on nie oddycha?",
		"I will check if he is breathing.", "Ich werde prüfen ob er atmet.", "Sprawdzę czy oddycha.",
		"I think he's not breathing.", "Ich glaube er atmet nicht.", "Chyba nie oddycha.",
		"If he is not breathing we start.", "Wenn er nicht atmet drücken wir.", "Jeśli nie oddycha zaczynamy.",
		# compounds and double negation
		"He is not breathing and he is responding.", "Er reagiert nicht aber er atmet normal.", "Nie reaguje ale oddycha.",
		"He is not not breathing.", "Er atmet nicht nicht.", "On nie nie oddycha.",
		# off topic
		"The vaccine is not breathing.", "Der Hund atmet nicht.", "Kot nie oddycha.",
		"Anna, please call me later.", "Anna ruf mich später an.", "Anno zadzwoń do mnie.",
	]:
		var got := Speech.action_for(text)
		check(got.is_empty(), "must not accept '%s' but got '%s'" % [text, got])
	return failures
