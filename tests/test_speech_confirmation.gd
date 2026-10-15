extends "res://tests/suite.gd"
const Speech = preload("res://scripts/scenario/spoken_observation.gd")
const Confirm = preload("res://scripts/scenario/speech_confirmation.gd")

func run() -> Array[String]:
	failures.clear()
	for text in ["Are you okay? Can you hear me? He is not responding.", "Are you okay can you hear me he is not responding", "He is not responding. Can you hear me?", "Hello, sir, are you okay? He is not responding."]:
		check(Speech.action_for(text) == "check_responsiveness", "patient questions with completed finding: " + text)
	for text in ["Are you okay?", "Are you okay? He is not responding?", "If he is not responding. Can you hear me?", "He is not responding. He is responding.", "He is not responding. He is not breathing normally.", "Do not say he is not responding."]:
		check(Speech.action_for(text).is_empty(), "uncertain or conflicting multiple sentences blocked: " + text)
	for text in ["I have given one rescue breath.", "I have given the first rescue breath.", "I have given the second rescue breath."]:
		check(Speech.action_for(text) == "ventilation", "completed breath report: " + text)
	check(Speech.action_for("I will give the second rescue breath").is_empty(), "planned breath is not completion")
	for text in ["He isn't responding.", "No response.", "He is unresponsive."]:
		check(Speech.action_for(text) == "check_responsiveness", "clear equivalent: " + text)
	for text in ["He is responding", "He is breathing normally", "I will check breathing", "He isn't responding?", "No response and no breathing"]:
		check(Speech.action_for(text).is_empty(), "opposite, question or compound stays blocked")
	var gate := Confirm.new()
	for text in ["I have given the first breath.", "I've given the second breath.", "We have given the first breath."]:
		check(Speech.action_for(text) == "ventilation", "natural completed breath report: " + text)
	check(Speech.action_for("I will give the first breath").is_empty(), "planned ordinary breath remains blocked")
	check(gate.evaluate("We have given the first bread.", "breath", ["ventilation"], 0).get("proposal") == "ventilation", "bread transcription needs confirmation")
	check(gate.evaluate("yes", "breath", ["ventilation"], 1).get("action") == "ventilation", "confirmed breath passes")
	check(gate.evaluate("We have given the first bread.", "cpr", ["compression"], 2).is_empty(), "breath proposal blocked before thirty")
	var allowed := ["begin_check"]
	check(gate.evaluate("scene a save.", "a", allowed, 0).get("proposal") == "begin_check", "headset safety mistranscription asks confirmation")
	check(gate.evaluate("yes", "a", allowed, 1).get("action") == "begin_check", "headset safety report needs explicit confirmation")
	check(not gate.evaluate("yes", "a", allowed, 0).has("action"), "bare yes cannot advance")
	check(gate.evaluate("Tassini's safe!", "a", allowed, 100).get("proposal") == "begin_check", "misheard phrase asks confirmation")
	check(gate.evaluate("yes", "a", allowed, 200).get("action") == "begin_check", "specific pending confirmation passes")
	check(not gate.evaluate("yes", "a", allowed, 300).has("action"), "confirmation consumed once")
	gate.evaluate("Tassini's safe", "a", allowed, 400)
	check(not gate.evaluate("yes", "b", allowed, 500).has("action"), "stage change invalidates confirmation")
	gate.evaluate("Tassini's safe", "a", allowed, 600)
	check(not gate.evaluate("yes", "a", allowed, 31000).has("action"), "expired proposal cannot advance")
	gate.evaluate("Tassini's safe", "a", allowed, 32000)
	check(not gate.evaluate("no", "a", allowed, 32100).has("action"), "no cancels")
	check(gate.evaluate("The vaccine is safe", "a", allowed, 32200).is_empty(), "unrelated safety statement not guessed")
	check(gate.evaluate("Tassini's safe", "a", ["call_emergency"], 32300).is_empty(), "out of order proposal blocked")
	return failures
