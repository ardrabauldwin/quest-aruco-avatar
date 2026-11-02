extends RefCounted
## Exact, conservative phrase grammar. Reports are NOT physical verification.
## A report may follow patient-directed questions. Ambiguous or conflicting
## reports remain blocked; one utterance can produce at most one observation.
const PHRASES := {
	"start": ["start exercise", "start the exercise", "übung starten", "rozpocznij ćwiczenie"],
	"begin_check": ["the scene is safe", "scene is safe", "die umgebung ist sicher", "miejsce jest bezpieczne"],
	"check_responsiveness": ["he is not responding", "the patient is not responding", "er reagiert nicht", "pacjent nie reaguje"],
	"call_emergency": ["anna please call 112", "please call 112", "anna call 112", "bitte ruf 112 an", "anna ruf 112 an", "zadzwoń pod 112"],
	"check_breathing": ["he is not breathing normally", "the patient is not breathing normally", "er atmet nicht normal", "pacjent nie oddycha prawidłowo"],
	"ventilation": ["i have given one rescue breath", "ich habe eine beatmung gegeben", "wykonałem jeden oddech ratowniczy", "wykonałam jeden oddech ratowniczy"],
	"compression_only": ["use compression only mode", "nur herzdruckmassage", "tylko uciski klatki piersiowej"],
	"handover": ["hand over the patient", "patienten übergeben", "przekaż pacjenta"]
}

## Additional whole-utterance alternatives. These identify reports/requests,
## never verify physical actions or count compressions from spoken numbers.
const EXTRA_PHRASES := {
	"begin_check": [
		"it is safe to approach", "the surroundings are safe", "i checked the surroundings and the scene is safe",
		"die umgebung ist abgesichert", "ich kann mich sicher nähern", "ich habe die umgebung geprüft sie ist sicher",
		"można bezpiecznie podejść", "miejsce zdarzenia jest bezpieczne", "sprawdziłem otoczenie jest bezpieczne", "sprawdziłam otoczenie jest bezpieczne"
	],
	"check_responsiveness": [
		"he did not respond", "he did not react", "there is no response", "he does not respond to my voice",
		"der patient reagiert nicht auf ansprechen", "er reagiert nicht auf meine ansprache", "ich habe ihn angesprochen er reagiert nicht",
		"pacjent nie reaguje na mój głos", "pacjent nie reaguje na wołanie", "nie ma reakcji"
	],
	"call_emergency": [
		"anna please phone 112", "anna please call an ambulance", "please call emergency services",
		"anna ruf bitte die 112 an", "anna ruf bitte den rettungsdienst an", "bitte wählen sie die 112",
		"anno zadzwoń proszę pod 112", "anno wezwij pogotowie", "proszę wezwać pogotowie"
	],
	"check_breathing": [
		"he is not breathing at all", "there is no normal breathing", "i checked his breathing it is not normal",
		"er atmet überhaupt nicht", "ich habe die atmung geprüft er atmet nicht normal", "es ist keine normale atmung vorhanden",
		"pacjent wcale nie oddycha", "nie ma prawidłowego oddechu", "sprawdziłem oddech pacjent nie oddycha prawidłowo", "sprawdziłam oddech pacjent nie oddycha prawidłowo"
	],
	"ventilation": [
		"one rescue breath completed", "the first rescue breath is complete", "the second rescue breath is complete", "i have delivered one rescue breath",
		"ich habe die erste beatmung durchgeführt", "ich habe die zweite beatmung durchgeführt", "die erste beatmung ist durchgeführt", "die zweite beatmung ist durchgeführt",
		"pierwszy oddech ratowniczy wykonany", "drugi oddech ratowniczy wykonany", "pierwszy oddech wykonany", "drugi oddech wykonany"
	],
	"compression_only": [
		"select compression only mode", "choose compression only mode",
		"modus nur herzdruckmassage wählen", "nur herzdruckmassage auswählen",
		"wybieram tryb samych ucisków", "wybieram same uciski klatki piersiowej"
	],
	"handover": [
		"please hand over the patient", "hand the patient over to the ambulance crew",
		"bitte den patienten übergeben", "patienten an den rettungsdienst übergeben",
		"przekaż pacjenta ratownikom", "proszę przekazać pacjenta ratownikom"
	]
}

static func action_for(text: String) -> String:
	var direct := _single_action(text)
	if not direct.is_empty(): return direct
	var concept := preload("res://scripts/scenario/concept_reports.gd").action_for(text)
	if not concept.is_empty(): return concept
	var clean := normalise(text)
	# ASR sometimes omits punctuation. Remove only known patient-directed
	# questions at the beginning, never arbitrary words around a matched phrase.
	var greetings := ["are you okay", "are you ok", "can you hear me", "are you all right", "hello", "sir", "can you respond", "please open your eyes"]
	# Headset review 2026-10-29: "No, he is not responding" was refused as a negation.
	# A leading interjection followed by punctuation is not part of the finding. Only
	# with punctuation: a bare "no " must keep "no response" intact.
	for interjection: String in ["no", "yes", "okay", "ok", "well", "so", "alright", "right"]:
		for mark in [",", ".", "!", ";"]:
			if clean.begins_with(interjection + mark):
				clean = clean.substr(interjection.length() + 1).strip_edges()
	for _pass in range(8):
		var removed := false
		for prefix: String in greetings:
			if clean.begins_with(prefix + " ") or clean.begins_with(prefix + "?") or clean.begins_with(prefix + ".") or clean.begins_with(prefix + "!") or clean.begins_with(prefix + ","):
				clean = clean.substr(prefix.length()).strip_edges()
				while not clean.is_empty() and clean[0] in ["?", ".", "!", ","]:
					clean = clean.substr(1).strip_edges()
				removed = true
				break
		if not removed: break
	direct = _single_action(clean)
	if not direct.is_empty(): return direct
	var splitter := RegEx.new()
	splitter.compile("[^.!?;]+[.!?;]?")
	var found := ""
	for match_item in splitter.search_all(clean):
		var sentence := match_item.get_string().strip_edges()
		var neutral := sentence.trim_suffix("?").trim_suffix(".").trim_suffix("!").trim_suffix(";").strip_edges()
		if neutral in greetings: continue
		var action := _single_action(sentence)
		# Unknown context can contain a denial or hypothetical. Ask the learner
		# to clarify rather than silently extracting a dangerous substring.
		if action.is_empty(): return ""
		if not found.is_empty() and found != action: return ""
		found = action
	return found

