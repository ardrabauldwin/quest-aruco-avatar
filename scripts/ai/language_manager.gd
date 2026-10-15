class_name NaretLanguage
extends RefCounted
## All deterministic training instructions have German and Polish equivalents.
## Intent recognition assists communication; it must never prove physical actions.

const SUPPORTED := ["de", "pl", "en"]

const STRINGS := {
	"en": {
  "state.idle": "Ready",
  "state.intro": "Arrival",
  "state.check_patient": "Assessment",
  "state.call_help": "Call for help",
  "state.cpr": "CPR",
  "state.aed": "AED",
  "state.recovery": "Debrief",
  "instruction.idle": "Start adult BLS training. This is a simulation, not a medical device.",
  "instruction.intro": "Make sure you and others are safe. The person is lying motionless. Begin your assessment.",
  "instruction.check_patient": "Speak loudly to the person and gently shake their shoulders. Do they respond?",
  "instruction.check_breathing": "While the emergency call connects: open the airway (head tilt, chin lift) and check for normal breathing for no more than 10 seconds. Gasping, slow or panting breaths are not normal breathing. If in doubt, treat this as cardiac arrest.",
  "instruction.call_help": "No response: shout for help and call 112 immediately on speakerphone, or ask someone to call. Check breathing afterwards.",
  "instruction.cpr": "30 compressions : 2 breaths. Lower half of the breastbone, 100-120/min, 5-6 cm, allowing full recoil. If rescue breaths are not possible, give continuous compressions.",
  "instruction.ventilate": "Give 2 rescue breaths, each lasting about 1 second with visible chest rise. Keep the interruption below 10 seconds. Then immediately resume compressions.",
  "instruction.aed": "Switch on the AED and attach the pads to the bare chest. With a second rescuer, continue compressions meanwhile. Follow the AED instructions.",
  "instruction.aed_clear": "AED: Nobody touches the person. Check and confirm that everyone is clear before analysis.",
  "instruction.aed_analyze": "The AED is ready to analyse the rhythm. Nobody may touch the person.",
  "instruction.aed_shock": "AED: Shock advised. Check again and confirm that nobody touches the person. Deliver a shock only when instructed by the AED.",
  "instruction.aed_shock_ready": "Everyone is clear. Deliver the shock, then immediately resume with 30 compressions.",
  "instruction.aed_resume": "AED: No shock advised. Immediately resume with 30 compressions.",
  "instruction.reassessment": "The AED requests another analysis. Nobody touches the person. Follow its instructions.",
  "instruction.recovery": "Signs of life and normal breathing have returned. Continue monitoring breathing, leave the AED connected and hand over to the emergency services.",
  "instruction.handover": "The emergency services have taken over in the simulation. Discuss the sequence, interruptions and communication.",
  "action.start": "Start training",
  "action.begin_check": "Scene safe - assess",
  "action.check_responsiveness": "Check responsiveness",
  "action.check_breathing": "Check breathing",
  "action.call_emergency": "Ask someone to call 112",
  "action.request_aed": "Ask someone to fetch an AED",
  "action.compression": "Compression",
  "action.ventilation": "Rescue breath",
  "action.compression_only": "Compressions only",
  "action.attach_aed": "Attach and switch on AED",
  "action.clear_patient": "Nobody touches the person",
  "action.analyze_rhythm": "Let the AED analyse",
  "action.shock": "Deliver AED shock",
  "action.resume_cpr": "Resume compressions immediately",
  "action.reassess": "AED: analyse again",
  "action.simulate_rosc": "Instructor: simulate signs of life",
  "action.handover": "Emergency services take over",
  "action.reassure": "Reassure the relative",
  "action.reset": "New training",
  "bystander.default": "What happened? Please help! What can I do?",
  "mode.own": "Own language",
  "mode.neighbour": "Neighbour language",
  "error.invalid_action": "This step does not fit the current training state yet.",
  "error.check_responsiveness_first": "First check whether the person responds.",
  "error.call_first": "For an unresponsive person, first call 112 on speakerphone, then check breathing.",
  "error.check_result": "This scenario practises an unresponsive person who is not breathing normally.",
  "error.ventilate_first": "30 compressions completed: give 2 rescue breaths or select continuous compressions.",
  "error.compress_first": "Begin with 30 compressions before the 2 rescue breaths.",
  "error.aed_safety": "AED safety clearance is missing. Nobody may touch the person.",
  "error.aed_not_due": "Continue compressions immediately. The AED usually requests another analysis after 2 minutes.",
  "error.trainer_only": "Only the instructor may explicitly simulate signs of life, after further CPR.",
  "error.contact_during_analysis": "Contact detected: AED clearance cancelled. Make sure everyone is clear again.",
  "error.aed_missing": "The AED has not arrived. Continue compressions until it is brought.",
  "score.notice": "Training data, not a clinically validated assessment. Depth from hand tracking is an estimate."
},
	"de": {
		"state.idle": "Bereit", "state.intro": "Einsatzbeginn", "state.check_patient": "Prüfen",
		"state.call_help": "Hilfe rufen", "state.cpr": "Wiederbelebung", "state.aed": "AED", "state.recovery": "Nachbesprechung",
		"instruction.idle": "Starte das Erwachsenen-BLS-Training. Dies ist eine Simulation, kein Medizinprodukt.",
		"instruction.intro": "Achte auf Sicherheit für dich und andere. Die Person liegt regungslos. Beginne die Prüfung.",
		"instruction.check_patient": "Sprich die Person laut an und schüttle vorsichtig an den Schultern. Reagiert sie?",
		"instruction.check_breathing": "Während der Notruf aufgebaut wird: Atemwege öffnen (Kopf überstrecken, Kinn anheben), höchstens 10 Sekunden auf normale Atmung prüfen. Schnappatmung, langsames oder hechelndes Atmen ist keine normale Atmung. Im Zweifel: wie Kreislaufstillstand behandeln.",
		"instruction.call_help": "Keine Reaktion: laut um Hilfe rufen und sofort 112 anrufen (Lautsprecher) oder eine Person damit beauftragen. Die Atmung wird danach geprüft.",
		"instruction.cpr": "30 Kompressionen : 2 Beatmungen. Untere Hälfte des Brustbeins, 100–120/min, 5–6 cm, vollständig entlasten. Wenn Beatmung nicht möglich ist: kontinuierlich drücken.",
		"instruction.ventilate": "Gib 2 Atemspenden, je etwa 1 Sekunde mit sichtbarem Anheben des Brustkorbs. Unterbrechung unter 10 Sekunden. Danach sofort weiterdrücken.",
		"instruction.aed": "AED einschalten und Elektroden auf den entblößten Brustkorb kleben. Mit zweiter Hilfsperson währenddessen weiterdrücken. Den AED-Anweisungen folgen.",
		"instruction.aed_clear": "AED: Niemand berührt die Person. Abstand prüfen und bestätigen, bevor die Analyse beginnt.",
		"instruction.aed_analyze": "AED ist bereit zur Rhythmusanalyse. Niemand darf die Person berühren.",
		"instruction.aed_shock": "AED: Schock empfohlen. Erneut prüfen und bestätigen, dass niemand die Person berührt. Schock nur auf AED-Anweisung auslösen.",
		"instruction.aed_shock_ready": "Alle sind auf Abstand. Schock auslösen, danach sofort mit 30 Kompressionen fortfahren.",
		"instruction.aed_resume": "AED: Kein Schock empfohlen. Sofort mit 30 Kompressionen fortfahren.",
		"instruction.reassessment": "AED fordert eine erneute Analyse an. Niemand berührt die Person. Den AED-Anweisungen folgen.",
		"instruction.recovery": "Lebenszeichen und normale Atmung sind zurück. Atmung weiter überwachen, AED angeschlossen lassen und an den Rettungsdienst übergeben.",
		"instruction.handover": "Der Rettungsdienst hat in der Simulation übernommen. Besprecht Reihenfolge, Unterbrechungen und Kommunikation.",
		"action.start": "Training starten", "action.begin_check": "Umgebung sicher · Prüfen",
		"action.check_responsiveness": "Bewusstsein prüfen", "action.check_breathing": "Atmung prüfen",
		"action.call_emergency": "112 beauftragen", "action.request_aed": "AED holen lassen",
		"action.compression": "Kompression", "action.ventilation": "Beatmung",
		"action.compression_only": "Nur Kompressionen", "action.attach_aed": "AED anlegen & einschalten",
		"action.clear_patient": "Niemand berührt die Person", "action.analyze_rhythm": "AED analysieren lassen",
		"action.shock": "AED-Schock auslösen", "action.resume_cpr": "Sofort weiterdrücken",
		"action.reassess": "AED: Erneute Analyse", "action.simulate_rosc": "Trainer: Lebenszeichen simulieren",
		"action.handover": "Rettungsdienst übernimmt", "action.reassure": "Angehörige beruhigen", "action.reset": "Neues Training",
		"bystander.default": "Was ist passiert? Bitte helfen Sie! Was kann ich tun?",
		"mode.own": "Eigene Sprache", "mode.neighbour": "Nachbarsprache",
		"error.invalid_action": "Dieser Schritt passt noch nicht zum aktuellen Trainingszustand.",
		"error.check_responsiveness_first": "Prüfe zuerst, ob die Person reagiert.",
		"error.call_first": "Zuerst 112 anrufen (Lautsprecher), dann die Atmung prüfen – bei jeder Person, die nicht reagiert.",
		"error.check_result": "Dieses Szenario übt fehlende Reaktion und fehlende normale Atmung.",
		"error.ventilate_first": "30 Kompressionen erreicht: Gib jetzt 2 Atemspenden oder wähle kontinuierliche Kompressionen.",
		"error.compress_first": "Beginne mit 30 Kompressionen vor den 2 Atemspenden.",
		"error.aed_safety": "AED-Sicherheitsfreigabe fehlt. Niemand darf die Person berühren.",
		"error.aed_not_due": "Sofort weiterdrücken. Der AED fordert üblicherweise nach 2 Minuten die nächste Analyse an.",
		"error.trainer_only": "Lebenszeichen dürfen nur ausdrücklich von der Trainingsleitung simuliert werden, nach weiterer CPR.",
		"error.contact_during_analysis": "Kontakt erkannt: AED-Freigabe aufgehoben. Erneut Abstand sicherstellen.",
		"error.aed_missing": "Der AED ist noch nicht da. Weiterdrücken, bis er gebracht wird.",
		"score.notice": "Übungsdaten, keine klinisch validierte Bewertung. Hand-Tracking-Drucktiefe ist eine Schätzung.",
	},
	"pl": {
		"state.idle": "Gotowość", "state.intro": "Początek", "state.check_patient": "Ocena",
		"state.call_help": "Wezwanie pomocy", "state.cpr": "Resuscytacja", "state.aed": "AED", "state.recovery": "Omówienie",
		"instruction.idle": "Rozpocznij trening BLS osoby dorosłej. To symulacja, a nie wyrób medyczny.",
		"instruction.intro": "Zadbaj o bezpieczeństwo swoje i innych. Osoba leży nieruchomo. Rozpocznij ocenę.",
		"instruction.check_patient": "Głośno zwróć się do osoby i delikatnie potrząśnij jej ramionami. Czy reaguje?",
		"instruction.check_breathing": "W trakcie łączenia z 112: udrożnij drogi oddechowe (odchyl głowę, unieś żuchwę) i oceniaj oddech maksymalnie 10 sekund. Oddech agonalny, wolny lub szybki i płytki nie jest prawidłowy. W razie wątpliwości traktuj jak zatrzymanie krążenia.",
		"instruction.call_help": "Brak reakcji: głośno wołaj o pomoc i natychmiast zadzwoń pod 112 (głośnik) lub zleć to innej osobie. Oddech oceń potem.",
		"instruction.cpr": "30 uciśnięć : 2 oddechy. Dolna połowa mostka, 100–120/min, głębokość 5–6 cm, pełne odciążenie. Jeśli oddechy są niemożliwe, uciskaj bez przerwy.",
		"instruction.ventilate": "Wykonaj 2 oddechy ratownicze, każdy około 1 sekundy, z widocznym unoszeniem klatki piersiowej. Przerwa poniżej 10 sekund. Potem natychmiast uciskaj.",
		"instruction.aed": "Włącz AED i naklej elektrody na odsłoniętą klatkę piersiową. Drugi ratownik w tym czasie kontynuuje uciskanie. Wykonuj polecenia AED.",
		"instruction.aed_clear": "AED: Nikt nie dotyka poszkodowanego. Sprawdź i potwierdź bezpieczeństwo przed analizą.",
		"instruction.aed_analyze": "AED jest gotowy do analizy rytmu. Nikt nie może dotykać poszkodowanego.",
		"instruction.aed_shock": "AED: Zalecane wyładowanie. Ponownie sprawdź i potwierdź, że nikt nie dotyka poszkodowanego. Wyładowanie tylko na polecenie AED.",
		"instruction.aed_shock_ready": "Wszyscy odsunęli się. Wykonaj wyładowanie, potem natychmiast rozpocznij 30 uciśnięć.",
		"instruction.aed_resume": "AED: Wyładowanie niezalecane. Natychmiast rozpocznij 30 uciśnięć.",
		"instruction.reassessment": "AED poleca ponowną analizę. Nikt nie dotyka poszkodowanego. Wykonuj polecenia AED.",
		"instruction.recovery": "Powróciły oznaki życia i prawidłowy oddech. Nadal monitoruj oddech, nie odłączaj AED i przekaż poszkodowanego zespołowi ratownictwa.",
		"instruction.handover": "Zespół ratownictwa przejął pomoc w symulacji. Omówcie kolejność, przerwy i komunikację.",
		"action.start": "Rozpocznij trening", "action.begin_check": "Miejsce bezpieczne · Oceń",
		"action.check_responsiveness": "Sprawdź reakcję", "action.check_breathing": "Sprawdź oddech",
		"action.call_emergency": "Zleć telefon pod 112", "action.request_aed": "Poproś o AED",
		"action.compression": "Uciśnięcie", "action.ventilation": "Oddech ratowniczy",
		"action.compression_only": "Tylko uciśnięcia", "action.attach_aed": "Podłącz i włącz AED",
		"action.clear_patient": "Nikt nie dotyka osoby", "action.analyze_rhythm": "Rozpocznij analizę AED",
		"action.shock": "Wyładowanie AED", "action.resume_cpr": "Natychmiast uciskaj",
		"action.reassess": "AED: Ponowna analiza", "action.simulate_rosc": "Instruktor: Symuluj oznaki życia",
		"action.handover": "Ratownicy przejmują pomoc", "action.reassure": "Uspokój bliskich", "action.reset": "Nowy trening",
		"bystander.default": "Co się stało? Proszę pomóc! Co mogę zrobić?",
		"mode.own": "Język ojczysty", "mode.neighbour": "Język sąsiada",
		"error.invalid_action": "Ten krok nie pasuje jeszcze do aktualnego etapu treningu.",
		"error.check_responsiveness_first": "Najpierw sprawdź, czy osoba reaguje.",
		"error.call_first": "Najpierw zadzwoń pod 112 (głośnik), potem oceń oddech – u każdej osoby, która nie reaguje.",
		"error.check_result": "Ten scenariusz ćwiczy brak reakcji i brak prawidłowego oddechu.",
		"error.ventilate_first": "Wykonano 30 uciśnięć: teraz 2 oddechy lub wybierz ciągłe uciskanie.",
		"error.compress_first": "Przed 2 oddechami wykonaj 30 uciśnięć.",
		"error.aed_safety": "Brak potwierdzenia bezpieczeństwa AED. Nikt nie może dotykać poszkodowanego.",
		"error.aed_not_due": "Kontynuuj uciskanie. AED zwykle poleca kolejną analizę po 2 minutach.",
		"error.trainer_only": "Tylko instruktor może jawnie zasymulować oznaki życia, po dalszej resuscytacji.",
		"error.contact_during_analysis": "Wykryto dotyk: anulowano zgodę AED. Ponownie zapewnij odstęp.",
		"error.aed_missing": "AED jeszcze nie dotarł. Uciskaj dalej, aż ktoś go przyniesie.",
		"score.notice": "Dane treningowe, bez walidacji klinicznej. Głębokość z pozycji dłoni jest szacunkowa.",
	}
}

