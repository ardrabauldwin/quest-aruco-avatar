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

static func action_for(text: String) -> String:
	var direct := _single_action(text)
	if not direct.is_empty(): return direct
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

static func reports_breath_pair(text: String) -> bool:
	# Explicit completed report only; no timing-based or inferred ventilation.
	var clean := normalise(text)
	if "?" in clean: return false
	for mark in [".", "!", ","]: clean = clean.replace(mark, "")
	return clean in ["two rescue breaths are given", "two rescue breaths have been given", "both rescue breaths are given", "both rescue breaths have been given", "i have given two rescue breaths", "i gave two rescue breaths", "i have given two breaths", "i gave two breaths", "i have given him two breaths", "i have given both breaths", "i have completed both rescue breaths", "ich habe zwei beatmungen gegeben", "ich habe beide beatmungen durchgeführt", "wykonałem dwa oddechy ratownicze", "wykonałam dwa oddechy ratownicze", "i have given 2 rescue breaths", "i have given 2 breaths"]
