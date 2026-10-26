extends "res://tests/suite.gd"

class Decisions extends "res://scripts/scenario/ccbm_bridge.gd":
	var calls := 0
	func _request(action: String) -> void:
		calls += 1
		_scenario.submit_action(action)

func run() -> Array[String]:
	failures.clear()
	for first_reported in [false, true]:
		var scenario := NaretScenario.new()
		scenario.cpr_witness_only = true
		scenario.start()
		for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing"]:
			scenario.submit_action(action)
		for i in 30: scenario.submit_action("compression")
		if first_reported: scenario.submit_action("ventilation")
		var bridge := Decisions.new()
		bridge.configure(scenario)
		check(bridge.observe_breath_pair(), "completed-pair report is accepted during the breath step")
		check(bridge.calls == (1 if first_reported else 2), "only the remaining breaths require decisions")
		check(scenario.cycles == 1 and scenario.cycle_compressions == 0, "pair resumes the next compression cycle")
		check(not bridge.observe_breath_pair(), "repeated pair cannot count in the next compression stage")
		check(scenario.ventilations == 2, "first report plus pair never creates three breaths")
		bridge.free()
		scenario.free()
	return failures
