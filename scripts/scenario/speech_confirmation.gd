extends RefCounted
## Only explicit pending proposals can be confirmed. No fuzzy clinical acceptance.
const Speech = preload("res://scripts/scenario/spoken_observation.gd")
const Fuzzy = preload("res://scripts/scenario/fuzzy_speech.gd")
const LIFETIME_MS := 30000
var _action := ""
var _context := ""
var _deadline := 0
var _breaths := 1
var _language := "en"

func clear() -> void:
	_action = ""
	_context = ""
	_deadline = 0
	_breaths = 1

func evaluate(text: String, context: String, allowed: Array, now: int, language := "en") -> Dictionary:
	if context != _context or now > _deadline or language != _language:
		clear()
	_language = language
	var clean := Speech.normalise(text)
	for punctuation in [".", "!", ","]:
		clean = clean.replace(punctuation, "")
	var yes_words: Array = {"en": ["yes", "yes that is correct", "correct"], "de": ["ja", "ja das stimmt", "ja richtig", "ja genau", "genau", "richtig"], "pl": ["tak", "tak zgadza się", "zgadza się", "tak potwierdzam", "dokładnie"]}.get(language, [])
	var no_words: Array = {"en": ["no", "no that is wrong", "cancel"], "de": ["nein", "nein das stimmt nicht", "das stimmt nicht", "abbrechen"], "pl": ["nie", "nie zgadza się", "nie to nie tak", "anuluj"]}.get(language, [])
	if clean in yes_words:
		var confirmed := _action
		var breaths := _breaths
		clear()
		if confirmed in allowed:
			return {"action": confirmed, "breaths": breaths}
		return {"message": repeat_message(language)}
	if clean in no_words:
		clear()
		return {"message": repeat_message(language)}
	# A new utterance replaces any proposal; it cannot silently confirm an old one.
	clear()
	# Observed ASR confusion: ask explicitly about the pair. Never replace
	# arbitrary occurrences of "bread" or silently count an uncertain report.
	if clean in ["i have given two rescue bread", "i have given two rescue breads",
		"we have given two rescue bread", "we have given two rescue breads"] and "ventilation" in allowed:
		_action = "ventilation"
		_breaths = 2
		_context = context
		_deadline = now + LIFETIME_MS
		return {"proposal": "ventilation", "breaths": 2}
	var direct := Speech.action_for(text)
	if not direct.is_empty():
		return {"action": direct}
	# Bounded proposals, including the observed scene transcription error. Never
	# turn unrelated 'vaccine is safe', positive findings or compound claims into actions.
	var candidates := {
		"we have given the first bread": "ventilation",
		"i have given the first bread": "ventilation",
		"we have given the second bread": "ventilation",
		"i have given the second bread": "ventilation",
		"scene a save": "begin_check",
		"tassini's safe": "begin_check",
		"i think the scene is safe": "begin_check",
		"i think he is not responding": "check_responsiveness",
		"i think he is not breathing normally": "check_breathing"
	}
	var localized_candidates := {
		"de": {"ich glaube die umgebung ist sicher": "begin_check", "ich glaube er reagiert nicht": "check_responsiveness", "ich glaube er atmet nicht normal": "check_breathing"},
		"pl": {"myślę że miejsce jest bezpieczne": "begin_check", "myślę że pacjent nie reaguje": "check_responsiveness", "myślę że pacjent nie oddycha prawidłowo": "check_breathing"}
	}
	var candidate := str(candidates.get(clean, "")) if language == "en" else str(localized_candidates.get(language, {}).get(clean, ""))
	if candidate.is_empty() or candidate not in allowed:
		var fuzzy := Fuzzy.propose(text, language, allowed)
		if fuzzy.is_empty(): return {}
		_action = str(fuzzy.proposal)
		_breaths = int(fuzzy.breaths)
		_context = context
		_deadline = now + LIFETIME_MS
		return fuzzy
	_action = candidate
	_context = context
	_deadline = now + LIFETIME_MS
	return {"proposal": candidate}

static func repeat_message(language: String) -> String:
	return {"en": "No report confirmed. Please state the completed check and finding.", "de": "Keine Meldung bestätigt. Bitte sagen Sie, was Sie geprüft und festgestellt haben.", "pl": "Nie potwierdzono zgłoszenia. Powiedz, co sprawdzono i jaki był wynik."}.get(language, "Please repeat your report.")

static func question(action: String, breaths: int, language: String) -> String:
	var lines := {
		"en": {"begin_check": "Did you say the scene is safe? Say yes or no.", "check_responsiveness": "Did you report that he is not responding? Say yes or no.", "check_breathing": "Did you report that he is not breathing normally? Say yes or no.", "ventilation": "Did you complete one rescue breath? Say yes or no.", "pair": "Did you complete two rescue breaths? Say yes or no."},
		"de": {"begin_check": "Haben Sie gesagt, dass die Umgebung sicher ist? Antworten Sie mit ja oder nein.", "check_responsiveness": "Haben Sie festgestellt, dass er nicht reagiert? Antworten Sie mit ja oder nein.", "check_breathing": "Haben Sie festgestellt, dass er nicht normal atmet? Antworten Sie mit ja oder nein.", "ventilation": "Haben Sie eine Beatmung durchgeführt? Antworten Sie mit ja oder nein.", "pair": "Haben Sie zwei Beatmungen durchgeführt? Antworten Sie mit ja oder nein."},
		"pl": {"begin_check": "Czy miejsce jest bezpieczne? Odpowiedz tak lub nie.", "check_responsiveness": "Czy stwierdzono, że pacjent nie reaguje? Odpowiedz tak lub nie.", "check_breathing": "Czy stwierdzono, że pacjent nie oddycha prawidłowo? Odpowiedz tak lub nie.", "ventilation": "Czy wykonano jeden oddech ratowniczy? Odpowiedz tak lub nie.", "pair": "Czy wykonano dwa oddechy ratownicze? Odpowiedz tak lub nie."}
	}
	var key := "pair" if action == "ventilation" and breaths == 2 else action
	return str(lines.get(language, lines.en).get(key, repeat_message(language)))
