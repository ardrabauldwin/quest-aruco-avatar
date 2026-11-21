extends "res://tests/suite.gd"
const Bridge = preload("res://scripts/scenario/ccbm_bridge.gd")

func run() -> Array[String]:
	failures.clear()
	for only_compressions in [false, true]:
		var scenario := NaretScenario.new()
		var bridge := Bridge.new()
		bridge.configure(scenario)
		scenario.event_recorded.connect(bridge.observe_accepted)
		scenario.start()
		for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing"]:
			check(scenario.submit_action(action), "CPR preparation " + action)
		if only_compressions: scenario.submit_action("compression_only")
		scenario.submit_action("compression", {"source":"hand_tracking"})
		scenario.submit_action("attach_aed")
		var expected := [true, true, false, true, true, false, true, true, false]
		var results: Array[bool] = []
		for i in expected.size():
			check(not scenario.submit_action("analyze_rhythm"), "every analysis requires clearance")
			check(scenario.submit_action("clear_patient"), "clearance for decision %d" % i)
			check(scenario.submit_action("analyze_rhythm"), "analysis for decision %d" % i)
			results.append(scenario.shock_advised)
			check(scenario.shock_advised == expected[i], "fixed shock/shock/no-shock decision %d" % i)
			var code := "shock_advised" if expected[i] else "no_shock_advised"
			check(bridge._history[-1] == code, "CCBM sees actual scripted decision %d" % i)
			if i == 2:
				# Contact after a no-shock result must not consume that pattern entry.
				scenario.submit_action("patient_contact", {"source":"hand_tracking"})
				check(scenario.aed_decisions_completed == i, "interruption does not advance pattern")
				scenario.submit_action("clear_patient")
				scenario.submit_action("analyze_rhythm")
				check(not scenario.shock_advised, "repeated interrupted analysis retains no-shock result")
			if expected[i]:
				check(not scenario.submit_action("shock"), "shock needs second clearance")
				scenario.submit_action("clear_patient")
				check(scenario.submit_action("shock"), "scripted shock completes")
			else:
				check(not scenario.submit_action("shock"), "no-shock cannot deliver a shock")
				check(scenario.submit_action("resume_cpr"), "no-shock also resumes CPR")
			check(scenario.state == NaretScenario.State.CPR and scenario.outcome == "ongoing", "every branch resumes CPR without automatic recovery")
			check(scenario.aed_decisions_completed == i + 1 and scenario.cycle_compressions == 0, "one completed decision and fresh set")
			scenario.submit_action("compression", {"source":"hand_tracking"})
			check(scenario.cycle_compressions == 1 and scenario.compressions == i + 2, "next press is one; session total remains")
			if i < expected.size() - 1:
				scenario.advance_simulation(119.9)
				check(not scenario.analysis_due, "same 120-second reassessment interval")
				scenario.advance_simulation(0.1)
				check(scenario.submit_action("reassess"), "next scripted decision after CPR interval")
		check(results == expected and scenario.shock_count == 6, "three complete pattern repetitions")
		check(scenario.get_summary().aed_decision_source == "scripted_repeating_pattern", "report labels decision source explicitly")
		scenario.submit_action("handover")
		check(scenario.state == NaretScenario.State.RECOVERY and scenario.outcome == "simulated_handover", "exercise ends explicitly")
		scenario.start()
		check(scenario.aed_decisions_completed == 0 and scenario.shock_count == 0 and scenario.shock_advised, "restart returns to first pattern entry")
		bridge.free()
		scenario.free()
	return failures
