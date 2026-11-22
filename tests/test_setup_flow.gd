extends "res://tests/suite.gd"
## The choices before the scenario (wrist fold-out keys, 18 Nov 2026).

func run() -> Array[String]:
	failures.clear()
	var flow := NaretSetupFlow.new()
	check(not flow.done(), "nothing chosen yet")
	flow.answers = {"language": "de", "mode": "own", "situation": "B", "breaths": "yes"}
	check(flow.done(), "with a situation the choices are complete")
	flow.answers["breaths"] = "no"
	check(flow.answers.breaths == "no" and flow.done(), "a later change keeps them complete")
	return failures
