class_name NaretHandover
extends RefCounted
## Handover to the ambulance crew (team to-do, issue #1, 8. Übergabe an den Rettungsdienst):
## „Die Person reagiert nicht. Die Person atmet nicht normal. Ich habe gedrückt. Der AED hat
## einen Schock abgegeben.“ Which facts a spoken handover contains, in any order and wording.
## The crew speaks in the Sie-form (didactic structure p. 53 exceptions: AED and crew).

const FACTS := {
	"no_response": {"en": ["not respond", "unresponsive", "no response", "unconscious"], "de": ["reagiert nicht", "keine reaktion", "bewusstlos"], "pl": ["nie reaguje", "nieprzytomn", "brak reakcji"]},
	"not_breathing": {"en": ["not breathing", "no breathing", "isn't breathing"], "de": ["atmet nicht", "keine atmung", "keine normale atmung"], "pl": ["nie oddycha", "brak oddechu"]},
	"compressions": {"en": ["compression", "pushed", "pressed", "cpr", "chest"], "de": ["gedrückt", "herzdruckmassage", "reanimiert", "wiederbelebung", "kompression"], "pl": ["uciska", "masaż serca", "resuscyt", "rko"]},
	"breaths": {"en": ["breath", "ventilat", "30:2", "30 2"], "de": ["beatm", "30:2", "30 zu 2"], "pl": ["oddech", "wentyl", "30:2"]},
	"aed": {"en": ["aed", "defibrillator"], "de": ["aed", "defibrillator"], "pl": ["aed", "defibrylator"]},
	"shock": {"en": ["shock"], "de": ["schock"], "pl": ["wyładowan", "defibrylacj"]},
}
## The handover is complete with these; the rest is listed in the debrief when mentioned.
const REQUIRED := ["no_response", "not_breathing", "compressions"]

const CREW := {
	# One prompt, once (26 Nov 2026): the crew asks for the whole handover in one sentence.
	"arrive": {"de": "Guten Tag, Rettungsdienst. Drücken Sie bitte weiter und sagen Sie uns kurz: Reagiert die Person, atmet sie normal, und was haben Sie gemacht?",
		"pl": "Dzień dobry, ratownictwo medyczne. Proszę dalej uciskać i krótko powiedzieć: czy osoba reaguje, czy oddycha normalnie i co zostało zrobione?",
		"en": "Hello, ambulance service. Please keep pushing and tell us briefly: does the person respond, are they breathing normally, and what did you do?"},
	"arrive_aed": {"de": "Guten Tag, Rettungsdienst. Drücken Sie bitte weiter und sagen Sie uns kurz: Reagiert die Person, atmet sie normal, was haben Sie gemacht, und hat der AED einen Schock abgegeben?",
		"pl": "Dzień dobry, ratownictwo medyczne. Proszę dalej uciskać i krótko powiedzieć: czy osoba reaguje, czy oddycha normalnie, co zostało zrobione i czy AED wykonał wyładowanie?",
		"en": "Hello, ambulance service. Please keep pushing and tell us briefly: does the person respond, are they breathing normally, what did you do, and did the AED deliver a shock?"},
	# One line for A and B (26 Nov 2026: "The AED stays attached" removed).
	"take_over": {"de": "Danke. Wir übernehmen jetzt. Nehmen Sie bitte die Hände von der Person und treten Sie zurück.",
		"pl": "Dziękuję. Teraz przejmujemy. Proszę zabrać ręce od tej osoby i się odsunąć.",
		"en": "Thank you. We are taking over now. Please take your hands off the person and step back."},
}

## "No" to "Does the person respond?" / "Is the person breathing normally?" is the fact
## itself – only an answer that starts with the word for no ("Nein, …", "Nie.", "No."):
## "Keine Ahnung" or "reagiert nicht" are not a no to the other question (18 Nov 2026).
const NO_WORDS := {"de": ["nein"], "pl": ["nie"], "en": ["no", "nope"]}

static func answers_no(text: String, language: String) -> bool:
	var words := text.to_lower().replace(",", " ").replace(".", " ").replace("!", " ").replace("?", " ").split(" ", false)
	return not words.is_empty() and words[0] in NO_WORDS.get(language, NO_WORDS.en)

## The trainee asks what to say ("Was soll ich sagen?"): the instructor lists the points.
const WHAT_TO_SAY := ["was soll ich", "was meinen sie", "was muss ich", "was genau", "wie bitte", "was sagen",
	"what should i", "what do you mean", "what do i say", "what must i", "sorry?", "pardon",
	"co mam", "co powiedzieć", "co pan ma na myśli", "co pani ma na myśli", "słucham?", "nie rozumiem"]

static func asks_what_to_say(text: String) -> bool:
	var clean := " " + text.to_lower() + " "
	for phrase: String in WHAT_TO_SAY:
		if phrase in clean: return true
	return false

const YES_WORDS := {"de": ["ja", "jawohl", "genau", "richtig"], "pl": ["tak"], "en": ["yes", "yeah", "yep", "correct"]}

## A yes/no answer that starts with yes ("Ja, …", "Tak.", "Yes.").
static func answers_yes(text: String, language: String) -> bool:
	var words := text.to_lower().replace(",", " ").replace(".", " ").replace("!", " ").replace("?", " ").split(" ", false)
	return not words.is_empty() and words[0] in YES_WORDS.get(language, YES_WORDS.en)

static func missing(all_facts: Array) -> Array[String]:
	var out: Array[String] = []
	for fact: String in REQUIRED:
		if not fact in all_facts: out.append(fact)
	return out

static func facts(text: String, language: String) -> Array[String]:
	var clean := " " + text.to_lower() + " "
	var found: Array[String] = []
	for fact: String in FACTS:
		var words: Array = FACTS[fact].get(language, FACTS[fact].en)
		for word: String in words:
			if word in clean:
				found.append(fact)
				break
	return found

static func complete(all_facts: Array) -> bool:
	for fact in REQUIRED:
		if not fact in all_facts: return false
	return true

static func crew_line(key: String, language: String) -> String:
	return str(CREW[key].get(language, CREW[key].en))
