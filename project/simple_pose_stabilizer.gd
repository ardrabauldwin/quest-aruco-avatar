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

# Relocation is deliberately separate from the display dead zone. These provisional values are
# searched by tune_filter.py; crossing a dead zone alone must never disable the prior.
var relocation_position_threshold_m := 0.100
var relocation_rotation_threshold_deg := 5.0
var relocation_confirm_detections := 7
var relocation_stable_position_m := 0.002
var relocation_stable_rotation_deg := 0.5
var relocation_stable_detections := 7

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
var _position_relocation_candidate_count := 0
var _rotation_relocation_candidate_count := 0
var _position_relocation_stable_count := 0
var _rotation_relocation_stable_count := 0
var _position_relocating := false
var _rotation_relocating := false
var _position_relocation_ready := false
var _rotation_relocation_ready := false
var _relocation_previous_target := Transform3D.IDENTITY
var _has_relocation_previous_target := false


func configure(
		p_window: int,
		p_position_dead_zone_m: float,
		p_rotation_dead_zone_deg: float,
		p_smoothing_time_s: float,
		p_prior_time_s: float = 1.0,
		p_relocation_position_threshold_m: float = 0.100,
		p_relocation_rotation_threshold_deg: float = 5.0,
		p_relocation_confirm_detections: int = 7,
		p_relocation_stable_position_m: float = 0.002,
		p_relocation_stable_rotation_deg: float = 0.5,
		p_relocation_stable_detections: int = 7
) -> void:
	window = maxi(p_window, 1)
	position_dead_zone_m = maxf(p_position_dead_zone_m, 0.0)
	rotation_dead_zone_deg = maxf(p_rotation_dead_zone_deg, 0.0)
	smoothing_time_s = maxf(p_smoothing_time_s, 0.0)
	prior_time_s = maxf(p_prior_time_s, 0.0)
	relocation_position_threshold_m = maxf(p_relocation_position_threshold_m, 0.0)
	relocation_rotation_threshold_deg = maxf(p_relocation_rotation_threshold_deg, 0.0)
	relocation_confirm_detections = maxi(p_relocation_confirm_detections, 1)
	relocation_stable_position_m = maxf(p_relocation_stable_position_m, 0.0)
	relocation_stable_rotation_deg = maxf(p_relocation_stable_rotation_deg, 0.0)
	relocation_stable_detections = maxi(p_relocation_stable_detections, 1)
	while _recent_poses.size() > window:
		_recent_poses.pop_front()


func update(
		raw_pose: Transform3D,
		delta_s: float,
		detection_ms: int = -1,
		rest_pose: Transform3D = Transform3D.IDENTITY,
		use_rest_prior: bool = false
) -> Transform3D:
	var accepted_detection := _accept_new_detection(raw_pose, detection_ms)
	if accepted_detection and use_rest_prior:
		_update_relocation_state(rest_pose)
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
		# Dead zones never control the prior. Only a separately confirmed genuine relocation can
		# suspend it, independently for position and rotation.
		if not _position_relocating:
			next_position = next_position.lerp(rest_pose.origin, pull)
		if not _rotation_relocating:
			next_rotation = next_rotation.normalized().slerp(
				rest_pose.basis.get_rotation_quaternion().normalized(),
				pull
			).normalized()

	_stable_pose = Transform3D(Basis(next_rotation), next_position)
	return _stable_pose


## Add at most one sample per OpenCV result, never one sample per render frame.
func _accept_new_detection(raw_pose: Transform3D, detection_ms: int) -> bool:
	if detection_ms < 0 or detection_ms == _last_detection_ms:
		return false

	_last_detection_ms = detection_ms
	_recent_poses.append(raw_pose)
	while _recent_poses.size() > window:
		_recent_poses.pop_front()
	if _reacquiring:
		if _recent_poses.size() < window:
			return true
		_set_measurement_target(_medoid())
		# The avatar is hidden while this window is collected. Start directly at the confirmed
		# post-gap pose instead of interpolating visibly from a stale pre-gap world position.
		_stable_pose = _target_pose
		_reacquiring = false
		_hold_anchor_once = true
		return true

	# Before the window fills, use the newest measurement instead of a weak partial medoid.
	_set_measurement_target(_medoid() if _recent_poses.size() == window else raw_pose)
	return true


