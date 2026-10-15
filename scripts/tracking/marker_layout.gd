class_name NaretMarkerLayout
extends RefCounted
## Combines visible markers into one estimated chest anchor in room coordinates.
## A pose contains a position and a rotation. All distances here are in metres.
## This script does not detect markers or smooth their movement.

# When enabled, keep the body horizontal. This changes rotation, not height.
var floor_orientation := false
var marker_size_m := 0.10
# For each marker ID: the saved transform from that marker to the common anchor.
var offsets: Dictionary = {}
# Converts the common anchor's coordinate system to the patient's sternum anchor.
# The patient's model alignment is handled separately by spatial_anchor.gd.
var common_to_sternum := Transform3D.IDENTITY

static func rigid(pose: Transform3D) -> bool:
	# Reject invalid numbers, mirrored axes and scaling. We need position + rotation only.
	return pose.is_finite() and pose.basis.determinant() > 0.0 \
		and pose.basis.is_equal_approx(pose.basis.orthonormalized())

func load_profile(path: String) -> Error:
	var cfg := ConfigFile.new()
	var error := cfg.load(path)
	if error != OK:
		return error
	# 1. Read and validate the common-to-sternum transform and physical marker size.
	if not cfg.has_section_key("layout", "common_to_sternum"):
		return ERR_INVALID_DATA
	var bridge: Variant = cfg.get_value("layout", "common_to_sternum")
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
	# 3. Replace the current calibration only after the entire file passes validation.
	floor_orientation = bool(cfg.get_value("layout", "floor_orientation", false))
	offsets = loaded_offsets
	marker_size_m = size
	common_to_sternum = bridge
	return OK

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
		# In the old marker frame, local Y points along the body and local Z down.
		var along := common.basis.y.slide(Vector3.UP)
		if along.length_squared() < 0.000001:
			return {} # A nearly vertical body axis gives no reliable horizontal heading.
		along = along.normalized()
		common.basis = Basis(along.cross(Vector3.DOWN).normalized(), along, Vector3.DOWN)
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
