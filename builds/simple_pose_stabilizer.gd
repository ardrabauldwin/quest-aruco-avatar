class_name SimplePoseStabilizer
extends RefCounted

## Three simple steps:
##   1. Select the medoid of the latest few ArUco detections.
##   2. Ignore tiny changes caused by ordinary tracking noise.
##   3. Smooth real position and rotation movement.
##
## The four numbers below arrive from the AvatarRig inspector rather than being fixed here, so
## they can be tuned live over the remote debugger instead of by redeploying. Their defaults are
## what the 3 August recordings measured, not guesses.

# How many detections to compare when picking the medoid. At about 8 detections a second, 5 is
# roughly 0.6 seconds of history.
var window := 5

# Changes smaller than these are HELD - the pose does not move at all until the change exceeds
# them. Zero deliberately. The fused pose carries about 7 mm of noise, and a 3 mm dead zone made
# it sit still, jump, and sit still again; that stair-stepping reads as jitter far more than the
# smooth drift it replaced. Smoothing is what removes noise, not a dead zone.
var position_dead_zone_m := 0.0
var rotation_dead_zone_deg := 0.0

# Seconds to ease toward a new pose. The mannequin stays where it is put, so lag costs nothing and
# the only question is how fast the avatar should catch up after it is nudged. Measured with the
# markers stationary: 2.46 mm of frame-to-frame movement at 0.15 s, 0.72 mm at 0.5 s.
var smoothing_time_s := 0.5

# Scales that make a position difference and a rotation difference comparable when picking the
# medoid. These are NOT the dead zones. They used to be, which meant a dead zone of zero divided
# by zero here - and it also tied outlier rejection to a threshold that has nothing to do with it.
var medoid_position_scale_m := 0.015
var medoid_rotation_scale_rad := deg_to_rad(3.0)

var _stable_pose := Transform3D.IDENTITY
var _target_pose := Transform3D.IDENTITY
var _recent_poses: Array[Transform3D] = []
var _last_detection_ms := -1  # I have not stored any ArUco detection time yet.
var _ready := false


## Push the inspector's values in. Does not reset: changing a number mid-session should retune the
## filter, not blank the avatar until the window refills.
func configure(
		p_window: int,
		p_position_dead_zone_m: float,
		p_rotation_dead_zone_deg: float,
		p_smoothing_time_s: float
) -> void:
	window = maxi(p_window, 1)
	position_dead_zone_m = maxf(p_position_dead_zone_m, 0.0)  # No negative distance.
	rotation_dead_zone_deg = maxf(p_rotation_dead_zone_deg, 0.0)
	smoothing_time_s = maxf(p_smoothing_time_s, 0.0)          # No negative time.
	while _recent_poses.size() > window:
		_recent_poses.pop_front()


func update(
		raw_pose: Transform3D,
		delta_s: float,
		detection_ms: int = -1
) -> Transform3D:
	# Add the pose once, only when OpenCV produces a new detection. The render loop runs about
	# nine times faster than detection, so sampling every frame would fill the window with copies
	# of one detection and make the smoothing time mean nothing.
	if detection_ms < 0 or detection_ms != _last_detection_ms:
		_last_detection_ms = detection_ms
		_recent_poses.append(raw_pose)
		while _recent_poses.size() > window:
			_recent_poses.pop_front()

		# A medoid is only trustworthy once the window is full; before that, take the newest.
		_target_pose = _medoid() if _recent_poses.size() == window else raw_pose

	# If the stabilizer has not started yet: set stable pose directly to target pose.
	if not _ready:
		_stable_pose = _target_pose
		_ready = true
		return _stable_pose

	var next_position := _stable_pose.origin
	var stable_rotation := _stable_pose.basis.get_rotation_quaternion()
	var target_rotation := _target_pose.basis.get_rotation_quaternion()
	var next_rotation := stable_rotation

	# Move position only when its own dead zone is exceeded.
	if (
		_stable_pose.origin.distance_to(_target_pose.origin)
		> position_dead_zone_m
	):
		next_position = _stable_pose.origin.lerp(
			_target_pose.origin,
			_smoothing_amount(delta_s)
		)

	# Turn only when its own dead zone is exceeded.
	if (
		rad_to_deg(stable_rotation.angle_to(target_rotation))
		> rotation_dead_zone_deg
	):
		next_rotation = stable_rotation.slerp(
			target_rotation,
			_smoothing_amount(delta_s)
		).normalized()

	_stable_pose = Transform3D(Basis(next_rotation), next_position)
	return _stable_pose


## Has the stabilizer received its first pose yet?
func is_ready() -> bool:
	return _ready


## Start fresh after recalibration.
func reset() -> void:
	_stable_pose = Transform3D.IDENTITY
	_target_pose = Transform3D.IDENTITY
	_recent_poses.clear()
	_last_detection_ms = -1
	_ready = false


## The most central of the recent poses.
##
## Used to reject the occasional one-frame ArUco outlier. Each pose scores the sum of its distances
## to all the others, and the lowest score wins. Safer than averaging: a bad pose drags an average
## away from the truth, whereas the medoid can only ever return a pose that was really detected.
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


## One comparable number containing both position and rotation difference.
func _pose_distance(a: Transform3D, b: Transform3D) -> float:
	var position_distance := (
		a.origin.distance_to(b.origin) / medoid_position_scale_m
	)
	var rotation_distance := (
		a.basis.get_rotation_quaternion().angle_to(
			b.basis.get_rotation_quaternion()
		)
		/ medoid_rotation_scale_rad
	)
	return position_distance + rotation_distance


func _smoothing_amount(delta_s: float) -> float:
	if smoothing_time_s <= 0.0:
		return 1.0  # No smoothing: go straight to the medoid.
	return 1.0 - exp(-maxf(delta_s, 0.0) / smoothing_time_s)
