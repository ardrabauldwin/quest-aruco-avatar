class_name CommonPoseProvider
extends RefCounted
## Reconstructs one 6DOF pose for ID0 common.
##
## Marker names:
##   aruco_patch0 = common (the final target)
##   aruco_patch1 = chest
##   aruco_patch2 = torso
##
## Each marker has a saved marker-to-common offset. A visible marker rebuilds
## ID0 common with:
##
##     marker.global_transform * marker_to_common
##
## Several visible markers are fused. With no visible marker, the last good
## pose is held.

var _offsets := {}
var _common_pose := Transform3D.IDENTITY
var _has_common_pose := false

## How much of the body's rotation to measure, and how much to hold at its calibrated value.
##
## Measuring an angle that cannot change does not discover anything - it only adds that angle's
## measurement noise to the result. And rotation noise is expensive here: the avatar's body reaches
## more than a metre from ID0, so every degree of rotation error becomes about 30 mm of
## misplacement at the head and the feet, against roughly 7 mm of position error. Rotation is the
## dominant term by more than an order of magnitude.
##
## Measured on the 3 August recordings, as wobble of the returned rotation while nothing moved:
##
##     MEASURE_ALL      4.07 deg   ~120 mm at the extremities, and it got worse as the head moved
##     HOLD_CALIBRATED  0    deg     0 mm, because nothing is measured
##
## Position always comes live from the markers, so the avatar still follows the mannequin if it is
## nudged - HOLD_CALIBRATED stops it turning on its own, it does not freeze it in place.
##
## A yaw-only mode used to sit between these two, measuring the turn about world up and holding the
## tilt, at 1.20 deg. It is gone: one axis cannot tell what the mannequin is doing. Laying it down
## is about 90 degrees of TILT and almost no yaw, so the mode both failed to report the largest
## change the body can make and charged 1.20 deg of noise for the privilege. The whole rotation is
## compared instead, which costs nothing and sees every case.
enum Rotation {
	MEASURE_ALL,       ## All three angles from the markers. Correct if the body really can tumble.
	HOLD_CALIBRATED,   ## Hold all three. Needs a button press after the mannequin is turned.
	HOLD_FOLLOW_TURNS, ## Hold all three, but adopt a new facing when the body is really turned.
}

var rotation_mode: int = Rotation.HOLD_FOLLOW_TURNS

## What separates a real move from noise, for HOLD_FOLLOW_TURNS.
##
## Holding the rotation gives no wobble but goes stale the moment the mannequin is moved. Measuring
## it follows the move but never stops wobbling. Neither is necessary: the two are far apart in
## size. The fused rotation wobbles about 4 degrees at worst, while laying a mannequin down or
## turning it on its chair moves it by tens - so a threshold above the noise and far below any
## real move tells them apart with room to spare.
##
## The whole rotation is compared, not just the yaw. Restricting it to yaw was a mistake: laying
## the mannequin down is almost entirely a TILT change, so a yaw-only test sat there insisting
## nothing had happened while the avatar stood upright over a body lying flat.
##
## The hold time is what stops a burst of bad detections from counting as a move. The rotation has
## to stay past the threshold continuously; one wild frame resets it. That is also why 15 degrees
## is safe despite ID2's tilt wobbling up to 9 - noise does not hold still for two thirds of a
## second, and a mannequin that has actually been laid down never comes back under the threshold.
var follow_turn_deg := 15.0
var follow_turn_hold_ms := 700

## How long to average detections for before a held orientation is accepted.
##
## A held rotation is only measured once and then kept, so whatever error it is measured with is
## frozen in rather than averaged away by everything that follows - which is the opposite of how
## the position behaves. Taking one frame hands the hold the full 4.07 deg of single-frame noise.
## Averaging a second of detections instead brings it to about 1.4 deg, and the cost is a second of
## staleness after a real move, during which the position has already followed.
var orientation_average_ms := 1000

## Emitted once a new held orientation has finished settling, so it can be written to disk. Without
## it the orientation would be re-learned from scratch on every launch.
signal orientation_settled

var _turning_since_ms := 0
var _settling: Array[Basis] = []
var _settling_since_ms := 0

var _rest_basis := Basis.IDENTITY
var _has_rest := false

# Samples gathered between begin_calibration() and finish_calibration(): marker -> offsets.
var _calibration_samples := {}
var _calibrating := false


