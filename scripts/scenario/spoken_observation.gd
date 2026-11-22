extends RefCounted
## One file for understanding a spoken BLS report by rule, in English, German and Polish.
## Reports are NOT physical verification: a sentence can mark a step as reported, never
## prove that a hand moved. One utterance yields at most one step; anything unclear
## yields nothing and goes on to the confirmation question or the cloud interpreter.
##
## Layout, top to bottom:
##   1. normalise()            spelling out contractions and spoken numbers
##   2. grammar_action()       whole-sentence patterns per step and language
##   3. action_for()           the entry point: interjection and greeting stripping,
##                             two-sentence utterances, then the grammar
##   4. reports_breath_pair()  the explicit two-breath report list (exact, because a
##                             breath count must be exact)
##   5. classify_safety()      "safe" / "unsafe" / "" by meaning, for the first step only
##   6. aed_action_for()       the two spoken AED requests: fetch the AED, everyone clear
##   7. propose()              near-miss repair: one wrong word away from a rule becomes a
##                             yes/no proposal, never an accepted step
##
## History: the exact phrase tables, the concept_reports.gd grammar, safety_report.gd,
## aed_requests.gd and fuzzy_speech.gd were merged
## here on 11 Nov 2026 after the headset logs of 3 and 9 Nov showed correct transcripts
## ("He's not breathing at all", "Anna, please call 112 and put the call on speaker") that
## no rule accepted. Every rule needs the negation next to its verb; positive findings,
## questions, plans, doubts, conditionals, compounds and double negations are refused.

# --- 1. normalisation -------------------------------------------------------------------

const CONTRACTIONS := {
	"he's not": "he is not", "she's not": "she is not", "patient's not": "patient is not",
	"person's not": "person is not", "man's not": "man is not", "woman's not": "woman is not",
	"victim's not": "victim is not", "he's no longer": "he is no longer", "she's no longer": "she is no longer",
	"there's no": "there is no", "isn't": "is not", "doesn't": "does not", "hasn't": "has not",
	"didn't": "did not", "aren't": "are not", "can't": "cannot", "won't": "will not",
	"i've": "i have", "we've": "we have", "i'll": "i will", "let's": "let us",
	"one one two": "112", "eins eins zwei": "112", "jeden jeden dwa": "112",
}

static func normalise(text: String) -> String:
	var clean := text.to_lower().strip_edges().replace("’", "'").replace("\n", " ").replace("\r", " ")
	for short: String in CONTRACTIONS:
		clean = clean.replace(short, CONTRACTIONS[short])
	return clean

# --- 2. whole-sentence grammar -----------------------------------------------------------

