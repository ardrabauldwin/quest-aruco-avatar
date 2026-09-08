extends Node3D
# NEW SCRIPT -- tuning only. Touches nothing else: avatar_rig_6dof.gd, avatar_rig.gd,
# avatar_rig_3.gd, main_3d.gd and the scene are all left exactly as they are.
#
# Same 6DOF placement as avatar_rig_6dof.gd, but position_offset starts at ZERO -- so the avatar
# sits exactly ON the markers' midpoint, with no hidden correction. You then move it in X, Y and Z
# until it fits the real manikin, and the value is printed so it can be copied into the real rig.
#
# ONLY x / y / z are tunable live. Everything else (scale, rotation, transparency) is set in the
# Inspector as usual.
#
#   KEYBOARD      A / D  ->  x-  / x+        (left / right)
#                 W / S  ->  y+  / y-        (up / down)
#                 Q / E  ->  z-  / z+        (forward / back)
#
#   QUEST         left stick  left/right  ->  x
#                 left stick  up/down     ->  y
#                 right stick up/down     ->  z

@export var head_marker: Node3D          # aruco_patch0 (id 0)
@export var chest_marker: Node3D         # aruco_patch1 (id 1)

@export_group("Placement")
# STARTS AT ZERO: the avatar sits on the markers. Tune live, then copy the final value out.
@export var position_offset := Vector3.ZERO
@export var avatar_scale := 1.0
@export var extra_rotation_degrees := Vector3(-90, 0, 0)
@export var follow_speed := 60.0

@export_group("Live tuning (x/y/z only)")
# Metres per second while a key or stick is held. 0.05 = 5cm/s: slow enough to land on a value.
@export var nudge_speed := 0.05
# Assign the two XRController3D nodes to tune with the thumbsticks. Empty = keyboard only.
@export var xr_controller_left: XRController3D
@export var xr_controller_right: XRController3D
# Optional Label3D to read the value in the headset. Empty = console only.
@export var readout: Label3D

@export_group("Look")
@export_range(0.0, 0.95, 0.05) var avatar_transparency := 0.6
@export var avatar_tint := Color.WHITE

var _placed := false
var _rot := Quaternion.IDENTITY
var _h_seen := false
var _c_seen := false
var _last_h := Vector3.INF
var _last_c := Vector3.INF
var _print_timer := 0.0


func _ready() -> void:
	_apply_look(self)
	_show()


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


# This frame's x/y/z nudge, in the avatar's own frame (metres). The axes are exactly the axes of
# position_offset, so what you move IS what you type into the real rig afterwards.
func _read_input(delta: float) -> Vector3:
	var dir := Vector3.ZERO

	# --- Quest thumbsticks ---
	if xr_controller_left != null:
		var s: Vector2 = xr_controller_left.get_vector2("primary")
		dir.x += s.x          # left stick left/right -> x
		dir.y += s.y          # left stick up/down    -> y
	if xr_controller_right != null:
		dir.z += -xr_controller_right.get_vector2("primary").y   # right stick up/down -> z

	# --- Keyboard (raw key checks: no action map needed) ---
	if Input.is_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): dir.x += 1.0
	if Input.is_key_pressed(KEY_W): dir.y += 1.0
	if Input.is_key_pressed(KEY_S): dir.y -= 1.0
	if Input.is_key_pressed(KEY_Q): dir.z -= 1.0
	if Input.is_key_pressed(KEY_E): dir.z += 1.0

	return dir * nudge_speed * delta


func _show() -> void:
	if readout != null:
		readout.text = "offset (%+.3f, %+.3f, %+.3f)" % [
				position_offset.x, position_offset.y, position_offset.z]


func _process(delta: float) -> void:
	if head_marker == null or chest_marker == null:
		return

	var nudge := _read_input(delta)
	if nudge != Vector3.ZERO:
		position_offset += nudge
		_show()

	# Print once a second so the value is recoverable with: adb logcat -s godot
	_print_timer += delta
	if _print_timer >= 1.0:
		_print_timer = 0.0
		print("TUNE  position_offset = Vector3(%.4f, %.4f, %.4f)" % [
				position_offset.x, position_offset.y, position_offset.z])

	var h := head_marker.global_transform
	var c := chest_marker.global_transform

	# Show once both markers have been seen, then hold the last pose through dropouts.
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

	# Midpoint, then the nudge. position_offset is a distance INSIDE the model, so it scales with
	# the mesh -- same convention as avatar_rig_6dof.gd, so the tuned value transfers unchanged.
	var mid := (h.origin + c.origin) * 0.5
	var basis := Basis(_rot)
	var pos := mid + basis * (position_offset * avatar_scale)
	global_transform = Transform3D(basis.scaled(Vector3.ONE * avatar_scale), pos)