## Detect a genuine relocation from the measurement-only medoid. Entry requires a separate large
## threshold for several detections; settling requires small successive changes. Candidate samples
## already count toward settling, so a marker that reappears at a stationary new location does not
## wait through two unnecessary confirmation periods.
func _update_relocation_state(rest_pose: Transform3D) -> void:
	if not _has_measurement_target:
		return

	var target_rotation := _target_pose.basis.get_rotation_quaternion().normalized()
	var rest_rotation := rest_pose.basis.get_rotation_quaternion().normalized()
	var position_offset := _target_pose.origin.distance_to(rest_pose.origin)
	var rotation_offset_deg := rad_to_deg(target_rotation.angle_to(rest_rotation))
	var position_is_stable := false
	var rotation_is_stable := false
	if _has_relocation_previous_target:
		position_is_stable = (
			_target_pose.origin.distance_to(_relocation_previous_target.origin)
			<= relocation_stable_position_m
		)
		rotation_is_stable = rad_to_deg(
			target_rotation.angle_to(
				_relocation_previous_target.basis.get_rotation_quaternion().normalized()
			)
		) <= relocation_stable_rotation_deg

	_update_position_relocation(position_offset, position_is_stable)
	_update_rotation_relocation(rotation_offset_deg, rotation_is_stable)
	_relocation_previous_target = _target_pose
	_has_relocation_previous_target = true


func _update_position_relocation(offset_m: float, is_stable: bool) -> void:
	if _position_relocation_ready:
		return
	if not _position_relocating:
		if offset_m >= relocation_position_threshold_m:
			_position_relocation_candidate_count += 1
			_position_relocation_stable_count = (
				_position_relocation_stable_count + 1 if is_stable else 0
			)
		else:
			_position_relocation_candidate_count = 0
			_position_relocation_stable_count = 0
		if _position_relocation_candidate_count >= relocation_confirm_detections:
			_position_relocating = true
	else:
		_position_relocation_stable_count = (
			_position_relocation_stable_count + 1 if is_stable else 0
		)
	_position_relocation_ready = (
		_position_relocating
		and _position_relocation_stable_count >= relocation_stable_detections
	)


func _update_rotation_relocation(offset_deg: float, is_stable: bool) -> void:
	if _rotation_relocation_ready:
		return
	if not _rotation_relocating:
		if offset_deg >= relocation_rotation_threshold_deg:
			_rotation_relocation_candidate_count += 1
			_rotation_relocation_stable_count = (
				_rotation_relocation_stable_count + 1 if is_stable else 0
			)
		else:
			_rotation_relocation_candidate_count = 0
			_rotation_relocation_stable_count = 0
		if _rotation_relocation_candidate_count >= relocation_confirm_detections:
			_rotation_relocating = true
	else:
		_rotation_relocation_stable_count = (
			_rotation_relocation_stable_count + 1 if is_stable else 0
		)
	_rotation_relocation_ready = (
		_rotation_relocating
		and _rotation_relocation_stable_count >= relocation_stable_detections
	)


func _set_measurement_target(pose: Transform3D) -> void:
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


func position_relocation_ready() -> bool:
	return _position_relocation_ready


func rotation_relocation_ready() -> bool:
	return _rotation_relocation_ready


## Called only after the provider has adopted the stable measurement as its new rest.
func complete_relocation(position_completed: bool, rotation_completed: bool) -> void:
	if position_completed:
		_position_relocating = false
		_position_relocation_ready = false
		_position_relocation_candidate_count = 0
		_position_relocation_stable_count = 0
	if rotation_completed:
		_rotation_relocating = false
		_rotation_relocation_ready = false
		_rotation_relocation_candidate_count = 0
		_rotation_relocation_stable_count = 0
	_relocation_previous_target = _target_pose
	_has_relocation_previous_target = true


## Place the avatar at robust rest without discarding genuine measurements collected while hidden.
func anchor_at(pose: Transform3D) -> void:
	_stable_pose = pose
	_target_pose = pose
	_ready = true
	_hold_anchor_once = true
	_reacquiring = false
	_reset_relocation_state()


## Keep the displayed pose, but ensure reacquisition does not use pre-loss measurements.
func clear_measurement_history() -> void:
	_recent_poses.clear()
	_last_detection_ms = -1
	_has_measurement_target = false
	_reset_relocation_state()
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
	_reset_relocation_state()


func _reset_relocation_state() -> void:
	_position_relocation_candidate_count = 0
	_rotation_relocation_candidate_count = 0
	_position_relocation_stable_count = 0
	_rotation_relocation_stable_count = 0
	_position_relocating = false
	_rotation_relocating = false
	_position_relocation_ready = false
	_rotation_relocation_ready = false
	_relocation_previous_target = Transform3D.IDENTITY
	_has_relocation_previous_target = false


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
