extends Node3D
# DEBUG: draws a colored XYZ axis on each ArUco marker so you can see its full 6DOF pose live —
# red = X, green = Y, blue = Z. The gizmo's position shows the 3 translation DOF, its rotation the
# 3 rotation DOF. It follows the aruco_patch nodes that main_3d.gd updates (they survive being
# reparented at startup because these are resolved Node references). Also hides Paul's plain black
# placeholder cubes on those patches.

# Assign the patch nodes (aruco_patch0, aruco_patch1) in the inspector.
@export var markers: Array[Node3D] = []
@export var axis_length := 0.1        # metres
@export var axis_thickness := 0.006   # metres
@export var hide_placeholder_boxes := true

var _gizmos: Array[Node3D] = []

func _ready() -> void:
	for i in markers.size():
		var g := _make_axis()
		g.visible = false
		add_child(g)
		_gizmos.append(g)

func _process(_delta: float) -> void:
	for i in markers.size():
		var n := markers[i]
		var g := _gizmos[i]
		if n == null or g == null:
			continue
		if hide_placeholder_boxes:
			for c in n.get_children():
				if c is MeshInstance3D:
					c.visible = false
		g.global_transform = n.global_transform
		g.visible = true

func _make_axis() -> Node3D:
	var root := Node3D.new()
	root.add_child(_bar(Vector3(1, 0, 0), Color(1.0, 0.18, 0.18)))   # X red
	root.add_child(_bar(Vector3(0, 1, 0), Color(0.2, 1.0, 0.35)))    # Y green
	root.add_child(_bar(Vector3(0, 0, 1), Color(0.3, 0.55, 1.0)))    # Z blue
	return root

func _bar(axis: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var t := axis_thickness
	var l := axis_length
	bm.size = Vector3(
		l if axis.x > 0.5 else t,
		l if axis.y > 0.5 else t,
		l if axis.z > 0.5 else t)
	mi.mesh = bm
	mi.position = axis * (l * 0.5)     # start at origin, extend along +axis
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.no_depth_test = true           # draw over passthrough so it's always visible
	mi.material_override = mat
	return mi
