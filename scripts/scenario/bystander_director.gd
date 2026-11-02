class_name NaretBystanderDirector
extends Node
## Plays Anna and Marek through scenario 1 of docs/DREHBUCH.md. It watches the
## scenario's events and the live CPR measurements and decides who says and does
## what; the scenario controller still owns every clinical rule. Scene numbers in
## the comments (1.1 …) are the rows of the Drehbuch table.

signal line_spoken(key: String, speaker: String)

const LINES_PATH := "res://data/bystander_lines.json"
## Real public AEDs are about a minute away; the training shortens the errand.
const FETCH_S := 45.0
const URGE_AFTER_S := 8.0
## From the 112 call (ERC 2025: breathing is checked while the call connects).
const BREATH_CHECK_S := 12.0
## Jan gasps once during the breathing check; Anna takes it for breathing.
const AGONAL_AFTER_S := 3.5
const PAUSE_S := 10.0
const PROMPT_CALL_S := 15.0
const PROMPT_AED_S := 20.0
const INTRUDE_S := 4.0
const RESUME_AFTER_SHOCK_S := 5.0
const GOOD_STREAK := 15
## 1.18 The ambulance arrives this long after the circulation came back.
const EMS_AFTER_S := 8.0
## Strokes after a pause whose rate does not count: the rate averages the last
## five intervals, which still hold the hands getting onto the chest.
const WARMUP_STROKES := 5

var scenario: NaretScenario
var anna: NaretBystander
var marek: NaretBystander
var patient: Node3D
var aed: NaretAED
## (key, text, language, speaker) -> void; main routes it to the audio manager.
var speak: Callable
## () -> String: the language the bystanders speak in the current mode.
var language: Callable = func(): return "de"
## () -> void: one compression by Marek (main animates the chest and counts it).
var compress: Callable
## () -> Vector3: where the trainee's head is.
var trainee: Callable = func(): return Vector3.ZERO

var _lines: Dictionary = {}
var _t := 0.0
var _said: Dictionary = {}
var _timers: Array = []
var _state_t := 0.0
var _breath_check_t := -1.0
var _called_t := -1.0
var _cpr_started_t := -1.0
var _last_activity_t := -1.0
var _shock_t := -1.0
var _wrong_strokes := 0
## Strokes after a pause that do not count for the rate: the first interval
## still contains the time the hands took to get onto the chest.
var _warmup := 0
var _good := 0
var _slow := 0
var _fast := 0
var _fetch_left := -1.0
var _intrude_left := -1.0
var _intruded := false
var _homes: Dictionary = {}
## Marek keeps compressing while the trainee applies the pads (ERC 2025).
var marek_compressing := false
var _stroke_phase := 0.0
var _take_over_t := -INF
## Lines that wait until the AED has finished speaking (people let the device talk).
var _after_quiet: Array[Callable] = []
var _quiet_since := -1.0
const HELPER_RATE := 110.0
## From the sternum to where the kneeling helper's pelvis is (cpr clip).
const HELPER_REACH := 0.40  # hands 0.40 m in front of the hips (data/motion/cpr_keyposes.py)
const KNEEL_S := 1.9

func configure(p_scenario: NaretScenario, p_anna: NaretBystander, p_marek: NaretBystander, p_patient: Node3D, p_aed: NaretAED) -> void:
	scenario = p_scenario
	anna = p_anna
	marek = p_marek
	patient = p_patient
	aed = p_aed
	for bystander in [anna, marek]:
		if bystander:
			bystander.patient = patient
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LINES_PATH))
	_lines = parsed if parsed is Dictionary else {}
	scenario.state_changed.connect(_on_state_changed)
	scenario.event_recorded.connect(_on_event)

