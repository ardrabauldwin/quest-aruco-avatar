extends Node
## Real CCBM: packaged native filter on Quest; external worker on desktop.
## Only structural observation codes leave this node; no audio/transcripts.
## Speech describes reported findings; hand detection supplies compression events.
## CCBM tracks exercise progression, not the physical correctness of a spoken claim.
signal decision(action: String, details: Dictionary)
signal status_changed(status: String)
signal tracking_updated(posterior: Dictionary)
const Speech = preload("res://scripts/scenario/spoken_observation.gd")
const Protocol = preload("res://scripts/scenario/ccbm_protocol.gd")
const ACTIONS := Protocol.ACTIONS
var endpoint := ""
var threshold := 0.90 # Prototype acceptance policy, not a measured optimum.
var _scenario: NaretScenario
var _http: HTTPRequest
var _pending := false
var _generation := 0
var _history: Array[String] = []
var _compression_observed := false
var _mode_observed := false
var _native: RefCounted
var _history_revision := 0
var _safety_changed := false
var _tracking_dirty := false
var _tracking_active := false
var last_tracking: Dictionary = {}

func configure(scenario: NaretScenario) -> void:
	if is_instance_valid(_scenario) and _scenario.state_changed.is_connected(_on_scenario_state_changed):
		_scenario.state_changed.disconnect(_on_scenario_state_changed)
	_scenario = scenario
	if not _scenario.state_changed.is_connected(_on_scenario_state_changed):
		_scenario.state_changed.connect(_on_scenario_state_changed)

func _on_scenario_state_changed(state: int) -> void:
	if state == NaretScenario.State.IDLE: reset()

func _ready() -> void:
	if OS.has_feature("android"):
		_native = preload("res://scripts/scenario/ccbm_native.gd").new()
		var native_ready: bool = _native.configure_android()
		print("NARET_CCBM_NATIVE ready=", native_ready)
		if not native_ready:
			status_changed.emit("ccbm_unavailable")
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
	_history_revision += 1
	_safety_changed = false
	_tracking_dirty = false
	_tracking_active = false
	last_tracking.clear()
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
	if action not in Protocol.SPOKEN and action != "start":
		status_changed.emit("ccbm_compression_requires_tracking")
		return true
	if action == "start":
		if _scenario.state == NaretScenario.State.IDLE:
			decision.emit("start", {"source": "speech", "measurement_verified": false})
		return true
	if _scenario.state == NaretScenario.State.IDLE and action == "begin_check":
		# A safety report while idle starts the exercise (2026-10-29) but is not accepted
		# as the first step (2026-11-03): the trainee must first hear the instructor's
		# "check whether the scene is safe" and then report it, as in the real sequence.
		decision.emit("start", {"source": "speech", "measurement_verified": false})
		return true
	if action not in _scenario.get_available_actions():
		status_changed.emit("ccbm_out_of_order")
		return true
	_request(action)
	return true

func _append_observation(action: String) -> void:
	_history.append(action)
	_history_revision += 1

func observe_accepted(event: Dictionary) -> void:
	var action := str(event.get("action", ""))
	if not event.get("accepted", false):
		# The scenario rejects contact as an exercise action while actually revoking clearance.
		# Keep that real sensor event, once, rather than preserving stale clearance in CCBM.
		if action == "patient_contact" and event.get("reason") == "error.contact_during_analysis":
			if _safety_changed:
				_append_observation("patient_contact")
				_safety_changed = false
				_tracking_dirty = true
				_schedule_tracking()
			elif _pending:
				# A contact sample during an in-flight clearance invalidates that
				# decision too, even if the model was already in its uncleared state.
				_history_revision += 1
		return
	if action in ["start", "reset"]:
		reset()
		return
	if action == "compression":
		if _compression_observed: return # One onset, not a native process for every stroke.
		_append_observation("compression")
		_compression_observed = true
	elif action == "compression_only":
		if not _mode_observed:
			_append_observation(action)
			_mode_observed = true
	elif action in ACTIONS:
		_append_observation(action)
	else:
		return
	if action in ["attach_aed", "reassess", "shock", "resume_cpr"]:
		_compression_observed = false
		_safety_changed = false
	if action == "clear_patient": _safety_changed = true
	if action == "analyze_rhythm":
		# Result is read from the accepted simulator event, never from TTS or an LLM claim.
		_append_observation("shock_advised" if _scenario.aed_stage == NaretScenario.AEDStage.SHOCK_ADVISED else "no_shock_advised")
		if _scenario.outcome == "rosc": _append_observation("recovery")
	if action in ["request_aed", "attach_aed", "clear_patient", "analyze_rhythm", "shock", "resume_cpr", "reassess"] or (_scenario._aed_used and action == "compression"):
		_tracking_dirty = true
		_schedule_tracking()

