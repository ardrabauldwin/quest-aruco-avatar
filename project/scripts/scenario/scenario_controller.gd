class_name NaretScenario
extends Node
## Deterministic adult BLS practice sequence following the ERC Guidelines 2025:
## unresponsive -> call 112 at once (speaker), then open the airway and check
## breathing while the call connects -> CPR; the AED as soon as it is there.
## https://www.erc.edu/science-research/guidelines/guidelines-2025/guidelines-2025-english
## Educational simulation only; buttons/hand estimates do not verify clinical care.

signal state_changed(state: int)
signal event_recorded(event: Dictionary)

enum State { IDLE, INTRO, CHECK_PATIENT, CALL_HELP, CPR, AED, RECOVERY }
enum AEDStage { ATTACHED, READY_TO_ANALYZE, SHOCK_ADVISED, READY_TO_SHOCK, NO_SHOCK }
const STATE_NAMES := ["idle", "intro", "check_patient", "call_help", "cpr", "aed", "recovery"]
const AED_REASSESS_SECONDS := 120.0

@export_range(1.0, 20.0, 1.0) var simulation_speed := 1.0
var language := "de"
var cpr_witness_only := false
var observation_driven := false
var state: int = State.IDLE
var elapsed := 0.0
var compressions := 0
var ventilations := 0
var cycles := 0
var shock_count := 0
var cycle_compressions := 0
var cycle_ventilations := 0
var compression_only := false
var responsiveness_checked := false
var breathing_checked := false
var emergency_called := false
var aed_requested := false
var aed_attached := false
## False while the AED is still on its way (NaretBystanderDirector brings it);
## tests and the desktop without a director keep it at hand.
var aed_available := true
var aed_stage: int = AEDStage.ATTACHED
var analysis_due := false
var shock_advised := true # Scripted initial VF; a trainer can configure a nonshockable scenario.
## Chance that one shock ends the VF. Whether it did only shows at the next rhythm
## analysis after two minutes of CPR, as in reality; often a second or third shock
## is needed. ponytail: flat per-shock chance, the third shock always converts so
## a course session ends; a trainer setting can replace it.
var shock_success_chance := 0.5
const MAX_SHOCKS := 3
var rng := RandomNumberGenerator.new()
var rosc_pending := false
var last_error := ""
var errors := 0
var reassessments := 0
var outcome := "ongoing"
var _cpr_after_aed := 0
var _aed_cycle_elapsed := 0.0
var _aed_used := false
var _event_sequence := 0

func _process(delta: float) -> void:
	advance_simulation(delta * simulation_speed)

func advance_simulation(seconds: float) -> void:
	if seconds <= 0.0 or not is_finite(seconds) or state == State.IDLE or state == State.RECOVERY:
		return
	elapsed += seconds
	if state == State.CPR and _aed_used:
		_aed_cycle_elapsed += seconds
		if _aed_cycle_elapsed >= AED_REASSESS_SECONDS:
			analysis_due = true

func start() -> void:
	reset()
	_transition(State.INTRO)
	_record("start", true, {})

func reset() -> void:
	state = State.IDLE
	elapsed = 0.0
	compressions = 0
	ventilations = 0
	cycles = 0
	shock_count = 0
	cycle_compressions = 0
	cycle_ventilations = 0
	compression_only = false
	responsiveness_checked = false
	breathing_checked = false
	emergency_called = false
	aed_requested = false
	aed_attached = false
	aed_stage = AEDStage.ATTACHED
	analysis_due = false
	last_error = ""
	errors = 0
	reassessments = 0
	outcome = "ongoing"
	_cpr_after_aed = 0
	_aed_cycle_elapsed = 0.0
	_aed_used = false
	_event_sequence = 0
	rosc_pending = false
	state_changed.emit(state)

func submit_action(action: String, details: Dictionary = {}) -> bool:
	last_error = ""
	if cpr_witness_only and (action in ["request_aed", "attach_aed", "clear_patient", "analyze_rhythm", "shock", "resume_cpr", "reassess", "simulate_rosc", "patient_contact"] or details.get("source", "") == "bystander"):
		return _reject(action, "error.invalid_action", details)
	if action == "start":
		start()
		return true
	if action == "reset":
		reset()
		return true
	if state == State.IDLE or state == State.RECOVERY:
		return _reject(action, "error.invalid_action", details)
	if action == "reassure":
		return _accept(action, details)
	if action == "request_aed" and state >= State.CALL_HELP and not aed_requested:
		aed_requested = true
		return _accept(action, details)
	if action == "handover" and state >= State.CPR:
		outcome = "simulated_handover"
		_transition(State.RECOVERY)
		return _accept(action, details)
	match state:
		State.INTRO:
			if action == "begin_check":
				_transition(State.CHECK_PATIENT)
				return _accept(action, details)
		State.CHECK_PATIENT:
			if action == "check_responsiveness" and not responsiveness_checked:
				if bool(details.get("responsive", false)):
					return _reject(action, "error.check_result", details)
				responsiveness_checked = true
				# ERC 2025: anyone unresponsive -> 112 straight away.
				_transition(State.CALL_HELP)
				return _accept(action, details)
			if action == "check_breathing":
				return _reject(action, "error.check_responsiveness_first", details)
		State.CALL_HELP:
			if action == "call_emergency" and not emergency_called:
				emergency_called = true
				return _accept(action, details)
			if action == "check_breathing":
				# Breathing is assessed while the call connects, not before it.
				if not emergency_called:
					return _reject(action, "error.call_first", details)
				if bool(details.get("normal_breathing", false)):
					return _reject(action, "error.check_result", details)
				breathing_checked = true
				_transition(State.CPR)
				return _accept(action, details)
		State.CPR:
			return _cpr_action(action, details)
		State.AED:
			return _aed_action(action, details)
	return _reject(action, "error.invalid_action", details)