## Save the marker-to-common offset for every supplied marker.
##
## Single-frame calibration. Kept for the other avatar_rig_navel_* variants that call it,
## but prefer begin/add/finish below: one frame is taken from one viewpoint, and a marker's
## pose error is systematic per viewpoint, so the offset inherits that whole error. Averaging
## over many viewpoints is what cancels it.
func calibrate(markers: Array, common_pose: Transform3D) -> void:
	# Deliberately discards the stored orientation rather than leaving it: a full recalibration
	# after the mannequin has been moved must replace it, and an earlier version only filled the
	# orientation in when it was MISSING, so loading a file had already marked it as known and the
	# guard silently kept the old orientation forever.
	recalibrate_orientation()
	for marker in markers:
		if marker != null:
			_offsets[marker] = (
				marker.global_transform.affine_inverse()
				* common_pose
			)


## Start gathering calibration samples. Walk around while this is running.
func begin_calibration() -> void:
	_calibration_samples.clear()
	_calibrating = true


func is_calibrating() -> bool:
	return _calibrating


## Record one marker-to-common offset per visible marker. Call once per NEW detection, not
## once per rendered frame, or standing still would flood the average with duplicates of a
## single viewpoint and defeat the point of averaging.
func add_calibration_sample(markers: Array, common_pose: Transform3D) -> void:
	if not _calibrating:
		return
	# Nothing here touches the orientation: get_pose() settles that on its own from the first
	# second of detections, walk or no walk.
	for marker in markers:
		if marker == null:
			continue
		# Typed, not inferred: the loop variable of an untyped Array is a Variant, so ":=" has
		# nothing to infer from and Godot 4.7 rejects it at parse time.
		var offset: Transform3D = marker.global_transform.affine_inverse() * common_pose
		if not _calibration_samples.has(marker):
			_calibration_samples[marker] = []
		_calibration_samples[marker].append(offset)


## Average the gathered samples into the offsets. Returns how many samples the best-covered
## marker contributed; 0 means nothing was gathered and the old offsets are left untouched.
func finish_calibration() -> int:
	_calibrating = false
	var most := 0
	for marker in _calibration_samples:
		var samples: Array = _calibration_samples[marker]
		if samples.is_empty():
			continue
		_offsets[marker] = _fuse(samples)
		most = maxi(most, samples.size())
	_calibration_samples.clear()
	return most


## How many samples the best-covered marker has so far, for live feedback while gathering.
func calibration_sample_count() -> int:
	var most := 0
	for marker in _calibration_samples:
		most = maxi(most, (_calibration_samples[marker] as Array).size())
	return most


## Rebuild and fuse ID0 common from the visible calibrated markers.
func get_pose(visible_now: Array) -> Transform3D:
	var views: Array[Transform3D] = []

	for marker in visible_now:
		if marker != null and _offsets.has(marker):
			var marker_to_common: Transform3D = _offsets[marker]
			var estimated_common_pose: Transform3D = (
				marker.global_transform * marker_to_common
			)
			views.append(estimated_common_pose)

	if not views.is_empty():
		_common_pose = _hold_tilt(_fuse(views))
		_has_common_pose = true

	return _common_pose


## Relearn which way the body is facing, WITHOUT touching the marker offsets.
##
## These two halves of the calibration go stale for different reasons, so they are worth being
## able to redo separately. The offsets describe markers glued to the mannequin and stay true
## wherever it is carried; the orientation describes where it is standing, and goes stale the
## moment it is turned - or the moment the headset's world frame is recentred, even though nobody
## touched the mannequin. Redoing the whole calibration to fix that would throw away offsets
## averaged over a whole walk and replace them with one frame from one viewpoint.
##
## Takes no pose, and does not finish here: it FORGETS the stored orientation, and the next second
## of detections settles a fresh one and emits orientation_settled. Sampling the instant the button
## went down would hand the hold a single frame's noise to keep - see orientation_average_ms.
func recalibrate_orientation() -> void:
	_has_rest = false
	_settling.clear()
	_turning_since_ms = 0


