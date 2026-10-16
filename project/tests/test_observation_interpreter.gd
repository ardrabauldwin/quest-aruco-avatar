extends "res://tests/suite.gd"
const Interpreter = preload("res://scripts/ai/observation_interpreter.gd")

func run() -> Array[String]:
	failures.clear()
	# These validate structured-output policy, not a live language model's accuracy.
	for phrase in ["I checked him; he did not react", "Ich habe ihn geprüft, er reagiert nicht", "Sprawdziłem, pacjent nie reaguje"]:
		var response := {"action": "check_responsiveness", "kind": "report", "result": "unresponsive", "evidence": phrase}
		var parsed := Interpreter.parse(JSON.stringify(response), phrase)
		check(Interpreter.accepted_action(parsed, phrase) == "check_responsiveness", "Paraphrase report structure: " + phrase)
	for kind in ["question", "intention", "uncertain", "conversation"]:
		check(Interpreter.accepted_action({"action": "check_responsiveness", "kind": kind, "result": "unresponsive"}, "example").is_empty(), "Non-completed kind rejected: " + kind)
	check(Interpreter.accepted_action({"action": "check_responsiveness", "kind": "report", "result": "responsive"}, "He responds").is_empty(), "Opposite finding must not advance")
	check(Interpreter.accepted_action({"action": "check_breathing", "kind": "report", "result": "normal"}, "Breathing normally").is_empty(), "Normal breathing must not start CPR")
	check(Interpreter.accepted_action({"action": "ventilation", "kind": "report", "result": "none"}, "I will give breaths").is_empty(), "No invented breath")
	check(Interpreter.accepted_action({"action": "call_emergency", "kind": "request", "result": "none"}, "Could you call 112?") == "call_emergency", "Polite request may be accepted")
	check(Interpreter.accepted_action({"action": "check_responsiveness", "kind": "report", "result": "unresponsive"}, "He is not responding?").is_empty(), "Question about a finding requires clarification")
	check(Interpreter.parse('{"action":"handover","kind":"request","result":"none","evidence":"invented"}', "Hello").is_empty(), "Evidence must occur in actual utterance")
	check(Interpreter.parse('{"action":"shock","kind":"request","result":"none","evidence":"shock"}', "shock").is_empty(), "Unknown action rejected")
	check(Interpreter.parse('not json', "hello").is_empty(), "Malformed model reply rejected")
	check(Interpreter.parse('{"action":7}', "hello").is_empty(), "Wrong types rejected")
	for lang in ["en", "de", "pl"]:
		check(not Interpreter.clarification_text(lang).is_empty(), "Local clarification available " + lang)
	return failures