func line_text(key: String, lang: String) -> String:
	return str(_lines.get(key, {}).get(lang, ""))

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	## Deterministic clock, so tests can fast-forward the scene.
	_t += delta
	for timer in _timers.duplicate():
		if _t >= timer[0]:
			_timers.erase(timer)
			timer[1].call()
	if scenario == null:
		return
	var state := scenario.state
	# 1.1 Nobody moves: Anna pleads. Switched off on headset review 2026-10-29: the
	# "Please, do something!" line interrupted trainees who were already acting.
	if false and state == NaretScenario.State.INTRO and _t - _state_t > URGE_AFTER_S:
		_say_once("anna_urge")
	# 1.5 Nobody has been sent to call 112 yet: Marek offers.
	if state == NaretScenario.State.CALL_HELP and not scenario.emergency_called and _t - _state_t > PROMPT_CALL_S:
		_say_once("marek_prompt_call")
	# 1.4 Breathing check dragging on.
	if _breath_check_t >= 0.0 and not scenario.breathing_checked and _t - _breath_check_t > BREATH_CHECK_S:
		_say_once("anna_breathing")
	if state == NaretScenario.State.CPR:
		_direct_cpr()
	if _fetch_left > 0.0:
		_fetch_left -= delta
		if _fetch_left <= 0.0:
			_bring_aed()
	# 1.16 Two minutes are up: Marek offers to swap before the AED interrupts (ERC:
	# change compressor every 2 min, during the analysis).
	if scenario.analysis_due and scenario.state == NaretScenario.State.CPR:
		_say("marek_swap", 60.0)
	if not _after_quiet.is_empty():
		var quiet := aed == null or not aed.is_speaking()
		_quiet_since = (_quiet_since if _quiet_since >= 0.0 else _t) if quiet else -1.0
		if quiet and _t - _quiet_since > 0.4:
			var waiting := _after_quiet.duplicate()
			_after_quiet.clear()
			for action: Callable in waiting:
				action.call()
	if marek_compressing:
		if scenario.aed_attached or scenario.state != NaretScenario.State.CPR:
			_marek_stop()
		else:
			_stroke_phase += delta * HELPER_RATE / 60.0
			if _stroke_phase >= 1.0:
				_stroke_phase -= 1.0
				if compress.is_valid():
					compress.call()
	# 1.13 Anna is about to touch Jan during the analysis.
	if _intrude_left > 0.0:
		_intrude_left -= delta
		if _intrude_left <= 0.0:
			_touch_patient()

func _direct_cpr() -> void:
	var since_start := _t - _cpr_started_t if _cpr_started_t >= 0.0 else 0.0
	# 1.6 Nobody has been sent for the AED: Marek offers.
	if scenario.emergency_called and not scenario.aed_requested and _called_t >= 0.0 and _t - _called_t > PROMPT_AED_S:
		_say_once("marek_prompt_aed")
	# 1.11 Hands off the chest for too long; applying the AED is not a pause.
	var applying_aed := aed != null and aed.powered and not scenario.aed_attached
	if _last_activity_t >= 0.0 and _t - _last_activity_t > PAUSE_S and not applying_aed:
		_say("anna_pause", 15.0)
	# 1.15 Nobody resumes after the shock.
	if _shock_t >= 0.0 and _last_activity_t <= _shock_t and _t - _shock_t > RESUME_AFTER_SHOCK_S:
		_shock_t = -1.0
		_say("marek_resume", 0.0)

func _on_state_changed(state: int) -> void:
	_state_t = _t
	match state:
		NaretScenario.State.IDLE:
			_reset()
		NaretScenario.State.INTRO:
			_reset()
			_remember_homes()
			scenario.aed_available = false
			_say("anna_arrive", 0.0)
		NaretScenario.State.CPR:
			# Every return to CPR (after an analysis too) restarts the pause clock.
			_last_activity_t = _t
			if _cpr_started_t < 0.0:
				_cpr_started_t = _t
		NaretScenario.State.RECOVERY:
			if scenario.outcome in ["trainer_simulated_rosc", "rosc"]:
				_when_aed_quiet(func(): _say("anna_relief", 0.0))
				_after(EMS_AFTER_S, func(): _say("marek_ems", 0.0))
				if marek:
					marek.set_emotion("relief")
			if anna:
				anna.attention = "trainee"

