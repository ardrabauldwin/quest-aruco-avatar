extends RefCounted
## Structural observation codes shared by speech decisions and device tracking.
const ACTIONS := ["begin_check", "check_responsiveness", "call_emergency", "check_breathing", "compression", "compression_only", "ventilation", "handover", "request_aed", "attach_aed", "clear_patient", "analyze_rhythm", "shock_advised", "no_shock_advised", "shock", "resume_cpr", "reassess", "patient_contact", "recovery"]
const SPOKEN := ["begin_check", "check_responsiveness", "call_emergency", "check_breathing", "ventilation", "compression_only", "handover", "request_aed", "clear_patient"]
static func canonical(action: String) -> String:
	if action in ["ventilation_first", "ventilation_second"]: return "ventilation"
	if action in ["clear_for_analysis", "clear_for_shock"]: return "clear_patient"
	return action
