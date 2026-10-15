class_name NaretTrainingCoach
extends RefCounted
## Guidance describes the next task; it never submits an action or verifies technique.
## The selected exercise omits AED interaction, not the general importance of an AED.

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
		NaretScenario.State.RECOVERY: return "finish"
	return "aed"

static func asks_for_help(text: String) -> bool:
	var words := text.to_lower()
	# Naming Anna explicitly routes a question to the witness instead.
	if "anna" in words: return false
	for phrase in ["what shall", "what can i do", "what's next", "what is next", "what now", "can you guide", "tell me what to do"]:
		if phrase in words: return true
	for phrase in ["instructor", "what next", "what should", "what do i", "how do i", "how should", "how deep", "how fast", "how long", "how many", "how to", "help me", "i am stuck", "i'm stuck", "repeat the instruction", "was soll", "wie soll", "wie tief", "wie schnell", "wie lange", "wie viele", "was jetzt", "hilf mir", "co dalej", "co mam", "jak mam", "jak głęboko", "jak szybko", "jak długo", "ile ucisk", "pomóż mi"]:
		if phrase in words: return true
	return false

static func asks_witness(text: String) -> bool:
	var words := text.to_lower()
	# Clinical requests still travel through CCBM, even when addressed to Anna.
	if "112" in words or "call" in words or "breath" in words: return false
	for phrase in ["what happened", "what has happened", "what's happened", "what is his name", "what's his name", "how old", "your husband", "was ist passiert", "co się stało"]:
		if phrase in words: return true
	return false

static func instruction(key: String, language: String) -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/coach_steps.json"))
	return str(data.get(language, data.en).get(key, data.en.get(key, "Ask the instructor for the next step.")))

static func context(scenario: NaretScenario, language: String) -> Dictionary:
	var key := step(scenario)
	var guide := {}
	for topic in ["response", "call", "breathing", "compressions", "breath_one", "breath_two", "compression_only", "handover", "aed"]:
		guide[topic] = instruction(topic, language)
	return {"language": language, "scenario_state": scenario.get_state_name(),
		"next_step": key, "approved_instruction": instruction(key, language),
		"approved_guide": guide,
		"compression_count": scenario.cycle_compressions, "breath_reports": scenario.cycle_ventilations,
		"emergency_call_reported": scenario.emergency_called,
		"scope": "one witness Anna; no AED interaction in this exercise; breaths and findings are reported, not sensor verified",
		"patient_facts": "Anna's husband Jan collapsed. Do not invent age, medical history, cause, allergies or timing; unknown facts remain unknown."}

static func feedback(scenario: NaretScenario, report: String, status: String, language: String) -> String:
	var key := step(scenario)
	var repeated_safety := status == "ccbm_out_of_order" and key == "response" and preload("res://scripts/scenario/spoken_observation.gd").action_for(report) == "begin_check"
	var introductions := {
		"en": "You already reported that the scene is safe. We are now checking whether he responds. " if repeated_safety else "That report does not confirm the current check. ",
		"de": "Sie haben bereits gemeldet, dass die Umgebung sicher ist. Jetzt prüfen wir seine Reaktion. " if repeated_safety else "Diese Meldung bestätigt die aktuelle Prüfung nicht. ",
		"pl": "Już zgłoszono, że miejsce jest bezpieczne. Teraz sprawdzamy, czy reaguje. " if repeated_safety else "To zgłoszenie nie potwierdza bieżącej oceny. "}
	return str(introductions.get(language, introductions.en)) + instruction(key, language)
