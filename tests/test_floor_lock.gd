extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var origin_transform := Transform3D(Basis.IDENTITY, Vector3(1, 0.3, 2))
	var reference := Transform3D(Basis.IDENTITY, Vector3(0, -0.15, 0))
	check(absf(NaretOpenXRSetup.reference_floor_height(origin_transform, reference) - 0.15) < 0.0001,
		"floor must include XR recenter reference, not just origin height")
	var anchor := NaretSpatialAnchor.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(anchor)
	var patient := Node3D.new()
	patient.name = "Mannequin"
	anchor.add_child(patient)
	var model := Node3D.new()
	model.name = "Model"
	patient.add_child(model)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	model.add_child(mesh)
	var hidden := MeshInstance3D.new()
	hidden.mesh = BoxMesh.new()
	hidden.position.y = -10.0
	hidden.visible = false
	patient.add_child(hidden)
	anchor.floor_locked = true
	anchor.floor_y = 0.2
	anchor.locked = true
	anchor.has_marker_pose = true
	anchor.locked_pose.origin = Vector3(2, 3, 4)
	anchor.refresh()
	check(absf(anchor.global_position.y - 0.7) < 0.0001, "model bottom must meet floor")
	anchor.marker_to_mannequin.origin = Vector3(0.05, 1.0, -0.03)
	anchor.refresh()
	check(absf(anchor.global_position.y - 0.7) < 0.0001, "vertical nudge must not lift floor-locked model")
	check(absf(anchor.global_position.x - 2.05) < 0.0001, "horizontal nudge must preview")
	check(anchor.locked_pose.origin == Vector3(2, 3, 4), "floor lock must preserve measured anchor")
	anchor.marker_to_mannequin = Transform3D.IDENTITY
	anchor.nudge_world(Vector3(0.1, 2.0, -0.1), 0.0)
	check(absf(anchor.global_position.x - 2.1) < 0.0001, "controller translation previews horizontally")
	check(absf(anchor.global_position.y - 0.7) < 0.0001, "controller input cannot change floor height")
	anchor.nudge_world(Vector3.ZERO, PI / 2.0)
	check(anchor.global_basis.get_scale().is_equal_approx(Vector3.ONE), "controller yaw preserves scale")
	check(anchor.locked_pose.origin == Vector3(2, 3, 4), "controller nudge never edits tracking")
	anchor.floor_adjustment_m = 0.03
	anchor.refresh()
	check(absf(anchor.global_position.y - 0.73) < 0.0001, "patient floor adjustment previews without changing tracking")
	check(is_equal_approx(anchor.floor_y, 0.2), "patient height adjustment does not move room floor")
	anchor.calibrated = true
	anchor.marker_to_mannequin = Transform3D.IDENTITY
	anchor.locked_pose.origin.y = -1.0
	anchor.floor_adjustment_m = -0.194
	anchor.refresh()
	check(absf(anchor.global_position.y - 0.7) < 0.0001, "saved downward calibration cannot put resting mesh below floor")
	check(is_equal_approx(anchor.floor_adjustment_m, -0.194), "floor contact limit does not rewrite saved nudge")
	anchor.locked_pose.origin.y = 1.0
	anchor.floor_adjustment_m = 0.0
	anchor.refresh()
	check(is_equal_approx(anchor.global_position.y, 0.7), "active floor lock also grounds a calibrated position above floor")
	var alignment_before := anchor.marker_to_mannequin
	var measurement_before := anchor.locked_pose
	anchor.adjust_patient_height(-0.75)
	check(is_equal_approx(anchor.global_position.y, -0.05), "explicit floor correction can lower a floating patient")
	anchor.refresh()
	check(is_equal_approx(anchor.global_position.y, -0.05), "floor refresh retains explicit correction")
	check(anchor.marker_to_mannequin == alignment_before and anchor.locked_pose == measurement_before, "height correction preserves saved alignment and marker measurement")
	check(is_equal_approx(anchor.floor_y, 0.2), "height correction leaves Quest floor reference unchanged")
	anchor.calibration_file = "user://test-manual-floor.cfg"
	check(anchor.save_calibration() == OK, "manual height saves")
	var loaded := NaretSpatialAnchor.new()
	loaded.calibration_file = anchor.calibration_file
	check(loaded.load_calibration() == OK and is_equal_approx(loaded.manual_floor_correction_m, -0.75), "manual height survives reload")
	loaded.free()
	DirAccess.remove_absolute(anchor.calibration_file)
	anchor.free()
	await _test_real_patient()
	await _test_standing_people()
	return failures

