extends Node3D
# Simple placement: sit the avatar at the MIDPOINT of the two markers, orient it by their averaged
# rotation, and size it by their distance. HEAD = aruco_patch0 (ID 0), CHEST = aruco_patch1 (ID 1).
# main_3d.gd writes each detected marker's world pose into its patch node every frame.

@export var head_marker: Node3D
@export var chest_marker: Node3D
# The avatar's own head-to-chest length in meters (sizes the avatar to the real marker spacing).
@export var model_head_to_chest := 0.39
# Fixed twist so the model's axes line up with the markers.
@export var extra_rotation_degrees := Vector3(-90, 0, 0)
# Rotation smoothing. Higher = snappier; 0 = instant. Position + scale always snap.
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

	# Show only once BOTH markers have been detected (moved off their default pose).
	if not h.origin.is_equal_approx(_last_h): _h_seen = true
	if not c.origin.is_equal_approx(_last_c): _c_seen = true
	_last_h = h.origin
	_last_c = c.origin
	if not (_h_seen and _c_seen):
		visible = false
		return
	visible = true

	var dist := h.origin.distance_to(c.origin)
	if dist < 0.02:
		return

	# Orientation: average the two markers' rotations, then the fixed model twist.
	var avg := h.basis.get_rotation_quaternion().slerp(c.basis.get_rotation_quaternion(), 0.5)
	var rot_q := (Basis(avg) * Basis.from_euler(extra_rotation_degrees * (PI / 180.0))).get_rotation_quaternion()
	if not _placed or follow_speed <= 0.0:
		_rot = rot_q
		_placed = true
	else:
		_rot = _rot.slerp(rot_q, clampf(follow_speed * delta, 0.0, 1.0))

	# Position = midpoint of the markers; scale = their distance.
	var mid := (h.origin + c.origin) * 0.5
	global_transform = Transform3D(Basis(_rot).scaled(Vector3.ONE * (dist / model_head_to_chest)), mid)