func _on_event(event: Dictionary) -> void:
	if not event.get("accepted", false):
		return
	var action: String = event.get("action", "")
	var details: Dictionary = event.get("details", {})
	match action:
		"check_responsiveness":
			_say("anna_name", 0.0)
			# 1.3 Marek steps in once it is clear nobody responds.
			_after(2.5, func():
				_say("marek_offer", 0.0)
				if marek:
					marek.walk_to(_near_trainee(_home("marek")))
					marek.attention = "trainee")
		"check_breathing":
			_breath_check_t = -1.0
		"call_emergency":
			_called_t = _t
			_breath_check_t = _t
			# ERC 2025: agonal gasping is not normal breathing, whatever Anna hopes.
			_after(AGONAL_AFTER_S, func():
				if scenario.state == NaretScenario.State.CALL_HELP:
					if patient and patient.has_method("ventilate"):
						patient.call("ventilate")
					_say("anna_agonal", 0.0))
			_say("marek_call", 0.0)
			if marek and not marek.is_walking():
				marek.show_phone()
			_after(5.0, func(): _say("marek_dispatch", 0.0))

		"request_aed":
			_say("marek_go_aed", 0.0)
			_send_for_aed()
		"compression":
			if details.get("source", "") == "bystander":
				_last_activity_t = _t
				return
			# The trainee is back on the chest: Marek lets go (not for the last
			# strokes of the handover itself).
			if marek_compressing and _t - _take_over_t > 2.0:
				_marek_stop()
			_on_compression(float(details.get("rate_bpm", 0.0)))
		"ventilation":
			_last_activity_t = _t
		"analyze_rhythm":
			if _intrude_left > 0.0:
				_touch_patient()
		"shock":
			_shock_t = _t
			_say("anna_shock", 0.0)
		"handover":
			_say("marek_ems", 0.0)
		"clear_patient":
			# 1.13 The trainee cleared everyone; now Anna, frightened, steps in anyway.
			if scenario.aed_stage == NaretScenario.AEDStage.READY_TO_ANALYZE and not _intruded:
				_start_intrusion()

func _on_compression(rate: float) -> void:
	if _t - _last_activity_t > 2.0:
		_warmup = WARMUP_STROKES
	_last_activity_t = _t
	if _warmup > 0:
		_warmup -= 1
		return
	if rate <= 0.0 or rate > 400.0:
		return
	# A little tolerance round 100–120/min: tracked hands measure the rate with a
	# few per minute of noise, and one noisy stroke must not trigger a correction.
	_good = _good + 1 if rate >= 98.0 and rate <= 122.0 else 0
	_slow = _slow + 1 if rate < 98.0 else 0
	_fast = _fast + 1 if rate > 124.0 else 0
	if _good >= GOOD_STREAK:
		_say("anna_good", 90.0)
	# The dispatcher speaks through Marek's phone: only while he is here with it.
	if scenario.emergency_called and _marek_on_phone():
		if _slow >= 4:
			_say("marek_faster", 20.0)
		if _fast >= 4:
			_say("marek_slower", 20.0)

func on_stroke(correct_position: bool) -> void:
	## 1.10 Every measured stroke, also off target (those never reach the scenario):
	## three in a row off the centre of the chest and the dispatcher corrects via
	## Marek. Hands lifted for breaths or the AED are no strokes and never count.
	_wrong_strokes = 0 if correct_position else _wrong_strokes + 1
	if _wrong_strokes >= 3 and scenario and scenario.emergency_called and _marek_on_phone():
		_say("marek_position", 20.0)

func _marek_on_phone() -> bool:
	return marek == null or (marek.visible and _fetch_left <= 0.0 and not (aed and aed._held))

func on_intent(intent: String) -> void:
	## Spoken "Abstand! Nicht berühren!" while Anna reaches for Jan (1.14).
	if intent == "keep_clear" and _intrude_left > 0.0:
		_intrude_left = -1.0
		_say("anna_sorry", 0.0)
		_anna_back()

