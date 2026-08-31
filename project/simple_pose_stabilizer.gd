class_name SimplePoseStabilizer
extends RefCounted
## Stabilization order:
##   1. Select the medoid of recent independent detections.
##   2. Apply position and rotation dead zones.
##   3. Smooth toward the selected measurement.
##   4. If enabled, pull gently toward session rest.

var window := 3
var position_dead_zone_m := 0.005
var rotation_dead_zone_deg := 1.5
var smoothing_time_s := 0.5
var prior_time_s := 1.0

# Converts rotation into equivalent point displacement inside the medoid score.
# 0.2864789 m preserves the old 15 mm / 3 degree balance exactly. It is provisional until the
# stationary + CPR experiment chooses a radius from the analysis grid.
var medoid_rotation_radius_m := 0.2864789

var _stable_pose := Transform3D.IDENTITY
var _target_pose := Transform3D.IDENTITY
var _recent_poses: Array[Transform3D] = []
var _last_detection_ms := -1
var _ready := false
var _hold_anchor_once := false
var _reacquiring := false
var _has_measurement_target := false
var _target_stable_detections := 0


func configure(
		p_window: int,
		p_position_dead_zone_m: float,
		p_rotation_dead_zone_deg: float,
		p_smoothing_time_s: float,
		p_prior_time_s: float = 1.0
) -> void:
	window = maxi(p_window, 1)
	position_dead_zone_m = maxf(p_position_dead_zone_m, 0.0)
	rotation_dead_zone_deg = maxf(p_rotation_dead_zone_deg, 0.0)
	smoothing_time_s = maxf(p_smoothing_time_s, 0.0)
	prior_time_s = maxf(p_prior_time_s, 0.0)
	while _recent_poses.size() > window:
		_recent_poses.pop_front()


func update(
		raw_pose: Transform3D,
		delta_s: float,
		detection_ms: int = -1,
		rest_pose: Transform3D = Transform3D.IDENTITY,
		use_rest_prior: bool = false
) -> Transform3D:
	_accept_new_detection(raw_pose, detection_ms)
	# After a complete tracking gap, hold the existing avatar until a full fresh medoid window is
	# available. This prevents one bad first reacquired detection from moving the avatar.
	if _reacquiring:
		return _stable_pose

	# The first visible frame after rest confirmation must be exactly the robust rest pose.
	if _hold_anchor_once:
		_hold_anchor_once = false
		return _stable_pose

	if not _ready:
		_stable_pose = _target_pose
		_ready = true
		return _stable_pose

	var amount := _smoothing_amount(delta_s)
	var next_position := _smoothed_position(amount)
	var next_rotation := _smoothed_rotation(amount)

	if use_rest_prior and prior_time_s > 0.0:
		var pull := 1.0 - exp(-maxf(delta_s, 0.0) / prior_time_s)
		# The prior removes noise only around its remembered rest. Once the robust measurement has
		# genuinely moved beyond the corresponding dead zone, do not let the old rest oppose that
		# movement. Position and rotation are gated independently so a translation can retain a stable
		# resting orientation, and a genuine rotation can retain a stable position.
		if _target_pose.origin.distance_to(rest_pose.origin) <= position_dead_zone_m:
			next_position = next_position.lerp(rest_pose.origin, pull)
		if rad_to_deg(
			_target_pose.basis.get_rotation_quaternion().angle_to(
				rest_pose.basis.get_rotation_quaternion()
			)
		) <= rotation_dead_zone_deg:
			next_rotation = next_rotation.normalized().slerp(
				rest_pose.basis.get_rotation_quaternion().normalized(),
				pull
			).normalized()

	_stable_pose = Transform3D(Basis(next_rotation), next_position)
	return _stable_pose


