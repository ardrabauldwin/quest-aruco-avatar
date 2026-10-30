class_name NaretMarkerLayout
extends RefCounted
## Combines visible markers into one estimated chest anchor in room coordinates.
## A pose contains a position and a rotation. All distances here are in metres.
## This script does not detect markers or smooth their movement.

# When enabled, keep the body horizontal. This changes rotation, not height.
var floor_orientation := false
var marker_size_m := 0.10
# All in-memory common anchors use patient-style axes: +Y up, +Z along the
# body, -Z toward the head (before any separately saved model rotation).
# For each marker ID: the transform from that marker to this common anchor.
var offsets: Dictionary = {}
# Optional physical common-to-chest calibration, not a required axis adapter.
# The patient's model alignment is handled separately by spatial_anchor.gd.
var common_to_sternum := Transform3D.IDENTITY
# Where a "marker_centroid" profile moved the common point, in its saved frame.
var common_shift := Vector3.ZERO
const SAVED_COMMON_POINT := "as_saved"
const MARKER_CENTROID := "marker_centroid"
const PATIENT_FRAME := "patient_y_up"
const LEGACY_FRAME := "legacy_z_down"
# Used only while importing an old profile, never in the standard fusion path.
const LEGACY_TO_PATIENT := Transform3D(Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3.ZERO)
const LEGACY_ANCHOR_FLIP := Transform3D(Basis(Vector3.RIGHT, Vector3.DOWN, Vector3.FORWARD), Vector3.ZERO)

static func rigid(pose: Transform3D) -> bool:
	# Reject invalid numbers, mirrored axes and scaling. We need position + rotation only.
	return pose.is_finite() and pose.basis.determinant() > 0.0 \
		and pose.basis.is_equal_approx(pose.basis.orthonormalized())

func load_profile(path: String) -> Error:
	var cfg := ConfigFile.new()
	var error := cfg.load(path)
	if error != OK:
		return error
	# 1. New profiles already use patient axes. Unlabelled older profiles need
	# their explicit bridge so their output pose can be preserved on import.
	var frame := str(cfg.get_value("layout", "common_frame", LEGACY_FRAME))
	if frame not in [PATIENT_FRAME, LEGACY_FRAME]:
		return ERR_INVALID_DATA
	if frame == LEGACY_FRAME and not cfg.has_section_key("layout", "common_to_sternum"):
		return ERR_INVALID_DATA
	var common_point := str(cfg.get_value("layout", "common_point", SAVED_COMMON_POINT))
	if common_point not in [SAVED_COMMON_POINT, MARKER_CENTROID]:
		return ERR_INVALID_DATA
	var bridge: Variant = cfg.get_value("layout", "common_to_sternum", Transform3D.IDENTITY)
	var size := float(cfg.get_value("layout", "marker_size_m", 0.0))
	if not bridge is Transform3D or not rigid(bridge) or not is_finite(size) or size < 0.01 or size > 0.30:
		return ERR_INVALID_DATA
	# 2. Read each marker's saved offset. DICT_4X4_50 has IDs 0 through 49.
	var loaded_offsets := {}
	for id in range(50):
		var key := "aruco_patch%d" % id
		if cfg.has_section_key("common", key):
			var offset: Variant = cfg.get_value("common", key)
			if not offset is Transform3D or not rigid(offset):
				return ERR_INVALID_DATA
			loaded_offsets[id] = offset
	if loaded_offsets.is_empty():
		return ERR_INVALID_DATA
	if frame == LEGACY_FRAME:
		for id in loaded_offsets:
			loaded_offsets[id] = (loaded_offsets[id] as Transform3D) * LEGACY_TO_PATIENT
		bridge = LEGACY_TO_PATIENT.affine_inverse() * (bridge as Transform3D) * LEGACY_ANCHOR_FLIP
	# 3. Saved offsets may all point at one marker. Move them to the middle of the
	# marker centres, so the common point stays there whichever markers are visible.
	var shift := _marker_centroid(loaded_offsets) if common_point == MARKER_CENTROID else Vector3.ZERO
	for id in loaded_offsets:
		loaded_offsets[id] = (loaded_offsets[id] as Transform3D) * Transform3D(Basis.IDENTITY, shift)
	# 4. Replace the current calibration only after the entire file passes validation.
	floor_orientation = bool(cfg.get_value("layout", "floor_orientation", false))
	offsets = loaded_offsets
	common_shift = shift
	marker_size_m = size
	common_to_sternum = bridge
	return OK

func _marker_centroid(marker_offsets: Dictionary) -> Vector3:
	var sum := Vector3.ZERO
	for id in marker_offsets:
		sum += (marker_offsets[id] as Transform3D).affine_inverse().origin
	return sum / marker_offsets.size()

func fuse(world_poses: Dictionary) -> Dictionary:
	# 1. Make every visible marker estimate the SAME common anchor.
	# Example: marker 1's position is not marker 0's position; its saved offset
	# tells us how to reach the common anchor from marker 1.
	var estimates: Array[Transform3D] = []
	var used: Array[int] = []
	for id in world_poses:
		if not offsets.has(id):
			continue
		var pose: Transform3D = world_poses[id]
		if not rigid(pose):
			continue
		estimates.append(pose * offsets[id])
		used.append(id)
	if estimates.is_empty():
		# No usable marker: do not provide a new placement.
		return {}
	# 2. Average the common-anchor estimates. One marker also works by itself.
	var common := _average_pose(estimates)
	# 3. Report the largest distance from an estimate to the average.
	# This is marker disagreement, not proof of accuracy and not a rejection rule.
	var spread := 0.0
	for pose in estimates:
		spread = maxf(spread, pose.origin.distance_to(common.origin))
	if floor_orientation:
		# 4. Flatten the body direction onto the horizontal plane.
		# Common and patient anchors now share +Y up and +Z along the body.
		var along := common.basis.z.slide(Vector3.UP)
		if along.length_squared() < 0.000001:
			return {} # A nearly vertical body axis gives no reliable horizontal heading.
		along = along.normalized()
		common.basis = Basis(Vector3.UP.cross(along).normalized(), Vector3.UP, along)
	# 5. Return the patient's anchor, contributing marker IDs and disagreement.
	return {
		"pose": common * common_to_sternum,
		"ids": used,
		"position_spread_m": spread,
	}

func _average_pose(poses: Array[Transform3D]) -> Transform3D:
	var position_sum := Vector3.ZERO
	var rotation_sum := Quaternion(0, 0, 0, 0)
	var reference_rotation := poses[0].basis.get_rotation_quaternion()
	for pose in poses:
		position_sum += pose.origin
		var rotation := pose.basis.get_rotation_quaternion()
		# A quaternion and its negative describe the same rotation.
		# Give them matching signs so they do not cancel when we add them.
		if rotation.dot(reference_rotation) < 0:
			rotation = -rotation
		rotation_sum += rotation
	var average_position := position_sum / poses.size()
	var average_rotation := rotation_sum.normalized()
	return Transform3D(Basis(average_rotation), average_position)
