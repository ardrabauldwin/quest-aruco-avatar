extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var anchor := NaretSpatialAnchor.new()
	root.add_child(anchor)
	var patient: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	anchor.add_child(patient)
	await process_frame
	anchor.marker_to_mannequin = Transform3D.IDENTITY
	anchor.floor_locked = true
	anchor.locked = true
	anchor.has_marker_pose = true
	anchor.refresh()
	var model := patient.get_node("Model") as Node3D
	var torso_bottom := INF
	for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if not String(instance.name).ends_with("Body"):
			continue
		for surface in instance.mesh.get_surface_count():
			for vertex in NaretSpatialAnchor.posed_vertices(instance, surface):
				var local_point := model.global_transform.affine_inverse() * instance.global_transform * vertex
				if absf(local_point.x) < 0.1 and local_point.z > -0.24 and local_point.z < 0.125:
					torso_bottom = minf(torso_bottom, (instance.global_transform * vertex).y)
	print("GEOMETRY_CHECK root_y=", anchor.global_position.y, " torso_back_y=", torso_bottom, " sternum_y=", patient.sternum.global_position.y)
	anchor.free()
	quit()
