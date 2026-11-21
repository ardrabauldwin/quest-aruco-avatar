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
## 14 Nov 2026: a third way to finish, by time. With the manikin on the floor and the
## trainee standing, the marker is small and seen at a slant: about 1.5 readings a
## second, each a few centimetres off the last (headset log, x from 0.24 to 0.31 m). The
## estimate then never settles to 1.5 mm, and 100 readings take over a minute, during
## which only the marker gizmo shows ("stuck in the gizmo"). Once the marker has been
## read at least TIMED_MIN_SAMPLES times over TIMED_FALLBACK_MS, the median of what was
## collected is taken. It is reported as a fallback: good enough to start, not as exact
## as a settled estimate. A clear, close view still finishes at 42 readings in about a
## second and a half, as before.
##
## 20 Nov 2026 (headset, late evening, dim room): the marker was read only about once a
## second, for 7 s, and then the trainee looked at the hand menu. Fewer than 10 readings had
## come in, so the patient was never placed ("why no avatar placement"). Five readings over
## three seconds are now enough; the later tracking still refines the place.
const TIMED_FALLBACK_MS := 3000
const TIMED_MIN_SAMPLES := 5

# Keep all startup samples, not just the last five. Each checkpoint re-estimates
# the position and rotation from everything collected during this setup.
var samples: Array[Transform3D] = []
var last_ms := -1
var next_checkpoint := FIRST_CHECKPOINT
var previous := Transform3D.IDENTITY
var have_previous := false
var stable_checks := 0
var used_fallback := false
var first_ms := -1

func observe(pose: Transform3D, detection_ms: int) -> Dictionary:
	# 1. A rendered frame is not necessarily a new camera detection.
	# Ignore repeated/older timestamps and malformed poses.
	if detection_ms <= last_ms or not NaretMarkerLayout.rigid(pose):
		return {}
	last_ms = detection_ms
	if first_ms < 0: first_ms = detection_ms
	samples.append(pose.orthonormalized())
	var checkpoint := samples.size() >= next_checkpoint
	var fallback := samples.size() >= FALLBACK_SAMPLES 		or (samples.size() >= TIMED_MIN_SAMPLES and detection_ms - first_ms >= TIMED_FALLBACK_MS)
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
	# The main marker pipeline floor-locks before collecting these samples.
	# For horizontal samples only heading remains: compare circular yaw angles,
	# not full quaternions. Standalone non-floor-locked inputs retain 3D support.
	var horizontal := true
	for pose in poses:
		if not pose.basis.y.is_equal_approx(Vector3.UP):
			horizontal = false
			break
	var orientation: Basis
	if horizontal:
		orientation = Basis(Vector3.UP, _yaw_medoid(poses))
	else:
		orientation = Basis(_rotation_medoid(poses))
	return Transform3D(orientation, _median_position(poses))


## Choose one observed heading with the least summed circular angular distance.
## Read common +Z: Basis(UP, yaw) reconstructs that same orientation, without
## a 180-degree forward/-Z convention change. Position is estimated separately.
func _yaw_medoid(poses: Array[Transform3D]) -> float:
	var headings: Array[float] = []
	for pose in poses:
		headings.append(atan2(pose.basis.z.x, pose.basis.z.z))
	var best := headings[0]
	var best_score := INF
	for candidate in headings:
		var score := 0.0
		for other in headings:
			score += absf(wrapf(candidate - other, -PI, PI))
		if score < best_score:
			best_score = score
			best = candidate
	return best


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
