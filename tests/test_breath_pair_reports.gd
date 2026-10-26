extends "res://tests/suite.gd"
const Speech = preload("res://scripts/scenario/spoken_observation.gd")
const Confirm = preload("res://scripts/scenario/speech_confirmation.gd")

class Bridge extends Node:
	var pairs := 0
	var singles := 0
	func observe_breath_pair() -> bool:
		pairs += 1
		return true
	func observe_action(_action: String) -> bool:
		singles += 1
		return true

class Voice extends NaretAudioManager:
	var questions: Array[String] = []
	func speak(text: String, _lang: String = "pl", _clip: String = "calm", _speaker: String = "bystander") -> void:
		questions.append(text)

func run() -> Array[String]:
	failures.clear()
	for text in ["Two rescue breaths are given.", "Two rescue breaths have been given."]:
		check(Speech.reports_breath_pair(text), "observed completed pair wording: " + text)
	for text in ["I have given two rescue bread.", "I have given two rescue breads."]:
		check(not Speech.reports_breath_pair(text), "mishearing is not silently corrected")
		var gate := Confirm.new()
		var proposal := gate.evaluate(text, "cycle0:0", ["ventilation"], 0)
		check(proposal.get("proposal") == "ventilation" and proposal.get("breaths") == 2, "ask about two breaths, not one")
		var confirmed := gate.evaluate("yes", "cycle0:0", ["ventilation"], 1)
		check(confirmed.get("action") == "ventilation" and confirmed.get("breaths") == 2, "yes preserves the pair")
		check(not gate.evaluate("yes", "cycle0:0", ["ventilation"], 2).has("action"), "pair confirmation is consumed once")
		check(gate.evaluate(text, "compressing", ["compression"], 3).is_empty(), "no breath confirmation before the compression step finishes")
	for text in ["Two rescue breaths are given?", "I will give two rescue breaths", "I have not given two rescue breaths", "I ate two rescue breads"]:
		check(not Speech.reports_breath_pair(text), "question, plan, denial and unrelated speech remain blocked")
	var controls: Node = load("res://scripts/main.gd").new()
	controls._language = "en"
	controls.scenario = NaretScenario.new()
	controls.scenario.cpr_witness_only = true
	controls.scenario.start()
	for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing"]:
		controls.scenario.submit_action(action)
	for _i in range(30): controls.scenario.submit_action("compression", {"source": "hand_tracking"})
	controls.ccbm = Bridge.new()
	controls.audio_manager = Voice.new()
	controls._on_transcript("I have given two rescue breads.")
	check(controls.audio_manager.questions.back() == "Did you complete two rescue breaths? Say yes or no.", "main asks the correct confirmation")
	check(controls.ccbm.pairs == 0 and controls.ccbm.singles == 0, "mishearing creates no observation")
	controls._on_transcript("yes")
	check(controls.ccbm.pairs == 1 and controls.ccbm.singles == 0, "confirmed pair goes through the existing two-decision CCBM path")
	controls._on_transcript("Two rescue breaths are given.")
	check(controls.ccbm.pairs == 2 and controls.ccbm.singles == 0, "clear pair wording uses the same guarded path")
	controls.audio_manager.free()
	controls.ccbm.free()
	controls.scenario.free()
	controls.free()
	return failures