static func grammar_action(text: String) -> String:
	var clean := normalise(text)
	# A vocative name with its comma is not a clause boundary: "Anna, please call 112".
	var vocative := RegEx.new()
	vocative.compile("^(?:anna|anno|ania|marek|marku)(?:\\s*[,!]\\s*|\\s+)")
	clean = vocative.sub(clean, "")
	# "I checked his breathing, it is not normal": the comma after a check clause is not a
	# compound either. Only these check clauses may carry one; anything else with a comma stays
	# refused below.
	var checked := RegEx.new()
	checked.compile("^((?:i (?:checked|examined|looked at) [^,]{2,40}|ich habe [^,]{2,40} (?:geprüft|überprüft|gecheckt|angesprochen|gerüttelt)|sprawdził(?:em|am) [^,]{2,30})),\\s*")
	clean = checked.sub(clean, "$1 ")
	# Keep commas/semicolons as clause boundaries: do not extract a report from a
	# denial, quotation, conditional, question, or compound statement.
	if clean.contains("?") or clean.contains(",") or clean.contains(";"): return ""
	while clean.ends_with(".") or clean.ends_with("!"):
		clean = clean.left(-1).strip_edges()
	var spaces := RegEx.new()
	spaces.compile("\\s+")
	clean = spaces.sub(clean, " ", true)
	var en_subject := "(?:he|she|the patient|this patient|the man|the woman|the person|the victim|the casualty)"
	var en_detail := "(?: (?:at all|any more|anymore|to me|to my voice|to touch|to shaking|when i shake him|when i shake her))?"
	var de_subject := "(?:er|sie|der patient|die patientin|dieser patient|der mann|die frau|die person|der verletzte)"
	var de_adverb := "(?:(?:überhaupt|gar|leider|weiterhin|jetzt|immer noch|auch) )?"
	var pl_subject := "(?:on|ona|pacjent|pacjentka|ten pacjent|mężczyzna|kobieta|ta osoba|poszkodowany|poszkodowana)"
	var pl_adverb := "(?:(?:nadal|w ogóle|wcale|już|dalej) )?"
	var rules := {
		"check_responsiveness": [
			en_subject + " (?:is not|is no longer) (?:responding|reacting|responsive|conscious|answering)" + en_detail + "(?: (?:and|or) (?:to )?(?:touch|shaking|my voice))?",
			en_subject + " does not (?:respond|react|answer|wake up)" + en_detail,
			en_subject + " (?:did not|has not) (?:respond|responded|react|reacted|wake up|woken up)" + en_detail,
			en_subject + " is (?:unresponsive|unconscious|not conscious|out cold)",
			"(?:there is |i get |i see )?no (?:response|reaction)(?: at all| from him| from her| to my voice| to touch)?",
			"not responding(?: at all)?", "unresponsive",
			"i (?:spoke to|shook|called) (?:him|her|the patient)(?: and)? (?:he|she|the patient) (?:is not responding|does not respond|did not respond|is unresponsive)",
			de_subject + " reagiert " + de_adverb + "nicht(?: mehr)?(?: auf (?:ansprache|ansprechen|anfassen|berührung|rütteln|schütteln|mich|meine stimme|meine ansprache|mein ansprechen)(?: (?:und|oder) (?:ansprache|ansprechen|anfassen|berührung|rütteln|schütteln))?)?",
			de_subject + " zeigt " + de_adverb + "keine reaktion(?: auf (?:ansprache|ansprechen|anfassen|berührung|rütteln|schütteln))?",
			de_subject + " (?:antwortet|wacht) " + de_adverb + "nicht(?: auf)?",
			de_subject + " ist " + de_adverb + "(?:nicht ansprechbar|bewusstlos|ohne bewusstsein|nicht bei bewusstsein)",
			"keine reaktion(?: auf (?:ansprache|ansprechen|anfassen|berührung|rütteln|schütteln))?", "nicht ansprechbar", "bewusstlos",
			"ich habe (?:ihn|sie|den patienten) (?:angesprochen|gerüttelt|geschüttelt)(?: und)? (?:er|sie) reagiert nicht",
			pl_subject + " " + pl_adverb + "nie (?:reaguje|odpowiada|odzywa się|budzi się)(?: na (?:głos|dotyk|wołanie|potrząsanie|mnie|mój głos)(?: (?:ani|i|lub) na (?:głos|dotyk|wołanie|potrząsanie))?| w ogóle| wcale)?",
			pl_subject + " (?:jest )?(?:nieprzytomny|nieprzytomna|bez świadomości)",
			pl_subject + " nie jest (?:przytomny|przytomna)",
			"(?:nie ma |brak )?(?:żadnej )?reakcji(?: na (?:głos|dotyk|wołanie|potrząsanie))?", "brak reakcji", "nie reaguje(?: w ogóle| wcale)?",
		],
		"check_breathing": [
			en_subject + " (?:is not|is no longer) breathing(?: (?:normally|properly|right|at all|any more|anymore))?",
			en_subject + " does not breathe(?: (?:normally|properly|at all))?",
			en_subject + " has stopped breathing",
			en_subject + " is (?:only |just )?gasping(?: for air)?",
			"(?:there is |i see |i can see |i feel |i hear )?no (?:normal )?breathing(?: at all)?",
			"(?:his |her |the |the patient's )?breathing is (?:not normal|abnormal|agonal)",
			"not breathing(?: (?:normally|at all))?", "no normal breathing", "agonal breathing", "(?:only |just )?gasping",
			"i checked (?:his|her|the|the patient's) breathing(?: and)? (?:it is not normal|he is not breathing(?: normally)?|she is not breathing(?: normally)?|there is no normal breathing)",
			de_subject + " atmet " + de_adverb + "nicht(?: mehr)?(?: (?:normal|normalerweise|richtig))?",
			de_subject + " hat aufgehört zu atmen",
			de_subject + " (?:hat|zeigt) " + de_adverb + "(?:eine )?schnappatmung",
			de_subject + " schnappt nur nach luft",
			"(?:es ist |es gibt |ich sehe |ich spüre |ich höre )?keine (?:normale )?atmung(?: (?:vorhanden|feststellbar|erkennbar|mehr))?",
			"(?:die |seine |ihre )?atmung ist nicht normal", "schnappatmung", "atmet nicht(?: normal)?",
			"ich habe (?:die|seine|ihre) atmung (?:geprüft|überprüft|gecheckt)(?: und)? (?:er|sie) atmet nicht(?: normal)?",
			pl_subject + " " + pl_adverb + "nie oddycha(?: (?:normalnie|prawidłowo|poprawnie|w ogóle|wcale))?",
			pl_subject + " (?:przestał|przestała) oddychać",
			pl_subject + " (?:ma |tylko )?(?:oddech agonalny|łapie powietrze)",
			"(?:nie ma |brak )(?:prawidłowego |normalnego |żadnego )?oddechu(?: w ogóle)?",
			"(?:jego |jej )?oddech (?:jest )?(?:nieprawidłowy|nienormalny|agonalny)", "oddech nie jest (?:prawidłowy|normalny)",
			"nie oddycha(?: (?:prawidłowo|normalnie|w ogóle|wcale))?", "oddech agonalny",
			"sprawdził(?:em|am) oddech(?: i)? (?:pacjent |on |ona )?nie oddycha(?: (?:prawidłowo|normalnie))?",
		],
		"begin_check": [
			"(?:the )?(?:scene|area|surroundings|place|environment) (?:is|are) (?:(?:now|completely|all) )?(?:safe|clear|secure|secured)",
			"it is safe(?: to approach| here)?", "(?:everything|all) is safe(?: here)?", "no danger(?: here)?",
			"i checked (?:the surroundings|the scene|the area|around)(?: and)? (?:the scene|the area|it|everything) is (?:safe|clear)",
			"(?:die umgebung|die einsatzstelle|der ort|die stelle) ist (?:(?:jetzt|hier|komplett) )?(?:sicher|abgesichert|gesichert)",
			"ich kann mich sicher nähern", "(?:es ist|alles ist|hier ist es) sicher", "keine gefahr",
			"ich habe (?:die umgebung|die einsatzstelle) (?:geprüft|überprüft|gecheckt)(?: und)? (?:sie|es|alles) ist sicher",
			"(?:miejsce|otoczenie|miejsce zdarzenia) jest (?:(?:teraz|już|całkowicie) )?bezpieczne",
			"można bezpiecznie podejść", "(?:jest|wszystko jest|tu jest) bezpiecznie", "nie ma zagrożenia",
			"sprawdził(?:em|am) (?:otoczenie|miejsce)(?: i)? (?:jest|wszystko jest) bezpieczn(?:e|ie)",
		],
		"ventilation": [
			"(?:i|we) (?:have (?:just |already |now )?)?(?:given|gave|delivered|completed) (?:him |her |the patient )?(?:one|a|the first|the second) (?:rescue )?breath",
			"(?:one|a|the first|the second) (?:rescue )?breath (?:is )?(?:completed|complete|done|given|delivered)",
			"(?:ich habe|wir haben) (?:(?:gerade|bereits|jetzt) )?(?:ihm |ihr |dem patienten )?(?:eine|die erste|die zweite) (?:beatmung|atemspende) (?:gegeben|durchgeführt|gemacht)",
			"(?:ich habe|wir haben) (?:(?:ihn|sie|den patienten) )?einmal beatmet",
			"(?:die )?(?:erste|zweite) (?:beatmung|atemspende) (?:ist )?(?:durchgeführt|gegeben|gemacht|erledigt)",
			"(?:właśnie |już )?(?:wykonałem|wykonałam|podałem|podałam|zrobiłem|zrobiłam) (?:już |właśnie )?(?:pacjentowi )?(?:jeden|pierwszy|drugi) oddech(?: ratowniczy)?",
			"(?:pierwszy|drugi|jeden) oddech(?: ratowniczy)? (?:wykonany|zrobiony|podany)",
		],
		"call_emergency": [
			"(?:please )?(?:call|phone|ring|dial) (?:112|the 112|the emergency number|emergency services|the emergency services|an ambulance|the ambulance|for an ambulance)(?: please)?(?: now)?(?: and (?:put (?:it|the call|the phone) on speaker|use the speaker|switch on the speaker))?",
			"(?:bitte )?(?:ruf|rufe|rufen sie|wähl|wähle|wählen sie) (?:bitte )?(?:die |den |einen )?(?:112|notruf|rettungsdienst|krankenwagen|rettungswagen)(?: an)?(?: bitte)?(?: und (?:stell|stelle|stellen sie) (?:das telefon |den anruf )?auf (?:lautsprecher|laut))?",
			"(?:proszę )?(?:zadzwoń|zadzwonić|wezwij|wezwać|dzwoń) (?:proszę )?(?:pod (?:numer )?112|na 112|po pogotowie|pogotowie|po karetkę|karetkę|pomoc pod numerem 112)(?: proszę)?(?: i (?:włącz|włączyć) (?:głośnomówiący|tryb głośnomówiący|głośnik))?"
		],
		"start": [
			"(?:please )?(?:start|begin) (?:the )?(?:exercise|training|scenario)", "let us (?:start|begin)(?: the (?:exercise|training))?",
			"(?:die )?(?:übung|das training) (?:starten|beginnen)", "(?:bitte )?(?:übung|training) starten",
			"(?:rozpocznij|zacznij|rozpocznijmy|zacznijmy) ćwiczenie", "start ćwiczenia", "zaczynamy(?: ćwiczenie)?",
		],
		"compression_only": [
			"(?:please )?(?:use|select|choose|switch to) (?:the )?compression(?: |-)only(?: mode)?", "compression(?: |-)only(?: mode)?",
			"(?:i will|we will) (?:do|give) (?:compressions|chest compressions) only",
			"(?:modus )?nur herzdruckmassage(?: wählen| auswählen)?", "nur (?:drücken|kompressionen|thoraxkompressionen)",
			"tylko uciski(?: klatki piersiowej)?", "wybieram (?:tryb samych ucisków|same uciski(?: klatki piersiowej)?)", "same uciski",
		],
		"handover": [
			"(?:please )?hand (?:over )?the patient(?: over)?(?: to (?:the )?(?:ambulance|ambulance crew|paramedics|emergency services))?",
			"(?:i|we) hand (?:the patient |him |her )?over(?: to (?:the )?(?:ambulance|ambulance crew|paramedics))?", "handover",
			"(?:bitte )?(?:den )?patienten(?: an den rettungsdienst)? übergeben", "(?:ich )?übergebe (?:den patienten|an den rettungsdienst)",
			"(?:proszę )?(?:przekaż|przekazać) pacjenta(?: ratownikom)?", "przekazuję pacjenta(?: ratownikom)?",
		]
	}
	for action: String in rules:
		for pattern: String in rules[action]:
			var matcher := RegEx.new()
			matcher.compile("^(?:" + pattern + ")$")
			if matcher.search(clean) != null: return action
	return ""