func _test_real_patient() -> void:
	# The primitive-box test cannot catch the original bug: this GLB stores its
	# body in an upright bind pose, while the visible skeleton is already lying.
	var anchor := NaretSpatialAnchor.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(anchor)
	var patient: Node3D = load("res://scenes/mannequin.tscn").instantiate()
	anchor.add_child(patient)
	check((patient.get_node("Model") as Node3D).scale.is_equal_approx(Vector3(0.9, 0.9, 0.9)), "patient uses modest uniform fitting without changing proportions")
	await (Engine.get_main_loop() as SceneTree).process_frame
	anchor.default_model_rotation_degrees = Vector3(180, 0, 0)
	anchor.marker_to_mannequin = anchor.sternum_offset()
	anchor.floor_locked = true
	anchor.locked = true
	anchor.has_marker_pose = true
	anchor.locked_pose.origin = Vector3(0, 0.25, 0)
	anchor.refresh()
	# With the broken raw-vertex logic the displayed chest was about 1.02 m high.
	check(anchor.global_position.y < 0.4, "skinned patient must not be lifted a metre by its bind pose")
	check(anchor.global_position.y > -0.4, "skinned floor correction stays near the real resting body")
	var lowest := INF
	for vertex in anchor._floor_vertices:
		lowest = minf(lowest, (anchor.global_transform * vertex).y)
	check(absf(lowest) < 0.0001, "resting skinned mesh contacts the configured floor")
	print("Floor regression: patient root Y=", anchor.global_position.y, " resting mesh bottom=", lowest)
	# A hand-measured chest height puts the sternum there, flattened or lowered.
	var model := patient.get_node("Model") as Node3D
	# A real marker pose cancels the scene's 180° model rotation: chest up.
	anchor.locked_pose.basis = Basis(Vector3.RIGHT, PI)
	anchor.refresh()
	var native_rise := (patient as NaretMannequin).get_sternum_transform().origin.y
	check(native_rise > 0.1, "face-up patient's sternum lies above the floor, got %s" % native_rise)
	anchor.chest_height_m = native_rise - 0.04
	anchor.chest_fit = "flatten"
	anchor.refresh()
	check(absf(patient.get_sternum_transform().origin.y - anchor.chest_height_m) < 0.003, "flatten puts the sternum on the measured chest height")
	check(absf(_lowest(anchor)) < 0.001 and model.scale.y < 0.9 and is_equal_approx(model.scale.x, 0.9), "flatten keeps the back on the floor and only thins the body")
	anchor.chest_fit = "shift"
	anchor.refresh()
	check(absf(patient.get_sternum_transform().origin.y - anchor.chest_height_m) < 0.003, "shift puts the sternum on the measured chest height")
	check(is_equal_approx(model.scale.y, 0.9) and _lowest(anchor) < -0.03, "shift keeps the thickness and lowers the body into the floor")
	anchor.chest_height_m = 0.0
	anchor.refresh()
	check(absf(_lowest(anchor)) < 0.001 and is_equal_approx(model.scale.y, 0.9), "without a chest height the patient rests on the floor unchanged")
	# The live landmark key moves the body under a fixed ring.
	var mannequin := patient as NaretMannequin
	var ring_before := mannequin.sternum.position
	var body_before := model.position
	# Relative to whatever offset the scene ships with.
	mannequin.sternum_landmark_offset += Vector3(0, 0, -0.03)
	check(mannequin.apply_sternum_landmark_offset(), "an edited landmark offset applies")
	check(mannequin.sternum.position == ring_before and model.position.is_equal_approx(body_before + Vector3(0, 0, 0.03)), "landmark offset moves the body toward the feet, not the ring")
	check(not mannequin.apply_sternum_landmark_offset(), "applying an unchanged offset does nothing")
	anchor.free()

func _lowest(anchor: NaretSpatialAnchor) -> float:
	var lowest := INF
	for vertex in anchor._floor_vertices:
		lowest = minf(lowest, (anchor.global_transform * vertex).y)
	return lowest

func _test_standing_people() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for path in ["res://scenes/bystander.tscn", "res://scenes/bystander_male.tscn"]:
		var person: NaretBystander = load(path).instantiate()
		tree.root.add_child(person)
		await tree.process_frame
		person.place_on_floor(Transform3D(Basis.IDENTITY, Vector3(1, -0.194, 2)))
		var lowest := INF
		for node in person.get_node("Model").find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			for surface in mesh.mesh.get_surface_count():
				for vertex in NaretSpatialAnchor.posed_vertices(mesh, surface):
					lowest = minf(lowest, (mesh.global_transform * vertex).y)
		check(absf(lowest + 0.194) < 0.001, path + ": visible skinned feet touch corrected floor")
		person.free()
