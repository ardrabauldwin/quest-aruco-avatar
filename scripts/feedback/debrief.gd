class_name NaretDebrief
extends RefCounted
## Debriefing after the handover (issue #1, 8. „Zurücktreten, Debriefing“). Built from what
## the session measured, in the structure of a professional debrief: what happened, what
## went well, what to improve, one take-home message. `spoken` is the short version the
## instructor says; `text` is the full version for the results panel (BBCode).
## Descriptive practice feedback, not a clinical assessment.

const GOOD_SHARE := 0.7 # 70 % of the measured compressions in the target range counts as good
const FIRST_COMPRESSION_GOOD_S := 60.0

const T := {
	"de": {
		"title": "Debriefing", "situation_A": "Situation A, allein.", "situation_B": "Situation B, mit Helfern.",
		"good": "Gut gelungen", "improve": "Daran arbeiten", "take_home": "Merksatz",
		"safety": "Du hast die Sicherheit nach %d Sekunden geprüft.",
		"call": "Den Notruf hast du nach %d Sekunden ausgelöst, vor der Atemkontrolle, wie empfohlen.",
		"call_late": "Der Notruf kam erst nach %d Sekunden; ruf früher, direkt nach der Reaktionsprüfung.",
		"aed_delegated": "Du hast den AED direkt bei einer Person angefordert.",
		"first_compression": "Die erste Kompression kam nach %d Sekunden.",
		"first_compression_late": "Bis zur ersten Kompression hat es %d Sekunden gedauert; versuche, schneller zu beginnen.",
		"rate_good": "Die Frequenz lag bei %d Prozent der Kompressionen im Ziel von 100 bis 120 pro Minute.",
		"rate_low": "Nur %d Prozent der Kompressionen lagen im Frequenzziel von 100 bis 120 pro Minute; halte den Takt.",
		"depth_good": "Die Drucktiefe lag bei %d Prozent im Ziel von 5 bis 6 Zentimetern.",
		"depth_low": "Nur %d Prozent der Kompressionen erreichten 5 bis 6 Zentimeter Tiefe; drück kräftiger und entlaste vollständig.",
		"pauses_none": "Deine Unterbrechungen blieben unter 10 Sekunden.",
		"pauses": "%d-mal war die Unterbrechung länger als 10 Sekunden; halte die Pausen kurz.",
		"shocks": "Der AED hat %d-mal geschockt, und du hast danach sofort weitergedrückt.",
		"handover_full": "Deine Übergabe war vollständig.",
		"handover_missing": "Bei der Übergabe fehlte zunächst: %s.",
		"fact_no_response": "dass die Person nicht reagiert", "fact_not_breathing": "dass sie nicht normal atmet", "fact_compressions": "was du gemacht hast", "fact_aed": "dass der AED geschockt hat",
		"refusals": "%d Schritte musste ich zurückweisen, weil ich die Handlung nicht gesehen habe.",
		"take_home_text": "Prüfen, Rufen, Drücken – und die Pausen so kurz wie möglich halten.",
	},
	"pl": {
		"title": "Omówienie", "situation_A": "Sytuacja A, sam lub sama.", "situation_B": "Sytuacja B, z pomocnikami.",
		"good": "Dobrze wykonane", "improve": "Do poprawy", "take_home": "Do zapamiętania",
		"safety": "Bezpieczeństwo sprawdzono po %d sekundach.",
		"call": "Numer 112 wezwano po %d sekundach, przed oceną oddechu, zgodnie z zaleceniami.",
		"call_late": "Wezwanie 112 nastąpiło dopiero po %d sekundach; dzwoń wcześniej, zaraz po ocenie reakcji.",
		"aed_delegated": "AED zlecono bezpośrednio konkretnej osobie.",
		"first_compression": "Pierwsze uciśnięcie nastąpiło po %d sekundach.",
		"first_compression_late": "Do pierwszego uciśnięcia minęło %d sekund; spróbuj zacząć szybciej.",
		"rate_good": "Częstotliwość: %d procent uciśnięć w zakresie 100–120 na minutę.",
		"rate_low": "Tylko %d procent uciśnięć mieściło się w zakresie 100–120 na minutę; trzymaj rytm.",
		"depth_good": "Głębokość: %d procent uciśnięć w zakresie 5–6 centymetrów.",
		"depth_low": "Tylko %d procent uciśnięć osiągnęło 5–6 centymetrów; uciskaj mocniej i w pełni odciążaj.",
		"pauses_none": "Przerwy były krótsze niż 10 sekund.",
		"pauses": "%d razy przerwa trwała dłużej niż 10 sekund; skracaj przerwy.",
		"shocks": "AED wykonał %d wyładowanie(a), a uciskanie wznowiono od razu.",
		"handover_full": "Przekazanie informacji było kompletne.",
		"handover_missing": "W przekazaniu początkowo zabrakło: %s.",
		"fact_no_response": "że osoba nie reaguje", "fact_not_breathing": "że nie oddycha normalnie", "fact_compressions": "co zostało zrobione", "fact_aed": "że AED wykonał wyładowanie",
		"refusals": "%d kroków musiałem odrzucić, bo nie widziałem wykonania.",
		"take_home_text": "Sprawdź, wezwij, uciskaj – i rób jak najkrótsze przerwy.",
	},
	"en": {
		"title": "Debriefing", "situation_A": "Situation A, alone.", "situation_B": "Situation B, with helpers.",
		"good": "What went well", "improve": "What to work on", "take_home": "Take-home message",
		"safety": "You checked safety after %d seconds.",
		"call": "You called 112 after %d seconds, before the breathing check, as recommended.",
		"call_late": "The call to 112 came only after %d seconds; call earlier, right after the response check.",
		"aed_delegated": "You asked a specific person to fetch the AED.",
		"first_compression": "The first compression came after %d seconds.",
		"first_compression_late": "It took %d seconds until the first compression; try to start sooner.",
		"rate_good": "%d percent of the compressions were at the target rate of 100 to 120 per minute.",
		"rate_low": "Only %d percent of the compressions were at the target rate of 100 to 120 per minute; keep the rhythm.",
		"depth_good": "%d percent of the compressions reached the target depth of 5 to 6 centimetres.",
		"depth_low": "Only %d percent of the compressions reached 5 to 6 centimetres; push harder and release fully.",
		"pauses_none": "Your interruptions stayed under 10 seconds.",
		"pauses": "%d times the interruption was longer than 10 seconds; keep pauses short.",
		"shocks": "The AED shocked %d times, and you resumed compressions straight away.",
		"handover_full": "Your handover was complete.",
		"handover_missing": "The handover was at first missing: %s.",
		"fact_no_response": "that the person does not respond", "fact_not_breathing": "that they are not breathing normally", "fact_compressions": "what you did", "fact_aed": "that the AED delivered a shock",
		"refusals": "%d steps had to be refused because I did not see the action.",
		"take_home_text": "Check, call, compress – and keep pauses as short as possible.",
	},
}