func _start_intrusion() -> void:
	_intruded = true
	_intrude_left = INTRUDE_S
	_say("anna_touch", 0.0)
	if anna and patient:
		# She comes from across the patient, never through the kneeling trainee.
		var side: Vector3 = patient.global_position - trainee.call()
		side.y = 0.0
		if side.length_squared() < 0.01:
			side = anna.global_position - patient.global_position
			side.y = 0.0
		anna.walk_to(patient.global_position + side.normalized() * 0.6)
		anna.attention = "patient"
		anna.arrived.connect(func(): anna.set_posture("reach"), CONNECT_ONE_SHOT)

func _touch_patient() -> void:
	## Contact during the analysis: the scenario voids the clearance (error).
	_intrude_left = -1.0
	scenario.submit_action("patient_contact", {"source": "bystander"})
	_after(1.5, func():
		_say("anna_sorry", 0.0)
		_anna_back())

func _anna_back() -> void:
	if anna:
		anna.set_posture("")
		anna.attention = "auto"
		anna.walk_to(_home("anna").origin)

func _send_for_aed() -> void:
	## 1.6 Marek leaves to fetch the device and comes back with it.
	_fetch_left = FETCH_S
	if marek == null:
		return
	marek.set_posture("")
	marek.walk_to(_exit_point())
	marek.arrived.connect(_hide_marek, CONNECT_ONE_SHOT)

func _hide_marek() -> void:
	marek.visible = false

func _bring_aed() -> void:
	_fetch_left = -1.0
	if marek == null or aed == null:
		scenario.aed_available = true
		return
	# He may still be on his way out when the errand is over; he must not vanish
	# on arriving back instead.
	if marek.arrived.is_connected(_hide_marek):
		marek.arrived.disconnect(_hide_marek)
	marek.visible = true
	marek.global_position = _exit_point()
	aed.pick_up(marek)
	var drop := _aed_drop_point()
	marek.walk_to(drop)
	marek.arrived.connect(func():
		aed.put_down()
		scenario.aed_available = true
		_say("marek_back_aed", 0.0)
		if scenario.state == NaretScenario.State.CPR and not scenario.aed_attached:
			_marek_take_over()
		else:
			marek.walk_to(_near_trainee(_home("marek"))), CONNECT_ONE_SHOT)

func _marek_take_over() -> void:
	## ERC 2025 with two rescuers: one compresses while the other applies the pads.
	## Marek kneels across from the trainee, level with the sternum.
	marek.walk_to(_helper_spot())
	marek.attention = "patient"
	# Deferred: this may run inside an `arrived` emission, which would call a
	# handler connected now straight away, at the wrong spot.
	_on_marek_arrival.call_deferred(func():
		if scenario.aed_attached or scenario.state != NaretScenario.State.CPR:
			return
		# Square to the sternum, so his hands (clip: 0.40 m ahead) land on it.
		var marker: Variant = patient.get("sternum")
		var sternum: Vector3 = (marker as Node3D).global_position if marker is Node3D else patient.global_position
		var to_patient := sternum - marek.global_position
		to_patient.y = 0.0
		# Characters model +Z forward; looking_at aims -Z.
		marek.global_basis = Basis.looking_at(-to_patient.normalized(), Vector3.UP)
		# Kneel down (one-off clip), then compress; he says so on the way down.
		marek.set_posture("kneel")
		_say("marek_take_over", 0.0)
		_after(KNEEL_S, func():
			if scenario.aed_attached or scenario.state != NaretScenario.State.CPR:
				return
			marek.set_posture("cpr")
			_stroke_phase = 0.0
			_take_over_t = _t
			marek_compressing = true))

func _on_marek_arrival(action: Callable) -> void:
	marek.arrived.connect(action, CONNECT_ONE_SHOT)

func _marek_stop() -> void:
	marek_compressing = false
	if marek:
		marek.set_posture("")
		marek.attention = "auto"
		marek.walk_to(_near_trainee(_home("marek")))

func _helper_spot() -> Vector3:
	## Beside the patient's chest on the side away from the trainee.
	var marker: Variant = patient.get("sternum")
	var sternum: Vector3 = (marker as Node3D).global_position if marker is Node3D else patient.global_position
	var across: Vector3 = sternum - trainee.call()
	across.y = 0.0
	if across.length_squared() < 0.01:
		across = patient.global_basis.x
	return sternum + across.normalized() * HELPER_REACH

