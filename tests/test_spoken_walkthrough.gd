extends "res://tests/suite.gd"
## A full BLS run driven only by spoken sentences, in German, Polish and English, through the
## real scenario state machine, the real rule file and the real yes/no question (11 Nov 2026).
## Covers what a person on the headset would say, including silence answered with "yes".
## Not covered here: the microphone and Whisper, which need a real voice.
const Speech = preload("res://scripts/scenario/spoken_observation.gd")
const Coach = preload("res://scripts/ai/training_coach.gd")
const Confirmation = preload("res://scripts/ai/speech_pipeline.gd").Confirmation
const Scenario = preload("res://scripts/scenario/scenario_controller.gd")

const RUNS := {
	"de": [
		["Die Umgebung ist sicher, keine Gefahr.", "begin_check", "check_patient"],
		["Er reagiert nicht auf Ansprache und Rütteln.", "check_responsiveness", "call_help"],
		["Anna, ruf bitte den Rettungsdienst an und stell auf Lautsprecher.", "call_emergency", "call_help"],
		["Er atmet gar nicht mehr.", "check_breathing", "cpr"],
	],
	"pl": [
		["Miejsce jest bezpieczne, nie ma zagrożenia.", "begin_check", "check_patient"],
		["Pacjent w ogóle nie reaguje.", "check_responsiveness", "call_help"],
		["Anno, zadzwoń na 112 i włącz głośnomówiący.", "call_emergency", "call_help"],
		["On wcale nie oddycha.", "check_breathing", "cpr"],
	],
	"en": [
		["The scene is safe.", "begin_check", "check_patient"],
		["He's not responding at all.", "check_responsiveness", "call_help"],
		["Anna, please call 112 and put the call on speaker.", "call_emergency", "call_help"],
		["He's not breathing at all.", "check_breathing", "cpr"],
	],
}
const YES := {"de": "Ja.", "pl": "Tak.", "en": "Yes."}
const NO := {"de": "Nein.", "pl": "Nie.", "en": "No."}
const WRONG := {
	"de": ["Er atmet normal.", "Atmet er überhaupt?", "Ich glaube, er atmet nicht.", "Der Hund atmet nicht."],
	"pl": ["Pacjent oddycha prawidłowo.", "Czy on oddycha?", "Chyba nie oddycha.", "Kot nie oddycha."],
	"en": ["He is breathing normally.", "Is he breathing?", "I think he's not breathing.", "The dog is not breathing."],
}

func _submit(scenario: NaretScenario, text: String, language: String) -> String:
	# The same order as main._on_transcript: safety by meaning first at the first step, then the rules.
	var action := ""
	if "begin_check" in scenario.get_available_actions():
		var safety: String = Speech.classify_safety(text, language)
		if safety == "safe": action = "begin_check"
		elif safety == "unsafe": return "unsafe"
	if action.is_empty(): action = Speech.action_for(text)
	if action.is_empty(): return ""
	var details := {"source": "speech"}
	if action == "check_responsiveness": details["responsive"] = false
	if action == "check_breathing": details["normal_breathing"] = false
	return action if scenario.submit_action(action, details) else "rejected:" + action

func run() -> Array[String]:
	failures.clear()
	for language: String in RUNS:
		# 1. the spoken run, step by step
		var scenario := Scenario.new()
		scenario.language = language
		scenario.submit_action("start")
		check(scenario.state == NaretScenario.State.INTRO, language + ": run starts at the arrival step")
		for step: Array in RUNS[language]:
			var got := _submit(scenario, step[0], language)
			check(got == step[1], "%s: '%s' -> expected %s, got '%s'" % [language, step[0], step[1], got])
			check(scenario.get_state_name() == step[2], "%s: after '%s' the scenario is in %s, not %s" % [language, step[0], step[2], scenario.get_state_name()])
		# 2. wrong sentences at the breathing step never move the scenario
		var probe := Scenario.new()
		probe.language = language
		probe.submit_action("start")
		_submit(probe, RUNS[language][0][0], language)
		_submit(probe, RUNS[language][1][0], language)
		_submit(probe, RUNS[language][2][0], language)
		for text: String in WRONG[language]:
			var got := _submit(probe, text, language)
			check(got == "", "%s: '%s' must not be a step, got '%s'" % [language, text, got])
			check(probe.get_state_name() == "call_help", "%s: '%s' must not move the scenario" % [language, text])
		# 3. silence at the breathing step: the step question, then one word
		var pick: Dictionary = Coach.step_question(Coach.step(probe))
		check(pick.get("action") == "check_breathing", language + ": silence at the breathing step asks about breathing")
		var gate := Confirmation.new()
		var context := "ctx-" + language
		gate.propose(str(pick.action), context, 0, language, int(pick.breaths))
		var question := Confirmation.question(str(pick.action), int(pick.breaths), language)
		check(not question.is_empty(), language + ": the question has text")
		var answer: Dictionary = gate.evaluate(YES[language], context, probe.get_available_actions(), 1000, language)
		check(answer.get("action") == "check_breathing", "%s: '%s' confirms the asked step" % [language, YES[language]])
		check(probe.submit_action("check_breathing", {"source": "speech", "normal_breathing": false}), language + ": the confirmed step is accepted by the scenario")
		check(probe.get_state_name() == "cpr", language + ": and the run is in CPR")
		# 4. "no" cancels, a stray later "yes" does nothing
		var gate2 := Confirmation.new()
		gate2.propose("begin_check", "c", 0, language, 1)
		check(not gate2.evaluate(NO[language], "c", ["begin_check"], 10, language).has("action"), "%s: '%s' cancels" % [language, NO[language]])
		check(not gate2.evaluate(YES[language], "c", ["begin_check"], 20, language).has("action"), language + ": a yes after a no confirms nothing")
		scenario.free()
		probe.free()
	return failures