static func _single_action(text: String) -> String:
	var clean := normalise(text)
	if "?" in clean: return ""
	for mark in [".", ",", "!", ":", ";"]:
		clean = clean.replace(mark, "")
	while "  " in clean: clean = clean.replace("  ", " ")
	for action: String in PHRASES:
		if clean in PHRASES[action]: return action
	for action: String in EXTRA_PHRASES:
		if clean in EXTRA_PHRASES[action]: return action
	var alternatives := {
		"check_responsiveness": ["he isn't responding", "the patient isn't responding", "no response", "he is unresponsive", "the patient is unresponsive"],
		"check_breathing": ["he isn't breathing normally", "he is not breathing", "he isn't breathing", "the patient is not breathing", "no normal breathing"],
		"begin_check": ["the area is safe", "the scene is clear"],
		"call_emergency": ["anna please call one one two", "please call one one two", "anna call emergency services", "anna please call emergency services"],
		"ventilation": ["i gave one rescue breath", "i have given a rescue breath", "i have given the first rescue breath", "i have given the second rescue breath", "i gave the first rescue breath", "i gave the second rescue breath", "i have given the first breath", "i have given the second breath", "i've given the first breath", "i've given the second breath", "i gave the first breath", "i gave the second breath", "we have given the first breath", "we have given the second breath"]
	}
	for action: String in alternatives:
		if clean in alternatives[action]: return action
	return ""

static func normalise(text: String) -> String:
	return text.to_lower().strip_edges().replace("’", "'").replace("\n", " ").replace("\r", " ")

## Explicit completed two-breath reports. Whisper only turns speech into text; it
## does not decide meaning, so every accepted wording is listed here. Plans,
## questions, denials and single-breath reports are deliberately absent.
const BREATH_PAIR_PHRASES := [
	# English
	"two rescue breaths are given", "two rescue breaths have been given", "both rescue breaths are given",
	"both rescue breaths have been given", "i have given two rescue breaths", "i gave two rescue breaths",
	"i have given two breaths", "i gave two breaths", "i have given him two breaths", "i have given both breaths",
	"i have completed both rescue breaths", "i have given 2 rescue breaths", "i have given 2 breaths",
	# German
	"ich habe zwei beatmungen gegeben", "ich habe beide beatmungen durchgeführt", "ich habe beide beatmungen gegeben",
	"ich habe zwei beatmungen durchgeführt", "ich habe zwei beatmungen gemacht", "ich habe beide beatmungen gemacht",
	"wir haben zwei beatmungen gegeben", "wir haben beide beatmungen gegeben", "zwei beatmungen gegeben",
	"zwei beatmungen sind gegeben", "beide beatmungen sind gegeben", "zwei beatmungen durchgeführt",
	"beide beatmungen durchgeführt", "ich habe zwei atemspenden gegeben", "ich habe beide atemspenden gegeben",
	"zwei atemspenden gegeben", "beide atemspenden gegeben", "ich habe zweimal beatmet", "ich habe zwei mal beatmet",
	"ich habe ihn zweimal beatmet", "ich habe ihn zwei mal beatmet", "ich habe 2 beatmungen gegeben",
	"ich habe 2 atemspenden gegeben", "ich habe 2 mal beatmet",
	# Polish
	"wykonałem dwa oddechy ratownicze", "wykonałam dwa oddechy ratownicze", "wykonałem dwa oddechy", "wykonałam dwa oddechy",
	"wykonałem oba oddechy", "wykonałam oba oddechy", "wykonałem oba oddechy ratownicze", "wykonałam oba oddechy ratownicze",
	"zrobiłem dwa oddechy", "zrobiłam dwa oddechy", "zrobiłem dwa oddechy ratownicze", "zrobiłam dwa oddechy ratownicze",
	"dałem dwa oddechy", "dałam dwa oddechy", "dałem dwa oddechy ratownicze", "dałam dwa oddechy ratownicze",
	"dwa oddechy wykonane", "dwa oddechy ratownicze wykonane", "oba oddechy wykonane", "oba oddechy ratownicze wykonane",
	"wykonałem 2 oddechy", "wykonałam 2 oddechy", "wykonałem 2 oddechy ratownicze", "wykonałam 2 oddechy ratownicze"
]

static func reports_breath_pair(text: String) -> bool:
	# Explicit completed report only; no timing-based or inferred ventilation.
	var clean := normalise(text)
	if "?" in clean: return false
	for mark in [".", "!", ","]: clean = clean.replace(mark, "")
	while "  " in clean: clean = clean.replace("  ", " ")
	return clean.strip_edges() in BREATH_PAIR_PHRASES
