extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var path := "user://reset_old_patient_nudges_test.cfg"
	var config := ConfigFile.new()
	var scale := Vector3(0.8, 1.1, 1.2)
	var original := Transform3D(Basis.from_euler(Vector3(PI, 0.2, 0.1)) * Basis.from_scale(scale), Vector3(0.15, 0.27, -0.19))
	config.set_value("calibration", "marker_to_mannequin", original)
	config.set_value("calibration", "calibrated", true)
	config.set_value("calibration", "floor_touch_offset_m", 0.05)
	config.set_value("calibration", "floor_touch_source", "local_floor")
	config.set_value("calibration", "manual_floor_correction_m", -0.03)
	config.set_value("calibration", "chest_height_m", 0.2)
	config.set_value("calibration", "chest_fit", "shift")
	config.save(path)
	var tree := Engine.get_main_loop() as SceneTree
	var anchor := NaretSpatialAnchor.new()
	anchor.patient_anchor_axes = true
	anchor.patient_alignment_revision = 2
	anchor.calibration_file = path
	var patient: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	anchor.add_child(patient)
	tree.root.add_child(anchor)
	check(not anchor.calibrated, "discarded alignment requires explicit confirmation")
	check(anchor.marker_to_mannequin.is_equal_approx(anchor.sternum_offset(scale)), "old translation and rotation removed; scaled geometry alignment retained")
	check(anchor.marker_to_mannequin.basis.get_scale().is_equal_approx(scale), "existing size is not reset by removing nudges")
	check(is_equal_approx(anchor.floor_touch_offset_m, 0.05) and is_equal_approx(anchor.manual_floor_correction_m, -0.03) and is_equal_approx(anchor.chest_height_m, 0.2), "floor and chest measurements remain separate and unchanged")
	anchor.locked = true
	anchor.has_marker_pose = true
	anchor.locked_pose = Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.4, 0.3, -1.0))
	anchor.refresh()
	check(patient.sternum.global_position.is_equal_approx(anchor.locked_pose.origin + anchor.locked_pose.basis.y * anchor.marker_thickness_m), "without floor override, default sternum follows fused anchor with only existing thickness correction")
	var untouched := ConfigFile.new()
	untouched.load(path)
	check((untouched.get_value("calibration", "marker_to_mannequin") as Transform3D).is_equal_approx(original), "loading does not overwrite original saved data")
	check(anchor.save_calibration() == OK, "floor/chest save can safely write reset alignment")
	var saved := ConfigFile.new()
	saved.load(path)
	check((saved.get_value("previous_patient_alignment", "marker_to_mannequin") as Transform3D).is_equal_approx(original), "original alignment retained when saving replaces it")
	anchor.nudge_world(Vector3(0.01, 0, 0), 0.02)
	anchor.calibrated = true
	var deliberate := anchor.marker_to_mannequin
	check(anchor.save_calibration() == OK and anchor.load_calibration() == OK, "new deliberate alignment can be saved and loaded")
	check(anchor.calibrated and anchor.marker_to_mannequin.is_equal_approx(deliberate), "reset does not erase future deliberate nudges")
	anchor.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return failures
