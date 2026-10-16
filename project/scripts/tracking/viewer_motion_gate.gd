class_name NaretViewerMotionGate
extends RefCounted
## Decides whether a new marker pose may update the already placed patient.
## tick() reads HMD movement every rendered frame; evaluate() receives detections.
## Returning {} means HOLD. Returning {"pose": ...} supplies a filter target.
## This preserves the user's old gate; it does not prove the markers are accurate.
## Patient heading is local -Z. Only horizontal position and yaw are judged here.
var head: Node3D
var moving := true
var gate_state := "settling"
const HEAD_STILL_SPEED_MPS := 0.15
const HEAD_STILL_TURN_DPS := 20.0
const HEAD_WINDOW_S := 0.3
const HEAD_SETTLE_S := 0.5
# These are pose differences, not head-motion speed limits. BOTH limits must
# pass to save the initial post-movement difference as viewpoint bias.
const VIEW_BIAS_MAX_M := 0.10
const VIEW_BIAS_MAX_DEG := 10.0
const VIEW_BIAS_SAMPLES := 5
const FOLLOW_ANYWAY_M := 0.30
# Large-change override: either limit exceeded for three full-evidence detections.
# This is a heuristic: a persistent detection error can still look like a real move.
const FOLLOW_ANYWAY_DEG := 25.0
const JUDGE_MOVE_MAX_RANGE_M := 1.8
var _head_samples: Array = []      # [time_s, position, yaw]
var _head_time_s := 0.0
var _head_still_s := 0.0
var _view_bias_ready := false
var _view_bias_position := Vector3.ZERO
var _view_bias_yaw := 0.0
var _view_bias_samples: Array = []
var _view_bias_last_ms := -1
var _follow_big_count := 0
var _window_partial := false   # a settle window that saw hidden markers or a hand on the chest
var _follow_big_last_ms := -1
const FOLLOW_ANYWAY_DETECTIONS := 3

func tick(delta: float) -> void:
	# Compare the newest HMD position/yaw with the oldest in a 0.3-second window.
	# Position change / elapsed time gives speed; yaw change / time gives turn rate.
	# Only yaw is measured: looking up/down does not directly trigger the turn limit.
	_head_time_s += delta
	var t: Transform3D = head.global_transform
	var yaw := _head_yaw(t.basis)
	_head_samples.append([_head_time_s, t.origin, yaw])
	while _head_samples.size() > 1 and float(_head_samples[0][0]) < _head_time_s - HEAD_WINDOW_S:
		_head_samples.pop_front()
	var first: Array = _head_samples[0]
	var span := _head_time_s - float(first[0])
	var sample_moving := false
	if span > 0.05:
		var speed := t.origin.distance_to(first[1]) / span
		var turn := rad_to_deg(absf(wrapf(yaw - float(first[2]), -PI, PI))) / span
		sample_moving = speed > HEAD_STILL_SPEED_MPS or turn > HEAD_STILL_TURN_DPS
	if sample_moving:
		_head_still_s = 0.0
	else:
		_head_still_s += delta
	moving = _head_still_s < HEAD_SETTLE_S
	# Even below both speed limits, wait 0.5 seconds before treating the head as still.


