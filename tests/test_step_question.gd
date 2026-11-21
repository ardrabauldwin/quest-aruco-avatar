extends "res://tests/suite.gd"
## Silence or an unusable transcript ends in the step's own yes/no question (11 Nov 2026),
## and one word then confirms exactly that step, nothing else.
const Coach = preload("res://scripts/ai/training_coach.gd")
const Confirmation = preload("res://scripts/ai/speech_pipeline.gd").Confirmation

func run() -> Array[String]:
	failures.clear()
	var expected := {
		"safety": {"action": "begin_check", "breaths": 1},
		"response": {"action": "check_responsiveness", "breaths": 1},
		"call": {"action": "call_emergency", "breaths": 1},
		"breathing": {"action": "check_breathing", "breaths": 1},
		"breaths": {"action": "ventilation", "breaths": 2},
	}
	for step: String in expected:
		check(Coach.step_question(step) == expected[step], "step with a spoken report gets its question: " + step)
	for step in ["setup", "compressions", "compression_only", "aed_clear", "aed_analyse", "aed_shock_clear", "aed_countdown", "aed_resume", "finish", "aed"]:
		check(Coach.step_question(step).is_empty(), "step without a spoken report gets no question: " + step)
	for step: String in expected:
		for language in ["en", "de", "pl"]:
			var question := Confirmation.question(str(expected[step].action), int(expected[step].breaths), language)
			check(not question.is_empty() and question != Confirmation.repeat_message(language), "a real question exists for %s in %s" % [step, language])
	# one word answers it
	var gate := Confirmation.new()
	gate.propose("check_breathing", "ctx", 0, "de", 1)
	check(gate.evaluate("Ja.", "ctx", ["check_breathing"], 1000, "de").get("action") == "check_breathing", "German yes confirms the asked step")
	gate.propose("ventilation", "ctx", 0, "pl", 2)
	var pair: Dictionary = gate.evaluate("tak", "ctx", ["ventilation"], 500, "pl")
	check(pair.get("action") == "ventilation" and pair.get("breaths") == 2, "Polish yes confirms the two-breath question as a pair")
	gate.propose("begin_check", "ctx", 0, "en", 1)
	check(not gate.evaluate("no", "ctx", ["begin_check"], 10, "en").has("action"), "no cancels the asked step")
	gate.propose("begin_check", "ctx", 0, "en", 1)
	check(not gate.evaluate("yes", "other-ctx", ["begin_check"], 10, "en").has("action"), "a yes after the scenario moved on confirms nothing")
	gate.propose("begin_check", "ctx", 0, "en", 1)
	check(not gate.evaluate("yes", "ctx", ["begin_check"], Confirmation.LIFETIME_MS + 1, "en").has("action"), "a yes after the lifetime confirms nothing")
	return failures
