extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var captured := ConfigFile.new()
	check(captured.load("res://tests/fixtures/patient_pivot_expected.cfg") == OK, "pre-refactor placement fixture loads")
	var tree := Engine.get_main_loop() as SceneTree
	for section in captured.get_sections():
		var anchor := NaretSpatialAnchor.new()
		anchor.patient_anchor_axes = true
		anchor.calibration_file = "user://pivot_regression_missing.cfg"
		var patient: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
		anchor.add_child(patient)
		tree.root.add_child(anchor)
		anchor.marker_to_mannequin = captured.get_value(section, "alignment")
		anchor.floor_locked = true
		anchor.floor_y = captured.get_value(section, "floor_y")
		anchor.has_marker_pose = true
		anchor.locked = true
		anchor.locked_pose = captured.get_value(section, "anchor")
		anchor.refresh()
		var fit := str(captured.get_value(section, "fit"))
		if fit != "none":
			anchor.chest_height_m = captured.get_value(section, "chest_height")
			anchor.chest_fit = fit
			anchor.refresh()
		check(patient.sternum.position.is_zero_approx(), fit + ": pivot remains on compression point, including thickness fitting")
		check(patient.global_position.is_equal_approx(patient.sternum.global_position), fit + ": patient origin is its sternum")
		var expected_body: Transform3D = captured.get_value(section, "body")
		check(patient.get_body_transform().is_equal_approx(expected_body), fit + ": authored body reference preserves previous world coordinates")
		for path in ["Model", "ScanReference", "Heart", "Sternum", "MouthZone", "ForeheadZone"]:
			var expected: Transform3D = captured.get_value(section, path)
			check((patient.get_node(path) as Node3D).global_transform.is_equal_approx(expected), fit + ": " + path + " stays in its previous world pose")
		var aed := NaretAED.new()
		aed._mannequin = patient
		for name in NaretAED.PAD_POSES:
			check(aed._pad_target(name).is_equal_approx(captured.get_value(section, name)), fit + ": AED " + name + " target preserved")
		aed.free()
		var app = load("res://scripts/main.gd").new()
		app.mannequin = patient
		app.anchor = anchor
		anchor.manual_floor_correction_m = 0.06
		check(is_equal_approx(app._patient_floor_centre().y, anchor.floor_y), fit + ": bystander centre uses floor, not chest or patient height nudge")
		var expected_rect := _rect(expected_body, [-0.35, 0.35], [-1.05, 1.05])
		check((app._local_rect([-0.35, 0.35], [-1.05, 1.05]) as Rect2).is_equal_approx(expected_rect), fit + ": bystander exclusion footprint preserved")
		app.free()
		var interaction := NaretXRInteraction.new()
		interaction._mannequin = patient
		for point in [Vector3(0, 0.2, 0), Vector3(0.33, 0.43, 1.0), Vector3(0.4, 0.2, 0), Vector3(0, -0.1, 0)]:
			var before: bool = absf(point.x) < 0.34 and point.y > -0.04 and point.y < 0.44 and point.z > -0.95 and point.z < 1.10
			check(interaction._point_near_patient(expected_body * point) == before, fit + ": whole-body contact envelope preserved")
		interaction.free()
		anchor.free()
	return failures

func _rect(frame: Transform3D, xs: Array, zs: Array) -> Rect2:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for x in xs:
		for z in zs:
			var point := frame * Vector3(x, 0, z)
			minimum = minimum.min(Vector2(point.x, point.z))
			maximum = maximum.max(Vector2(point.x, point.z))
	return Rect2(minimum, maximum - minimum)
