extends RefCounted
## Whole-report slot grammar, not keyword extraction. Unknown surrounding clauses
## fall through to the interpreter; finding negation must stay with its verb.
##
## 
const CONTRACTIONS := {
	"he's not": "he is not", "she's not": "she is not", "patient's not": "patient is not",
	"person's not": "person is not", "man's not": "man is not", "woman's not": "woman is not",
	"victim's not": "victim is not", "he's no longer": "he is no longer", "she's no longer": "she is no longer",
	"there's no": "there is no", "isn't": "is not", "doesn't": "does not", "hasn't": "has not",
	"didn't": "did not", "aren't": "are not", "can't": "cannot", "won't": "will not",
}

static func normalise(text: String) -> String:
	var clean := text.to_lower().strip_edges().replace("’", "'")
	for short: String in CONTRACTIONS:
		clean = clean.replace(short, CONTRACTIONS[short])
	return clean

static func action_for(text: String) -> String:
	var clean := normalise(text)
	# A vocative name with its comma is not a clause boundary: "Anna, please call 112".
	var vocative := RegEx.new()
	vocative.compile("^(?:anna|anno|ania|marek|marku)(?:\\s*[,!]\\s*|\\s+)")
	clean = vocative.sub(clean, "")
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
			en_subject + " (?:is not|is no longer) (?:responding|reacting|responsive|conscious|answering)" + en_detail,
			en_subject + " does not (?:respond|react|answer|wake up)" + en_detail,
			en_subject + " (?:did not|has not) (?:respond|responded|react|reacted|wake up|woken up)" + en_detail,
			en_subject + " is (?:unresponsive|unconscious|not conscious|out cold)",
			"(?:there is |i get |i see )?no (?:response|reaction)(?: at all| from him| from her| to my voice| to touch)?",
			"not responding(?: at all)?", "unresponsive",
			de_subject + " reagiert " + de_adverb + "nicht(?: mehr)?(?: auf (?:ansprache|ansprechen|anfassen|berührung|rütteln|schütteln|mich|meine stimme))?",
			de_subject + " zeigt " + de_adverb + "keine reaktion(?: auf (?:ansprache|ansprechen|anfassen|berührung|rütteln|schütteln))?",
			de_subject + " (?:antwortet|wacht) " + de_adverb + "nicht(?: auf)?",
			de_subject + " ist " + de_adverb + "(?:nicht ansprechbar|bewusstlos|ohne bewusstsein|nicht bei bewusstsein)",
			"keine reaktion(?: auf (?:ansprache|ansprechen|anfassen|berührung|rütteln|schütteln))?", "nicht ansprechbar", "bewusstlos",
			pl_subject + " " + pl_adverb + "nie (?:reaguje|odpowiada|odzywa się|budzi się)(?: na (?:głos|dotyk|wołanie|potrząsanie|mnie|mój głos)| w ogóle| wcale)?",
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
			de_subject + " atmet " + de_adverb + "nicht(?: mehr)?(?: (?:normal|normalerweise|richtig))?",
			de_subject + " hat aufgehört zu atmen",
			de_subject + " (?:hat|zeigt) " + de_adverb + "(?:eine )?schnappatmung",
			de_subject + " schnappt nur nach luft",
			"(?:es ist |es gibt |ich sehe |ich spüre |ich höre )?keine (?:normale )?atmung(?: (?:vorhanden|feststellbar|erkennbar|mehr))?",
			"(?:die |seine |ihre )?atmung ist nicht normal", "schnappatmung", "atmet nicht(?: normal)?",
			pl_subject + " " + pl_adverb + "nie oddycha(?: (?:normalnie|prawidłowo|poprawnie|w ogóle|wcale))?",
			pl_subject + " (?:przestał|przestała) oddychać",
			pl_subject + " (?:ma |tylko )?(?:oddech agonalny|łapie powietrze)",
			"(?:nie ma |brak )(?:prawidłowego |normalnego |żadnego )?oddechu(?: w ogóle)?",
			"(?:jego |jej )?oddech (?:jest )?(?:nieprawidłowy|nienormalny|agonalny)", "oddech nie jest (?:prawidłowy|normalny)",
			"nie oddycha(?: (?:prawidłowo|normalnie|w ogóle|wcale))?", "oddech agonalny",
		],
		"begin_check": [
			"(?:the scene|the area|the surroundings|the place) (?:is|are) (?:(?:now|completely) )?safe",
			"(?:die umgebung|die einsatzstelle|der ort|die stelle) ist (?:(?:jetzt|hier|komplett) )?sicher",
			"(?:miejsce|otoczenie|miejsce zdarzenia) jest (?:(?:teraz|już|całkowicie) )?bezpieczne"
		],
		"ventilation": [
			"(?:i|we) (?:have (?:just |already )?given|gave) (?:him |her |the patient )?(?:one|a|the first|the second) (?:rescue )?breath",
			"(?:ich habe|wir haben) (?:(?:gerade|bereits|jetzt) )?(?:ihm |ihr |dem patienten )?(?:eine|die erste|die zweite) (?:beatmung|atemspende) (?:gegeben|durchgeführt|gemacht)",
			"(?:ich habe|wir haben) (?:(?:ihn|sie|den patienten) )?einmal beatmet",
			"(?:właśnie |już )?(?:wykonałem|wykonałam|podałem|podałam|zrobiłem|zrobiłam) (?:już |właśnie )?(?:pacjentowi )?(?:jeden|pierwszy|drugi) oddech(?: ratowniczy)?"
		],
		"call_emergency": [
			"(?:please )?(?:call|phone|ring|dial) (?:112|the 112|the emergency number|emergency services|the emergency services|an ambulance|the ambulance|for an ambulance)(?: please)?(?: now)?(?: and (?:put (?:it|the call|the phone) on speaker|use the speaker|switch on the speaker))?",
			"(?:bitte )?(?:ruf|rufe|rufen sie|wähl|wähle|wählen sie) (?:bitte )?(?:die |den |einen )?(?:112|notruf|rettungsdienst|krankenwagen|rettungswagen)(?: an)?(?: bitte)?(?: und (?:stell|stelle|stellen sie) (?:das telefon |den anruf )?auf (?:lautsprecher|laut))?",
			"(?:proszę )?(?:zadzwoń|zadzwonić|wezwij|wezwać|dzwoń) (?:proszę )?(?:pod (?:numer )?112|na 112|po pogotowie|pogotowie|po karetkę|karetkę|pomoc pod numerem 112)(?: proszę)?(?: i (?:włącz|włączyć) (?:głośnomówiący|tryb głośnomówiący|głośnik))?"
		]
	}
	for action: String in rules:
		for pattern: String in rules[action]:
			var matcher := RegEx.new()
			matcher.compile("^(?:" + pattern + ")$")
			if matcher.search(clean) != null: return action
	return ""
