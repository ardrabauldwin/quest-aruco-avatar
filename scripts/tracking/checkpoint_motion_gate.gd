extends "res://scripts/tracking/viewer_motion_gate.gd"
## Experimental post-startup confirmation. No bias subtraction or large-move bypass.
## A stable pose can still be systematically wrong; this is not depth correction.
const MAX_HISTORY := 100
var candidate := NaretStartupPlacement.new()
var candidate_readings := 0
var stable_comparisons := 0
var _checkpoint := 30
var _previous := Transform3D.IDENTITY
var _have_previous := false
var _last_detection := -1


func tick(delta: float) -> void:
	# Reuse the history/timer, but include pitch and roll in angular motion.
	_head_time_s += delta
	var pose := head.global_transform
	var rotation := pose.basis.orthonormalized().get_rotation_quaternion()
	_head_samples.append([_head_time_s, pose.origin, rotation])
	while _head_samples.size() > 1 and float(_head_samples[0][0]) < _head_time_s - HEAD_WINDOW_S:
		_head_samples.pop_front()
	var first: Array = _head_samples[0]
	var span := _head_time_s - float(first[0])
	var sample_moving := false
	if span > 0.05:
		var speed := pose.origin.distance_to(first[1]) / span
		var turn := rad_to_deg(rotation.angle_to(first[2])) / span
		sample_moving = speed > HEAD_STILL_SPEED_MPS or turn > HEAD_STILL_TURN_DPS
	_head_still_s = 0.0 if sample_moving else _head_still_s + delta
	moving = _head_still_s < HEAD_SETTLE_S
	if moving:
		_clear_candidate()


func evaluate(raw_pose: Transform3D, display: Transform3D, detection_ms: int, full_evidence: bool = true) -> Dictionary:
	if detection_ms <= _last_detection:
		return {}
	_last_detection = detection_ms
	if not full_evidence or moving or head.global_position.distance_to(display.origin) > JUDGE_MOVE_MAX_RANGE_M:
		_clear_candidate()
		gate_state = "hold_partial" if not full_evidence else ("hold_moving" if moving else "hold_far")
		return {}
	if not NaretMarkerLayout.rigid(raw_pose):
		_clear_candidate()
		gate_state = "hold_invalid"
		return {}
	# Height remains a floor/chest concern. Confirm only horizontal pose + yaw.
	var along := raw_pose.basis.z.slide(Vector3.UP).normalized()
	if along.length_squared() < 0.5:
		_clear_candidate()
		return {}
	var sample := Transform3D(Basis(Vector3.UP.cross(along), Vector3.UP, along), raw_pose.origin)
	sample.origin.y = display.origin.y
	candidate.samples.append(sample)
	candidate_readings += 1
	if candidate.samples.size() > MAX_HISTORY:
		candidate.samples.pop_front()
	gate_state = "checkpoint_collecting"
	if candidate_readings < _checkpoint:
		return {}
	_checkpoint += 3
	var estimate := candidate._robust_estimate(candidate.samples)
	var stable := _have_previous and _near(estimate, _previous)
	# Accumulated medians alone can mask a slow drift. Require the newest three
	# measurements to agree with the candidate as well.
	for i in range(candidate.samples.size() - 3, candidate.samples.size()):
		stable = stable and _near(candidate.samples[i], estimate)
	stable_comparisons = stable_comparisons + 1 if stable else 0
	_previous = estimate
	_have_previous = true
	if stable_comparisons < 4:
		return {}
	var count := candidate_readings
	_clear_candidate()
	gate_state = "checkpoint_confirmed"
	return {"pose": estimate, "samples": count, "confirmed": true}


func _near(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) <= NaretStartupPlacement.STABLE_POSITION_M \
		and a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()) <= NaretStartupPlacement.STABLE_ROTATION_RAD


func _clear_candidate() -> void:
	candidate.samples.clear()
	candidate_readings = 0
	stable_comparisons = 0
	_checkpoint = 30
	_have_previous = false
