extends RefCounted
## Whole-report slot grammar, not keyword extraction. Unknown surrounding clauses
## fall through to the interpreter; finding negation must stay with its verb.
static func action_for(text: String) -> String:
	var clean := text.to_lower().strip_edges().replace("’", "'")
	# Keep commas/semicolons as clause boundaries: do not extract a report from a
	# denial, quotation, conditional, question, or compound statement.
	if clean.contains("?") or clean.contains(",") or clean.contains(";"): return ""
	while clean.ends_with(".") or clean.ends_with("!"):
		clean = clean.left(-1).strip_edges()
	var spaces := RegEx.new()
	spaces.compile("\\s+")
	clean = spaces.sub(clean, " ", true)
	var en_subject := "(?:he|the patient|this patient)"
	var de_subject := "(?:er|der patient|dieser patient|der mann)"
	var pl_subject := "(?:on|pacjent|ten pacjent|mężczyzna)"
	var rules := {
		"check_responsiveness": [
			en_subject + " (?:(?:is not|isn't) responding|(?:does not|doesn't) respond)",
			de_subject + " reagiert (?:(?:überhaupt|gar|leider|weiterhin) )?nicht(?: auf (?:ansprache|berührung))?",
			de_subject + " zeigt (?:(?:weiterhin|leider) )?keine reaktion",
			"keine reaktion",
			pl_subject + " (?:(?:nadal|w ogóle) )?nie (?:reaguje|odpowiada)(?: na (?:głos|dotyk)| w ogóle)?",
			"brak reakcji"
		],
		"check_breathing": [
			en_subject + " (?:is not|isn't) breathing(?: (?:normally|at all))?",
			en_subject + " (?:does not|doesn't) breathe(?: normally)?",
			de_subject + " atmet (?:(?:leider|weiterhin) )?nicht(?: (?:normal|normalerweise|mehr))?",
			"keine normale atmung",
			pl_subject + " (?:(?:nadal|w ogóle) )?nie oddycha(?: (?:normalnie|prawidłowo|w ogóle))?",
			"brak (?:prawidłowego|normalnego) oddechu"
		],
		"begin_check": [
			"(?:the scene|the area|the surroundings) (?:is|are) (?:(?:now|completely) )?safe",
			"(?:die umgebung|die einsatzstelle) ist (?:(?:jetzt|hier) )?sicher",
			"(?:miejsce|otoczenie|miejsce zdarzenia) jest (?:(?:teraz|już) )?bezpieczne"
		],
		"ventilation": [
			"(?:i|we) (?:have (?:just |already )?given|gave) (?:him |the patient )?(?:one|a|the first|the second) (?:rescue )?breath",
			"(?:ich habe|wir haben) (?:(?:gerade|bereits|jetzt) )?(?:ihm |dem patienten )?(?:eine|die erste|die zweite) (?:beatmung|atemspende) (?:gegeben|durchgeführt)",
			"(?:ich habe|wir haben) (?:(?:ihn|den patienten) )?einmal beatmet",
			"(?:właśnie |już )?(?:wykonałem|wykonałam|podałem|podałam|zrobiłem|zrobiłam) (?:już |właśnie )?(?:pacjentowi )?(?:jeden|pierwszy|drugi) oddech(?: ratowniczy)?"
		],
		"call_emergency": [
			"(?:anna )?(?:bitte )?ruf (?:112|die 112|den rettungsdienst) an",
			"(?:(?:anna|anno) )?(?:proszę )?zadzwoń (?:pod (?:numer )?112|po pogotowie)"
		]
	}
	for action: String in rules:
		for pattern: String in rules[action]:
			var matcher := RegEx.new()
			matcher.compile("^(?:" + pattern + ")$")
			if matcher.search(clean) != null: return action
	return ""
