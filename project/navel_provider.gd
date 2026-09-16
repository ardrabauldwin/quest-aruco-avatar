class_name CommonPoseProvider
extends RefCounted
## Reconstructs one common 6DOF pose from any calibrated markers in the newest result.

signal orientation_settled

# Rest checkpoints selected by the 2026-09-04 grid run (identical winner across both the
# 105 mm-assumed and 617.5 mm-corrected searches): E0 at 30 detections, then every 3.
# Earliest confirmation is detection 42 (4 consecutive stable checks).
var rest_initial_detections := 30
var rest_checkpoint_step := 3
var rest_required_stable_checks := 4
var rest_max_detections := 100
var rest_stable_position_m := 0.0015
var rest_stable_rotation_deg := 1.0

var _offsets := {}
var _common_pose := Transform3D.IDENTITY
var _has_common_pose := false

var _rest_pose := Transform3D.IDENTITY
var _has_rest_pose := false
var _rest_collecting := true
var _rest_samples: Array[Transform3D] = []
var _rest_last_detection_ms := -1
var _rest_next_checkpoint := 20
var _rest_previous_estimate := Transform3D.IDENTITY
var _rest_has_previous_estimate := false
var _rest_stable_checks := 0
var _rest_reanchor_last_detection_ms := -1
## Estimates whose down axis tilts more than this from world down are mirror solutions (see
## _is_flipped). Good markers on the mannequin measure 5-25 deg, flipped ones 85-95 deg.
var max_flip_tilt_deg := 45.0
var rejected_flips := 0
## Optional per-marker fusion weight (marker node -> weight, default 1). The common marker is the
## most consistent of the three across viewpoints (2026-09-15 recordings), so the rig may weight it up.
var marker_weights := {}
## How long a flipped marker may be replaced by its own last good pose (ms). The mannequin is
## static, so a one-second-old good pose is a better measurement than none; on the 2026-09-15
## recordings this halved the far-left wobble (6 -> 4 cm) and changed nothing at 1.7 m.
var flip_hold_ms := 1000
var held_flips := 0
var _last_good := {}


## Each independent detection contributes one estimate of the same common point.
## Inferred missing markers contain no new measurement and must not be fused again.
func get_pose(markers: Array, detection_ms: int = -1) -> Transform3D:
	var estimates: Array[Transform3D] = []
	var weights: Array[float] = []
	for marker in markers:
		if marker != null and _offsets.has(marker):
			var marker_to_common: Transform3D = _offsets[marker]
			var estimate: Transform3D = marker.global_transform * marker_to_common
			if _is_flipped(estimate):
				rejected_flips += 1
				# The mannequin does not move: this marker's last good pose is still a valid
				# measurement for a short while, and keeping it stops the average from collapsing
				# onto whichever single marker happens not to flip from this viewpoint.
				var last: Dictionary = _last_good.get(marker, {})
				if not last.is_empty() and detection_ms >= 0 and detection_ms - int(last["ms"]) <= flip_hold_ms:
					estimates.append(last["pose"])
					weights.append(float(marker_weights.get(marker, 1.0)))
					held_flips += 1
				continue
			if detection_ms >= 0:
				_last_good[marker] = {"pose": estimate, "ms": detection_ms}
			estimates.append(estimate)
			weights.append(float(marker_weights.get(marker, 1.0)))
	if estimates.is_empty():
		return _common_pose
	_common_pose = _floor_lock(_fuse(estimates, weights))
	_has_common_pose = true
	_update_rest(_common_pose, detection_ms)
	return _common_pose


func is_ready() -> bool:
	return _has_common_pose


func rest_pose() -> Transform3D:
	return _rest_pose


func has_rest_pose() -> bool:
	return _has_rest_pose


## Forget only the session rest pose. Permanent marker offsets remain unchanged.
func recalibrate_orientation() -> void:
	_restart_rest_collection()


func _update_rest(measured_pose: Transform3D, detection_ms: int) -> void:
	if _rest_collecting:
		if _collect_rest_sample(measured_pose, detection_ms):
			orientation_settled.emit()
		return

	# Once startup rest exists, only the stabilizer's confirmed stable endpoint may change it.
	# Never educate rest from this raw fused pose.