static func text(key: String, lang: String = "de") -> String:
	var selected: Dictionary = STRINGS.get(lang, STRINGS.de)
	return str(selected.get(key, STRINGS.de.get(key, key)))

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

static func next_language(lang: String) -> String:
	return SUPPORTED[(SUPPORTED.find(lang) + 1) % SUPPORTED.size()]

const UI_EN := {
  "\u00dcben, wenn es\nwirklich z\u00e4hlt.": "Practise when it\nreally matters.",
  "BLS trainieren. Nachbarsprache sprechen.": "Practise BLS. Speak the neighbour language.",
  "Kalibrieren": "Calibrate",
  "QCPR-Sim": "QCPR simulator",
  "Ziehen: Ansicht drehen   \u00b7   Scrollen: Zoom   \u00b7   C: Dr\u00fccken   \u00b7   V: Beatmen   \u00b7   F2: QCPR": "Drag: rotate view | Scroll: zoom | C: compression | V: breath",
  "Mit Anna sprechen \u2026": "Talk to Anna...",
  "EKG / SIMULATION": "ECG / SIMULATION",
  "DRUCK": "COMPRESSIONS",
  "FEHLER": "ERRORS",
  "Druck": "Compressions",
  "Atem": "Breaths",
  " \u00b7 Unvollst. Entlastung": " | Incomplete recoil",
  "Training starten": "Start training",
  "Neues Training": "New training",
  "Nachbesprechung": "Debrief",
  "Export": "Export",
  "Nachbar": "Neighbour",
  "Eigene": "Own",
  "Aufnahme": "Recording",
  "Marker-Kalibrierung": "Marker calibration",
  "DICT_4X4_50 \u00b7 Schwarzes Markerquadrat messen.\nScan mit realer Puppe abgleichen, dann Offset speichern. X/Y/Z in Metern im Markerraum.": "DICT_4X4_50: measure the black marker square.\nAlign the scan with the real mannequin, then save the offset. X/Y/Z are metres in marker space.",
  "Puppenscan \u00b7 1:1-Referenz": "Mannequin scan: 1:1 reference",
  "Skalierung": "Scale",
  "Kalibrierung speichern": "Save calibration",
  "Gespeichert": "Saved",
  "Schlie\u00dfen": "Close",
  "Bitte zuerst die Platzierung kalibrieren und speichern.": "First calibrate and save the placement.",
  "Schock simuliert \u00b7 Sofort CPR fortsetzen": "Shock simulated: immediately resume CPR",
  "Exportiert: ": "Exported: ",
  "Trainer: ROSC simuliert": "Instructor: simulated signs of life",
  "Trainer-ROSC nach AED und fortgesetzter CPR verf\u00fcgbar": "Instructor recovery simulation requires AED and further CPR",
  "Dein Training im R\u00fcckblick": "Your training review",
  "Mehr Details: nach unten scrollen": "Scroll down for more details",
  "Session-JSON exportieren": "Export session JSON",
  "\u00dcbungsdaten": "Training data",
  "Simulation beendet: \u00dcbergabe an den Rettungsdienst.": "Simulation ended: handover to emergency services.",
  "Die Trainingsleitung hat Lebenszeichen simuliert. Dies ist keine vorhergesagte Schockwirkung.": "The instructor simulated signs of life. This does not predict the effect of a shock.",
  "Zwischenstand dieser Trainingssession.": "Progress in this training session.",
  "Dauer: %.0f s   \u00b7   Akzeptierte Aktionen: %d\nKompressionen: %d   \u00b7   Beatmungen: %d\nAED-Schocks: %d   \u00b7   Abgelehnte Aktionen: %d": "Duration: %.0f s | Accepted actions: %d\nCompressions: %d | Breaths: %d\nAED shocks: %d | Rejected actions: %d",
  "\u00dcbungsuhr: %.0f\u00d7 beschleunigt": "Training clock: %.0fx speed",
  "Das hat im Ablauf geklappt": "What went well",
  "Noch keine best\u00e4tigten BLS-Meilensteine aufgezeichnet.": "No confirmed BLS milestones recorded yet.",
  "Kontinuierliche Kompressionen wurden gew\u00e4hlt; keine Beatmungen vorgeschrieben.": "Continuous compressions selected; breaths were not required.",
  "Vollst\u00e4ndige 30:2-Zyklen: %d.": "Completed 30:2 cycles: %d.",
  "Daran k\u00f6nnt ihr arbeiten": "What to work on",
  "Keine abgelehnten Aktionen im Ablauf protokolliert. Das best\u00e4tigt die Bedienreihenfolge, nicht die Qualit\u00e4t realer CPR.": "No rejected actions recorded. This confirms the input sequence, not the quality of real CPR.",
  "Weitere Fehlergruppen stehen im JSON-Export.": "More error groups are available in the JSON export.",
  "zuerst ": "first at ",
  "Nicht protokolliert: ": "Not recorded: ",
  "Besprecht, was im gew\u00e4hlten Szenario noch erforderlich war.": "Discuss what was still required in the chosen scenario.",
  "Messung und Einordnung": "Measurements and interpretation",
  "Verifizierte Drucktiefen: %d/%d im Zielbereich 5\u20136 cm.": "Verified depths: %d/%d within the 5-6 cm target range.",
  "Keine verifizierte Drucktiefe gemessen. Tastatur und Hand-Tracking best\u00e4tigen ausschlie\u00dflich simulierte Handlungen.": "No verified compression depth measured. Keyboard and hand tracking confirm simulated actions only.",
  "Verifizierte Frequenzen: %d/%d im Zielbereich 100\u2013120/min.": "Verified rates: %d/%d within the 100-120/min target range.",
  "F\u00fcr den n\u00e4chsten Durchlauf": "For your next attempt",
  "Bei fehlender Reaktion normale Atmung h\u00f6chstens 10 s pr\u00fcfen. 112 und AED organisieren. 30:2, 100\u2013120/min, 5\u20136 cm und vollst\u00e4ndige Entlastung. Nach AED-Schock oder Entscheidung gegen einen Schock sofort weiterdr\u00fccken.": "For an unresponsive person, check normal breathing for no more than 10 seconds. Arrange 112 and an AED. Use 30:2, 100-120/min, 5-6 cm and full recoil. Resume compressions immediately after an AED shock or a no-shock decision.",
  "Nicht passender Schritt": "Inappropriate step"
}

static func ui(german: String, polish: String, lang: String) -> String:
	if lang == "en": return str(UI_EN.get(german, german))
	return polish if lang == "pl" else german
