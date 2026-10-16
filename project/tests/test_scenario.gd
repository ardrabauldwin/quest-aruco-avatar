extends "res://tests/suite.gd"

const Scenario = preload("res://scripts/scenario/scenario_controller.gd")
const Score = preload("res://scripts/feedback/score_tracker.gd")
const SessionLog = preload("res://scripts/feedback/session_logger.gd")

func run() -> Array[String]:
	for lang: String in ["de", "pl"]:
		_test_complete_flow(lang)
	_test_nonshockable()
	_test_shock_outcome()
	_test_helper_compressions()
	_test_compression_only()
	_test_export_and_quality()
	return failures

func enter_cpr(scenario: Node) -> void:
	scenario.start()
	check(scenario.submit_action("begin_check"), "Begin patient check")
	check(scenario.submit_action("check_responsiveness"), "Confirm unresponsive")
	check(scenario.submit_action("call_emergency"), "ERC 2025: 112 for anyone unresponsive")
	check(scenario.submit_action("check_breathing"), "Abnormal breathing starts immediate CPR")

func _test_complete_flow(lang: String) -> void:
	var scenario := Scenario.new()
	scenario.language = lang
	scenario.shock_success_chance = 0.0 # this flow keeps the VF past its one shock
	scenario.start()
	check(scenario.state == Scenario.State.INTRO, lang + ": starts at INTRO")
	check(not scenario.submit_action("shock"), "Cannot shock before AED")
	check(scenario.submit_action("begin_check"), "Safety check")
	check(not scenario.submit_action("check_breathing"), "Awareness is checked before breathing")
	check(scenario.submit_action("check_responsiveness"), "Awareness check accepted")
	check(scenario.state == Scenario.State.CALL_HELP, "ERC 2025: no response leads straight to the emergency call")
	check(scenario.get_instruction_key() == "instruction.call_help", "Call prompt follows the missing response")
	check(not scenario.submit_action("check_breathing") and scenario.last_error == "error.call_first", "ERC 2025: breathing is assessed after 112 is called")
	check(scenario.submit_action("request_aed"), "Request AED while arranging emergency response")
	check(scenario.state == Scenario.State.CALL_HELP, "AED request does not replace 112")
	check(scenario.submit_action("call_emergency"), "Call 112")
	check(scenario.state == Scenario.State.CALL_HELP and scenario.get_instruction_key() == "instruction.check_breathing", "Breathing is checked while the call connects")
	check(not scenario.submit_action("check_breathing", {"normal_breathing": true}), "Normal breathing cannot be declared cardiac arrest")
	check(scenario.submit_action("check_breathing"), "Breathing check accepted")
	check(scenario.state == Scenario.State.CPR, "Abnormal breathing starts CPR")
	check(not scenario.submit_action("ventilation"), "Cannot begin ratio with ventilation")
	for index in range(30):
		check(scenario.submit_action("compression"), "Compression %d accepted" % index)
	check(not scenario.submit_action("compression"), "31st compression requires breath or compression-only mode")
	check(scenario.submit_action("ventilation"), "First breath")
	check(scenario.cycle_compressions == 30, "First breath preserves ratio progress")
	check(scenario.submit_action("ventilation"), "Second breath")
	check(scenario.cycles == 1 and scenario.compressions == 30 and scenario.ventilations == 2, "30:2 accounting")
	check(scenario.submit_action("attach_aed"), "Attach AED")
	check(not scenario.submit_action("analyze_rhythm"), "Analysis requires clearance")
	check(scenario.submit_action("clear_patient"), "Clear for analysis")
	check(scenario.submit_action("analyze_rhythm"), "AED analysis")
	check(not scenario.submit_action("shock"), "Shock requires fresh clearance")
	check(scenario.submit_action("clear_patient"), "Clear for shock")
	check(not scenario.submit_action("patient_contact"), "Contact cancels AED safety clearance")
	check(not scenario.submit_action("shock"), "Contact prevents shock")
	check(scenario.submit_action("clear_patient"), "Clear again")
	check(scenario.submit_action("analyze_rhythm"), "Repeat interrupted analysis")
	check(scenario.submit_action("clear_patient"), "Fresh shock clearance")
	check(scenario.submit_action("shock"), "Safe indicated shock accepted")
	check(scenario.state == Scenario.State.CPR and scenario.shock_count == 1, "Shock immediately resumes CPR, never automatic recovery")
	check(not scenario.submit_action("simulate_rosc", {"trainer": true}), "Trainer cannot skip postshock CPR")
	check(scenario.submit_action("compression"), "Postshock compression")
	check(not scenario.submit_action("simulate_rosc"), "ROSC requires explicit trainer injection")
	check(not scenario.submit_action("reassess"), "No immediate rhythm reassessment after shock")
	scenario.advance_simulation(119.9)
	check(not scenario.analysis_due, "AED interval is not early")
	scenario.advance_simulation(0.1)
	check(scenario.analysis_due, "AED requests analysis after 120s of simulated CPR")
	check(scenario.submit_action("reassess"), "Reassessment after AED prompt")
	check(scenario.reassessments == 1 and scenario.state == Scenario.State.AED, "Reassessment re-enters safe analysis")
	scenario.shock_advised = false
	scenario.submit_action("clear_patient")
	scenario.submit_action("analyze_rhythm")
	check(scenario.submit_action("resume_cpr"), "No shock advised resumes CPR")
	check(not scenario.submit_action("simulate_rosc", {"trainer": true}), "Every AED cycle requires further CPR before trainer ROSC")
	check(scenario.submit_action("compression"), "Further CPR after repeated analysis")
	check(scenario.submit_action("simulate_rosc", {"trainer": true}), "Explicit trainer-simulated signs of life")
	check(scenario.state == Scenario.State.RECOVERY, "End in briefing")
	var summary := scenario.get_summary()
	check(summary.outcome == "trainer_simulated_rosc" and not summary.clinically_validated, "Summary labels simulation and validity")
	check(not scenario.submit_action("compression"), "Completed training does not accept compressions")
	scenario.reset()
	check(scenario.state == Scenario.State.IDLE and scenario.compressions == 0 and scenario.shock_count == 0, "Reset clears clinical and counters state")
	scenario.free()

