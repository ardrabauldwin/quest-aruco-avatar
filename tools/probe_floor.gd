extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var anchor := NaretSpatialAnchor.new()
	root.add_child(anchor)
	var patient: Node3D = load("res://scenes/mannequin.tscn").instantiate()
	anchor.add_child(patient)
	anchor.default_model_rotation_degrees = Vector3(180, 0, 0)
	anchor.marker_to_mannequin = anchor.sternum_offset()
	anchor.global_transform = anchor.marker_to_mannequin
	await process_frame
	await process_frame
	for instance: MeshInstance3D in patient.find_children("*", "MeshInstance3D", true, false):
		var lowest := INF
		for surface in instance.mesh.get_surface_count():
			for v in NaretSpatialAnchor.posed_vertices(instance, surface):
				lowest = minf(lowest, (instance.global_transform * v).y)
		print("FLOOR_PROBE ", patient.get_path_to(instance), " visible=", instance.is_visible_in_tree(), " lowest=", lowest)
		if instance.skin != null:
			var baked := instance.bake_mesh_from_current_skeleton_pose()
			var rendered_lowest := INF
			for surface in baked.get_surface_count():
				for v in baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					rendered_lowest = minf(rendered_lowest, (instance.global_transform * v).y)
			print("FLOOR_RENDER_CHECK ", instance.name, " baked=", rendered_lowest, " difference=", rendered_lowest - lowest)
	anchor.free()
	quit()
