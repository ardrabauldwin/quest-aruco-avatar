class_name NaretScanFitTouch
extends Node
## Lines the 1:1 mannequin scan up with the real mannequin using both tracked
## hands. After the key press the trainee has WAIT_S to place them:
## "edge": both hands below the torso's cut-off, pinkies against the cut face;
## "sides": one hand left and one right of the torso, index fingers against it.
## The last SAMPLE_S of the wait are averaged; a hand that moved more than
## STILL_M in that window or was not tracked fails the measurement.

signal measured(kind: String, hands: Array)
signal failed(kind: String)

const WAIT_S := 4.0
const SAMPLE_S := 1.0
const STILL_M := 0.015
const MIN_SAMPLES := 10
const JOINTS := {
	"edge": [XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP],
	"sides": [XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP],
}

var active := false
var kind := ""
var _origin: XROrigin3D
var _elapsed := 0.0
var _samples: Array = [[], []]
var _radii: Array = [PackedFloat32Array(), PackedFloat32Array()]

func start(origin: XROrigin3D, fit: String) -> void:
	_origin = origin
	kind = fit
	_elapsed = 0.0
	_samples = [[], []]
	_radii = [PackedFloat32Array(), PackedFloat32Array()]
	active = true

func seconds_left() -> int:
	return ceili(WAIT_S - _elapsed) if active else 0

func _process(delta: float) -> void:
	if not active or _origin == null:
		return
	_elapsed += delta
	if _elapsed >= WAIT_S - SAMPLE_S:
		for index in 2:
			var hand := NaretXRInteraction.hand_tracker(index)
			var points := PackedVector3Array()
			var radii := PackedFloat32Array()
			for joint: int in JOINTS[kind]:
				var pose: Variant = NaretXRInteraction.tracked_joint(hand, joint) if hand else null
				if pose == null:
					break
				points.append(_origin.global_transform * (pose as Transform3D).origin)
				radii.append(hand.get_hand_joint_radius(joint) * _origin.global_basis.get_scale().x)
			if points.size() == JOINTS[kind].size():
				_samples[index].append(points)
				_radii[index] = radii
	if _elapsed < WAIT_S:
		return
	active = false
	var hands := []
	for index in 2:
		var mean := average(_samples[index])
		if mean.is_empty():
			print("NARET_SCAN_FIT_TOUCH kind=%s hand=%d samples=%d rejected" % [kind, index, _samples[index].size()])
			failed.emit(kind)
			return
		var joints := []
		for j in mean.size():
			joints.append({"position": mean[j], "radius": _radii[index][j]})
		hands.append(joints)
	print("NARET_SCAN_FIT_TOUCH kind=%s left=%s right=%s" % [kind, hands[0][0].position, hands[1][0].position])
	measured.emit(kind, hands)

static func shift(fit: String, hands: Array, scan: PackedVector3Array) -> Vector3:
	## Pure: how far the scan has to move, in mannequin space (-Z toward the head,
	## +X to one side), so it meets the measured fingers. `hands` holds each hand's
	## joints in that space; `scan` the scan's vertices. Only the measured axis moves.
	if hands.size() != 2 or scan.is_empty():
		return Vector3.ZERO
	if fit == "edge":
		# Per hand the pinky joint nearest the torso; its side touches the cut face.
		var contact := Vector3.ZERO
		for joints: Array in hands:
			var nearest: Dictionary = joints[0]
			for joint: Dictionary in joints:
				if (joint.position as Vector3).z < (nearest.position as Vector3).z:
					nearest = joint
			contact += ((nearest.position as Vector3) - Vector3(0, 0, nearest.radius)) * 0.5
		# The scan's lowest edge at the pinkies' height; the whole scan if none lies there.
		var edge := band_extent(scan, contact, Vector3(INF, 0.04, INF), 2)
		return Vector3(0, 0, contact.z - edge.y) if is_finite(edge.y) else Vector3.ZERO
	# Index tips on opposite sides: their radii cancel in the midpoint.
	var middle: Vector3 = ((hands[0][0].position as Vector3) + (hands[1][0].position as Vector3)) * 0.5
	var sides := band_extent(scan, middle, Vector3(INF, 0.04, 0.03), 0)
	return Vector3(middle.x - (sides.x + sides.y) * 0.5, 0, 0) if is_finite(sides.x) else Vector3.ZERO

static func band_extent(points: PackedVector3Array, around: Vector3, band: Vector3, axis: int) -> Vector2:
	## Min and max along `axis` of the points within `band` of `around` on the
	## other axes; falls back to all points when the band is empty.
	var low := INF
	var high := -INF
	for point in points:
		var gap := (point - around).abs()
		if gap.x > band.x or gap.y > band.y or gap.z > band.z:
			continue
		low = minf(low, point[axis])
		high = maxf(high, point[axis])
	if is_finite(low):
		return Vector2(low, high)
	for point in points:
		low = minf(low, point[axis])
		high = maxf(high, point[axis])
	return Vector2(low, high)

static func average(samples: Array) -> PackedVector3Array:
	## Pure so the acceptance rule is testable without a headset: the mean joint
	## positions, or empty when too few samples or one strayed beyond STILL_M.
	if samples.size() < MIN_SAMPLES:
		return PackedVector3Array()
	var mean := PackedVector3Array()
	mean.resize((samples[0] as PackedVector3Array).size())
	for points: PackedVector3Array in samples:
		for j in mean.size():
			mean[j] += points[j] / samples.size()
	for points: PackedVector3Array in samples:
		for j in mean.size():
			if points[j].distance_to(mean[j]) > STILL_M:
				return PackedVector3Array()
	return mean