# --- 3. entry point ----------------------------------------------------------------------

## Sentences a rescuer says to the patient, not to the app. Cut off the front of an utterance
## before the rules judge the rest: "Are you okay? Can you hear me? He is not responding."
## German and Polish added 11 Nov 2026; only this list, only at the front, never mid-sentence.
const PATIENT_ADDRESS := [
	"are you okay", "are you ok", "can you hear me", "are you all right", "hello", "sir", "can you respond", "please open your eyes",
	"hallo", "hören sie mich", "können sie mich hören", "alles in ordnung", "geht es ihnen gut", "ist alles in ordnung",
	"machen sie die augen auf", "öffnen sie die augen", "wachen sie auf", "hey",
	"halo", "słyszy mnie pan", "słyszy mnie pani", "czy mnie pan słyszy", "czy mnie pani słyszy", "wszystko w porządku",
	"czy wszystko w porządku", "proszę otworzyć oczy", "proszę pana", "proszę pani",
	# du-form of the didactic structure (issue #1, 3. Reaktion prüfen, 17 Nov 2026)
	"open your eyes", "hörst du mich", "hallo hörst du mich", "kannst du mich hören", "öffne die augen",
	"mach die augen auf", "czy mnie słyszysz", "halo czy mnie słyszysz", "słyszysz mnie", "otwórz oczy",
]

