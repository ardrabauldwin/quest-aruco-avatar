class_name NaretScoreTracker
extends RefCounted
## Descriptive practice feedback; it is not a clinical skills certification.

var accepted_actions := 0
var rejected_actions := 0
var milestones: Dictionary = {}
var errors: Array[Dictionary] = []
var measured_compressions := 0
var depth_in_range := 0
var rate_in_range := 0
var measured_rates := 0

func reset() -> void:
	accepted_actions = 0
	rejected_actions = 0
	milestones.clear()
	errors.clear()
	measured_compressions = 0
	depth_in_range = 0
	rate_in_range = 0
	measured_rates = 0

func record(event: Dictionary) -> void:
	if event.get("action", "") == "start":
		reset()
	if not bool(event.get("accepted", false)):
		rejected_actions += 1
		errors.append({"action": event.get("action", ""), "reason": event.get("reason", ""), "elapsed_s": event.get("elapsed_s", 0.0)})
		return
	accepted_actions += 1
	var action := str(event.get("action", ""))
	if action in ["check_responsiveness", "check_breathing", "call_emergency", "request_aed", "attach_aed", "clear_patient", "analyze_rhythm", "shock", "resume_cpr", "reassess", "reassure"]:
		if not milestones.has(action):
			milestones[action] = event.get("elapsed_s", 0.0)
	var details: Dictionary = event.get("details", {})
	if action != "compression" or not bool(details.get("measurement_verified", false)):
		return
	if details.has("depth_cm"):
		var depth := float(details.depth_cm)
		if is_finite(depth) and depth >= 0.0:
			measured_compressions += 1
			if depth >= 5.0 and depth <= 6.0:
				depth_in_range += 1
	if details.has("rate_bpm"):
		var rate := float(details.rate_bpm)
		if is_finite(rate) and rate > 0.0:
			measured_rates += 1
			if rate >= 100.0 and rate <= 120.0:
				rate_in_range += 1

func get_summary() -> Dictionary:
	return {
		"accepted_actions": accepted_actions, "rejected_actions": rejected_actions,
		"milestones_s": milestones.duplicate(true), "review": errors.duplicate(true),
		"verified_depth_samples": measured_compressions, "depth_in_range": depth_in_range,
		"verified_rate_samples": measured_rates, "rate_in_range": rate_in_range,
		"notice_key": "score.notice", "clinically_validated": false,
	}
