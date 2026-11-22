class_name NaretTrainingCoach
extends RefCounted
## Guidance describes the next task; it never submits an action or verifies technique.
## Guidance supports either the standalone witness exercise or the full AED scenario.

static func step(scenario: NaretScenario) -> String:
	match scenario.state:
		NaretScenario.State.IDLE: return "setup"
		NaretScenario.State.INTRO: return "safety"
		NaretScenario.State.CHECK_PATIENT: return "response"
		NaretScenario.State.CALL_HELP: return "breathing" if scenario.emergency_called else "call"
		NaretScenario.State.CPR:
			if scenario.compression_only: return "compression_only"
			if scenario.cycle_compressions < 30: return "compressions"
			return "breaths" # One prompt for the pair; no voice wait between breaths.
		NaretScenario.State.AED:
			return ["aed_clear", "aed_analyse", "aed_shock_clear", "aed_countdown", "aed_resume"][scenario.aed_stage]
		NaretScenario.State.RECOVERY: return "finish"
	return "aed"

## The yes/no question to ask when nothing usable was heard at a step (11 Nov 2026):
## the step's own report, so one word answers it. Steps without a spoken report (setup,
## compressions, AED handling, finish) get no question and keep the generic prompt.
static func step_question(step: String) -> Dictionary:
	match step:
		"safety": return {"action": "begin_check", "breaths": 1}
		"call": return {"action": "call_emergency", "breaths": 1}
		"breathing": return {"action": "check_breathing", "breaths": 1}
		"breaths": return {"action": "ventilation", "breaths": 2}
	return {}

const UNCERTAIN := ["i don't know", "i dont know", "i do not know", "don't know what", "not sure", "no idea", "i'm confused", "i am confused",
	"i don't understand", "i do not understand", "need help", "help me", "can you help", "what do i do",
	"ich weiß nicht", "ich weiss nicht", "weiß nicht", "keine ahnung", "nicht sicher", "unsicher", "verstehe nicht", "versteh nicht",
	"ich brauche hilfe", "kannst du mir helfen", "was muss ich", "was mache ich", "was tun",
	"nie wiem", "nie jestem pewn", "nie rozumiem", "pomocy", "potrzebuję pomocy", "co mam robić", "co robić", "co teraz"]

static func asks_for_help(text: String) -> bool:
	var words := text.to_lower()
	# Patient background belongs to the witness, even if the instructor was addressed.
	if asks_patient_history(text): return false
	# Uncertainty is a request for help too (18 Nov 2026), in all three languages.
	for phrase in UNCERTAIN:
		if phrase in words: return true
	for phrase in ["what shall", "what can i do", "what's next", "what is next", "what now", "can you guide", "tell me what to do"]:
		if phrase in words: return true
	for phrase in ["instructor", "what next", "what should", "what do i", "how do i", "how should", "how deep", "how fast", "how long", "how many", "how to", "help me", "i am stuck", "i'm stuck", "repeat the instruction", "was soll", "wie soll", "wie tief", "wie schnell", "wie lange", "wie viele", "was jetzt", "hilf mir", "co dalej", "co mam", "jak mam", "jak głęboko", "jak szybko", "jak długo", "ile ucisk", "pomóż mi"]:
		if phrase in words: return true
	return false

static func asks_patient_history(text: String) -> bool:
	var words := text.to_lower()
	# Questions about what to DO remain coaching, including disease-related ones.
	for phrase in ["what should", "how should", "how do i", "what do i", "how to", "was soll", "wie soll", "co mam", "jak mam"]:
		if phrase in words: return false
	var topic := false
	for phrase in ["medical history", "medical condition", "health issues", "health problem", "health condition", "illness", "disease", "diabet", "asthm", "heart condition", "medication", "medicine", "allerg", "vorkrank", "vorerkrank", "erkrank", "krankheit", "gesundheit", "medikament", "chorob", "choruje", "cukrzyc", "astm", "leki", "leków", "lekow", "uczulen"]:
		if phrase in words: topic = true
	if not topic: return false
	var patient := false
	for phrase in ["the patient", "the man", "this man", " he ", " his ", "der mann", "der patient", " er ", "seine ", "ten pan", "ten mężczyzna", "pacjent", " on ", "jego "]:
		if phrase in " " + words + " ": patient = true
	if not patient: return false
	if "?" in words: return true
	for phrase in ["does ", "did ", "has ", "is he", "do you know", "what ", "any ", "hat er", "hat ihr", "hat dein", "hatte er", "wissen sie", "weißt du", "welche ", "nimmt er", "czy ", "jakie ", "cierpi "]:
		if phrase in words: return true
	return false

static func asks_witness(text: String) -> bool:
	var words := text.to_lower()
	if asks_patient_history(text): return true
	# Commands/findings remain in the observation path, not free dialogue.
	for phrase in ["112", "call", "breath", "anrufen", "ruf ", "zadzwo", "wezwij"]:
		if phrase in words: return false
	for phrase in ["what happened", "what has happened", "what's happened", "what is his name", "what's his name", "how old", "do you know him", "wie heißt er", "kennen sie ihn", "kennst du ihn", "was ist passiert", "co się stało"]:
		if phrase in words: return true
	return false

