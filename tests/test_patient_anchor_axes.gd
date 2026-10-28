extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var standard := NaretMarkerLayout.new()
	var legacy := NaretMarkerLayout.new()
	check(standard.load_profile("res://data/user_marker_layout.cfg") == OK, "patient-axis profile loads without an axis bridge")
	check(legacy.load_profile("res://tests/fixtures/marker_layout_legacy.cfg") == OK, "old profile imports without editing saved calibration")
	check(standard.common_to_sternum.is_equal_approx(Transform3D.IDENTITY), "standard profile has no remaining axis conversion")
	var original := ConfigFile.new()
	original.load("res://tests/fixtures/marker_layout_legacy.cfg")
	for id in standard.offsets:
		var before: Transform3D = original.get_value("common", "aruco_patch%d" % id)
		var after: Transform3D = standard.offsets[id]
		check(before.origin.is_equal_approx(after.origin), "marker %d common-point translation unchanged" % id)
	var captured := ConfigFile.new()
	check(captured.load("res://tests/fixtures/marker_layout_expected.cfg") == OK, "pre-change poses available")
	for section in captured.get_sections():
		var poses: Dictionary = captured.get_value(section, "world_poses")
		var expected: Transform3D = (captured.get_value(section, "expected") as Transform3D) * NaretMarkerLayout.LEGACY_ANCHOR_FLIP
		for layout in [standard, legacy]:
			layout.floor_orientation = bool(captured.get_value(section, "floor_orientation"))
			var result: Dictionary = layout.fuse(poses)
			check(not result.is_empty(), section + " remains usable")
			if result.is_empty():
				continue
			check((result.pose as Transform3D).is_equal_approx(expected), section + " preserves common point and produces the equivalent Y-up anchor")
			check(is_equal_approx(float(result.position_spread_m), float(captured.get_value(section, "spread"))), section + " preserves marker disagreement")
			check(result.ids.size() == poses.size(), section + " preserves contributing markers")
			if layout.floor_orientation:
				check((result.pose as Transform3D).basis.y.is_equal_approx(Vector3.UP), section + " has patient-style +Y up")
	# New profiles may still provide a physically measured chest displacement.
	standard.floor_orientation = false
	var measurement := Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.2, 0.3, -1.0))
	var raw := measurement * (standard.offsets[0] as Transform3D).affine_inverse()
	standard.common_to_sternum = Transform3D(Basis.IDENTITY, Vector3(0, 0.02, -0.06))
	check((standard.fuse({0: raw}).pose as Transform3D).is_equal_approx(measurement * standard.common_to_sternum), "physical chest offset remains distinct from axis convention")
	_test_saved_alignment(captured)
	_test_default_alignment()
	return failures

func _test_saved_alignment(captured: ConfigFile) -> void:
	var path := "user://patient_axis_migration_test.cfg"
	var config := ConfigFile.new()
	var previous := Transform3D(Basis.from_euler(Vector3(PI + 0.02, 0.07, -0.01)).scaled(Vector3(0.8, 1.1, 0.9)), Vector3(0.07, 0.205, -0.199))
	config.set_value("calibration", "marker_to_mannequin", previous)
	config.set_value("calibration", "calibrated", true)
	config.save(path)
	var anchor := NaretSpatialAnchor.new()
	anchor.patient_anchor_axes = true
	anchor.calibration_file = path
	check(anchor.load_calibration() == OK, "legacy device alignment loads into patient axes")
	for section in captured.get_sections():
		var old_pose: Transform3D = captured.get_value(section, "expected")
		var new_pose := old_pose * NaretMarkerLayout.LEGACY_ANCHOR_FLIP
		check((old_pose * previous).is_equal_approx(new_pose * anchor.marker_to_mannequin), section + " preserves saved world model placement")
	check(anchor.save_calibration() == OK, "new saved alignment records its coordinate frame")
	var converted := anchor.marker_to_mannequin
	check(anchor.load_calibration() == OK and anchor.marker_to_mannequin.is_equal_approx(converted), "loading new alignment does not convert twice")
	anchor.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _test_default_alignment() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var old_anchor := NaretSpatialAnchor.new()
	old_anchor.calibration_file = "user://axis_default_missing_old.cfg"
	old_anchor.default_model_rotation_degrees = Vector3(180, 0, 0)
	var old_patient: Node3D = load("res://scenes/mannequin.tscn").instantiate()
	old_anchor.add_child(old_patient)
	tree.root.add_child(old_anchor)
	var new_anchor := NaretSpatialAnchor.new()
	new_anchor.calibration_file = "user://axis_default_missing_new.cfg"
	new_anchor.patient_anchor_axes = true
	var new_patient: Node3D = load("res://scenes/mannequin.tscn").instantiate()
	new_anchor.add_child(new_patient)
	tree.root.add_child(new_anchor)
	var old_pose := Transform3D(Basis(Vector3.RIGHT, PI) * Basis(Vector3.UP, 0.4), Vector3(0.5, 0.3, -1.0))
	old_anchor._apply(old_pose)
	new_anchor._apply(old_pose * NaretMarkerLayout.LEGACY_ANCHOR_FLIP)
	check(old_anchor.global_transform.is_equal_approx(new_anchor.global_transform), "default body placement including marker thickness is preserved")
	check((old_patient.get("sternum") as Node3D).global_position.is_equal_approx((new_patient.get("sternum") as Node3D).global_position), "default compression point is preserved")
	old_anchor.free()
	new_anchor.free()
