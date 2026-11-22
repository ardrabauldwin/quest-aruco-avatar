extends Node3D
class_name NaretParkSurround
## Issue #1, 1. Szenario-Start: „Außerhalb des Spielbereichs volle 3D-Szene, innerhalb
## Passthrough (Puppe und Hände bleiben real sichtbar).“
##
## The park is drawn (assets/park_surround.gdshader) on walls standing on the play-area
## boundary, up to CAP_HEIGHT, and on a cap over the play area at that height. From
## inside, every view ray leaves the area through one of them; below the horizon the
## shader paints the grass where the ray would meet the floor, so no ground mesh is
## needed. Inside the boundary nothing virtual is added. Walls and cap stand on the boundary,
## so with the depth sensor's occlusion on, real people and hands in the play area are
## nearer than them and stay visible in front of the park; the real room walls (further
## out) are hidden behind it.

const CAP_HEIGHT := 2.3
const OUTSET := 0.05
const PATIENT_MARGIN := 1.0
## Without a boundary (it is switched off on the training headset): a 3.5 x 3.5 m square
## centred on the patient (user, 17 Nov 2026).
const NO_BOUNDARY_HALF := 1.75

var _material: ShaderMaterial

func build(outline: PackedVector2Array, floor_y: float, patient_xz: Vector2) -> bool:
	## outline: the play area in world XZ. The patient must lie inside it; when the
	## boundary is too small (stationary boundary), the area is grown to include the
	## patient with PATIENT_MARGIN around. Returns false without a usable area.
	for child in get_children():
		child.queue_free()
	var area := _area(outline, patient_xz)
	if area.size() < 3:
		return false
	_material = ShaderMaterial.new()
	_material.shader = preload("res://assets/park_surround.gdshader")
	var center := Vector2.ZERO
	var radius := 0.0
	for point in area: center += point
	center /= area.size()
	for point in area: radius = maxf(radius, point.distance_to(center))
	_material.set_shader_parameter("floor_y", floor_y)
	_material.set_shader_parameter("path_center", center)
	_material.set_shader_parameter("path_radius", radius + 4.0)
	_add_mesh("Walls", _walls(area, floor_y), _material)
	_add_mesh("Cap", _cap(area, floor_y + CAP_HEIGHT), _material)
	return true

static func _area(outline: PackedVector2Array, patient_xz: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array(outline)
	var inside := points.size() >= 3 and Geometry2D.is_point_in_polygon(patient_xz, points)
	if inside:
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			if Geometry2D.get_closest_point_to_segment(patient_xz, a, b).distance_to(patient_xz) < PATIENT_MARGIN:
				inside = false
				break
	if not inside:
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			points.append(patient_xz + corner * NO_BOUNDARY_HALF)
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	if hull.size() < 3:
		return PackedVector2Array()
	# Slightly outside the boundary, so nothing stands on the line itself.
	var grown := Geometry2D.offset_polygon(hull, OUTSET)
	return grown[0] if not grown.is_empty() else hull

func _add_mesh(mesh_name: String, mesh: ArrayMesh, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

static func _walls(area: PackedVector2Array, floor_y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in area.size():
		var a := area[i]
		var b := area[(i + 1) % area.size()]
		var a0 := Vector3(a.x, floor_y, a.y)
		var b0 := Vector3(b.x, floor_y, b.y)
		var a1 := a0 + Vector3.UP * CAP_HEIGHT
		var b1 := b0 + Vector3.UP * CAP_HEIGHT
		for v in [a0, b0, b1, a0, b1, a1]:
			st.add_vertex(v)
	return st.commit()

static func _cap(area: PackedVector2Array, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(area)
	for index in indices:
		st.add_vertex(Vector3(area[index].x, y, area[index].y))
	return st.commit()
