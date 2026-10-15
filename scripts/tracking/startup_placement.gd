class_name NaretStartupPlacement
extends RefCounted
## Chooses the first patient anchor from fresh, fused marker poses.
## observe() returns {} while collecting, or a dictionary containing the accepted pose.
## The caller keeps the patient hidden until a pose is accepted.
## All samples use room coordinates; distances are metres and angles are radians.
const FIRST_CHECKPOINT := 30
const CHECKPOINT_STEP := 3
const REQUIRED_STABLE_CHECKS := 4
const FALLBACK_SAMPLES := 100
const STABLE_POSITION_M := 0.0015 # 1.5 mm between consecutive estimates.
const STABLE_ROTATION_RAD := deg_to_rad(1.0)

# Keep all startup samples, not just the last five. Each checkpoint re-estimates
# the position and rotation from everything collected during this setup.
var samples: Array[Transform3D] = []
var last_ms := -1
var next_checkpoint := FIRST_CHECKPOINT
var previous := Transform3D.IDENTITY
var have_previous := false
var stable_checks := 0
var used_fallback := false

func observe(pose: Transform3D, detection_ms: int) -> Dictionary:
	# 1. A rendered frame is not necessarily a new camera detection.
	# Ignore repeated/older timestamps and malformed poses.
	if detection_ms <= last_ms or not NaretMarkerLayout.rigid(pose):
		return {}
	last_ms = detection_ms
	samples.append(pose.orthonormalized())
	var checkpoint := samples.size() >= next_checkpoint
	var fallback := samples.size() >= FALLBACK_SAMPLES
	if not checkpoint and not fallback:
		return {}
	var estimate := _robust_estimate(samples)
	# 2. Compare estimates at 30, 33, 36, ... fresh detections.
	# Four consecutive successful comparisons give earliest acceptance at 42.
	if checkpoint:
		if have_previous:
			var same_position := estimate.origin.distance_to(previous.origin) <= STABLE_POSITION_M
			var same_rotation := estimate.basis.get_rotation_quaternion().angle_to(previous.basis.get_rotation_quaternion()) <= STABLE_ROTATION_RAD
			if same_position and same_rotation:
				stable_checks += 1
			else:
				stable_checks = 0
		previous = estimate
		have_previous = true
		next_checkpoint += CHECKPOINT_STEP
	if stable_checks < REQUIRED_STABLE_CHECKS and not fallback:
		return {}
	# 3. The original rule accepts at 100 samples even without convergence.
	# This avoids waiting forever; fallback=true is NOT a quality guarantee.
	used_fallback = fallback and stable_checks < REQUIRED_STABLE_CHECKS
	return {"pose": estimate, "fallback": used_fallback, "samples": samples.size()}

func _robust_estimate(poses: Array[Transform3D]) -> Transform3D:
	return Transform3D(Basis(_rotation_medoid(poses)), _median_position(poses))


func _median_position(poses: Array[Transform3D]) -> Vector3:
	# Sort X, Y and Z independently and take each middle value.
	# This reduces the influence of isolated extreme readings.
	var xs: Array[float] = []
	var ys: Array[float] = []
	var zs: Array[float] = []
	for pose in poses:
		xs.append(pose.origin.x)
		ys.append(pose.origin.y)
		zs.append(pose.origin.z)
	xs.sort()
	ys.sort()
	zs.sort()
	return Vector3(_median_value(xs), _median_value(ys), _median_value(zs))


func _median_value(values: Array[float]) -> float:
	# Input must already be sorted. For an even count, average the two middle values.
	var upper := floori(float(values.size()) / 2.0)
	if values.size() % 2 == 1:
		return values[upper]
	return (values[upper - 1] + values[upper]) * 0.5


## Choose the measured rotation with the smallest total angular distance to all others.
## This is a medoid: one actual observed rotation, not an average of Euler angles.
func _rotation_medoid(poses: Array[Transform3D]) -> Quaternion:
	var best := poses[0].basis.get_rotation_quaternion().normalized()
	var best_score := INF
	for candidate_pose in poses:
		var candidate := candidate_pose.basis.get_rotation_quaternion().normalized()
		var score := 0.0
		for other_pose in poses:
			score += candidate.angle_to(
				other_pose.basis.get_rotation_quaternion().normalized()
			)
		if score < best_score:
			best_score = score
			best = candidate
	return best
