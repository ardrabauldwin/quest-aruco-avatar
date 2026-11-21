extends Node3D
## Visual pad-placement guidance only. Does not accept pads or advance CCBM.
## All following lengths describe drawing style, not clinical tolerances.
const GOLD := Color("ffe600")
## 14 Nov 2026 (headset: "the dashed lines near the armpit are not so visible"). The
## dashes were 2 mm wide and lay 2 mm on the skin; on the flank, seen at a flat angle or
## from the patient's other side, nothing of them was left. They are three times as wide
## now, and each place also has a solid frame of the pad's size held FRAME_LIFT_M off the
## skin along the pad's own direction, with its number as on the device's face (1 on the
## chest, 2 on the flank). The frame stands clear of the body, so the one on the flank
## shows over the chest from the far side as well.
## Later the same day the raised frames were taken out again ("why two boxes on each
## side"): the place is marked by the dashed outline on the skin alone, as it always
## was, only much thicker (10 mm, from 2) and brighter (a purer yellow that glows three
## times as strongly). SHOW_FRAMES brings the frames back.
const SHOW_FRAMES := false
const GLOW := 3.0
const DASH_M := 0.020
const GAP_M := 0.008
const LINE_M := 0.010
const SKIN_LIFT_M := 0.005
const FRAME_LIFT_M := 0.07
const FRAME_BAR_M := 0.008
const NUMBERS := {"PadRight": "1", "PadLeft": "2"}
var outlines: Dictionary = {}
var _patient: NaretMannequin
var _poses: Dictionary
var _size := Vector2.ZERO
var _built := false
var _building := false
var _wanted := false
var _placed: Dictionary = {}
var _generation := 0

func configure(patient: NaretMannequin, poses: Dictionary, size: Vector2) -> void:
	_patient = patient
	_poses = poses
	_size = size
	visible = false
	for key in _poses:
		var outline := MeshInstance3D.new()
		outline.name = str(key) + "GoldenGuide"
		outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = GOLD
		material.emission_enabled = true
		material.emission = GOLD
		material.emission_energy_multiplier = GLOW
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Depth testing stays enabled: guides must not show through the body.
		outline.material_override = material
		add_child(outline)
		outlines[key] = outline
		if SHOW_FRAMES: _add_frame(outline, key)

func _add_frame(outline: MeshInstance3D, key: Variant) -> void:
	## Child of the outline, so it shows and hides with it.
	var spec: Array = _poses[key]
	var frame := Node3D.new()
	frame.name = "Frame"
	frame.transform = Transform3D(Basis.from_euler(spec[1] * PI / 180.0), spec[0]) * Transform3D(Basis(), Vector3(0, FRAME_LIFT_M, 0))
	outline.add_child(frame)
	# Opaque, unshaded and drawn early, like the other markers that have to survive the
	# headset's real-world depth occlusion (see xr_interaction: shoulder frames).
	var solid := StandardMaterial3D.new()
	solid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	solid.albedo_color = GOLD
	solid.emission_enabled = true
	solid.emission = GOLD
	solid.emission_energy_multiplier = 1.0
	solid.cull_mode = BaseMaterial3D.CULL_DISABLED
	solid.render_priority = -60
	for bar in [[Vector3(_size.x, 0.004, FRAME_BAR_M), Vector3(0, 0, _size.y * 0.5)], [Vector3(_size.x, 0.004, FRAME_BAR_M), Vector3(0, 0, -_size.y * 0.5)],
			[Vector3(FRAME_BAR_M, 0.004, _size.y), Vector3(_size.x * 0.5, 0, 0)], [Vector3(FRAME_BAR_M, 0.004, _size.y), Vector3(-_size.x * 0.5, 0, 0)]]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = bar[0]
		mesh.mesh = box
		mesh.material_override = solid
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.position = bar[1]
		frame.add_child(mesh)
	# A short stem from the skin to the frame, so it is clear which spot it marks.
	var stem := MeshInstance3D.new()
	var rod := BoxMesh.new()
	rod.size = Vector3(0.004, FRAME_LIFT_M, 0.004)
	stem.mesh = rod
	stem.material_override = solid
	stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stem.position = Vector3(0, -FRAME_LIFT_M * 0.5, 0)
	frame.add_child(stem)
	var number := Label3D.new()
	number.text = str(NUMBERS.get(str(key), ""))
	number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	number.no_depth_test = true
	number.pixel_size = 0.0012
	number.font_size = 48
	number.outline_size = 12
	number.modulate = GOLD
	number.outline_modulate = Color(0.2, 0.13, 0.0)
	number.position = Vector3(0, 0.02, 0)
	frame.add_child(number)

func show_targets(wanted: bool, placed: Dictionary) -> void:
	_wanted = wanted
	_placed = placed.duplicate()
	global_transform = _patient.get_body_transform()
	if wanted and not _built and not _building:
		_building = true
		_build.call_deferred(_generation)
	_update_visibility()

func _update_visibility() -> void:
	visible = _wanted and _built
	for key in outlines:
		outlines[key].visible = not _placed.has(key)

func reset_guides() -> void:
	_generation += 1
	_wanted = false
	_built = false
	_building = false
	_placed.clear()
	visible = false
	for outline in outlines.values(): outline.mesh = null

