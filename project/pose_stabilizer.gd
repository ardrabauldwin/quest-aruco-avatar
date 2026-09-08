class_name PoseStabilizer
extends RefCounted
## Makes a moving Transform3D steadier in three steps:
##   1. Choose the medoid of the newest poses to reject bad jumps.
##   2. Ignore movement inside a small dead zone.
##   3. Smooth larger movement over time.

# How many recent poses are compared.
var window_size := 1

# Changes smaller than these values are ignored.
var position_dead_zone_m := 0.0
var rotation_dead_zone_rad := 0.0

# Larger values move more slowly toward the new pose. Zero means no smoothing.
var smoothing_time_s := 0.0

# Position and rotation count equally when deciding which sample is most central.
var medoid_position_scale_m := 0.015
var medoid_rotation_scale_rad := deg_to_rad(3.0)

# The recent input poses.
var _samples: Array[Transform3D] = []

# The stable pose returned to the caller.
var _pose := Transform3D.IDENTITY
var _has_pose := false
var _last_detection_ms := -1


## Set the filter values and start it fresh.
func configure(
		p_window_size: int,
		p_position_dead_zone_m: float,
		p_rotation_dead_zone_deg: float,
		p_smoothing_time_s: float
) -> void:
	window_size = maxi(p_window_size, 1) # A window cannot be smaller than one.
	position_dead_zone_m = maxf(p_position_dead_zone_m, 0.0) # No negative distance.
	rotation_dead_zone_rad = deg_to_rad(maxf(p_rotation_dead_zone_deg, 0.0))
	smoothing_time_s = maxf(p_smoothing_time_s, 0.0) # No negative time.
	reset()


## Forget all previous poses.
func reset() -> void:
	_samples.clear()
	_pose = Transform3D.IDENTITY
	_has_pose = false
	_last_detection_ms = -1


## Add a pose only when one of its ArUco markers has a new detection.
## This prevents the render loop from adding the same camera result many times.
func update_from_markers(sample: Transform3D, markers: Array) -> Transform3D:
	var newest_detection_ms := -1

	for marker in markers:
		if marker != null:
			newest_detection_ms = maxi(
				newest_detection_ms,
				int(marker.get_meta("last_detected_ms", -1))
			)

	# No new OpenCV result: keep the current stable pose.
	if newest_detection_ms < 0 or newest_detection_ms == _last_detection_ms:
		return _pose

	# Calculate the time since the previous camera detection.
	var delta_s := 0.0
	if _last_detection_ms >= 0:
		delta_s = float(newest_detection_ms - _last_detection_ms) / 1000.0
	_last_detection_ms = newest_detection_ms

	return update(sample, delta_s)


## Add one pose and return the new stable result.
func update(sample: Transform3D, delta_s: float) -> Transform3D:
	_samples.append(sample) # Remember the newest pose.

	# Remove the oldest pose when the window is full.
	while _samples.size() > window_size:
		_samples.pop_front()

	# A medoid is trustworthy only after the requested window is full.
	if _samples.size() < window_size:
		return _pose

	# Pick one real sample near all the others. A lone jump receives a high
	# distance score, so it is not selected.
	var target := _medoid(_samples)

	# The first valid target becomes the starting pose immediately.
	if not _has_pose:
		_pose = target
		_has_pose = true
		return _pose

	# Measure how far the target moved.
	var position_change := _pose.origin.distance_to(target.origin)
	var rotation_change := _rotation_difference(_pose, target)

	# Ignore tiny position and rotation changes.
	if position_change <= position_dead_zone_m and rotation_change <= rotation_dead_zone_rad:
		return _pose

	# With smoothing disabled, use the target directly.
	if smoothing_time_s == 0.0:
		_pose = target
		return _pose

	# Convert elapsed time into a smooth interpolation amount between zero and one.
	var amount := 1.0 - exp(-maxf(delta_s, 0.0) / smoothing_time_s)
	_pose = _pose.interpolate_with(target, amount)
	return _pose


## Whether update() has produced its first usable pose.
func has_pose() -> bool:
	return _has_pose


## Return the current stable pose.
func get_pose() -> Transform3D:
	return _pose


## Return how many poses are currently waiting in the medoid window.
func sample_count() -> int:
	return _samples.size()


## Return the real sample with the smallest total distance to all other samples.
func _medoid(poses: Array[Transform3D]) -> Transform3D:
	var best_pose := poses[0]
	var best_score := INF

	# Try every pose as the possible centre.
	for candidate in poses:
		var score := 0.0

		# Add its position and rotation distance to every other pose.
		for other in poses:
			score += candidate.origin.distance_to(other.origin) / maxf(
				medoid_position_scale_m,
				0.0001
			)
			score += _rotation_difference(candidate, other) / maxf(
				medoid_rotation_scale_rad,
				0.0001
			)

		# Remember the candidate with the smallest total distance.
		if score < best_score:
			best_score = score
			best_pose = candidate

	return best_pose


## Smallest angle in radians between two pose rotations.
func _rotation_difference(a: Transform3D, b: Transform3D) -> float:
	return a.basis.get_rotation_quaternion().angle_to(
		b.basis.get_rotation_quaternion()
	)