## summary: main's _session_summary(); extra: situation, handover_missing (Array), pause_overs (int).
static func build(summary: Dictionary, extra: Dictionary, language: String) -> Dictionary:
	var w: Dictionary = T.get(language, T.en)
	var score: Dictionary = summary.get("score", {})
	var session: Dictionary = summary.get("scenario", {})
	var m: Dictionary = score.get("milestones_s", {})
	var good: Array[String] = []
	var improve: Array[String] = []
	if m.has("begin_check"): good.append(w.safety % int(m.begin_check))
	if m.has("call_emergency"):
		var called := float(m.call_emergency)
		if not m.has("check_breathing") or called <= float(m.check_breathing): good.append(w.call % int(called))
		else: improve.append(w.call_late % int(called))
	if str(extra.get("situation", "B")) == "B" and m.has("request_aed"): good.append(w.aed_delegated)
	if m.has("compression"):
		var first := float(m.compression)
		if first <= FIRST_COMPRESSION_GOOD_S: good.append(w.first_compression % int(first))
		else: improve.append(w.first_compression_late % int(first))
	var rates := int(score.get("verified_rate_samples", 0))
	if rates >= 10:
		var share := roundi(100.0 * float(score.get("rate_in_range", 0)) / rates)
		if share >= GOOD_SHARE * 100.0: good.append(w.rate_good % share)
		else: improve.append(w.rate_low % share)
	var depths := int(score.get("verified_depth_samples", 0))
	if depths >= 10:
		var share := roundi(100.0 * float(score.get("depth_in_range", 0)) / depths)
		if share >= GOOD_SHARE * 100.0: good.append(w.depth_good % share)
		else: improve.append(w.depth_low % share)
	if int(session.get("compressions", 0)) > 0:
		var overs := int(extra.get("pause_overs", 0))
		if overs == 0: good.append(w.pauses_none)
		else: improve.append(w.pauses % overs)
	if int(session.get("shocks", 0)) > 0: good.append(w.shocks % int(session.shocks))
	var missing: Array = extra.get("handover_missing", [])
	if extra.has("handover_missing"):
		if missing.is_empty(): good.append(w.handover_full)
		else:
			var names: Array[String] = []
			for fact in missing: names.append(str(w.get("fact_" + str(fact), fact)))
			improve.append(w.handover_missing % ", ".join(names))
	var refusals := int(score.get("rejected_actions", 0))
	if refusals > 0: improve.append(w.refusals % refusals)

	var situation: String = w.situation_A if str(extra.get("situation", "B")) == "A" else w.situation_B
	var spoken: String = w.title + ". " + situation + " " + " ".join(good)
	if not improve.is_empty(): spoken += " " + " ".join(improve)
	spoken += " " + w.take_home_text
	# Large, clearly separated sections for reading in the headset (18 Nov 2026): title 34,
	# section headings 27, points 22, the take-home message boxed in colour.
	var text: String = "[font_size=34][b]%s[/b][/font_size]\n[font_size=22][color=#9fb3c2]%s[/color][/font_size]\n\n" % [w.title, situation]
	text += "[font_size=27][color=#7fe08a][b]%s[/b][/color][/font_size]\n" % w.good
	for line in good: text += "[font_size=22]   •  %s[/font_size]\n" % line
	if not improve.is_empty():
		text += "\n[font_size=27][color=#ffc857][b]%s[/b][/color][/font_size]\n" % w.improve
		for line in improve: text += "[font_size=22]   •  %s[/font_size]\n" % line
	text += "\n[font_size=25][bgcolor=#1d3a4a][color=#ffffff][b]  %s:  [/b]%s  [/color][/bgcolor][/font_size]\n\n" % [w.take_home, w.take_home_text]
	return {"spoken": spoken, "text": text, "good": good, "improve": improve}
