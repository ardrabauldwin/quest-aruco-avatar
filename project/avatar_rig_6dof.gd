extends Node3D
# FULL-6DOF avatar placement.
#
# Paul's pipeline gives each ArUco marker a complete 6DOF world pose T_i = (R_i, p_i).
# If we also know where that marker is MOUNTED on the model -- its model-space pose M_i -- then a
# single marker already determines the whole avatar:
#
#     T_avatar^(i) = T_i * M_i^-1
#
# With two markers we get TWO independent estimates and fuse them (average), which uses every DOF
# of both markers and is steadier than trusting either alone.
#
#     T_avatar = fuse( T_H * M_H^-1 ,  T_C * M_C^-1 )
#
# THE MOUNTS ARE THE CALIBRATION. M_i cannot be derived from tracking -- the camera sees where the
# marker is in the room, never where it sits on the body. Supply it one of three ways:
#   1. place a Node3D on the model at the marker's spot (assign below)   <- manual, what we do here
#   2. a rigged model: skeleton.get_bone_global_pose(bone)               <- automatic, needs bones
#   3. one-time calibration: align by hand once, save the transform      <- automatic afterwards

@export var head_marker: Node3D          # aruco_patch0 (id 0), world pose from main_3d
@export var chest_marker: Node3D         # aruco_patch1 (id 1)

# The MOUNTS: Node3Ds parented under the model, sitting exactly where each physical marker is stuck
# (and rotated the same way the marker is). Their local transform IS M_i.
@export var head_mount: Node3D
@export var chest_mount: Node3D

# Reject a pose that jumps more than this in one frame -- a planar-marker flip, not real motion.
@export var max_jump_degrees := 45.0
# Rotation smoothing. Higher = snappier. Position is snapped.
@export var follow_speed := 60.0

var _placed := false
var _rot := Quaternion.IDENTITY
var _h_seen := false
var _c_seen := false
var _last_h := Vector3.INF
var _last_c := Vector3.INF

# The avatar pose implied by ONE marker: T_avatar = T_marker * M_mount^-1
func _pose_from(marker: Node3D, mount: Node3D) -> Transform3D:
	return marker.global_transform * mount.transform.affine_inverse()

func _process(delta: float) -> void:
	if head_marker == null or chest_marker == null or head_mount == null or chest_mount == null:
		return

	# Only place the avatar once both markers have genuinely been detected.
	if not head_marker.global_position.is_equal_approx(_last_h): _h_seen = true
	if not chest_marker.global_position.is_equal_approx(_last_c): _c_seen = true
	_last_h = head_marker.global_position
	_last_c = chest_marker.global_position
	if not (_h_seen and _c_seen):
		visible = false
		return
	visible = true

	# Two independent estimates of the SAME rigid body, from each marker's full 6DOF.
	var t_h := _pose_from(head_marker, head_mount)
	var t_c := _pose_from(chest_marker, chest_mount)

	# Fuse: mean position, slerped rotation. (They should agree; disagreement = tracking error.)
	var q_h := t_h.basis.get_rotation_quaternion()
	var q_c := t_c.basis.get_rotation_quaternion()
	var rot_q := q_h.slerp(q_c, 0.5)
	var pos := (t_h.origin + t_c.origin) * 0.5

	# Outlier gate: a real body cannot swing this far in one frame -> it's a marker pose flip.
	if _placed and rad_to_deg(_rot.angle_to(rot_q)) > max_jump_degrees:
		return

	if not _placed or follow_speed <= 0.0:
		_rot = rot_q
		_placed = true
	else:
		_rot = _rot.slerp(rot_q, clampf(follow_speed * delta, 0.0, 1.0))

	global_transform = Transform3D(Basis(_rot), pos)
