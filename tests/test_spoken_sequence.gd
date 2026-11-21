extends "res://tests/suite.gd"
## Several steps in one breath (11 Nov 2026): every clear sentence is taken in order; an
## unclear or opposite clause anywhere refuses the whole utterance as before.
const Speech = preload("res://scripts/scenario/spoken_observation.gd")
const Scenario = preload("res://scripts/scenario/scenario_controller.gd")

func run() -> Array[String]:
	failures.clear()
	var accepted := {
		"The scene is safe. He is not responding.": ["begin_check", "check_responsiveness"],
		"Die Umgebung ist sicher. Er reagiert nicht.": ["begin_check", "check_responsiveness"],
		"Miejsce jest bezpieczne. Pacjent nie reaguje.": ["begin_check", "check_responsiveness"],
		"He's not responding. Anna, please call 112.": ["check_responsiveness", "call_emergency"],
		"Er reagiert nicht! Anna, ruf die 112 an!": ["check_responsiveness", "call_emergency"],
		"Are you okay? Can you hear me? He is not responding. He is not breathing normally.": ["check_responsiveness", "check_breathing"],
		"The scene is safe. The scene is safe. He is not responding.": ["begin_check", "check_responsiveness"],
		"Hallo, hören Sie mich? Er reagiert nicht. Er atmet nicht normal.": ["check_responsiveness", "check_breathing"],
		"Halo, słyszy mnie pan? Pacjent nie reaguje. Pacjent nie oddycha prawidłowo.": ["check_responsiveness", "check_breathing"],
	}
	for single in {"Hallo, hören Sie mich? Er reagiert nicht.": "check_responsiveness", "Halo, słyszy mnie pani? Nie reaguje.": "check_responsiveness",
			"Alles in Ordnung? Hören Sie mich? Er reagiert nicht.": "check_responsiveness", "Hallo? Er reagiert nicht?": "", "Halo, czy mnie pan słyszy? Czy on reaguje?": ""}:
		var one := Speech.action_for(single)
		check(one == {"Hallo, hören Sie mich? Er reagiert nicht.": "check_responsiveness", "Halo, słyszy mnie pani? Nie reaguje.": "check_responsiveness",
			"Alles in Ordnung? Hören Sie mich? Er reagiert nicht.": "check_responsiveness", "Hallo? Er reagiert nicht?": "", "Halo, czy mnie pan słyszy? Czy on reaguje?": ""}[single],
			"patient address stripped in German/Polish: '%s' -> '%s'" % [single, one])
	for text: String in accepted:
		var got := Speech.actions_for(text)
		check(got == accepted[text], "sequence from '%s': expected %s, got %s" % [text, accepted[text], got])
	for text in [
		"The scene is safe.",                                   # one step is not a sequence
		"The scene is safe. He is responding.",                  # second clause is the opposite finding
		"He is not responding. He is breathing normally.",       # opposite finding
		"The scene is safe. Is he breathing?",                   # question
		"He is not responding. I will check his breathing.",     # plan
		"Er reagiert nicht. Vielleicht atmet er.",               # doubt
		"Pacjent nie reaguje. Kot nie oddycha.",                 # off-topic clause
	]:
		var got := Speech.actions_for(text)
		check(got.is_empty(), "no sequence from '%s', got %s" % [text, got])
	# the scenario takes them in order, and skips a step already done
	var scenario := Scenario.new()
	scenario.submit_action("start")
	var sequence := Speech.actions_for("The scene is safe. He is not responding.")
	for action: String in sequence:
		if action in scenario.get_available_actions():
			scenario.submit_action(action, {"source": "speech", "responsive": false})
	check(scenario.get_state_name() == "call_help", "two steps in one breath at the first step reach the call step")
	var again := Speech.actions_for("The scene is safe. Anna, please call 112.")
	var taken := 0
	for action: String in again:
		if action in scenario.get_available_actions():
			scenario.submit_action(action, {"source": "speech"})
			taken += 1
	check(taken == 1 and scenario.emergency_called, "a step already done is skipped, the due one is taken")
	scenario.free()
	return failures