## Replace as much of the measured rotation as the chosen mode says is not worth measuring.
func _hold_tilt(pose: Transform3D) -> Transform3D:
	if rotation_mode == Rotation.MEASURE_ALL:
		return pose

	# No orientation yet: a first run, or a calibration file written before the orientation was
	# stored. Settle one from the first second of detections rather than handing back the measured
	# rotation forever, which is silently the 4.07 deg MEASURE_ALL case that this mode exists to
	# avoid - and which used to be exactly what an older file got.
	if not _has_rest:
		if not _settle_orientation(pose.basis):
			return pose
		orientation_settled.emit()
		return Transform3D(_rest_basis, pose.origin)

	if rotation_mode == Rotation.HOLD_CALIBRATED:
		return Transform3D(_rest_basis, pose.origin)

	# HOLD_FOLLOW_TURNS: keep handing back the held rotation, and adopt a new one only once the
	# measured rotation has stayed implausibly far away for long enough that a run of bad detections
	# cannot explain it. Until then the output does not move at all, so a real move costs a moment
	# of staleness and normal use costs no wobble.
	#
	# The whole rotation is compared, not its yaw: the difference has to include the tilt, or laying
	# the mannequin down - which is nearly all tilt and almost no yaw - would never register.
	var turned_by := (pose.basis * _rest_basis.inverse()).get_rotation_quaternion()
	var now := Time.get_ticks_msec()
	if turned_by.get_angle() > deg_to_rad(follow_turn_deg):
		if _turning_since_ms == 0:
			_turning_since_ms = now
		elif now - _turning_since_ms >= follow_turn_hold_ms:
			# Settled over a second, not snapshotted: the frame that happens to cross the timer is
			# no more trustworthy than any other, and this one gets kept until the next real move.
			if _settle_orientation(pose.basis):
				_turning_since_ms = 0
				orientation_settled.emit()
	else:
		_turning_since_ms = 0
		_settling.clear()
	return Transform3D(_rest_basis, pose.origin)


## Gather rotations for orientation_average_ms, then average them into _rest_basis.
##
## Returns false while still gathering, so the caller keeps handing back whatever it was already
## using, and true on the single frame the average lands.
func _settle_orientation(basis: Basis) -> bool:
	var settled := basis.orthonormalized()
	# One sample per DETECTION, not per rendered frame. get_pose() is called about nine times more
	# often than OpenCV produces a pose, and the repeats are bit-identical, so counting them would
	# weight each detection by how many frames it happened to span rather than equally.
	if _settling.is_empty():
		_settling_since_ms = Time.get_ticks_msec()
	elif settled.is_equal_approx(_settling[-1]):
		return false
	_settling.append(settled)

	if Time.get_ticks_msec() - _settling_since_ms < orientation_average_ms:
		return false

	var total := Quaternion(0, 0, 0, 0)
	var first := _settling[0].get_rotation_quaternion()
	for sample in _settling:
		var q := sample.get_rotation_quaternion()
		# q and -q are the same rotation, so unaligned signs would cancel into nonsense.
		if first.dot(q) < 0.0:
			q = -q
		total += q
	_rest_basis = Basis(total.normalized())
	_has_rest = true
	_settling.clear()
	return true


## True after the first valid common pose has been calculated.
func is_ready() -> bool:
	return _has_common_pose


## Write the calibration offsets to disk.
func save_to(path: String) -> void:
	var cfg := ConfigFile.new()
	for marker in _offsets:
		cfg.set_value("common", marker.name, _offsets[marker])
	# Saved alongside the offsets because it is part of the same calibration: the offsets say
	# where ID0 is, this says which way the body was lying when they were measured.
	if _has_rest:
		cfg.set_value("body", "rest_basis", _rest_basis)
	cfg.save(path)


## Reload calibration offsets and match them to marker nodes by name.
func load_from(path: String, markers: Array) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false

	_offsets.clear()
	for marker in markers:
		if marker != null and cfg.has_section_key("common", marker.name):
			_offsets[marker] = cfg.get_value("common", marker.name)

	# Older calibration files predate the tilt being stored. Without it the tilt cannot be held,
	# so the pose falls back to the full three-angle rotation until the next calibration.
	_has_rest = cfg.has_section_key("body", "rest_basis")
	if _has_rest:
		_rest_basis = cfg.get_value("body", "rest_basis")

	return not _offsets.is_empty()


## Average several poses. Used both to fuse per-marker estimates of ID0 common, and to
## average calibration offsets. Quaternions are sign-aligned to the first sample first,
## because q and -q are the same rotation and would otherwise cancel to nonsense.
func _fuse(poses: Array) -> Transform3D:
	var position := Vector3.ZERO
	var rotation := Quaternion(0, 0, 0, 0)
	var first: Quaternion = poses[0].basis.get_rotation_quaternion()

	for pose in poses:
		position += pose.origin
		var q: Quaternion = pose.basis.get_rotation_quaternion()
		if first.dot(q) < 0.0:
			q = -q
		rotation += q

	return Transform3D(
		Basis(rotation.normalized()),
		position / poses.size()
	)
