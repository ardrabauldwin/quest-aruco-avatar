extends "res://tests/suite.gd"
const Speech = preload("res://scripts/scenario/spoken_observation.gd")
const Gate = preload("res://scripts/scenario/speech_confirmation.gd")

func run() -> Array[String]:
	failures.clear()
	var reports := {
		"Der Mann reagiert gar nicht.": "check_responsiveness",
		"Der Patient zeigt weiterhin keine Reaktion.": "check_responsiveness",
		"Keine Reaktion.": "check_responsiveness",
		"Pacjent nie odpowiada.": "check_responsiveness",
		"Mężczyzna nie reaguje w ogóle.": "check_responsiveness",
		"Brak reakcji.": "check_responsiveness",
		"Keine normale Atmung.": "check_breathing",
		"Pacjent nie oddycha w ogóle.": "check_breathing",
		"Brak prawidłowego oddechu.": "check_breathing",
		"Miejsce zdarzenia jest już bezpieczne.": "begin_check",
		"Ich habe ihn einmal beatmet.": "ventilation",
		"Wir haben den Patienten einmal beatmet.": "ventilation",
		"Zrobiłam już pierwszy oddech ratowniczy.": "ventilation",
		"Zrobiłem właśnie drugi oddech.": "ventilation",
		"Anna bitte ruf die 112 an.": "call_emergency",
		"Anno proszę zadzwoń pod numer 112.": "call_emergency"
	}
	for text: String in reports:
		check(Speech.action_for(text) == reports[text], "natural German/Polish report: " + text)
	for text in ["Der Patient zeigt eine Reaktion", "Der Patient zeigt nicht keine Reaktion", "Keine Reaktion?", "Er wird keine Reaktion zeigen", "Pacjent odpowiada", "Brak reakcji ale oddycha", "Czy pacjent nie odpowiada", "Pacjent nie odpowiada?", "Ich habe ihn nicht einmal beatmet", "Ich werde ihn einmal beatmen", "Nie zrobiłam pierwszego oddechu", "Zrobię pierwszy oddech", "Wir haben ihn zweimal beatmet", "Anna bitte ruf nicht die 112 an", "Anno proszę nie dzwoń pod numer 112"]:
		check(Speech.action_for(text).is_empty(), "positive, negated, future or compound report blocked: " + text)
	var uncertain := [
		["de", "Ich glaube, die Umgebung ist sicher.", "begin_check", "ja genau", "nein das stimmt nicht"],
		["de", "Ich glaube, er reagiert nicht.", "check_responsiveness", "ja richtig", "nein"],
		["de", "Ich glaube, er atmet nicht normal.", "check_breathing", "genau", "abbrechen"],
		["pl", "Myślę, że miejsce jest bezpieczne.", "begin_check", "tak potwierdzam", "nie to nie tak"],
		["pl", "Myślę, że pacjent nie reaguje.", "check_responsiveness", "dokładnie", "nie"],
		["pl", "Myślę, że pacjent nie oddycha prawidłowo.", "check_breathing", "tak zgadza się", "anuluj"]
	]
	for fixture: Array in uncertain:
		var gate := Gate.new()
		var allowed := [fixture[2]]
		check(Speech.action_for(fixture[1]).is_empty(), "uncertainty never directly confirms a finding")
		var proposal := gate.evaluate(fixture[1], "step", allowed, 0, fixture[0])
		check(proposal.get("proposal") == fixture[2] and not proposal.has("action"), "uncertain report asks confirmation")
		check(gate.evaluate(fixture[3], "step", allowed, 1, fixture[0]).get("action") == fixture[2], "natural localized yes confirms pending report")
		gate.evaluate(fixture[1], "step", allowed, 2, fixture[0])
		check(not gate.evaluate(fixture[4], "step", allowed, 3, fixture[0]).has("action"), "localized no cancels")
		check(not gate.evaluate(fixture[3], "step", allowed, 4, fixture[0]).has("action"), "cancelled report stays cancelled")
		check(gate.evaluate(fixture[1], "other", [], 5, fixture[0]).is_empty(), "out-of-order report cannot create a proposal")
	for text in ["Ich habe zweimal beatmet", "Ich habe beide Beatmungen durchgeführt", "Wykonałam oba oddechy ratownicze", "Zrobiłem dwa oddechy"]:
		check(Speech.reports_breath_pair(text), "two-breath route preserved: " + text)
	return failures