## Phrases that are clearly spoken TO the patient to test his response (issue #1, gate
## "lautes Ansprechen"): found anywhere in the utterance, not only at its front.
const RESPONSE_ADDRESS := ["can you hear me", "open your eyes", "are you okay", "are you ok", "are you all right",
	"hörst du mich", "kannst du mich hören", "hören sie mich", "können sie mich hören", "öffne die augen",
	"mach die augen auf", "machen sie die augen auf", "öffnen sie die augen", "czy mnie słyszysz", "słyszysz mnie",
	"otwórz oczy", "czy mnie pan słyszy", "czy mnie pani słyszy", "słyszy mnie pan", "słyszy mnie pani", "proszę otworzyć oczy",
	# Any similar wording (17 Nov 2026): a loud greeting or wake-up call counts too.
	"hallo", "hello", "halo", "hey", "hörst du", "hören sie", "can you hear", "słyszysz", "słyszy pan", "słyszy pani",
	"wach auf", "wachen sie auf", "wake up", "obudź się", "alles okay", "alles in ordnung", "geht es dir gut",
	"geht es ihnen gut", "wszystko w porządku", "augen auf", "eyes open"]

static func is_response_address(text: String) -> bool:
	var clean := normalise(text)
	for phrase: String in RESPONSE_ADDRESS:
		if phrase in clean: return true
	return false

