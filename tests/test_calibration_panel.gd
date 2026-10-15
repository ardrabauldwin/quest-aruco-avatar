extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var anchor := NaretSpatialAnchor.new()
	anchor.calibration_file = "user://compact_panel_test.cfg"
	tree.root.add_child(anchor)
	anchor.has_marker_pose = true
	anchor.locked_pose = Transform3D.IDENTITY
	anchor.locked = true
	var scale := Vector3(0.8, 1.1, 1.3)
	anchor.marker_to_mannequin = Transform3D(Basis.from_scale(scale), Vector3.ZERO)
	anchor.calibrated = true
	anchor.patient_opacity = 0.45
	anchor.floor_adjustment_m = 0.025
	check(anchor.save_calibration() == OK, "existing scaled calibration saved")
	var restored := NaretSpatialAnchor.new()
	restored.calibration_file = anchor.calibration_file
	check(restored.load_calibration() == OK, "display preferences load with existing calibration")
	check(is_equal_approx(restored.patient_opacity, 0.45), "patient opacity survives saving")
	check(is_equal_approx(restored.floor_adjustment_m, 0.025), "patient height adjustment survives saving")
	restored.free()
	var panel := NaretCalibrationPanel.new()
	panel.anchor = anchor
	tree.root.add_child(panel)
	check(panel._values.size() == 6, "only six adjustment fields")
	panel._values[0].value = 0.2
	panel._values[4].value = 30.0
	check(anchor.marker_to_mannequin.origin.is_equal_approx(Vector3(0.2, 0, 0)), "translation previews immediately")
	check(anchor.marker_to_mannequin.basis.get_scale().is_equal_approx(scale), "rotation preserves nonuniform model scale")
	check(anchor.global_transform.is_equal_approx(anchor.marker_to_mannequin), "preview refresh applies alignment")
	var saved := ConfigFile.new()
	saved.load(anchor.calibration_file)
	check(saved.get_value("calibration", "marker_to_mannequin").origin.is_equal_approx(Vector3.ZERO), "preview does not persist")
	anchor.locked = false
	panel._save_alignment()
	saved.load(anchor.calibration_file)
	check(saved.get_value("calibration", "marker_to_mannequin").origin.is_equal_approx(Vector3.ZERO), "save blocked before placement complete")
	anchor.locked = true
	panel._save_alignment()
	saved.load(anchor.calibration_file)
	check(saved.get_value("calibration", "marker_to_mannequin").is_equal_approx(anchor.marker_to_mannequin), "save uses existing calibration format")
	anchor.calibration_file = "user://missing_panel_directory/calibration.cfg"
	panel._save_alignment()
	check(panel._message.text == "Save failed" and not anchor.calibrated, "save failure handled")
	var preview := anchor.marker_to_mannequin
	panel._close_panel()
	check(anchor.marker_to_mannequin.is_equal_approx(preview), "close retains in-memory preview")
	await tree.process_frame
	anchor.free()
	return failures