static func instruction(key: String, language: String) -> String:
	if key.begins_with("aed_"):
		var helper: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aed_helper_guidance.json"))
		var languages: Dictionary = helper.get("languages", {})
		return str(languages.get(language, languages.get("en", {})).get(key, ""))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/coach_steps.json"))
	return str(data.get(language, data.en).get(key, data.en.get(key, "Ask the instructor for the next step.")))

static func current_instruction(scenario: NaretScenario, language: String) -> String:
	return instruction(current_key(scenario), language)

## The coach_steps key of the instruction for now (step plus situation and cycle).
static func current_key(scenario: NaretScenario) -> String:
	var key := step(scenario)
	# Situation A, alone (issue #1, 4. Hilfe rufen): the trainee calls 112 personally.
	if key == "call" and str(scenario.get_meta("situation", "B")) == "A":
		key = "call_alone"
	if key == "handover" and str(scenario.get_meta("situation", "B")) == "A":
		key = "handover_alone"
	if not scenario.cpr_witness_only and scenario.state == NaretScenario.State.CPR and scenario._aed_used and scenario._cpr_after_aed == 0:
		return "aed_resume_only" if scenario.compression_only else "aed_resume"
	if key == "compressions" and scenario.cycles > 0:
		key = "resume_compressions"
	# The full bag-and-mask explanation once; afterwards the short prompt (17 Nov 2026: the
	# 10-s limit could not be kept while a 10-s instruction was still playing).
	if key == "breaths" and scenario.cycles > 0:
		key = "breaths_short"
	return key

## ERC 2025 adult BLS facts the instructor answers CPR questions from (data/erc_bls_facts.json).
static func erc_facts() -> Array:
	var file := FileAccess.open("res://data/erc_bls_facts.json", FileAccess.READ)
	if file == null: return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed.get("facts", []) if parsed is Dictionary else []

## How to answer a trainee who reports or asks about something other than the exercise expects,
## for one step (data/deviation_guide.json). Compression-only uses the compression entries.
static func deviation_guide(step_key: String) -> Array:
	var file := FileAccess.open("res://data/deviation_guide.json", FileAccess.READ)
	if file == null: return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary: return []
	return parsed.get("compressions" if step_key == "compression_only" else step_key, [])

static func context(scenario: NaretScenario, language: String) -> Dictionary:
	var key := step(scenario)
	var guide := {}
	for topic in ["response", "call", "breathing", "compressions", "breath_one", "breath_two", "compression_only", "handover", "aed"]:
		guide[topic] = instruction("aed_apply" if topic == "aed" and not scenario.cpr_witness_only else topic, language)
	return {"language": language, "scenario_state": scenario.get_state_name(),
		"next_step": key, "approved_instruction": current_instruction(scenario, language),
		"approved_guide": guide,
		"erc_facts": erc_facts(),
		"deviation_guide": deviation_guide(key),
		"compression_count": scenario.cycle_compressions, "breath_reports": scenario.cycle_ventilations,
		"emergency_call_reported": scenario.emergency_called,
		"scope": ("one witness, a passer-by in a red jacket; no AED interaction in this exercise" if scenario.cpr_witness_only else "the passer-by in the red jacket calls 112 and remains the witness; the man with the blue backpack is a separate helper who brings the AED; instructor guides; trainee powers AED and places pads with hands, then follows fully automatic simulated analysis/shock prompts; the continuous training pattern repeats shock, shock, no shock, with CPR after each and no automatic recovery") + "; breaths and findings are reported, not sensor verified",
		"patient_facts": "A man has collapsed in a park. Nobody present knows him or anyone else here: his name, age, medical history, medication and allergies are unknown, and so are the cause and the exact time of the collapse; do not invent them. Never use names for anyone; call him the person (die Person, osoba)."}

static func feedback(scenario: NaretScenario, report: String, status: String, language: String) -> String:
	var key := step(scenario)
	var repeated_safety := status == "ccbm_out_of_order" and key == "response" and preload("res://scripts/scenario/spoken_observation.gd").action_for(report) == "begin_check"
	var introductions := {
		"en": "You already reported that the scene is safe. We are now checking whether he responds. " if repeated_safety else "That report does not confirm the current check. ",
		"de": "Sie haben bereits gemeldet, dass die Umgebung sicher ist. Jetzt prüfen wir seine Reaktion. " if repeated_safety else "Diese Meldung bestätigt die aktuelle Prüfung nicht. ",
		"pl": "Już zgłoszono, że miejsce jest bezpieczne. Teraz sprawdzamy, czy reaguje. " if repeated_safety else "To zgłoszenie nie potwierdza bieżącej oceny. "}
	return str(introductions.get(language, introductions.en)) + instruction(key, language)