static func action_for(text: String) -> String:
	var direct := grammar_action(text)
	if not direct.is_empty(): return direct
	var clean := normalise(text)
	# ASR sometimes omits punctuation. Remove only known patient-directed
	# questions at the beginning, never arbitrary words around a matched phrase.
	var greetings := PATIENT_ADDRESS
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
	direct = grammar_action(clean)
	if not direct.is_empty(): return direct
	var splitter := RegEx.new()
	splitter.compile("[^.!?;]+[.!?;]?")
	var found := ""
	for match_item in splitter.search_all(clean):
		var sentence := match_item.get_string().strip_edges()
		var neutral := sentence.trim_suffix("?").trim_suffix(".").trim_suffix("!").trim_suffix(";").strip_edges()
		if neutral in greetings: continue
		var action := grammar_action(sentence)
		# Unknown context can contain a denial or hypothetical. Ask the learner
		# to clarify rather than silently extracting a dangerous substring.
		if action.is_empty(): return ""
		if not found.is_empty() and found != action: return ""
		found = action
	return found

## Two or more steps in one breath, in order: "The scene is safe. He is not responding."
## (11 Nov 2026). Every sentence that is not a patient-directed question must itself be a
## clear report, otherwise nothing is returned and the utterance stays with action_for():
## an unclear or opposite clause must not be dropped silently. Consecutive repeats collapse.
## The sentence without the patient-directed questions at its front ("hallo, hören sie
## mich? er reagiert nicht" -> "er reagiert nicht"); "" when nothing else was said.
static func without_patient_address(sentence: String) -> String:
	var rest := sentence.strip_edges()
	for _pass in range(8):
		var removed := false
		for prefix: String in PATIENT_ADDRESS:
			if rest == prefix:
				return ""
			for mark in [" ", "?", ".", "!", ","]:
				if rest.begins_with(prefix + mark):
					rest = rest.substr(prefix.length()).strip_edges()
					while not rest.is_empty() and rest[0] in ["?", ".", "!", ","]:
						rest = rest.substr(1).strip_edges()
					removed = true
					break
			if removed: break
		if not removed: break
	return rest

static func actions_for(text: String) -> Array[String]:
	var clean := normalise(text)
	var splitter := RegEx.new()
	splitter.compile("[^.!?;]+[.!?;]?")
	var found: Array[String] = []
	for match_item in splitter.search_all(clean):
		var sentence := match_item.get_string().strip_edges()
		var neutral := sentence.trim_suffix("?").trim_suffix(".").trim_suffix("!").trim_suffix(";").strip_edges()
		var rest := without_patient_address(neutral)
		if rest.is_empty(): continue
		var action := grammar_action(rest if rest != neutral else sentence)
		if action.is_empty():
			found.clear()
			return found
		if found.is_empty() or found[found.size() - 1] != action:
			found.append(action)
	if found.size() < 2:
		found.clear()
	return found