## Returns true once the checkpoint rule confirms rest or reaches its robust fallback.
func _collect_rest_sample(pose: Transform3D, detection_ms: int) -> bool:
	if not _is_new_detection(pose, detection_ms):
		return false

	_rest_samples.append(pose.orthonormalized())
	var sample_count := _rest_samples.size()
	var at_checkpoint := sample_count >= _rest_next_checkpoint
	var reached_fallback := sample_count >= maxi(rest_max_detections, 1)
	# Fallback is an exact sample budget. It must not wait for the next checkpoint when a future
	# grid result chooses values such as initial=15, step=8, fallback=50.
	if not at_checkpoint and not reached_fallback:
		return false

	var estimate := _robust_estimate(_rest_samples)
	_rest_pose = estimate
	if at_checkpoint:
		_update_stability_count(estimate)
		_rest_previous_estimate = estimate
		_rest_has_previous_estimate = true
		_rest_next_checkpoint += maxi(rest_checkpoint_step, 1)

	var converged := _rest_stable_checks >= rest_required_stable_checks
	if not converged and not reached_fallback:
		return false

	_has_rest_pose = true
	_rest_collecting = false
	_rest_samples.clear()
	if reached_fallback and not converged:
		push_warning(
			"Common pose: rest estimates did not converge; using robust %d-detection fallback."
			% rest_max_detections
		)
	return true


## Accept exactly one rest sample per OpenCV result.
func _is_new_detection(pose: Transform3D, detection_ms: int) -> bool:
	if detection_ms >= 0:
		if detection_ms == _rest_last_detection_ms:
			return false
		_rest_last_detection_ms = detection_ms
		return true

	return _rest_samples.is_empty() or not pose.is_equal_approx(_rest_samples[-1])


func _update_stability_count(estimate: Transform3D) -> void:
	if not _rest_has_previous_estimate:
		return

	var position_change := estimate.origin.distance_to(_rest_previous_estimate.origin)
	var rotation_change_deg := rad_to_deg(
		estimate.basis.get_rotation_quaternion().angle_to(
			_rest_previous_estimate.basis.get_rotation_quaternion()
		)
	)
	if (
		position_change <= rest_stable_position_m
		and rotation_change_deg <= rest_stable_rotation_deg
	):
		_rest_stable_checks += 1
	else:
		_rest_stable_checks = 0


## Adopt the stable measurement-only medoid after the complete target window becomes stationary.
## Position and rotation are updated independently, exactly once per result.
func reanchor_rest_from_stable_target(
		measured_pose: Transform3D,
		detection_ms: int,
		reanchor_position: bool,
		reanchor_rotation: bool
) -> bool:
	if not _has_rest_pose or _rest_collecting:
		return false
	if detection_ms < 0 or detection_ms == _rest_reanchor_last_detection_ms:
		return false
	if not reanchor_position and not reanchor_rotation:
		return false
	_rest_reanchor_last_detection_ms = detection_ms

	var next_position := measured_pose.origin if reanchor_position else _rest_pose.origin
	var next_rotation := (
		measured_pose.basis.get_rotation_quaternion().normalized()
		if reanchor_rotation
		else _rest_pose.basis.get_rotation_quaternion().normalized()
	)
	_rest_pose = Transform3D(Basis(next_rotation), next_position)
	return true


func _restart_rest_collection() -> void:
	_has_rest_pose = false
	_rest_collecting = true
	_rest_samples.clear()
	_rest_last_detection_ms = -1
	_rest_next_checkpoint = maxi(rest_initial_detections, 1)
	_rest_previous_estimate = Transform3D.IDENTITY
	_rest_has_previous_estimate = false
	_rest_stable_checks = 0
	_rest_reanchor_last_detection_ms = -1


func _robust_estimate(poses: Array[Transform3D]) -> Transform3D:
	return Transform3D(Basis(_rotation_medoid(poses)), _median_position(poses))


func _median_position(poses: Array[Transform3D]) -> Vector3:
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
	var upper := floori(float(values.size()) / 2.0)
	if values.size() % 2 == 1:
		return values[upper]
	return (values[upper - 1] + values[upper]) * 0.5


## Choose the measured rotation with the smallest total angular distance to all others.
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


## Residual range error after the constant fx scale: the marker range reads right at ~1.2 m and
## too LONG beyond it, by RANGE_CORRECTION_K per metre of extra range (viewpoint recordings
## 2026-09-15, both sessions, common and navel: +5.8..+5.9 cm per m; joint fit k = 0.064,
## zero at 1.20 m). That is the "avatar retreats when I step back". Applied to the camera-space
## marker translation before it is baked to world (main_3d.gd and the replay), it leaves the
## common and navel markers within 1 cm of their close-range position out to 2.2 m. The chest
## marker keeps an extra, steeper error beyond 1.6 m that this does not model.
const RANGE_CORRECTION_K := 0.064
const RANGE_CORRECTION_R0 := 1.20


