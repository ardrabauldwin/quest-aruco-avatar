extends Node3D
# NEW SCRIPT -- tuning only. Nothing else is touched.
#
# 6DOF anchor + live tuning, with NO offset variable anywhere in the code.
#
#   THIS NODE is the anchor. Every frame it goes to the markers:
#       position = midpoint of the two markers
#       rotation = average of the two markers' rotations
#
#   `target` (the mannequin) is what you MOVE with the controllers. You are literally dragging
#   the mannequin around inside the anchor -- the same thing you would do in the editor, except
#   you can see the real manikin while you do it.
#
# There is no position_offset and no extra_rotation_degrees. The mannequin's own transform holds
# everything, so the number printed below is EXACTLY the mannequin's Position in the Inspector.
# Tune it, read the number, type it in, switch back to avatar_rig_anchor.gd. Done.
#
# SETUP
#   AvatarRig script      -> this file
#   head_marker           -> aruco_patch0
#   chest_marker          -> aruco_patch1
#   target                -> the mannequin child
#   xr_controller_left    -> LeftHand
#   xr_controller_right   -> RightHand
#
# CONTROLS                          keyboard
#   left stick  left/right  -> x      A / D
#   left stick  up/down     -> y      W / S
#   right stick up/down     -> z      Q / E

@export var head_marker: Node3D          # aruco_patch0 (id 0)
@export var chest_marker: Node3D         # aruco_patch1 (id 1)
# The node the sticks move. Normally the mannequin. Must be a child of this node.
@export var target: Node3D

@export_group("Live tuning")
# Metres per second while held. 0.05 = 5cm/s -- slow enough to land on a value.
@export var nudge_speed := 0.05
@export var xr_controller_left: XRController3D
@export var xr_controller_right: XRController3D
# Optional Label3D to read the value in the headset. Empty = console only.
@export var readout: Label3D

@export_group("Look")
# 0.0 = solid, 0.95 = nearly invisible. ~0.6 lets the real manikin show through clearly.
@export_range(0.0, 0.95, 0.05) var avatar_transparency := 0.6
# WHITE keeps the model's own colours. Set e.g. cyan to make it an obvious "virtual" ghost.
@export var avatar_tint := Color.WHITE

var _print_timer := 0.0


func _ready() -> void:
	_apply_look(self)


# Make every mesh under the avatar semi-transparent (and tinted), keeping its texture. Uses
# material alpha so it works on the gl_compatibility / mobile renderer the Quest build uses.
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


# This frame's nudge, in the ANCHOR's local space -- which is exactly the space the Inspector
# shows for the mannequin's Position. So what you push is what you type in afterwards.
func _read_input(delta: float) -> Vector3:
	var dir := Vector3.ZERO

	if xr_controller_left != null:
		var s: Vector2 = xr_controller_left.get_vector2("primary")
		dir.x += s.x          # left stick left/right -> x
		dir.y += s.y          # left stick up/down    -> y
	if xr_controller_right != null:
		dir.z += -xr_controller_right.get_vector2("primary").y   # right stick up/down -> z

	if Input.is_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): dir.x += 1.0
	if Input.is_key_pressed(KEY_W): dir.y += 1.0
	if Input.is_key_pressed(KEY_S): dir.y -= 1.0
	if Input.is_key_pressed(KEY_Q): dir.z -= 1.0
	if Input.is_key_pressed(KEY_E): dir.z += 1.0

	return dir * nudge_speed * delta


func _process(delta: float) -> void:
	# --- the bit you are tuning: move the mannequin inside the anchor --------------------
	if target != null:
		var nudge := _read_input(delta)
		if nudge != Vector3.ZERO:
			target.position += nudge
		if readout != null:
			readout.text = "mannequin Position\n(%+.3f, %+.3f, %+.3f)" % [
					target.position.x, target.position.y, target.position.z]
		# Printed once a second so it is recoverable with: adb logcat -s godot
		_print_timer += delta
		if _print_timer >= 1.0:
			_print_timer = 0.0
			print("TUNE  mannequin Position = (%.4f, %.4f, %.4f)" % [
					target.position.x, target.position.y, target.position.z])

	# --- the anchor: straight onto the markers, nothing added ----------------------------
	if head_marker == null or chest_marker == null:
		return
	var h := head_marker.global_transform
	var c := chest_marker.global_transform
	# slerp at 0.5 is the halfway rotation, and it takes the short way round -- so the two
	# markers' quaternions cannot cancel each other out.
	var q := h.basis.get_rotation_quaternion().slerp(c.basis.get_rotation_quaternion(), 0.5)
	global_transform = Transform3D(Basis(q), (h.origin + c.origin) * 0.5)