func evaluate(raw_pose: Transform3D, display: Transform3D, detection_ms: int, full_evidence: bool = true) -> Dictionary:
	# raw_pose is the new marker-based anchor; display is the held patient anchor.
	# full_evidence is supplied by the caller: all required markers visible,
	# with no hand covering the chest. It is not calculated from pose size here.
	if not full_evidence:
		_window_partial = true
	var offset := raw_pose.origin - display.origin
	offset.y = 0.0   # height is held separately
	var offset_deg := rad_to_deg(absf(wrapf(_yaw_of(raw_pose.basis) - _yaw_of(display.basis), -PI, PI)))
	if (offset.length() > FOLLOW_ANYWAY_M or offset_deg > FOLLOW_ANYWAY_DEG) and full_evidence:
		# A single far-range spike must not count: the move has to persist over detections.
		if detection_ms != _follow_big_last_ms:
			_follow_big_last_ms = detection_ms
			_follow_big_count += 1
		if _follow_big_count >= FOLLOW_ANYWAY_DETECTIONS:
			_view_bias_ready = false
			_view_bias_samples.clear()
			gate_state = "follow_big"
			return {"pose": raw_pose}
	else:
		_follow_big_count = 0
	if moving:
		# Normal head movement discards the old bias and starts a new settling window.
		_view_bias_ready = false
		_view_bias_samples.clear()
		_window_partial = false
		gate_state = "hold_moving"
		return {}
	if head.global_position.distance_to(display.origin) > JUDGE_MOVE_MAX_RANGE_M:
		# Too far to trust the markers for anything but a big move: hold. Smaller moves are
		# picked up when the viewer comes closer (the near settle then reads them as a move).
		_view_bias_ready = false
		_view_bias_samples.clear()
		gate_state = "hold_far"
		return {}
	if not _view_bias_ready:
		# Collect five different camera results after the head settles.
		if detection_ms != _view_bias_last_ms:
			_view_bias_last_ms = detection_ms
			_view_bias_samples.append(raw_pose)
		if _view_bias_samples.size() < VIEW_BIAS_SAMPLES:
			gate_state = "settling"
			return {}
		var xs: Array[float] = []
		var zs: Array[float] = []
		var yaws: Array[float] = []
		var display_yaw := _yaw_of(display.basis)
		for sample in _view_bias_samples:
			xs.append((sample as Transform3D).origin.x - display.origin.x)
			zs.append((sample as Transform3D).origin.z - display.origin.z)
			yaws.append(wrapf(_yaw_of((sample as Transform3D).basis) - display_yaw, -PI, PI))
		xs.sort()
		zs.sort()
		yaws.sort()
		var mid := VIEW_BIAS_SAMPLES / 2
		# Median of five = middle sorted value, separately for X, Z and yaw difference.
		var bias := Vector3(xs[mid], 0.0, zs[mid])
		var bias_yaw: float = yaws[mid]
		_view_bias_samples.clear()
		_view_bias_ready = true
		if bias.length() <= VIEW_BIAS_MAX_M and rad_to_deg(absf(bias_yaw)) <= VIEW_BIAS_MAX_DEG:
			# Remember this initial shift, then subtract it from later readings.
			# Example: held X=1.00 m, settled X=1.04 -> save +0.04 m.
			# A later X=1.06 -> corrected X=1.02, so later small moves CAN pass.
			_view_bias_position = bias
			_view_bias_yaw = bias_yaw
			gate_state = "biased"
			print("Viewer gate: settled; viewpoint bias %.1f cm / %.1f deg absorbed." % [bias.length() * 100.0, rad_to_deg(bias_yaw)])
		elif _window_partial:
			# Not enough evidence for a move: markers were hidden or a hand was on the chest during
			# the window. Hold the avatar and judge again from the next full window.
			_view_bias_ready = false
			_window_partial = false
			gate_state = "hold_partial"
			print("Viewer gate: %.1f cm / %.1f deg difference with markers hidden or hands on the chest - holding." % [bias.length() * 100.0, rad_to_deg(bias_yaw)])
			return {}
		else:
			_view_bias_position = Vector3.ZERO
			_view_bias_yaw = 0.0
			gate_state = "follow_moved"
			print("Viewer gate: settled; markers moved %.1f cm / %.1f deg while the head was still - following." % [bias.length() * 100.0, rad_to_deg(bias_yaw)])
	var corrected := raw_pose
	# This is an additive position/yaw correction, not a distance-scale correction.
	# The spatial anchor then holds height and smooths this target separately.
	corrected.origin -= _view_bias_position
	corrected.basis = Basis(Vector3.UP, -_view_bias_yaw) * corrected.basis
	return {"pose": corrected}


func _yaw_of(basis: Basis) -> float:
	return atan2(-basis.z.x, -basis.z.z)

func _head_yaw(basis: Basis) -> float:
	return atan2(-basis.z.x, -basis.z.z)
