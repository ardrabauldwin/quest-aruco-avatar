extends Node3D
# DEBUG: draws a coloured XYZ axis on each ArUco marker so you can see its full 6DOF pose live --
# red = X, green = Y, blue = Z. A marker's gizmo is shown ONLY while that marker is actually being
# detected; markers that are out of view (or not present at all, like a removed navel marker) have
# their gizmo hidden, so no stray axis floats in front of you. Also hides the plain placeholder
# cubes on the patches.

# Assign the patch nodes (aruco_patch0, aruco_patch1, aruco_patch2) in the inspector.
@export var markers: Array[Node3D] = []
@export var axis_length := 0.1        # metres
@export var axis_thickness := 0.006   # metres
@export var hide_placeholder_boxes := true
# A marker counts as detected when its marker script stamped it recently.
@export var fresh_ms := 300

var _gizmos: Array[Node3D] = []


func _ready() -> void:
	for i in markers.size():
		var g := _make_axis()
		g.visible = false
		add_child(g)
		_gizmos.append(g)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var newest_timestamp_ms := -1
	for marker in markers:
		if (
			marker != null
			and marker.has_meta("last_detected_ms")
			and now - int(marker.get_meta("last_detected_ms")) <= fresh_ms
		):
			newest_timestamp_ms = maxi(
				newest_timestamp_ms,
				int(marker.get_meta("last_detected_ms"))
			)

	for i in markers.size():
		var n := markers[i]
		var g := _gizmos[i]
		if n == null or g == null:
			continue

		# Match AvatarRig's fusion set exactly: a marker can remain freshness-eligible for 300 ms,
		# but it is visualized only when it belongs to the single newest camera result. This prevents
		# a remembered old gizmo from looking as though it participated in the current fusion.
		var used_in_newest_result := (
			n.has_meta("last_detected_ms")
			and now - int(n.get_meta("last_detected_ms")) <= fresh_ms
			and int(n.get_meta("last_detected_ms")) == newest_timestamp_ms
		)
		# Previously these meshes were forced invisible even during successful detections. Make the
		# authored 10 cm cube an unmistakable marker indicator, but keep it hidden before the first
		# detection and after the marker leaves view.
		if hide_placeholder_boxes:
			for c in n.get_children():
				if c is MeshInstance3D:
					c.visible = false
		g.visible = used_in_newest_result
		if used_in_newest_result:
			g.global_transform = n.global_transform


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