func _when_aed_quiet(action: Callable) -> void:
	## After the device's current announcement (immediately if there is no AED).
	_after_quiet.append(action)
	_quiet_since = -1.0

func _say(key: String, cooldown: float) -> void:
	## Speaks a line unless it was said less than `cooldown` seconds ago.
	var last: float = _said.get(key, -INF)
	if cooldown > 0.0 and _t - last < cooldown:
		return
	if not _lines.has(key):
		return
	_said[key] = _t
	var line: Dictionary = _lines[key]
	var lang: String = language.call()
	if speak.is_valid():
		speak.call(key, str(line.get(lang, line.get("de", ""))), lang, str(line.get("speaker", "anna")))
	line_spoken.emit(key, str(line.get("speaker", "anna")))

func _say_once(key: String) -> void:
	if not _said.has(key):
		_say(key, 0.0)

func _after(seconds: float, action: Callable) -> void:
	_timers.append([_t + seconds, action])

func _reset() -> void:
	_timers.clear()
	_said.clear()
	_breath_check_t = -1.0
	_called_t = -1.0
	_cpr_started_t = -1.0
	_last_activity_t = -1.0
	_shock_t = -1.0
	_wrong_strokes = 0
	_warmup = 0
	marek_compressing = false
	_after_quiet.clear()
	_good = 0
	_slow = 0
	_fast = 0
	_fetch_left = -1.0
	_intrude_left = -1.0
	_intruded = false
	for key in _homes:
		var who: NaretBystander = {"anna": anna, "marek": marek}[key]
		if who:
			who.visible = true
			who.set_posture("")
			who.attention = "auto"
			who.global_transform = _homes[key]
	if aed and aed.model:
		aed.reset()

func _remember_homes() -> void:
	## Where each stands when the scene starts (room placement may have moved them).
	for key in ["anna", "marek"]:
		var who: NaretBystander = {"anna": anna, "marek": marek}[key]
		if who:
			_homes[key] = who.global_transform

func _home(key: String) -> Transform3D:
	var who: NaretBystander = {"anna": anna, "marek": marek}[key]
	return _homes.get(key, who.global_transform if who else Transform3D.IDENTITY)

func _near_trainee(home: Transform3D) -> Vector3:
	## 1.3 Close enough to talk across the patient: a step in from where he stood,
	## about 1 m from the patient, facing the trainee over the chest.
	if patient == null:
		return home.origin
	var centre := patient.global_position
	var away := home.origin - centre
	away.y = 0.0
	var spot := home.origin if away.length() < 1.05 else centre + away.normalized() * 1.05 + Vector3(0, home.origin.y - centre.y, 0)
	return _clear_of_patient(spot)

func _clear_of_patient(point: Vector3) -> Vector3:
	## Never standing on the patient's feet or hands: out of the lying body's
	## footprint (patient-local, the walking route's) by a step.
	var local := patient.to_local(point)
	var half := Vector2(0.5 + 0.3, 1.2 + 0.3)
	if absf(local.x) < half.x and absf(local.z) < half.y:
		# Out through the nearer long side or end.
		if half.x - absf(local.x) < half.y - absf(local.z):
			local.x = signf(local.x if local.x != 0.0 else 1.0) * half.x
		else:
			local.z = signf(local.z if local.z != 0.0 else 1.0) * half.y
	var world := patient.to_global(local)
	return Vector3(world.x, point.y, world.z)

func _exit_point() -> Vector3:
	var home := _home("marek").origin
	var away := home - (patient.global_position if patient else Vector3.ZERO)
	away.y = 0.0
	return home + (away.normalized() if away.length() > 0.1 else Vector3.BACK) * 3.0

func _aed_drop_point() -> Vector3:
	## Standing next to where the device goes, on the side away from the patient.
	var spot := aed.home_position() if aed and aed.model else Vector3.ZERO
	var away := spot - (patient.global_position if patient else Vector3.ZERO)
	away.y = 0.0
	return spot + away.normalized() * 0.35