static func range_correct(ray_cam: Vector3) -> Vector3:
	var r := ray_cam.length()
	if r <= RANGE_CORRECTION_R0:
		return ray_cam
	return ray_cam * (1.0 - RANGE_CORRECTION_K * (r - RANGE_CORRECTION_R0) / r)


## Planar-marker pose ambiguity: seen at a glancing angle (side views, 1.5 m+) solvePnP sometimes
## returns the mirror solution. Its normal is then ~90 deg from where a marker lying on the
## mannequin can point, its heading 30-40 deg off and its position 12-14 cm off (viewpoint
## recording 2026-09-15: common flipped in 33% of left-view samples, chest in 86% of right-view
## samples). Averaged in, one flipped marker moves the avatar by a third of that, which was the
## side-view slide and the occasional turn. A mannequin marker always faces up, so an estimate
## whose down axis is more than max_flip_tilt_deg from world down is not a measurement.
func _is_flipped(estimate: Transform3D) -> bool:
	var down := estimate.basis.z.normalized()
	return down.angle_to(Vector3.DOWN) > deg_to_rad(max_flip_tilt_deg)


## Enforce the CPR domain rule: the marker/common local Y axis lies along the mannequin on the
## floor and local Z points down. The down sign matches the mannequin child's fixed -90 degree
## import correction so the avatar lies face-up. Only measured horizontal heading is retained.
func _floor_lock(pose: Transform3D) -> Transform3D:
	var up := Vector3.UP
	var body_z := Vector3.DOWN
	var body_y := pose.basis.y.slide(up)
	if body_y.length_squared() < 1.0e-6:
		# A nearly vertical body axis is an unusable ArUco orientation. Keep the last valid heading
		# when possible; before the first valid result, use a deterministic horizontal fallback.
		body_y = _common_pose.basis.y.slide(up) if _has_common_pose else Vector3.FORWARD
	body_y = body_y.normalized()
	var body_x := body_y.cross(body_z).normalized()
	var flat_basis := Basis(body_x, body_y, body_z).orthonormalized()
	# Floor locking constrains orientation only. Marker position remains untouched.
	return Transform3D(flat_basis, pose.origin)


## Fuse the common-pose estimates produced by same-frame markers.
func _fuse(poses: Array[Transform3D], weights: Array[float] = []) -> Transform3D:
	# Symmetric sign-aligned mean for every marker count: steadier than median/medoid while all
	# markers are good, at the cost of absorbing 1/3 of a corrupted marker's error. The robust
	# alternative stays in _robust_estimate (still used for rest collection) until the labelled
	# experiment compares mean, robust and agreement-checked mean.
	var position := Vector3.ZERO
	var rotation := Quaternion(0, 0, 0, 0)
	var first_rotation := poses[0].basis.get_rotation_quaternion()
	var total_weight := 0.0

	for i in poses.size():
		var pose := poses[i]
		var w: float = weights[i] if i < weights.size() else 1.0
		position += pose.origin * w
		var pose_rotation := pose.basis.get_rotation_quaternion()
		if first_rotation.dot(pose_rotation) < 0.0:
			pose_rotation = -pose_rotation
		rotation += pose_rotation * w
		total_weight += w

	return Transform3D(Basis(rotation.normalized()), position / total_weight)


## Persist marker-local offsets only. World-space rest is relearned every XR session.
func save_to(path: String) -> void:
	var cfg := ConfigFile.new()
	for marker in _offsets:
		cfg.set_value("common", marker.name, _offsets[marker])
	cfg.save(path)


func load_from(path: String, markers: Array) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false

	# Validate the complete file before replacing a previously loaded calibration. A partial user
	# file must fail so the caller can fall back to the bundled complete calibration.
	var loaded_offsets := {}
	var required_markers := 0
	for marker in markers:
		if marker == null:
			continue
		required_markers += 1
		if not cfg.has_section_key("common", marker.name):
			return false
		var value: Variant = cfg.get_value("common", marker.name)
		if typeof(value) != TYPE_TRANSFORM3D:
			return false
		loaded_offsets[marker] = value

	if required_markers == 0 or loaded_offsets.size() != required_markers:
		return false

	_offsets = loaded_offsets
	_restart_rest_collection()
	return true