func _schedule_tracking() -> void:
	if _tracking_dirty and not _tracking_active and not _pending and _native != null:
		_refresh_tracking.call_deferred()

func _refresh_tracking() -> void:
	if not _tracking_dirty or _tracking_active or _pending or _native == null: return
	_tracking_active = true
	_tracking_dirty = false
	var generation := _generation
	var revision := _history_revision
	var sequence: Array[String] = _history.duplicate()
	var result: Variant = await _native.infer(sequence)
	if generation != _generation: return
	_tracking_active = false
	if revision == _history_revision and result is Dictionary and result.get("engine") == "ccbm":
		last_tracking = result.duplicate()
		last_tracking["observation_count"] = sequence.size()
		tracking_updated.emit(last_tracking)
	elif revision == _history_revision:
		status_changed.emit("ccbm_tracking_unavailable")
	_schedule_tracking()

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
	if _native == null and (OS.has_feature("android") or not (endpoint.begins_with("https://") or endpoint.begins_with("http://127.0.0.1:"))):
		status_changed.emit("ccbm_unavailable")
		return
	if _history.size() >= 256:
		status_changed.emit("ccbm_session_limit")
		return
	_pending = true
	var generation := _generation
	var revision := _history_revision
	var sequence: Array[String] = _history.duplicate()
	sequence.append(action)
	var parsed: Variant
	if _native != null:
		parsed = await _native.infer(sequence)
		if generation != _generation: return
		_pending = false
		_schedule_tracking()
		if not parsed is Dictionary or parsed.has("error") or parsed.is_empty():
			status_changed.emit("ccbm_unavailable")
			return
	else:
		parsed = await _request_external(sequence, generation)
		if generation != _generation or parsed == null: return
	_schedule_tracking()
	if revision != _history_revision:
		status_changed.emit("ccbm_uncertain_repeat")
		return
	if not accepts(parsed, action, threshold) or action not in _scenario.get_available_actions():
		status_changed.emit("ccbm_uncertain_repeat")
		return
	decision.emit(action, {"source": "speech", "measurement_verified": false,
		"evidence_kind": "spoken_report", "inference_engine": "ccbm",
		"inference_probability": float(parsed.probability)})
	status_changed.emit("ccbm_accepted")

func _request_external(sequence: Array[String], generation: int) -> Variant:
	var body := JSON.stringify({"observations": sequence})
	var err := _http.request(endpoint, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		_pending = false
		status_changed.emit("ccbm_unavailable")
		return null
	var response: Array = await _http.request_completed
	if generation != _generation: return null
	_pending = false
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		status_changed.emit("ccbm_unavailable")
		return null
	return JSON.parse_string(response[3].get_string_from_utf8())

static func accepts(value: Variant, action: String, minimum: float) -> bool:
	if not value is Dictionary: return false
	if value.get("engine", "") != "ccbm" or value.get("action", "") != action: return false
	var probability: Variant = value.get("probability")
	if not (probability is float or probability is int): return false
	return is_finite(float(probability)) and float(probability) >= minimum and float(probability) <= 1.0
