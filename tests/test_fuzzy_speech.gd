extends "res://tests/suite.gd"
const Gate = preload("res://scripts/scenario/speech_confirmation.gd")
const Fuzzy = preload("res://scripts/scenario/fuzzy_speech.gd")

func run() -> Array[String]:
	failures.clear()
	var fixtures := [
		["en", "the scene is saef", "begin_check", "yes", "no"],
		["en", "i have given one rescue bread", "ventilation", "yes", "no"],
		["de", "die umgebung ist sichre", "begin_check", "ja", "nein"],
		["de", "der patient reagirt nicht", "check_responsiveness", "ja", "nein"],
		["de", "er atmet nicht normahl", "check_breathing", "ja", "nein"],
		["pl", "miejsce jest bezpieczn", "begin_check", "tak", "nie"],
		["pl", "pacjent nie reagje", "check_responsiveness", "tak", "nie"],
		["pl", "pacjent nie oddycha prawidlowo", "check_breathing", "tak", "nie"]
	]
	for fixture: Array in fixtures:
		var gate := Gate.new()
		var allowed := [fixture[2]]
		var proposal := gate.evaluate(fixture[1], "step", allowed, 0, fixture[0])
		check(proposal.get("proposal") == fixture[2] and not proposal.has("action"), "mishearing requires confirmation: " + str(fixture[1]))
		check(gate.evaluate(fixture[3], "step", allowed, 1, fixture[0]).get("action") == fixture[2], "localized affirmative confirms once")
		check(not gate.evaluate(fixture[3], "step", allowed, 2, fixture[0]).has("action"), "repeated affirmative does not count again")
		gate.evaluate(fixture[1], "step", allowed, 3, fixture[0])
		check(not gate.evaluate(fixture[4], "step", allowed, 4, fixture[0]).has("action"), "localized no cancels")
		check(not gate.evaluate(fixture[3], "step", allowed, 5, fixture[0]).has("action"), "cancelled proposal cannot be confirmed")
		check(Fuzzy.propose(fixture[1], fixture[0], []).is_empty(), "no permitted action means no proposal")
	var allowed := ["begin_check", "check_responsiveness", "check_breathing", "ventilation"]
	for language in ["en", "de", "pl"]:
		for opposite in ["the scene is unsafe", "die umgebung ist unsicher", "miejsce jest niebezpieczne", "er atmet nicht unnormal", "pacjent nie oddycha nieprawidłowo"]:
			check(Fuzzy.propose(opposite, language, allowed).is_empty(), "opposite safety/finding cannot be repaired: " + opposite)
		for text in ["he is breathing normally", "he is responding", "he is not not responding", "the patient is now responding", "he is not responding?", "i will give one rescue bread", "i have not given one rescue bread", "the vaccine is safe", "he is not responding and not breathing", "i have given three rescue breads", "er atmet normal", "er reagiert", "ich werde eine beatmung geben", "er atmet nicht normal?", "pacjent oddycha prawidłowo", "pacjent reaguje", "czy pacjent nie oddycha prawidłowo", "będę wykonywać oddech", "pacjent nie reaguje ale oddycha"]:
			check(Fuzzy.propose(text, language, allowed).is_empty(), "no repair of opposite/uncertain/count findings: " + text)
	var pair := Gate.new()
	check(pair.evaluate("i have given two rescue bread", "breaths", ["ventilation"], 0).get("breaths") == 2, "pair mishearing asks about two")
	check(pair.evaluate("yes", "breaths", ["ventilation"], 1).get("breaths") == 2, "confirmed pair retains count")
	var changed := Gate.new()
	changed.evaluate("die umgebung ist sichre", "a", ["begin_check"], 0, "de")
	check(not changed.evaluate("yes", "a", ["begin_check"], 1, "en").has("action"), "language change invalidates pending proposal")
	changed.evaluate("die umgebung ist sichre", "a", ["begin_check"], 0, "de")
	check(not changed.evaluate("ja", "b", ["begin_check"], 1, "de").has("action"), "stage change invalidates pending proposal")
	changed.evaluate("die umgebung ist sichre", "a", ["begin_check"], 0, "de")
	check(not changed.evaluate("ja", "a", ["begin_check"], 31000, "de").has("action"), "expiry invalidates pending proposal")
	for language in ["en", "de", "pl"]:
		for action in ["begin_check", "check_responsiveness", "check_breathing", "ventilation"]:
			check(not Gate.question(action, 1, language).is_empty(), "localized confirmation available")
		check(Gate.question("ventilation", 1, language) != Gate.question("ventilation", 2, language), "one/two questions differ")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/confirmation/manifest.json"))
	var recorded := {}
	for clip: Dictionary in manifest.clips:
		recorded[str(clip.language) + ":" + str(clip.text)] = clip.path
		var stream: AudioStream = load(str(clip.path))
		check(stream != null and stream.get_length() > 0.0, "offline confirmation audio decodes: " + str(clip.path))
	for language in ["en", "de", "pl"]:
		for action in ["begin_check", "check_responsiveness", "check_breathing", "ventilation"]:
			check(recorded.has(language + ":" + Gate.question(action, 1, language)), "exact question has offline recording")
		check(recorded.has(language + ":" + Gate.question("ventilation", 2, language)), "pair has its own matching offline recording")
		check(recorded.has(language + ":" + Gate.repeat_message(language)), "localized retry has offline recording")
	var started := Time.get_ticks_usec()
	for _index in 100:
		Fuzzy.propose("pacjent nie oddycha prawidlowo", "pl", allowed)
	print("NARET_FUZZY_PC_BENCH mean_ms=", (Time.get_ticks_usec() - started) / 100000.0)
	return failures