## Add at most one sample per OpenCV result, never one sample per render frame.
func _accept_new_detection(raw_pose: Transform3D, detection_ms: int) -> void:
	if detection_ms < 0 or detection_ms == _last_detection_ms:
		return

	_last_detection_ms = detection_ms
	_recent_poses.append(raw_pose)
	while _recent_poses.size() > window:
		_recent_poses.pop_front()
	if _reacquiring:
		if _recent_poses.size() < window:
			return
		_set_measurement_target(_medoid())
		# The avatar is hidden while this window is collected. Start directly at the confirmed
		# post-gap pose instead of interpolating visibly from a stale pre-gap world position.
		_stable_pose = _target_pose
		_reacquiring = false
		_hold_anchor_once = true
		return

	# Before the window fills, use the newest measurement instead of a weak partial medoid.
	_set_measurement_target(_medoid() if _recent_poses.size() == window else raw_pose)


func _set_measurement_target(pose: Transform3D) -> void:
	if _has_measurement_target:
		var position_change := _target_pose.origin.distance_to(pose.origin)
		var rotation_change_deg := rad_to_deg(
			_target_pose.basis.get_rotation_quaternion().angle_to(
				pose.basis.get_rotation_quaternion()
			)
		)
		if (
			position_change <= position_dead_zone_m
			and rotation_change_deg <= rotation_dead_zone_deg
		):
			_target_stable_detections += 1
		else:
			_target_stable_detections = 0
	else:
		_target_stable_detections = 0
	_has_measurement_target = true
	_target_pose = pose


func _smoothed_position(amount: float) -> Vector3:
	if _stable_pose.origin.distance_to(_target_pose.origin) <= position_dead_zone_m:
		return _stable_pose.origin
	return _stable_pose.origin.lerp(_target_pose.origin, amount)


func _smoothed_rotation(amount: float) -> Quaternion:
	var stable := _stable_pose.basis.get_rotation_quaternion()
	var target := _target_pose.basis.get_rotation_quaternion()
	if rad_to_deg(stable.angle_to(target)) <= rotation_dead_zone_deg:
		return stable
	return stable.slerp(target, amount).normalized()


func is_ready() -> bool:
	return _ready


func is_reacquiring() -> bool:
	return _reacquiring


## Measurement-only medoid target: it has no dead zone, smoothing or rest-prior bias.
func measurement_target() -> Transform3D:
	return _target_pose


## A full window followed by one window's worth of stable target comparisons is strong enough to
## teach the slow rest without letting one newly selected medoid move it.
func measurement_target_is_stable() -> bool:
	return (
		_has_measurement_target
		and _recent_poses.size() == window
		and _target_stable_detections >= window
	)
## Place the avatar at robust rest without discarding genuine measurements collected while hidden.
func anchor_at(pose: Transform3D) -> void:
	_stable_pose = pose
	_target_pose = pose
	_ready = true
	_hold_anchor_once = true
	_reacquiring = false


## Keep the displayed pose, but ensure reacquisition does not use pre-loss measurements.
func clear_measurement_history() -> void:
	_recent_poses.clear()
	_last_detection_ms = -1
	_has_measurement_target = false
	_target_stable_detections = 0
	if _ready:
		_target_pose = _stable_pose
		_reacquiring = window > 1


## Start completely fresh after startup/re-level rest is confirmed.
func reset() -> void:
	_stable_pose = Transform3D.IDENTITY
	_target_pose = Transform3D.IDENTITY
	_recent_poses.clear()
	_last_detection_ms = -1
	_ready = false
	_hold_anchor_once = false
	_reacquiring = false
	_has_measurement_target = false
	_target_stable_detections = 0


## Return the actual recent measurement closest to all other recent measurements.
func _medoid() -> Transform3D:
	var best := _recent_poses[0]
	var best_score := INF
	for candidate in _recent_poses:
		var score := 0.0
		for other in _recent_poses:
			score += _pose_distance(candidate, other)
		if score < best_score:
			best_score = score
			best = candidate
	return best


func _pose_distance(a: Transform3D, b: Transform3D) -> float:
	var position_distance_m := a.origin.distance_to(b.origin)
	var rotation_distance_rad := a.basis.get_rotation_quaternion().angle_to(
		b.basis.get_rotation_quaternion()
	)
	return position_distance_m + medoid_rotation_radius_m * rotation_distance_rad


func _smoothing_amount(delta_s: float) -> float:
	if smoothing_time_s <= 0.0:
		return 1.0
	return 1.0 - exp(-maxf(delta_s, 0.0) / smoothing_time_s)