func _test_nonshockable() -> void:
	var scenario := Scenario.new()
	scenario.shock_advised = false
	enter_cpr(scenario)
	check(scenario.submit_action("attach_aed"), "Available AED is used without waiting for full CPR cycle")
	scenario.submit_action("clear_patient")
	scenario.submit_action("analyze_rhythm")
	check(not scenario.submit_action("shock"), "Nonshockable rhythm cannot receive a shock")
	check(scenario.submit_action("resume_cpr"), "Nonshockable branch continues CPR")
	check(scenario.shock_count == 0 and scenario.state == Scenario.State.CPR, "No-shock branch does not imply recovery")
	check(scenario.submit_action("handover"), "Rescue-team handover is an explicit completion")
	check(scenario.outcome == "simulated_handover", "Handover outcome retained")
	scenario.free()

func _shock_cycle(scenario: Node) -> void:
	## Analysis, shock, then the two minutes of CPR until the device analyses again.
	scenario.submit_action("clear_patient")
	scenario.submit_action("analyze_rhythm")
	if scenario.state != Scenario.State.AED or scenario.aed_stage != Scenario.AEDStage.SHOCK_ADVISED:
		return
	scenario.submit_action("clear_patient")
	check(scenario.submit_action("shock"), "Advised shock delivered")
	scenario.submit_action("compression")
	scenario.advance_simulation(120.0)
	check(scenario.submit_action("reassess"), "Device reanalyses after two minutes")

