extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var anchor := NaretSpatialAnchor.new()
	anchor.calibration_file = "user://test_saved_height.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(anchor.calibration_file))
	(Engine.get_main_loop() as SceneTree).root.add_child(anchor)
	anchor.calibrated = true
	anchor.locked = true
	anchor.has_marker_pose = true
	anchor.locked_pose = Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0))
	anchor.marker_to_mannequin = Transform3D(Basis.IDENTITY, Vector3(0, -0.2, 0))
	anchor.floor_locked = true
	anchor.floor_y = -0.8
	anchor.refresh()
	check(is_equal_approx(anchor.global_position.y, 0.1), "saved marker-relative height wins over floor snapping")
	anchor.floor_y = 0.6
	anchor.refresh()
	check(is_equal_approx(anchor.global_position.y, 0.1), "floor reference change cannot move calibrated patient")
	anchor.floor_adjustment_m = 0.03
	anchor.refresh()
	check(is_equal_approx(anchor.global_position.y, 0.13), "manual vertical nudge applies once")
	check(anchor.save_calibration() == OK, "height calibration saves")
	anchor.floor_adjustment_m = 0.0
	check(anchor.load_calibration() == OK, "height calibration reloads")
	anchor.refresh()
	check(is_equal_approx(anchor.global_position.y, 0.13), "saved vertical nudge survives reload")
	var legacy := ConfigFile.new()
	legacy.load(anchor.calibration_file)
	legacy.erase_section_key("calibration", "marker_height_lock")
	legacy.set_value("calibration", "floor_adjustment_m", -0.194)
	legacy.save(anchor.calibration_file)
	anchor.load_calibration()
	anchor.refresh()
	check(is_equal_approx(anchor.global_position.y, -0.094), "legacy profile preserves the saved downward nudge")
	anchor.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_saved_height.cfg"))
	return failures