func _cpr_action(action: String, details: Dictionary) -> bool:
	match action:
		"compression":
			# ERC 2025: a second rescuer keeps compressing while the pads go on. Those
			# strokes are CPR, but not part of the trainee's own 30:2 cycle.
			if str(details.get("source", "")) == "bystander":
				compressions += 1
				if _aed_used:
					_cpr_after_aed += 1
				return _accept(action, details)
			if cycle_compressions >= 30 and not compression_only:
				return _reject(action, "error.ventilate_first", details)
			compressions += 1
			cycle_compressions += 1
			if _aed_used:
				_cpr_after_aed += 1
			if compression_only and cycle_compressions >= 30:
				cycles += 1
				cycle_compressions = 0
			return _accept(action, details)
		"ventilation":
			if compression_only or cycle_compressions < 30:
				return _reject(action, "error.compress_first", details)
			ventilations += 1
			cycle_ventilations += 1
			if cycle_ventilations == 2:
				cycles += 1
				cycle_compressions = 0
				cycle_ventilations = 0
			return _accept(action, details)
		"compression_only":
			if compression_only:
				return _reject(action, "error.invalid_action", details)
			compression_only = true
			cycle_compressions = 0
			cycle_ventilations = 0
			return _accept(action, details)
		"attach_aed":
			if aed_attached:
				return _reject(action, "error.invalid_action", details)
			if not aed_available:
				return _reject(action, "error.aed_missing", details)
			# Use an available AED promptly; never require an arbitrary completed CPR cycle.
			aed_attached = true
			aed_stage = AEDStage.ATTACHED
			_transition(State.AED)
			return _accept(action, details)
		"reassess":
			if not analysis_due:
				return _reject(action, "error.aed_not_due", details)
			reassessments += 1
			aed_stage = AEDStage.ATTACHED
			_transition(State.AED)
			return _accept(action, details)
		"simulate_rosc":
			if not bool(details.get("trainer", false)) or _cpr_after_aed <= 0:
				return _reject(action, "error.trainer_only", details)
			outcome = "trainer_simulated_rosc"
			_transition(State.RECOVERY)
			return _accept(action, details)
	return _reject(action, "error.invalid_action", details)

func _aed_action(action: String, details: Dictionary) -> bool:
	if action in ["compression", "ventilation", "patient_contact"]:
		# Physical contact invalidates both clearance confirmations.
		aed_stage = AEDStage.ATTACHED
		return _reject(action, "error.contact_during_analysis", details)
	match action:
		"clear_patient":
			if bool(details.get("contact", false)):
				aed_stage = AEDStage.ATTACHED
				return _reject(action, "error.aed_safety", details)
			if aed_stage == AEDStage.ATTACHED:
				aed_stage = AEDStage.READY_TO_ANALYZE
				return _accept(action, details)
			if aed_stage == AEDStage.SHOCK_ADVISED:
				aed_stage = AEDStage.READY_TO_SHOCK
				return _accept(action, details)
		"analyze_rhythm":
			if aed_stage != AEDStage.READY_TO_ANALYZE:
				return _reject(action, "error.aed_safety", details)
			if rosc_pending:
				# Organised rhythm with a pulse: no shock, the patient is back.
				aed_stage = AEDStage.NO_SHOCK
				outcome = "rosc"
				_accept(action, details)
				_transition(State.RECOVERY)
				return true
			aed_stage = AEDStage.SHOCK_ADVISED if shock_advised else AEDStage.NO_SHOCK
			return _accept(action, details)
		"shock":
			if aed_stage != AEDStage.READY_TO_SHOCK or not shock_advised:
				return _reject(action, "error.aed_safety", details)
			shock_count += 1
			rosc_pending = shock_count >= MAX_SHOCKS or rng.randf() < shock_success_chance
			_resume_after_aed()
			return _accept(action, details)
		"resume_cpr":
			if aed_stage != AEDStage.NO_SHOCK:
				return _reject(action, "error.invalid_action", details)
			_resume_after_aed()
			return _accept(action, details)
	return _reject(action, "error.invalid_action", details)

