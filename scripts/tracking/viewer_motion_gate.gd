class_name NaretViewerMotionGate
extends RefCounted
## Decides whether a new marker pose may update the already placed patient.
## tick() reads HMD movement every rendered frame; evaluate() receives detections.
## Returning {} means HOLD. Returning {"pose": ...} supplies a filter target.
## Stable marker estimates do not prove physical movement.
## Patient heading is local -Z. Only horizontal position and yaw are judged here.
var head: Node3D
var moving := true
var gate_state := "settling"
const HEAD_STILL_SPEED_MPS := 0.15
const HEAD_STILL_TURN_DPS := 20.0
const HEAD_WINDOW_S := 0.3
const HEAD_SETTLE_S := 0.5
# For a new move: distance<=15cm OR heading<=15degrees means hold/button.
# Only BOTH distance>15cm AND heading>15degrees open automatic confirmation.
const FOLLOW_ANYWAY_M := 0.15
const FOLLOW_ANYWAY_DEG := 15.0
const BIG_MOVE_FIRST_CHECK := 30
const BIG_MOVE_CHECK_STEP := 3
const BIG_MOVE_STABLE_CHECKS := 4
const BIG_MOVE_MAX_SAMPLES := 100
var _big_samples: Array[Transform3D] = []
var _big_readings := 0
var _big_last_ms := -1
var _big_next_check := BIG_MOVE_FIRST_CHECK
var _big_previous := Transform3D.IDENTITY
var _big_have_previous := false
var _big_stable := 0
var _big_confirmed := Transform3D.IDENTITY
var _big_following := false
# Default consumed by the separate optional checkpoint gate; not an outside-update rule.
const JUDGE_MOVE_MAX_RANGE_M := 1.8
var _head_samples: Array = []      # [time_s, position, full rotation]
var _head_time_s := 0.0
var _head_still_s := 0.0
func tick(delta: float) -> void:
	# Classify position and full rotation over the recent 0.3-second window.
	_head_time_s += delta
	var t: Transform3D = head.global_transform
	var rotation := t.basis.orthonormalized().get_rotation_quaternion()
	_head_samples.append([_head_time_s, t.origin, rotation])
	while _head_samples.size() > 1 and float(_head_samples[0][0]) < _head_time_s - HEAD_WINDOW_S:
		_head_samples.pop_front()
	var first: Array = _head_samples[0]
	var span := _head_time_s - float(first[0])
	var sample_moving := false
	if span > 0.05:
		var speed := t.origin.distance_to(first[1]) / span
		var turn := rad_to_deg(rotation.angle_to(first[2])) / span
		sample_moving = speed > HEAD_STILL_SPEED_MPS or turn > HEAD_STILL_TURN_DPS
	if sample_moving:
		_head_still_s = 0.0
	else:
		_head_still_s += delta
	moving = _head_still_s < HEAD_SETTLE_S
	# Even below both speed limits, wait 0.5 seconds before treating the head as still.


func evaluate(raw_pose: Transform3D, display: Transform3D, detection_ms: int, full_evidence: bool = true) -> Dictionary:
	var large := _evaluate_large_change(raw_pose, display, detection_ms, full_evidence)
	if not full_evidence or moving or not large.is_empty() or gate_state == "big_collecting":
		return large
	gate_state = "hold_outside"
	return {}


## Complete evidence and a settled viewer are mandatory for every update.
## Every passing target still uses the common filter.
func evaluate_large_change(raw_pose: Transform3D, display: Transform3D, detection_ms: int, full_evidence: bool = true) -> Dictionary:
	return _evaluate_large_change(raw_pose, display, detection_ms, full_evidence)

func _evaluate_large_change(raw_pose: Transform3D, display: Transform3D, detection_ms: int, full_evidence: bool) -> Dictionary:
	# raw_pose is the new marker-based anchor; display is the held patient anchor.
	# full_evidence is supplied by the caller: all required markers visible,
	# with no hand covering the chest. It is not calculated from pose size here.
	if not full_evidence:
		# Missing or covered markers must not drive the placed patient.
		_clear_big_move()
		_big_following = false
		gate_state = "hold_partial"
		return {}
	if moving:
		_clear_big_move()
		_big_following = false
		gate_state = "hold_moving"
		return {}
	var offset := raw_pose.origin - display.origin
	offset.y = 0.0   # height is held separately
	var offset_deg := rad_to_deg(absf(wrapf(_yaw_of(raw_pose.basis) - _yaw_of(display.basis), -PI, PI)))
	# Respect exact boundary values despite Vector3/Basis rounding.
	var moved := offset.length_squared() > Vector3(FOLLOW_ANYWAY_M, 0.0, 0.0).length_squared()
	var turned := offset_deg > FOLLOW_ANYWAY_DEG and not is_equal_approx(offset_deg, FOLLOW_ANYWAY_DEG)
	if moved and turned:
		var confirmed := _confirm_big_move(raw_pose, detection_ms)
		if confirmed.is_empty():
			if _big_following:
				gate_state = "follow_fixed"
				return {"pose": _big_confirmed}
			gate_state = "big_collecting"
			return {}
		_big_confirmed = confirmed.pose
		_big_following = true
		gate_state = "follow_big"
		print("Viewer gate: big move %.0f cm / %.0f deg confirmed after %d readings - following." % [offset.length() * 100.0, offset_deg, confirmed.samples])
		return {"pose": confirmed.pose, "confirmed": true}
	_clear_big_move()
	if _big_following:
		gate_state = "follow_fixed"
		return {"pose": _big_confirmed}
	gate_state = "no_large_change"
	return {}


## The startup placement's rule applied to readings that disagree with the shown patient by
## more than the large-change limits. {} while collecting; {pose, samples} once confirmed.
func _confirm_big_move(raw_pose: Transform3D, detection_ms: int) -> Dictionary:
	if detection_ms <= _big_last_ms or not NaretMarkerLayout.rigid(raw_pose):
		return {}
	_big_last_ms = detection_ms
	_big_samples.append(raw_pose.orthonormalized())
	_big_readings += 1
	while _big_samples.size() > BIG_MOVE_MAX_SAMPLES:
		_big_samples.pop_front()
	if _big_readings < _big_next_check:
		return {}
	_big_next_check += BIG_MOVE_CHECK_STEP
	var estimate: Transform3D = NaretStartupPlacement.new()._robust_estimate(_big_samples)
	var stable := _big_have_previous and _big_near(estimate, _big_previous)
	for i in range(_big_samples.size() - 3, _big_samples.size()):
		stable = stable and _big_near(_big_samples[i], estimate)
	_big_stable = _big_stable + 1 if stable else 0
	_big_previous = estimate
	_big_have_previous = true
	if _big_stable < BIG_MOVE_STABLE_CHECKS:
		return {}
	var count := _big_readings
	_clear_big_move()
	return {"pose": estimate, "samples": count}


func _big_near(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) <= NaretStartupPlacement.STABLE_POSITION_M \
		and a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()) <= NaretStartupPlacement.STABLE_ROTATION_RAD


func _clear_big_move() -> void:
	_big_samples.clear()
	_big_readings = 0
	_big_next_check = BIG_MOVE_FIRST_CHECK
	_big_have_previous = false
	_big_stable = 0


func _yaw_of(basis: Basis) -> float:
	return atan2(-basis.z.x, -basis.z.z)

func _head_yaw(basis: Basis) -> float:
	return atan2(-basis.z.x, -basis.z.z)

## Clear candidate evidence when switching regions or replacing placement.
func reset_pose_evidence() -> void:
	_big_following = false
	_clear_big_move()