func _test_shock_outcome() -> void:
	## Whether a shock worked shows only at the next analysis; the third always converts.
	var scenario := Scenario.new()
	scenario.shock_success_chance = 0.0
	enter_cpr(scenario)
	scenario.submit_action("attach_aed")
	for i in 3:
		_shock_cycle(scenario)
		check(scenario.state == Scenario.State.AED, "Still VF after shock %d" % (i + 1) if i < 2 else "Third shock converts")
	scenario.submit_action("clear_patient")
	scenario.submit_action("analyze_rhythm")
	check(scenario.state == Scenario.State.RECOVERY and scenario.outcome == "rosc" and scenario.shock_count == 3, "Analysis after the converting shock finds a pulse")
	scenario.free()
	var lucky := Scenario.new()
	lucky.shock_success_chance = 1.0
	enter_cpr(lucky)
	lucky.submit_action("attach_aed")
	_shock_cycle(lucky)
	lucky.submit_action("clear_patient")
	lucky.submit_action("analyze_rhythm")
	check(lucky.outcome == "rosc" and lucky.shock_count == 1, "A successful first shock ends in ROSC at the next analysis")
	lucky.free()

func _test_helper_compressions() -> void:
	## ERC 2025: a second rescuer compresses while the pads go on; that is CPR,
	## but it neither fills nor breaks the trainee's own 30:2 cycle.
	var scenario := Scenario.new()
	enter_cpr(scenario)
	for i in 10:
		scenario.submit_action("compression")
	for i in 40:
		check(scenario.submit_action("compression", {"source": "bystander"}), "Helper compression %d accepted" % i)
	check(scenario.compressions == 50 and scenario.cycle_compressions == 10, "Helper strokes count as CPR, not in the trainee's cycle")
	scenario.free()

func _test_compression_only() -> void:
	var scenario := Scenario.new()
	enter_cpr(scenario)
	check(not scenario.aed_requested and scenario.state == Scenario.State.CPR, "AED request never delays initial CPR")
	check(scenario.submit_action("request_aed"), "AED can be requested while performing CPR")
	check(scenario.submit_action("compression_only"), "Compression-only alternative available")
	for index in range(65):
		check(scenario.submit_action("compression"), "Continuous compression %d" % index)
	check(scenario.compressions == 65 and scenario.ventilations == 0, "Continuous compressions do not invent ventilations")
	check(not scenario.submit_action("ventilation"), "Compression-only mode does not require breaths")
	scenario.free()

func _test_export_and_quality() -> void:
	var scenario := Scenario.new()
	var score := Score.new()
	var logger := SessionLog.new()
	scenario.event_recorded.connect(score.record)
	scenario.event_recorded.connect(logger.record)
	enter_cpr(scenario)
	scenario.submit_action("compression", {"depth_cm": 5.5, "rate_bpm": 110.0, "source": "hand_tracking", "transcript": "private text", "api_key": "DO_NOT_EXPORT"})
	check(score.measured_compressions == 0, "Unverified hand depth never receives a clinical quality score")
	scenario.submit_action("compression", {"depth_cm": 5.5, "rate_bpm": 110.0, "measurement_verified": true, "source": "mannequin_sensor"})
	check(score.measured_compressions == 1 and score.depth_in_range == 1 and score.rate_in_range == 1, "Verified measurements count against requested ranges")
	scenario.submit_action("compression", {"depth_cm": 4.0, "rate_bpm": 130.0, "measurement_verified": true})
	check(score.measured_compressions == 2 and score.depth_in_range == 1 and score.rate_in_range == 1, "Out-of-range measured data not marked successful")
	var summary := scenario.get_summary()
	summary.feedback = score.get_summary()
	var document := logger.build_document(summary)
	var serialized := JSON.stringify(document)
	check(not serialized.contains("DO_NOT_EXPORT") and not serialized.contains("private text"), "Event whitelist drops sensitive free text")
	check(document.events.size() > 5 and document.schema_version == 1, "Versioned structured event log")
	var path := logger.save(summary, "user://test-artifacts/session-test.json")
	check(not path.is_empty() and FileAccess.file_exists(path), "JSON export saved")
	if not path.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(parsed is Dictionary and parsed.summary.compressions == 3, "Export roundtrip retains data")
		DirAccess.remove_absolute(path)
	scenario.start()
	check(logger.events.size() == 1 and score.measured_compressions == 0, "New session clears logger and score")
	scenario.free()
