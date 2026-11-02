extends "res://tests/suite.gd"
## The yellow FUSED ball stays on the fused marker point (marker 0); only the patient's
## sternum is shifted, to 3 cm headward (-Z) of the midpoint of markers 0 and 1.

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var shift: Vector3 = scene.get_node("SpatialAnchor").sternum_shift_m
	scene.free()
	var layout := NaretMarkerLayout.new()
	check(layout.load_profile("res://data/user_marker_layout.cfg") == OK, "marker layout loads")
	check(layout.common_to_sternum.is_equal_approx(Transform3D.IDENTITY), "the fused point stays on marker 0")
	var midpoint := (layout.offsets[1] as Transform3D).affine_inverse().origin / 2.0
	check(shift.distance_to(midpoint + Vector3(0, 0, -0.03)) < 0.001, "the scene's sternum shift is 3 cm headward of the midpoint of markers 0 and 1: " + str(shift))

	var path := "user://sternum_shift_test.cfg"
	DirAccess.remove_absolute(path)
	var anchor := NaretSpatialAnchor.new()
	anchor.patient_anchor_axes = true
	anchor.patient_alignment_revision = 2
	anchor.sternum_at_marker_height = true
	anchor.marker_thickness_m = 0.0
	anchor.sternum_shift_m = shift
	anchor.calibration_file = path
	var patient: Node3D = load("res://scenes/mannequin.tscn").instantiate()
	patient.name = "Mannequin"
	anchor.add_child(patient)
	tree.root.add_child(anchor)
	anchor.locked = true
	anchor.has_marker_pose = true
	anchor.locked_pose = Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.3, 0.125, -0.9))
	anchor.refresh()
	var expected := anchor.locked_pose * shift
	check(patient.sternum.global_position.distance_to(expected) < 0.001, "the sternum sits at the shifted point, turning with the markers: " + str(patient.sternum.global_position))
	anchor.free()
	DirAccess.remove_absolute(path)
	return failures
