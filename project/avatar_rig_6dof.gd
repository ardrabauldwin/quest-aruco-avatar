extends Node3D
# Placement = "average, then a positional nudge" (your design).
#   1. midpoint of the two markers' positions
#   2. rotation = the two markers' rotations averaged, + a fixed model twist
#   3. place the avatar there
#   4. + position_offset (in the avatar's own frame) to slide it onto the body
#   real 1:1 size (no distance scaling)
#
# The avatar is drawn semi-transparent (and optionally tinted) so the real manikin shows through.
# Once both markers have been seen it STAYS visible -- if a marker drops out it holds its last pose
# (it does not disappear).

@export var head_marker: Node3D          # aruco_patch0 (id 0)
@export var chest_marker: Node3D         # aruco_patch1 (id 1)
# Positional nudge from the markers' midpoint, in the avatar's own frame. (0,0,0) = at the midpoint.
@export var position_offset := Vector3.ZERO
# Uniform size multiplier for the avatar. 1.0 = real 1:1 size (the original behaviour).
# Raise/lower if the model is authored at a different scale than the real manikin.
@export var avatar_scale := 1.0
# Fixed twist so the model's axes line up with the markers.
@export var extra_rotation_degrees := Vector3(-90, 0, 0)
# Rotation smoothing. Higher = snappier; 0 = instant. Position is snapped.
@export var follow_speed := 60.0
# 0.0 = solid, 1.0 = invisible. ~0.6 = clearly see the real manikin + ArUco markers through it.
@export_range(0.0, 0.95, 0.05) var avatar_transparency := 0.6
# Colour tint. WHITE = keep the model's own colours. Set e.g. cyan/green to make it a clear
# "virtual" ghost that's easy to tell apart from the real manikin.
@export var avatar_tint := Color.WHITE

var _placed := false
var _rot := Quaternion.IDENTITY
var _h_seen := false
var _c_seen := false
var _last_h := Vector3.INF
var _last_c := Vector3.INF

func _ready() -> void:
	_apply_look(self)

# Make every mesh under the avatar semi-transparent (and tinted), keeping its texture. Uses material
# alpha so it works on the gl_compatibility / mobile renderer the Quest build uses.
func _apply_look(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				for i in mi.mesh.get_surface_count():
					var mat := mi.get_active_material(i)
					if mat is BaseMaterial3D:
						var m := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
						m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						m.albedo_color = Color(avatar_tint.r, avatar_tint.g, avatar_tint.b,
								clampf(1.0 - avatar_transparency, 0.05, 1.0))
						mi.set_surface_override_material(i, m)
		_apply_look(child)

func _process(delta: float) -> void:
	if head_marker == null or chest_marker == null:
		return
	var h := head_marker.global_transform
	var c := chest_marker.global_transform

	# Show once both markers have been detected at least once, then STAY visible (hold last pose
	# through dropouts -- do not disappear).
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

	# Midpoint, then nudge in the avatar's own frame. avatar_scale = 1.0 keeps real 1:1 size.
	var mid := (h.origin + c.origin) * 0.5
	# position_offset is a distance INSIDE the model (its origin -> the chest markers), so it must
	# scale with the mesh: shrink the avatar and that internal distance shrinks by the same factor.
	# Leaving it unscaled lands the chest (1 - avatar_scale) * offset away from the markers.
	var basis := Basis(_rot)
	var pos := mid + basis * (position_offset * avatar_scale)
	global_transform = Transform3D(basis.scaled(Vector3.ONE * avatar_scale), pos)