func torso_vertex_mask(body: MeshInstance3D, surface: int) -> PackedByteArray:
	# The torso and arms share one skinned mesh. Projecting onto the nearest
	# triangle without checking rig anatomy can put the lateral guide on an arm.
	var arrays := body.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var mask := PackedByteArray()
	mask.resize(vertices.size())
	mask.fill(1)
	var skeleton := body.get_node_or_null(body.skeleton) as Skeleton3D
	if body.skin == null or skeleton == null or arrays[Mesh.ARRAY_BONES] == null: return mask
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var influences := bones.size() / maxi(vertices.size(),1)
	for i in vertices.size():
		var largest := -1.0
		var bind := -1
		for j in influences:
			var index := i * influences + j
			if weights[index] > largest:
				largest = weights[index]
				bind = bones[index]
		if bind < 0 or bind >= body.skin.get_bind_count(): continue
		var bone := body.skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(body.skin.get_bind_name(bind))
		while bone >= 0:
			var name := String(skeleton.get_bone_name(bone)).to_lower()
			if "upperarm" in name or "lowerarm" in name or "forearm" in name or "hand" in name:
				mask[i] = 0
				break
			bone = skeleton.get_bone_parent(bone)
	return mask

func _body_triangles() -> Array[PackedVector3Array]:
	var triangles: Array[PackedVector3Array] = []
	var body := _patient.find_child("PatientBody", true, false) as MeshInstance3D
	if body == null or body.mesh == null: return triangles
	var mesh: Mesh = body.mesh
	var baked: ArrayMesh
	if DisplayServer.get_name() != "headless":
		baked = body.bake_mesh_from_current_skeleton_pose()
		if baked: mesh = baked
	var transform := _patient.get_body_transform().affine_inverse() * body.global_transform
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if baked else NaretSpatialAnchor.posed_vertices(body, surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var torso := torso_vertex_mask(body,surface)
		if indices.is_empty():
			for i in range(0, vertices.size() - 2, 3):
				if not torso[i] or not torso[i+1] or not torso[i+2]: continue
				triangles.append(PackedVector3Array([transform * vertices[i], transform * vertices[i+1], transform * vertices[i+2]]))
		else:
			for i in range(0, indices.size() - 2, 3):
				if not torso[indices[i]] or not torso[indices[i+1]] or not torso[indices[i+2]]: continue
				triangles.append(PackedVector3Array([transform * vertices[indices[i]], transform * vertices[indices[i+1]], transform * vertices[indices[i+2]]]))
	return triangles

func _on_skin(point: Vector3, normal: Vector3, triangles: Array[PackedVector3Array]) -> Variant:
	# Projection range comes from pad size, not an additional acceptance radius.
	var ray := point + normal * _size.length()
	var nearest := INF
	var hit: Variant = null
	for tri in triangles:
		var at: Variant = Geometry3D.ray_intersects_triangle(ray, -normal, tri[0], tri[1], tri[2])
		if at == null: continue
		var distance := ray.distance_to(at)
		if distance < nearest and distance <= _size.length() * 2.0:
			nearest = distance
			hit = (at as Vector3) + normal * SKIN_LIFT_M
	return hit

func _build(generation: int) -> void:
	# Build only when placement begins. Yield between groups of dashes instead
	# of doing skin ray tests in every frame throughout CPR.
	var triangles := _body_triangles()
	var tree := get_tree()
	for key in _poses:
		var spec: Array = _poses[key]
		var pose := Transform3D(Basis.from_euler(spec[1] * PI / 180.0), spec[0])
		var normal := pose.basis.y.normalized()
		var nearby: Array[PackedVector3Array] = []
		var reach := _size.length() * 1.5
		for tri in triangles:
			if AABB(tri[0], Vector3.ZERO).expand(tri[1]).expand(tri[2]).grow(reach).has_point(pose.origin): nearby.append(tri)
		var half := _size * 0.5
		var corners := [Vector3(-half.x,0,-half.y), Vector3(half.x,0,-half.y), Vector3(half.x,0,half.y), Vector3(-half.x,0,half.y)]
		# One flat rectangle (14 Nov 2026, evening: "the chest pad place should be shown
		# just as a rectangle, not like 3D"). The dashes used to be laid onto the skin one
		# by one, so the outline bent over the chest and round the flank like tape. Now
		# it lies in the pad's own plane, as the pad itself does, lifted just clear of
		# the highest skin under it so that no part sinks into the body.
		var lift := SKIN_LIFT_M
		var samples := 0
		for ix in 5:
			for iz in 5:
				var local := Vector3(lerpf(-half.x, half.x, ix / 4.0), 0.0, lerpf(-half.y, half.y, iz / 4.0))
				var hit: Variant = _on_skin(pose * local, normal, nearby)
				if hit != null: lift = maxf(lift, ((hit as Vector3) - pose * local).dot(normal))
				samples += 1
				if samples % 5 == 0:
					await tree.process_frame
					if generation != _generation: return
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var count := 0
		for side in 4:
			var a: Vector3 = corners[side]
			var b: Vector3 = corners[(side+1)%4]
			var direction := (b-a).normalized()
			var across := Vector3.UP.cross(direction) * (LINE_M*0.5)
			var distance := 0.0
			while distance < a.distance_to(b):
				var start := a + direction * distance
				var finish := a + direction * minf(distance + DASH_M, a.distance_to(b))
				var quad: Array[Vector3] = [start-across, start+across, finish+across, finish-across]
				for index in [0,1,2,0,2,3]: tool.add_vertex(pose * quad[index] + normal * lift)
				count += 6
				distance += DASH_M + GAP_M
		if generation != _generation: return
		if count > 0:
			tool.generate_normals()
			outlines[key].mesh = tool.commit()
	_built = true
	_building = false
	_update_visibility()
