extends Node3D
# 6DOF placement, anchor-style (the "understanding-transformations" pattern).
#
# THIS NODE IS THE ANCHOR. Every frame it simply moves to the pose the ArUco markers give:
#
#     position = midpoint of the two markers
#     rotation = average of the two markers' rotations
#
# The avatar is a CHILD of this node, placed BY HAND in the editor. That hand-authored child
# transform IS the offset -- and the rotation, and the scale. So there is no position_offset,
# no extra_rotation_degrees, no avatar_scale, and no sign convention to get backwards.
#
# SETUP
#   1. Put this script on the node that OWNS the mannequin (the avatar is its child).
#   2. Assign head_marker / chest_marker to the two aruco_patch nodes.
#   3. In the editor, drag / rotate / scale the mannequin child until it sits correctly around
#      THIS node's origin -- i.e. the anchor ends up where the markers' midpoint is on the body
#      (roughly mid-sternum, between the two markers).
#   4. Run. The anchor snaps onto the real markers and the avatar comes with it.
#
# To see what you are aligning to, temporarily add a small MeshInstance3D as a child of this
# node at (0,0,0): that cube marks exactly where the markers' midpoint will land.

@export var head_marker: Node3D          # aruco_patch0 (id 0)
@export var chest_marker: Node3D         # aruco_patch1 (id 1)

@export_group("Look")
# 0.0 = solid, 0.95 = nearly invisible. ~0.6 lets the real manikin show through clearly.
@export_range(0.0, 0.95, 0.05) var avatar_transparency := 0.6
# WHITE keeps the model's own colours. Set e.g. cyan to make it an obvious "virtual" ghost.
@export var avatar_tint := Color.WHITE


func _ready() -> void:
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


func _process(_delta: float) -> void:
	if head_marker == null or chest_marker == null:
		return

	var h := head_marker.global_transform
	var c := chest_marker.global_transform

	# Average the two rotations. slerp at 0.5 is the halfway rotation, and it takes the short
	# way round -- so the two markers' quaternions cannot cancel each other out.
	var q := h.basis.get_rotation_quaternion().slerp(c.basis.get_rotation_quaternion(), 0.5)

	global_transform = Transform3D(Basis(q), (h.origin + c.origin) * 0.5)
