extends Node3D
# Placement = "average, then ONE offset" (your simplification of the two-mount 6DOF).
#
#   1. average the two markers' positions  -> a stable midpoint on the body
#   2. shift that midpoint by ONE model offset (rotated) -> the avatar lands on the body,
#      not on the mesh's arbitrary origin
#   3. rotation = the two markers' rotations averaged, + a fixed model twist
#   4. real 1:1 size (no distance scaling)
#
# This is mathematically identical (for position) to placing two mounts and averaging the two
# marker*mount^-1 estimates, because  1/2(p_H - R m_H) + 1/2(p_C - R m_C) = midpoint - R*offset,
# where offset = the midpoint between where the two markers sit on the model. Half the setup:
# ONE anchor point instead of two mounts.

@export var head_marker: Node3D          # aruco_patch0 (id 0)
@export var chest_marker: Node3D         # aruco_patch1 (id 1)
# ONE offset: the model-local point that sits at the MIDPOINT between where the two markers are
# stuck. The marker-midpoint is shifted by this (rotated) so the avatar body lands correctly.
# Estimated from the mesh; assign anchor_point below to override with a placed node.
@export var anchor_offset := Vector3(0.0195, 0.227, -0.0975)
# Optional: a Node3D placed on the model at that midpoint. If set, it overrides anchor_offset
# (read live -> nudging the node moves the avatar, no numbers typed).
@export var anchor_point: Node3D
# Fixed twist so the model's axes line up with the markers.
@export var extra_rotation_degrees := Vector3(-90, 0, 0)
# Rotation smoothing. Higher = snappier; 0 = instant. Position is snapped.
@export var follow_speed := 60.0

var _placed := false
var _rot := Quaternion.IDENTITY
var _h_seen := false
var _c_seen := false
var _last_h := Vector3.INF
var _last_c := Vector3.INF

func _process(delta: float) -> void:
	if head_marker == null or chest_marker == null:
		return
	var h := head_marker.global_transform
	var c := chest_marker.global_transform

	# Show only once both markers have actually been detected (their patch node moved).
	if not h.origin.is_equal_approx(_last_h): _h_seen = true
	if not c.origin.is_equal_approx(_last_c): _c_seen = true
	_last_h = h.origin
	_last_c = c.origin
	if not (_h_seen and _c_seen):
		visible = false
		return
	visible = true

	# Rotation: average the two markers, then the fixed model twist.
	var avg := h.basis.get_rotation_quaternion().slerp(c.basis.get_rotation_quaternion(), 0.5)
	var rot_q := (Basis(avg) * Basis.from_euler(extra_rotation_degrees * (PI / 180.0))).get_rotation_quaternion()
	if not _placed or follow_speed <= 0.0:
		_rot = rot_q
		_placed = true
	else:
		_rot = _rot.slerp(rot_q, clampf(follow_speed * delta, 0.0, 1.0))

	# Position: midpoint of the two markers, shifted back by the single offset (rotated). Real size.
	var offset := anchor_point.position if anchor_point != null else anchor_offset
	var mid := (h.origin + c.origin) * 0.5
	var basis := Basis(_rot)
	global_transform = Transform3D(basis, mid - basis * offset)
