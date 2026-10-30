extends Node
## Real CCBM runs in an external worker. No local imitation of its posterior.
## Only structural observation codes leave this node; no audio/transcripts.
## Speech describes reported findings; hand detection supplies compression events.
## CCBM tracks exercise progression, not the physical correctness of a spoken claim.
signal decision(action: String, details: Dictionary)
signal status_changed(status: String)
const Speech = preload("res://scripts/scenario/spoken_observation.gd")
const ACTIONS := ["begin_check", "check_responsiveness", "call_emergency", "check_breathing", "compression", "ventilation", "compression_only", "handover"]
var endpoint := ""
var threshold := 0.90 # Prototype acceptance policy, not a measured optimum.
var _scenario: NaretScenario
var _http: HTTPRequest
var _pending := false
var _generation := 0
var _history: Array[String] = []
var _compression_observed := false
var _mode_observed := false

func configure(scenario: NaretScenario) -> void:
	_scenario = scenario

func _ready() -> void:
	var settings := ConfigFile.new()
	if settings.load("user://ccbm.cfg") == OK:
		endpoint = str(settings.get_value("ccbm", "endpoint", ""))
	if OS.has_environment("NARET_CCBM_URL"):
		endpoint = OS.get_environment("NARET_CCBM_URL")
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)

func reset() -> void:
	_generation += 1
	if _pending and is_instance_valid(_http):
		_http.cancel_request()
		_http.request_completed.emit(HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray())
	_pending = false
	_history.clear()
	_compression_observed = false
	_mode_observed = false
	# An in-flight old result is discarded using _generation.

func observe_speech(text: String) -> bool:
	var action := Speech.action_for(text)
	if action.is_empty(): return false
	return observe_action(action)

func observe_action(action: String) -> bool:
	if action not in ACTIONS and action != "start": return false
	# Saying "I am compressing" must never create a counted physical stroke.
	# Detected strokes reach observe_accepted() through the scenario event signal.
	if action == "compression":
		status_changed.emit("ccbm_compression_requires_tracking")
		return true
	if action == "start":
		if _scenario.state == NaretScenario.State.IDLE:
			decision.emit("start", {"source": "speech", "measurement_verified": false})
		return true
	if _scenario.state == NaretScenario.State.IDLE and action == "begin_check":
		# Headset review 2026-10-29: the first spoken report ("the scene is safe") came
		# before anyone said "start exercise" and was refused as out of order every time.
		# A safety report is a clear intent to begin: start, then judge it as usual.
		decision.emit("start", {"source": "speech", "measurement_verified": false})
	if action not in _scenario.get_available_actions():
		status_changed.emit("ccbm_out_of_order")
		return true
	_request(action)
	return true

func observe_accepted(event: Dictionary) -> void:
	if not event.get("accepted", false): return
	var action := str(event.get("action", ""))
	# Keep the model in sync with fallback/trainer actions too.
	if action in ["start", "reset"]:
		reset()
	elif action == "compression":
		# Count every stroke locally; CCBM models the onset, not 100 network calls/min.
		if not _compression_observed:
			_history.append("compression")
			_compression_observed = true
	elif action == "compression_only":
		if not _mode_observed:
			_history.append(action)
			_mode_observed = true
	elif action in ACTIONS:
		_history.append(action)

func observe_breath_pair() -> bool:
	# Each reported breath still requires its own CCBM decision and scenario guard.
	# A completed-pair report after a first individual report credits only the
	# remaining breath. Repeating the report after the cycle resets is rejected.
	if _pending or "ventilation" not in _scenario.get_available_actions():
		status_changed.emit("ccbm_out_of_order")
		return false
	_request_breath_pair()
	return true

func _request_breath_pair() -> void:
	var generation := _generation
	if _scenario.cycle_ventilations == 1:
		await _request("ventilation")
		return
	await _request("ventilation")
	if generation != _generation or _scenario.cycle_ventilations != 1:
		return # Failed first decision or session changed: do not fabricate a second.
	if "ventilation" in _scenario.get_available_actions():
		await _request("ventilation")

func _request(action: String) -> void:
	if _pending:
		status_changed.emit("ccbm_busy_repeat")
		return
	if not (endpoint.begins_with("https://") or endpoint.begins_with("http://127.0.0.1:")):
		status_changed.emit("ccbm_unavailable")
		return
	if _history.size() >= 256:
		status_changed.emit("ccbm_session_limit")
		return
	_pending = true
	var generation := _generation
	var sequence: Array[String] = _history.duplicate()
	sequence.append(action)
	var body := JSON.stringify({"observations": sequence})
	var err := _http.request(endpoint, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		_pending = false
		status_changed.emit("ccbm_unavailable")
		return
	var response: Array = await _http.request_completed
	_pending = false
	if generation != _generation: return
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		status_changed.emit("ccbm_unavailable")
		return
	var parsed: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if not accepts(parsed, action, threshold) or action not in _scenario.get_available_actions():
		status_changed.emit("ccbm_uncertain_repeat")
		return
	decision.emit(action, {"source": "speech", "measurement_verified": false,
		"evidence_kind": "spoken_report", "inference_engine": "ccbm",
		"inference_probability": float(parsed.probability)})
	status_changed.emit("ccbm_accepted")

static func accepts(value: Variant, action: String, minimum: float) -> bool:
	if not value is Dictionary: return false
	if value.get("engine", "") != "ccbm" or value.get("action", "") != action: return false
	var probability: Variant = value.get("probability")
	if not (probability is float or probability is int): return false
	return is_finite(float(probability)) and float(probability) >= minimum and float(probability) <= 1.0
