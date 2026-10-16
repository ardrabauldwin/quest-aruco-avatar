extends RefCounted
## Only explicit pending proposals can be confirmed. No fuzzy clinical acceptance.
const Speech = preload("res://scripts/scenario/spoken_observation.gd")
const LIFETIME_MS := 30000
var _action := ""
var _context := ""
var _deadline := 0

func clear() -> void:
	_action = ""
	_context = ""
	_deadline = 0

func evaluate(text: String, context: String, allowed: Array, now: int) -> Dictionary:
	if context != _context or now > _deadline:
		clear()
	var clean := Speech.normalise(text)
	for punctuation in [".", "!", ","]:
		clean = clean.replace(punctuation, "")
	if clean in ["yes", "yes that is correct", "correct"]:
		var confirmed := _action
		clear()
		if confirmed in allowed:
			return {"action": confirmed}
		return {"message": "No pending report to confirm. Please state the completed check and finding."}
	if clean in ["no", "no that is wrong", "cancel"]:
		clear()
		return {"message": "Report cancelled. Please state the completed check and finding."}
	# A new utterance replaces any proposal; it cannot silently confirm an old one.
	clear()
	var direct := Speech.action_for(text)
	if not direct.is_empty():
		return {"action": direct}
	# Bounded proposals, including the observed scene transcription error. Never
	# turn unrelated 'vaccine is safe', positive findings or compound claims into actions.
	var candidates := {
		"we have given the first bread": "ventilation",
		"i have given the first bread": "ventilation",
		"we have given the second bread": "ventilation",
		"i have given the second bread": "ventilation",
		"scene a save": "begin_check",
		"tassini's safe": "begin_check",
		"i think the scene is safe": "begin_check",
		"i think he is not responding": "check_responsiveness",
		"i think he is not breathing normally": "check_breathing"
	}
	var candidate := str(candidates.get(clean, ""))
	if candidate.is_empty() or candidate not in allowed:
		return {}
	_action = candidate
	_context = context
	_deadline = now + LIFETIME_MS
	return {"proposal": candidate}
