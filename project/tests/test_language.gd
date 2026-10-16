extends "res://tests/suite.gd"

const Language = preload("res://scripts/ai/language_manager.gd")

func run() -> Array[String]:
	for key: String in Language.STRINGS.de:
		check(Language.STRINGS.pl.has(key), "Polish translation exists for " + key)
		check(not Language.text(key, "pl").is_empty(), "Polish text is nonempty for " + key)
	for key: String in Language.STRINGS.pl:
		check(Language.STRINGS.de.has(key), "German translation exists for " + key)
	check(Language.text("state.cpr", "de") == "Wiederbelebung", "German state label")
	check(Language.text("state.cpr", "pl") == "Resuscytacja", "Polish state label")
	check(Language.text("state.cpr", "fr") == "Wiederbelebung", "Unknown language uses German fallback")
	check(Language.text("unknown.key") == "unknown.key", "Unknown key is visible")
	var cases := {
		"Bitte rufen Sie 112 an!": "call_emergency",
		"Zadzwoń pod 112!": "call_emergency",
		"Proszę wezwać pogotowie.": "call_emergency",
		"Hol bitte den AED.": "request_aed",
		"Proszę przynieść AED!": "request_aed",
		"Bitte bleiben Sie ruhig.": "reassure",
		"Proszę zachować spokój.": "reassure",
		"Nie bój się, pomogę.": "reassure",
		"Keine Angst, wir helfen.": "reassure",
		"Bitte nicht den AED holen": "",
		"Nie dzwoń pod 112": "",
		"Ich löse den Schock aus": "",
		"Wykonaj wyładowanie AED": "",
		"30 Kompressionen durchgeführt": "",
		"Atmung geprüft": "",
		"": "",
		"    ": "",
	}
	for transcript: String in cases:
		check(Language.infer_action(transcript) == cases[transcript], "Intent: " + transcript)
	return failures