# --- 4. explicit two-breath reports ------------------------------------------------------

## Whisper only turns speech into text; it does not decide meaning, so every accepted
## wording is listed here. Plans, questions, denials and single-breath reports are absent.
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

# --- 5. scene safety by meaning ----------------------------------------------------------

## Headset feedback 2026-11-03: trainees got stuck at the first step because only whole known
## sentences were accepted and "the scene is not safe" had no answer. Here a danger or a negation
## of safety wins over a safety word; questions and conditionals are never reports.

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


static func classify_safety(text: String, language: String) -> String:
	var clean := " " + _safety_normalise(text) + " "
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


static func _safety_normalise(text: String) -> String:
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

# --- 6. spoken AED requests --------------------------------------------------------------

## Explicit operational requests only; no voice attachment or shock commands.
## "Anna, call 112, and Marek, bring the AED" (13 Nov 2026: both are asked for at the
## call step). The device and a fetching verb in the sentence, no negation: Marek is
## sent. The name is not required: the recogniser writes Marek as Mark or Merck.
const AED_WORDS := ["aed", "a.e.d", "defibrillator", "defibrilator", "defi ", "defibrylator"]
const FETCH_WORDS := ["bring", "get ", "fetch", "grab", "hol", "besorg", "przynie", "przynieś", "idź po", "idz po"]
const CALL_WORDS := ["112", "one one two", "one-one-two", "call", "ruf", "notruf", "zadzwo", "dzwoń", "dzwon"]
const FETCH_NEGATIONS := [" not ", "don't", "do not", " nicht ", " kein", " nie "]

static func mentions_aed_fetch(text: String) -> bool:
	var words := " " + text.to_lower() + " "
	for negation: String in FETCH_NEGATIONS:
		if negation in words: return false
	var device := false
	for word: String in AED_WORDS: device = device or word in words
	var fetch := false
	for word: String in FETCH_WORDS: fetch = fetch or word in words
	return device and fetch

static func mentions_emergency_call(text: String) -> bool:
	var words := text.to_lower()
	for word: String in CALL_WORDS:
		if word in words: return true
	return false

static func without_aed_clause(text: String) -> String:
	## The sentence with the part about the device removed, for the rest of the pipeline.
	var kept: Array[String] = []
	var clause := ""
	var parts: Array[String] = []
	for piece in text.replace(" and ", "|").replace(" und ", "|").replace(" oraz ", "|").replace(" a ", "|") \
			.replace(",", "|").replace(".", "|").replace(";", "|").replace("!", "|").replace("?", "|").split("|", false):
		parts.append(piece.strip_edges())
	for part in parts:
		clause = " " + part.to_lower() + " "
		var device := false
		for word: String in AED_WORDS: device = device or word in clause
		if not device and not part.is_empty(): kept.append(part)
	return ", ".join(kept)

static func aed_action_for(text: String) -> String:
	var words := text.to_lower().strip_edges().trim_suffix(".").trim_suffix("!")
	if words in ["everyone clear", "everyone is clear", "everybody is clear", "nobody is touching him now", "all clear", "alle sind zurückgetreten", "wszyscy się odsunęli", "stand clear", "nobody is touching the patient", "alle zurück", "alle zurueck", "niemand berührt den patienten", "niemand beruehrt den patienten", "wszyscy odsunąć się", "nikt nie dotyka pacjenta"]:
		return "clear_patient"
	if words in ["marek, please bring the aed", "marek please bring the aed", "please bring the aed", "marek, get the aed", "marek get the aed", "marek, bring bitte den aed", "marek bring bitte den aed", "bitte hol den aed", "marek, przynieś aed", "marek przynieś aed", "przynieś aed"]:
		return "request_aed"
	return ""

# --- 7. near-miss repair proposals -------------------------------------------------------

