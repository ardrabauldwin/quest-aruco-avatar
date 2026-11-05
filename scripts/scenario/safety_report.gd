extends RefCounted
## Understands a scene-safety report by meaning, in English, German and Polish.
## classify() returns "safe", "unsafe" or "" (not a safety report: hand it on).
##
## Headset feedback 2026-11-03: trainees got stuck at the first step. The phrase grammar
## (spoken_observation.gd) accepts only whole known sentences, rejects any comma, and the
## cloud interpreter may only answer "safe", so "the scene is not safe" looped forever.
## Here a danger or a negation of safety wins over a safety word, questions and
## conditionals are never reports, and extra clauses ("..., I'm going to him") are fine.

const SAFE := {
	"en": ["safe", "secure", "secured", "clear", "all clear", "no danger", "no dangers", "no hazard", "no hazards",
		"nothing dangerous", "no risk", "no risks", "not dangerous", "no threat", "no threats", "danger free", "hazard free"],
	"de": ["sicher", "gesichert", "abgesichert", "ungefährlich", "keine gefahr", "keine gefahren", "nichts gefährlich",
		"nichts gefährliches", "kein risiko", "nicht gefährlich", "gefahrlos", "frei von gefahren"],
	"pl": ["bezpieczne", "bezpiecznie", "bezpieczny", "bezpieczna", "brak zagrożeń", "brak zagrożenia",
		"nie ma zagrożenia", "nie ma zagrożeń", "nie ma niebezpieczeństwa", "nic nie zagraża", "nie jest niebezpiecznie", "nie jest niebezpieczne"],
}
## Hazard nouns count only when stated ("there is a fire"), never when listed as checked
## ("I checked for traffic and fire, the scene is safe").
const UNSAFE := {
	"en": ["not safe", "isn't safe", "is unsafe", "unsafe", "not secure", "dangerous", "there is danger", "there's danger",
		"there is a danger", "there is a fire", "there's a fire", "there is fire", "something is burning", "there is smoke",
		"there's smoke", "there is traffic", "there's traffic", "there is a live wire", "there is electricity",
		"there is a gas leak", "i smell gas", "it smells of gas", "is a hazard", "hazardous"],
	"de": ["nicht sicher", "unsicher", "gefährlich", "es gibt gefahr", "es besteht gefahr", "da ist gefahr", "es brennt",
		"da ist feuer", "es gibt feuer", "da ist rauch", "es raucht", "da ist verkehr", "es gibt verkehr", "da ist strom",
		"es riecht nach gas", "gasgeruch", "ein gasleck"],
	"pl": ["nie jest bezpieczne", "nie jest bezpiecznie", "niebezpieczne", "niebezpiecznie", "jest zagrożenie",
		"jest niebezpieczeństwo", "jest ogień", "jest pożar", "pali się", "jest dym", "jest ruch", "jest prąd",
		"czuć gaz", "czuję gaz", "wyciek gazu"],
}
## Words that cancel a danger word right before it: "no fire", "keine Gefahr", "brak dymu".
const DANGER_DENIALS := ["no", "not", "without", "kein", "keine", "keinen", "ohne", "nicht", "brak", "bez", "nie ma"]
const QUESTION_STARTS := ["is ", "is it", "is the", "are ", "can ", "should ", "do i", "ist ", "sind ", "kann ", "darf ",
	"soll ", "czy ", "jest li"]
const CONDITIONALS := ["if ", "when ", "whether", "wenn ", "falls ", "ob ", "jeśli", "jeżeli", "gdy ", "czy "]


static func classify(text: String, language: String) -> String:
	var clean := " " + _normalise(text) + " "
	if clean.strip_edges().is_empty() or text.contains("?"):
		return ""
	for start: String in QUESTION_STARTS:
		if clean.strip_edges().begins_with(start.strip_edges() + " ") or clean.strip_edges() == start.strip_edges():
			return ""
	for word: String in CONDITIONALS:
		if (" " + word) in clean:
			return ""
	var lang := language if SAFE.has(language) else "en"
	# A safety phrase that itself contains a danger word ("keine Gefahr", "nie ma zagrożenia")
	# must not count as danger, so remove those first.
	var without_safe := clean
	for phrase: String in _by_length(SAFE[lang]):
		if phrase.begins_with("no ") or phrase.begins_with("not ") or phrase.begins_with("kein") \
				or phrase.begins_with("nicht ") or phrase.begins_with("brak ") or phrase.begins_with("nie ") \
				or phrase.begins_with("nic ") or phrase.begins_with("nichts ") or phrase.begins_with("nothing "):
			without_safe = without_safe.replace(" " + phrase + " ", " ")
	for phrase: String in _by_length(UNSAFE[lang]):
		var at := without_safe.find(" " + phrase + " ")
		if at >= 0 and not _denied(without_safe, at):
			return "unsafe"
	for phrase: String in SAFE[lang]:
		if (" " + phrase + " ") in clean:
			return "safe"
	return ""


static func _denied(text: String, at: int) -> bool:
	var before := text.substr(0, at).strip_edges()
	for denial: String in DANGER_DENIALS:
		if before.ends_with(" " + denial) or before == denial:
			return true
	return false


static func _normalise(text: String) -> String:
	var clean := text.to_lower().replace("’", "'").replace("\n", " ")
	for mark in [".", ",", "!", ";", ":", "\"", "„", "“", "”", "«", "»", "-"]:
		clean = clean.replace(mark, " ")
	while "  " in clean:
		clean = clean.replace("  ", " ")
	return clean.strip_edges()


static func _by_length(phrases: Array) -> Array:
	var sorted := phrases.duplicate()
	sorted.sort_custom(func(a: String, b: String): return a.length() > b.length())
	return sorted

