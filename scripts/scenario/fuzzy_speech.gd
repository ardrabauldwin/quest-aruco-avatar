extends RefCounted
## Similarity can propose a report, never establish a finding or count a breath.
## Thresholds are prototype policy, not calibrated recognition probabilities.
const MIN_SIMILARITY := 0.80
const MIN_MARGIN := 0.08
const ANCHORS := {
	"en": {
		"begin_check": ["the scene is safe", "the area is safe"],
		"check_responsiveness": ["he is not responding", "the patient is not responding", "he is unresponsive"],
		"check_breathing": ["he is not breathing", "he is not breathing normally", "the patient is not breathing normally"],
		"ventilation": ["i have given one rescue breath", "i gave one rescue breath", "i have given the first rescue breath", "i have given the second rescue breath", "we have given the first breath"],
		"breath_pair": ["i have given two rescue breaths", "we have given two rescue breaths"]
	},
	"de": {
		"begin_check": ["die umgebung ist sicher", "die einsatzstelle ist sicher"],
		"check_responsiveness": ["er reagiert nicht", "der patient reagiert nicht"],
		"check_breathing": ["er atmet nicht normal", "der patient atmet nicht normal"],
		"ventilation": ["ich habe eine beatmung gegeben", "ich habe die erste beatmung gegeben", "ich habe die zweite beatmung gegeben", "ich habe eine atemspende gegeben"],
		"breath_pair": ["ich habe zwei beatmungen gegeben", "ich habe beide beatmungen gegeben"]
	},
	"pl": {
		"begin_check": ["miejsce jest bezpieczne", "otoczenie jest bezpieczne"],
		"check_responsiveness": ["pacjent nie reaguje", "on nie reaguje"],
		"check_breathing": ["pacjent nie oddycha prawidłowo", "on nie oddycha normalnie"],
		"ventilation": ["wykonałem jeden oddech ratowniczy", "wykonałam jeden oddech ratowniczy", "wykonałem pierwszy oddech ratowniczy", "wykonałam drugi oddech ratowniczy"],
		"breath_pair": ["wykonałem dwa oddechy ratownicze", "wykonałam dwa oddechy ratownicze"]
	}
}
const NEGATIONS := ["not", "no", "isn't", "doesn't", "nicht", "kein", "keine", "keinen", "nie", "nigdy"]
const NUMBERS := ["one", "a", "first", "second", "two", "both", "1", "2", "3", "three", "eine", "erste", "zweite", "zwei", "beide", "drei", "jeden", "pierwszy", "drugi", "dwa", "oba", "trzy"]
const BLOCKERS := ["will", "would", "should", "might", "if", "maybe", "think", "perhaps", "and", "but", "or", "said", "says", "deny", "true", "actually", "abnormally", "werde", "werden", "würde", "soll", "wenn", "vielleicht", "glaube", "und", "aber", "oder", "sagt", "doch", "będę", "będzie", "czy", "jeśli", "może", "chyba", "i", "ale", "lub", "powiedział", "naprawdę"]

static func clean_text(text: String) -> String:
	var clean := text.to_lower().strip_edges().replace("’", "'")
	for mark in [".", "!", ","]: clean = clean.replace(mark, " ")
	var spaces := RegEx.new()
	spaces.compile("\\s+")
	return spaces.sub(clean, " ", true).strip_edges()

static func _protected(words: PackedStringArray, vocabulary: Array) -> Array:
	var found := []
	for word in words:
		if word in vocabulary: found.append(word)
	return found

static func propose(text: String, language: String, allowed: Array) -> Dictionary:
	if not ANCHORS.has(language) or text.length() > 240: return {}
	for mark in ["?", ";", ":", "\"", "“", "”", "\n"]:
		if mark in text: return {}
	var clean := clean_text(text)
	var words := clean.split(" ", false)
	if words.size() < 3: return {}
	for word in words:
		if word in ["unsafe", "unsicher", "niebezpieczne", "niebezpieczny", "unnormal", "abnormal", "nieprawidłowo", "denied", "forgotten"]: return {}
		# English I is a subject, Polish i is the conjunction 'and'.
		if word in BLOCKERS and not (word == "i" and language == "en"): return {}
	# Score every report class first; an unavailable action must not be forced
	# into the currently expected class just because it is the only allowed one.
	var scores := []
	for kind: String in ANCHORS[language]:
		var score := 0.0
		for anchor: String in ANCHORS[language][kind]:
			var reference := anchor.split(" ", false)
			if _protected(words, NEGATIONS) != _protected(reference, NEGATIONS): continue
			if kind in ["ventilation", "breath_pair"] and _protected(words, NUMBERS) != _protected(reference, NUMBERS): continue
			# Same token count, one misspelled/substituted token only. This avoids
			# repairing an omitted negation, added clause or changed breath count.
			if words.size() != reference.size(): continue
			var changes := 0
			for index in words.size():
				if words[index] != reference[index]: changes += 1
			if changes != 1: continue
			score = maxf(score, clean.similarity(anchor))
		scores.append({"kind": kind, "score": score})
	scores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	var best: Dictionary = scores[0]
	if best.score < MIN_SIMILARITY or best.score - scores[1].score < MIN_MARGIN: return {}
	var action := "ventilation" if best.kind == "breath_pair" else str(best.kind)
	if action not in allowed: return {}
	return {"proposal": action, "breaths": 2 if best.kind == "breath_pair" else 1, "similarity": best.score}
