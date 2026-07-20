extends Node3D

# Position comes from the CHEST marker.
# Rotation is the average of HEAD and CHEST marker rotations.
# HEAD = aruco_patch0 (ID 0), CHEST = aruco_patch1 (ID 1).

@export var head_marker: Node3D
@export var chest_marker: Node3D

@export var avatar_scale := 1.0
@export var model_chest_offset := Vector3(0.01, 0.22, 0.1)
@export var extra_rotation_degrees := Vector3(-90.0, 0.0, 0.0)
@export var follow_speed := 15.0

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

	if not h.origin.is_equal_approx(_last_h):
		_h_seen = true

	if not c.origin.is_equal_approx(_last_c):
		_c_seen = true

	_last_h = h.origin
	_last_c = c.origin

	if not (_h_seen and _c_seen):
		visible = false
		return

	visible = true

	# Average the head and chest rotations.
	var avg := h.basis.get_rotation_quaternion().slerp(
		c.basis.get_rotation_quaternion(),
		0.5
	)

	# Convert the model correction from degrees to radians.
	var correction_q := Quaternion.from_euler(
		extra_rotation_degrees * (PI / 180.0)
	)

	# Combine the average marker rotation with the model correction.
	var rot_q := avg * correction_q

	if not _placed or follow_speed <= 0.0:
		_rot = rot_q
		_placed = true
	else:
		_rot = _rot.slerp(
			rot_q,
			clampf(follow_speed * delta, 0.0, 1.0)
		)

	var basis := Basis(_rot).scaled(
		Vector3.ONE * avatar_scale
	)

	global_transform = Transform3D(
		basis,
		c.origin - basis * model_chest_offset
	)