## Similarity can propose a report, never establish a finding or count a breath.
## Thresholds are prototype policy, not calibrated recognition probabilities.
const MIN_SIMILARITY := 0.80
const MIN_MARGIN := 0.08
const ANCHORS := {
	"en": {
		"begin_check": ["the scene is safe", "the area is safe", "the environment is safe", "the surroundings are safe"],
		"check_responsiveness": ["he is not responding", "the patient is not responding", "he is unresponsive", "the person is not responding"],
		"check_breathing": ["he is not breathing", "he is not breathing normally", "the patient is not breathing normally", "the person is not breathing normally", "the person is not breathing"],
		"ventilation": ["i have given one rescue breath", "i gave one rescue breath", "i have given the first rescue breath", "i have given the second rescue breath", "we have given the first breath"],
		"breath_pair": ["i have given two rescue breaths", "we have given two rescue breaths"]
	},
	"de": {
		"begin_check": ["die umgebung ist sicher", "die einsatzstelle ist sicher"],
		"check_responsiveness": ["er reagiert nicht", "der patient reagiert nicht", "die person reagiert nicht"],
		"check_breathing": ["er atmet nicht normal", "der patient atmet nicht normal", "die person atmet nicht normal", "die person atmet nicht"],
		"ventilation": ["ich habe eine beatmung gegeben", "ich habe die erste beatmung gegeben", "ich habe die zweite beatmung gegeben", "ich habe eine atemspende gegeben"],
		"breath_pair": ["ich habe zwei beatmungen gegeben", "ich habe beide beatmungen gegeben"]
	},
	"pl": {
		"begin_check": ["miejsce jest bezpieczne", "otoczenie jest bezpieczne"],
		"check_responsiveness": ["pacjent nie reaguje", "on nie reaguje", "osoba nie reaguje"],
		"check_breathing": ["pacjent nie oddycha prawidłowo", "on nie oddycha normalnie", "osoba nie oddycha normalnie", "osoba nie oddycha"],
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

# --- 8. bystander intent from a free sentence ----------------------------------------------

## Narrow keyword intents for the bystander directors and tests ("keep_clear", "reassure",
## "call_emergency", "request_aed"). No free-text command administers a shock, records a
## compression, proves a breathing check, or changes patient vitals. Moved here from
## language_manager.gd on 11 Nov 2026 so that file holds texts only.
static func normalize(transcript: String) -> String:
	var normalized := transcript.to_lower().strip_edges()
	var replacements := {"ä": "a", "ö": "o", "ü": "u", "ß": "ss", "ą": "a", "ć": "c", "ę": "e", "ł": "l", "ń": "n", "ó": "o", "ś": "s", "ź": "z", "ż": "z"}
	for from: String in replacements:
		normalized = normalized.replace(from, replacements[from])
	for symbol: String in [".", ",", ":", ";", "!", "?", "-", "\n", "\t"]:
		normalized = normalized.replace(symbol, " ")
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")
	return " " + normalized.strip_edges() + " "

static func infer_action(transcript: String) -> String:
	var line := normalize(transcript)
	if line.strip_edges().is_empty():
		return ""
	# Keep this deliberately narrow: no free-text command administers a shock,
	# records a compression, proves a breathing check, or changes patient vitals.
	# "Abstand! Nicht berühren!" is checked before the negation guard below.
	if [" abstand", " zuruck", " weg da ", " gehen sie weg", " nicht beruhr", " nicht anfass", " finger weg",
			" odsun", " nie dotyk", " prosze odejsc", " z daleka ", " stand clear ", " step back "].any(func(w): return w in line):
		return "keep_clear"
	if [" nicht ", " kein ", " keine ", " keinesfalls ", " nie ", " not ", " don't ", " never "].any(func(w): return w in line):
		if [" angst ", " boj ", " martw ", " panik "].any(func(w): return w in line):
			return "reassure"
		return ""
	if [" 112 ", " notruf ", " rettungsdienst ", " pogotowie ", " pogotowia ", " emergency services ", " ambulance "].any(func(w): return w in line):
		if [" ruf ", " rufen ", " anrufen ", " alarmier", " wezw", " zadzwon", " dzwon", " call ", " phone "].any(func(w): return w in line):
			return "call_emergency"
	if [" aed ", " defibrillator ", " defibrylator "].any(func(w): return w in line):
		if [" hol ", " holen ", " hole ", " bring ", " bringen ", " przynies", " przyniose", " szuk", " fetch "].any(func(w): return w in line):
			return "request_aed"
	if [" ruhig ", " beruhig", " ich helfe ", " wir helfen ", " spokoj", " pomoge ", " pomozemy ", " stay calm ", " i will help "].any(func(w): return w in line):
		return "reassure"
	return ""
