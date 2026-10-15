extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _bounds(points: PackedVector3Array) -> Dictionary:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for point in points:
		low = low.min(point)
		high = high.max(point)
	return {"size_m": [high.x-low.x, high.y-low.y, high.z-low.z], "minimum_m": [low.x,low.y,low.z], "maximum_m": [high.x,high.y,high.z]}

func _points(node: Node3D, mount: Transform3D, skinned: bool) -> PackedVector3Array:
	var result := PackedVector3Array()
	for instance: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var local := mount * node.global_transform.affine_inverse() * instance.global_transform
		for surface in instance.mesh.get_surface_count():
			var vertices: PackedVector3Array = NaretSpatialAnchor.posed_vertices(instance, surface) if skinned else instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				result.append(local * vertex)
	return result

func _run() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file("C:/Users/bauld/Overlay/quest-aruco-avatar/project/assets/avatar/mannequin.glb", state) == OK)
	var old := document.generate_scene(state)
	root.add_child(old)
	var mount := Transform3D(Basis(Vector3(0.6872449,0,0), Vector3(0,-3.082737e-8,0.7052474), Vector3(0,-0.6681291,-2.920488e-8)), Vector3.ZERO)
	var patient: Node3D = load("res://scenes/mannequin.tscn").instantiate()
	root.add_child(patient)
	await process_frame
	var model := patient.get_node("Model") as Node3D
	var points := _points(model, Transform3D.IDENTITY, true)
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var pelvis := (model.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("pelvis"))).origin
	for bone_name in ["pelvis", "spine_01", "spine_02", "upperarm_l", "upperarm_r"]:
		print("FIT_BONE ", bone_name, " ", (model.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name))).origin)
	var upper := PackedVector3Array()
	# Explicit upper-body crop: everything from the pelvis plane toward the head.
	# This is an anatomical comparison region, not a claim about the old scan crop.
	for point in points:
		if point.z <= pelvis.z:
			upper.append(point)
	var result := {"old_source": _bounds(_points(old, Transform3D.IDENTITY, false)),
		"old_current_scene_mount": _bounds(_points(old, mount, false)),
		"new_full_body_skinned": _bounds(points), "new_head_to_pelvis_crop": _bounds(upper),
		"new_crop_pelvis_z_m": pelvis.z, "new_model_scale": str(model.scale)}
	FileAccess.open("res://build/patient_dimensions_comparison.json", FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print(JSON.stringify(result, "  "))
	old.free()
	patient.free()
	quit()