func _resume_after_aed() -> void:
	_aed_used = true
	_cpr_after_aed = 0
	_aed_cycle_elapsed = 0.0
	analysis_due = false
	cycle_compressions = 0
	cycle_ventilations = 0
	_transition(State.CPR)

func _transition(next_state: int) -> void:
	state = next_state
	state_changed.emit(state)

func _accept(action: String, details: Dictionary) -> bool:
	_record(action, true, details)
	return true

func _reject(action: String, reason: String, details: Dictionary) -> bool:
	last_error = reason
	errors += 1
	_record(action, false, details)
	return false

func _record(action: String, accepted: bool, details: Dictionary) -> void:
	_event_sequence += 1
	# Whitelist structural measurements. Never store arbitrary transcripts, names or API configuration.
	var measurements: Dictionary = {}
	for key: String in ["depth_cm", "rate_bpm", "recoil", "correct_position", "measurement_verified", "source", "trainer", "check_duration_s", "inference_probability"]:
		if details.has(key) and (details[key] is float or details[key] is int or details[key] is bool):
			measurements[key] = details[key]
	if details.get("source", "") in ["desktop", "controller", "hand_tracking", "mannequin_sensor", "speech", "test", "bystander"]:
		measurements["source"] = details["source"]
	if details.get("inference_engine", "") == "ccbm":
		measurements["inference_engine"] = "ccbm"
	if details.get("evidence_kind", "") == "spoken_report":
		measurements["evidence_kind"] = "spoken_report"
	event_recorded.emit({"sequence": _event_sequence, "elapsed_s": snappedf(elapsed, 0.001), "action": action, "accepted": accepted, "state": get_state_name(), "reason": last_error, "details": measurements})

func get_state_name() -> String:
	return STATE_NAMES[state]

func get_instruction_key() -> String:
	if state == State.CALL_HELP and emergency_called:
		return "instruction.check_breathing"
	if state == State.CPR:
		if analysis_due:
			return "instruction.reassessment"
		if cycle_compressions >= 30 and not compression_only:
			return "instruction.ventilate"
	if state == State.AED:
		return ["instruction.aed_clear", "instruction.aed_analyze", "instruction.aed_shock", "instruction.aed_shock_ready", "instruction.aed_resume"][aed_stage]
	if state == State.RECOVERY and outcome == "simulated_handover":
		return "instruction.handover"
	return "instruction." + get_state_name()

func get_available_actions() -> Array[String]:
	var actions: Array[String] = []
	match state:
		State.IDLE:
			actions.append("start")
		State.INTRO:
			actions.append("begin_check")
		State.CHECK_PATIENT:
			actions.append("check_responsiveness")
		State.CALL_HELP:
			actions.append("check_breathing" if emergency_called else "call_emergency")
		State.CPR:
			actions.append("ventilation" if cycle_compressions >= 30 and not compression_only else "compression")
			if not compression_only:
				actions.append("compression_only")
			if not aed_attached and aed_available:
				actions.append("attach_aed")
			if analysis_due:
				actions.append("reassess")
			if _cpr_after_aed > 0:
				actions.append("simulate_rosc")
			actions.append("handover")
		State.AED:
			actions.append(["clear_patient", "analyze_rhythm", "clear_patient", "shock", "resume_cpr"][aed_stage])
		State.RECOVERY:
			actions.append("reset")
	if state >= State.CALL_HELP and state < State.RECOVERY and not aed_requested:
		actions.append("request_aed")
	if state > State.IDLE and state < State.RECOVERY:
		actions.append("reassure")
	if cpr_witness_only:
		for excluded in ["request_aed", "attach_aed", "clear_patient", "analyze_rhythm", "shock", "resume_cpr", "reassess", "simulate_rosc"]:
			actions.erase(excluded)
	return actions

func get_interface_actions() -> Array[String]:
	var actions := get_available_actions()
	if observation_driven:
		# Setup/reset controls remain; routine progression comes from observations.
		for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing", "compression", "ventilation", "compression_only", "handover"]:
			actions.erase(action)
	return actions

func get_summary() -> Dictionary:
	return {
		"scenario": "cpr_single_witness_practice" if cpr_witness_only else "adult_bls_erc2025", "language": language, "state": get_state_name(),
		"elapsed_s": snappedf(elapsed, 0.01), "simulation_speed": simulation_speed,
		"compressions": compressions, "ventilations": ventilations, "cycles": cycles,
		"compression_only": compression_only, "shocks": shock_count, "reassessments": reassessments,
		"emergency_called": emergency_called, "aed_requested": aed_requested,
		"responsiveness_checked": responsiveness_checked, "breathing_checked": breathing_checked,
		"errors": errors, "outcome": outcome,
		"simulation_only": true, "clinically_validated": false,
		"guideline_url": "https://www.erc.edu/science-research/guidelines/guidelines-2025/guidelines-2025-english",
	}
