extends "res://tests/suite.gd"
const Bridge = preload("res://scripts/scenario/ccbm_bridge.gd")
const Native = preload("res://scripts/scenario/ccbm_native.gd")

class HeldClearance extends RefCounted:
	signal complete
	func infer(_observations: Array) -> Dictionary:
		await complete
		return {"engine":"ccbm", "action":"clear_patient", "probability":0.99}

func run() -> Array[String]:
	failures.clear()
	var scenario := NaretScenario.new()
	var bridge := Bridge.new()
	bridge.configure(scenario)
	scenario.event_recorded.connect(bridge.observe_accepted)
	scenario.start()
	for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing", "request_aed"]:
		check(scenario.submit_action(action), "initial actual scenario event " + action)
	for i in 17: scenario.submit_action("compression", {"source":"hand_tracking"})
	check(bridge._history.count("compression") == 1, "one onset before AED")
	scenario.submit_action("attach_aed")
	scenario.submit_action("clear_patient")
	scenario.submit_action("patient_contact", {"source":"hand_tracking"})
	scenario.submit_action("patient_contact", {"source":"hand_tracking"})
	check(bridge._history.count("patient_contact") == 1, "rejected sensor contact revokes native clearance once, not each poll")
	scenario.submit_action("clear_patient")
	scenario.submit_action("analyze_rhythm")
	check(bridge._history[-2] == "analyze_rhythm" and bridge._history[-1] == "shock_advised", "analysis result becomes structural model observation")
	scenario.submit_action("clear_patient")
	scenario.submit_action("shock")
	check(bridge._history[-1] == "shock", "actual shock completion reaches model without ASR")
	scenario.submit_action("compression", {"source":"hand_tracking"})
	check(bridge._history.count("compression") == 2, "new CPR onset after shock reaches CCBM")
	var length := bridge._history.size()
	for i in 10: scenario.submit_action("compression", {"source":"hand_tracking"})
	check(bridge._history.size() == length, "later presses do not launch repeated onset inference")
	scenario.aed_training_pattern = [false]
	scenario.analysis_due = true
	scenario.submit_action("reassess")
	scenario.submit_action("clear_patient")
	scenario.submit_action("analyze_rhythm")
	check(bridge._history[-1] == "no_shock_advised", "no-shock result reaches CCBM")
	scenario.submit_action("resume_cpr")
	scenario.submit_action("compression", {"source":"hand_tracking"})
	check(bridge._history[-2] == "resume_cpr" and bridge._history[-1] == "compression", "no-shock followed by new CPR onset")
	length = bridge._history.size()
	for action in ["shock", "analyze_rhythm", "attach_aed", "no_shock_advised", "recovery"]:
		bridge.observe_action(action)
	check(bridge._history.size() == length, "speech cannot fabricate physical AED events or outcomes")
	var output := 'Time "(clear_for_analysis)" "(clear_for_shock)" "BLOCKED"\n1 0.45 0.5 0.05'
	check(Native.parse_posterior(output, 1).get("action") == "clear_patient", "native clearance aliases aggregate into one observation code")
	check(not Native.supports_aed({"engine":"ccbm"}), "old witness-only packaged model is explicitly refused")
	var model: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://addons/ccbm_native/model.json"))
	check(Native.supports_aed(model), "packaged native model advertises all AED observation codes")
	scenario.reset()
	check(bridge._history.is_empty() and bridge.last_tracking.is_empty(), "session reset clears event history and tracking result")
	bridge.free()
	scenario.free()
	# Scheduling/guard check only; real inference is tested with the compiled filter separately.
	scenario = NaretScenario.new()
	scenario.start()
	bridge = Bridge.new()
	bridge.configure(scenario)
	scenario.event_recorded.connect(bridge.observe_accepted)
	for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing", "attach_aed"]:
		scenario.submit_action(action)
	var held := HeldClearance.new()
	bridge._native = held
	bridge._tracking_dirty = false
	var decisions: Array[String] = []
	bridge.decision.connect(func(action: String, _details: Dictionary): decisions.append(action))
	bridge.observe_action("clear_patient")
	scenario.submit_action("patient_contact", {"source":"hand_tracking"})
	held.complete.emit()
	check(decisions.is_empty() and not bridge._pending, "contact during a pending clearance prevents a stale native decision")
	bridge.free()
	scenario.free()
	return failures
