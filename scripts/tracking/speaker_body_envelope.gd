extends RefCounted
## Cache per-bone boxes once, then bound current animation with their corners.
## Positive normalised skin weights make each posed vertex a convex combination
## of points in these boxes. A containing circle therefore bounds the whole skin.
var _cache: Dictionary = {}


func radius(person: Node3D) -> float:
	var maximum := 0.0
	for node in person.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null: continue
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if mesh.skin == null or skeleton == null:
			maximum = maxf(maximum, _box_radius(mesh.get_aabb(), mesh.global_transform, person.global_position))
			continue
		var key := str(mesh.mesh.get_instance_id()) + ":" + str(mesh.skin.get_instance_id())
		if not _cache.has(key): _cache[key] = _bone_boxes(mesh, skeleton)
		var boxes: Dictionary = _cache[key]
		if boxes.is_empty(): return INF # Unknown geometry must not become a zero-sized body.
		for bind: int in boxes:
			var bone := mesh.skin.get_bind_bone(bind)
			if bone < 0: bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
			if bone < 0: return INF
			var transform := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
			maximum = maxf(maximum, _box_radius(boxes[bind], transform, person.global_position))
	return maximum if maximum > 0.0 else INF


func _bone_boxes(mesh: MeshInstance3D, _skeleton: Skeleton3D) -> Dictionary:
	var boxes: Dictionary = {}
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null: return {}
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty(): continue
		var influences := bones.size() / vertices.size()
		var morphs := mesh.mesh.surface_get_blend_shape_arrays(surface)
		for i in vertices.size():
			# Reserve all morph displacement directions up to the rig's existing
			# 2.2 maximum weight. This is conservative, including combinations.
			var padding := Vector3.ZERO
			for morph in morphs:
				var mv: PackedVector3Array = morph[Mesh.ARRAY_VERTEX]
				if mv.size() != vertices.size(): continue
				var displacement := mv[i] - vertices[i] if mesh.mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED else mv[i]
				padding += displacement.abs() * 2.2
			var total := 0.0
			for j in influences:
				var index := i * influences + j
				if weights[index] < 0.0: return {}
				total += weights[index]
				if weights[index] <= 0.0: continue
				var bind := bones[index]
				if bind < 0 or bind >= mesh.skin.get_bind_count(): return {}
				var box := AABB(vertices[i] - padding, padding * 2.0)
				var transformed := mesh.skin.get_bind_pose(bind) * box
				boxes[bind] = (boxes[bind] as AABB).merge(transformed) if boxes.has(bind) else transformed
			if absf(total - 1.0) > 0.001: return {}
	return boxes


func _box_radius(box: AABB, transform: Transform3D, centre: Vector3) -> float:
	var result := 0.0
	for i in 8:
		var point := transform * box.get_endpoint(i) - centre
		result = maxf(result, Vector2(point.x, point.z).length())
	return result
