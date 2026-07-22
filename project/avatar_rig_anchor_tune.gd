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
# CONTROLS  (Quest controllers only -- tuning is done in the headset, against the real manikin)
#   left stick  left/right  -> x
#   left stick  up/down     -> y
#   right stick up/down     -> z

@export var head_marker: Node3D          # aruco_patch0 (id 0)
@export var chest_marker: Node3D         # aruco_patch1 (id 1)
# The node the sticks move. Normally the mannequin. Must be a child of this node.
@export var target: Node3D

@export_group("Live tuning")
# Metres per second while held. 0.05 = 5cm/s -- slow enough to land on a value.
@export var nudge_speed := 0.05
@export var xr_controller_left: XRController3D
@export var xr_controller_right: XRController3D

@export_group("Look")
# 0.0 = solid, 0.95 = nearly invisible. ~0.6 lets the real manikin show through clearly.
@export_range(0.0, 0.95, 0.05) var avatar_transparency := 0.6
# WHITE keeps the model's own colours. Set e.g. cyan to make it an obvious "virtual" ghost.
@export var avatar_tint := Color.WHITE

var _print_timer := 0.0

# A marker node is only moved when main_3d.gd applies a fresh detection to it. So "its transform
# changed" means "the camera just saw it" -- that is how we know a marker has been detected
# without touching main_3d.gd.
var _seen_head := false
var _seen_chest := false
var _last_h: Transform3D
var _last_c: Transform3D


func _ready() -> void:
	# Remember the markers' start-of-scene poses, so the first real detection reads as a change.
	if head_marker != null:
		_last_h = head_marker.global_transform
	if chest_marker != null:
		_last_c = chest_marker.global_transform
	_apply_look()


# Make every mesh under the avatar semi-transparent (and tinted), keeping its texture. Uses
# material alpha so it works on the gl_compatibility / mobile renderer the Quest build uses.
#
# Matches on TYPE, not on name. The imported mannequin's mesh is called
# "E3A720C0_17A2_4863_AAAA_A710D22D5C4F" -- an auto-generated GUID that can change whenever the
# model is re-exported -- and it sits four levels down, under empty grouping nodes the Blender
# glTF exporter leaves behind (export/Geom/content/...). Matching the name, or reaching in by
# path, would silently stop working after any asset update; matching the type survives it.
# find_children() also does the recursion for us, in engine code.
func _apply_look() -> void:
	var alpha := clampf(1.0 - avatar_transparency, 0.05, 1.0)

	# owned = false: nodes inside an instanced scene (the .glb) are not owned by THIS scene, and
	# the default (true) would skip them -- silently, leaving the avatar opaque.
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		# Returns 0 when the mesh slot is empty, so this doubles as the null-mesh guard.
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_active_material(i)
			# Skips unassigned slots (null) and ShaderMaterials, which have no transparency knob.
			if mat is BaseMaterial3D:
				var m := mat.duplicate() as BaseMaterial3D
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.albedo_color = Color(avatar_tint, alpha)
				mi.set_surface_override_material(i, m)


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

	return dir * nudge_speed * delta


func _process(delta: float) -> void:
	# --- the anchor: straight onto the markers, nothing added ----------------------------
	if head_marker != null and chest_marker != null:
		if head_marker.global_transform != _last_h:
			_last_h = head_marker.global_transform
			_seen_head = true
		if chest_marker.global_transform != _last_c:
			_last_c = chest_marker.global_transform
			_seen_chest = true

		# Stay hidden until BOTH markers have been detected at least once, so the avatar never
		# appears at the markers' meaningless start-of-scene pose.
		visible = _seen_head and _seen_chest

		if visible:
			# slerp at 0.5 is the halfway rotation, and it takes the short way round -- so the
			# two markers' quaternions cannot cancel each other out.
			var q := _last_h.basis.get_rotation_quaternion().slerp(
					_last_c.basis.get_rotation_quaternion(), 0.5)
			global_transform = Transform3D(Basis(q), (_last_h.origin + _last_c.origin) * 0.5)

	# --- the bit you are tuning: move the mannequin inside the anchor --------------------
	if target != null:
		var nudge := _read_input(delta)
		if nudge != Vector3.ZERO:
			target.position += nudge
		# Printed once a second
		_print_timer += delta
		if _print_timer >= 1.0:
			_print_timer = 0.0
			print("TUNE  mannequin Position = (%.4f, %.4f, %.4f)" % [
					target.position.x, target.position.y, target.position.z])
