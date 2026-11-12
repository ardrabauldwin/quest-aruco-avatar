extends "res://tests/suite.gd"
const Speech = preload("res://scripts/scenario/spoken_observation.gd")
const Bridge = preload("res://scripts/scenario/ccbm_bridge.gd")

func run() -> Array[String]:
	failures.clear()
	check(Speech.action_for("He is not responding.") == "check_responsiveness", "English report")
	check(Speech.action_for("Er reagiert nicht.") == "check_responsiveness", "German report")
	check(Speech.action_for("Pacjent nie oddycha prawidłowo.") == "check_breathing", "Polish report")
	for utterance in ["He is not responding?", "If he is not responding", "Do not call 112", "He is responding", "I will give one rescue breath", "He is not responding and not breathing normally"]:
		check(Speech.action_for(utterance).is_empty(), "Do not infer completion: " + utterance)
	check(Bridge.accepts({"engine": "ccbm", "action": "check_breathing", "probability": 0.95}, "check_breathing", 0.9), "Matching posterior accepted")
	check(not Bridge.accepts({"engine": "ccbm", "action": "handover", "probability": 0.99}, "check_breathing", 0.9), "Other inferred action cannot advance")
	check(not Bridge.accepts({"engine": "ccbm", "action": "check_breathing", "probability": 0.6}, "check_breathing", 0.9), "Uncertain posterior held")
	check(not Bridge.accepts({"engine": "ccbm", "action": "check_breathing", "probability": INF}, "check_breathing", 0.9), "Invalid posterior held")
	var scenario := NaretScenario.new()
	scenario.cpr_witness_only = true
	var bridge := Bridge.new()
	bridge.configure(scenario)
	bridge.decision.connect(func(action: String, details: Dictionary): scenario.submit_action(action, details))
	bridge.observe_speech("Start exercise")
	check(scenario.state == NaretScenario.State.INTRO, "Spoken start routes to start action")
	bridge.observe_speech("He is not responding")
	check(scenario.state == NaretScenario.State.INTRO, "Out-of-order report held")
	bridge.observe_speech("The scene is safe")
	check(scenario.state == NaretScenario.State.INTRO, "Missing CCBM does not silently accept")
	scenario.observation_driven = true
	check(not "begin_check" in scenario.get_interface_actions(), "Routine buttons hidden in observation mode")
	check("begin_check" in scenario.get_available_actions(), "Observation transition still available")
	# Exercise adapter-to-controller wiring without claiming to run native CCBM.
	scenario.event_recorded.connect(bridge.observe_accepted)
	for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing"]:
		bridge.decision.emit(action, {"source": "speech", "measurement_verified": false})
	check(scenario.state == NaretScenario.State.CPR, "Adapter decisions advance through guarded stages")
	var history_before := bridge._history.size()
	check(bridge.observe_action("compression"), "Speech compression report handled")
	check(bridge._history.size() == history_before, "Speech cannot add a compression observation or count")
	for i in range(30): scenario.submit_action("compression", {"source": "hand_tracking"})
	check(bridge._history.count("compression") == 1, "30 strokes produce one CCBM onset observation")
	for i in range(2): bridge.decision.emit("ventilation", {"source": "speech", "measurement_verified": false})
	check(scenario.cycles == 1, "Reported breaths finish cycle without button")
	bridge.decision.emit("handover", {"source": "speech", "measurement_verified": false})
	check(scenario.state == NaretScenario.State.RECOVERY, "Spoken handover path")
	bridge.free()
	scenario.free()
	_check_desktop_bypass()
	return failures

func _check_desktop_bypass() -> void:
	# Desktop only, opt-in, no worker configured; the scenario guards still decide.
	var scenario := NaretScenario.new()
	scenario.cpr_witness_only = true
	var bridge := Bridge.new()
	bridge.configure(scenario)
	var statuses: Array[String] = []
	var engines: Array[String] = []
	bridge.status_changed.connect(func(status: String): statuses.append(status))
	bridge.decision.connect(func(action: String, details: Dictionary):
		engines.append(str(details.get("inference_engine", "")))
		scenario.submit_action(action, details))
	check(not bridge.bypass_active(), "Bypass is off unless switched on")
	bridge.desktop_bypass = true
	check(bridge.bypass_active() == not OS.has_feature("android"), "Bypass never applies on Quest")
	bridge.observe_speech("Die Umgebung ist sicher")
	check(scenario.state == NaretScenario.State.CHECK_PATIENT, "Bypass: safety report advances on desktop")
	check("ccbm_bypassed" in statuses and "ccbm_unavailable" not in statuses, "Bypass is reported, not hidden")
	check(engines.has("none_desktop_bypass"), "Bypass decisions are labelled as not CCBM")
	bridge.observe_speech("Er atmet nicht normal")
	check(scenario.state == NaretScenario.State.CHECK_PATIENT and not scenario.breathing_checked, "Bypass: out-of-order report still held")
	bridge.observe_speech("Er reagiert nicht")
	bridge.observe_speech("Anna, ruf 112 an")
	bridge.observe_speech("Er atmet nicht normal")
	check(scenario.state == NaretScenario.State.CPR, "Bypass: German reports reach CPR in ERC order")
	bridge.endpoint = "http://127.0.0.1:8766/infer"
	check(not bridge.bypass_active(), "A configured worker always takes precedence")
	bridge.free()
	scenario.free()
