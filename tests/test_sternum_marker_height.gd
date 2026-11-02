extends "res://tests/suite.gd"

func _place(at_marker: bool) -> Vector3:
	var tree := Engine.get_main_loop() as SceneTree
	var path := "user://sternum_marker_height_test.cfg"
	DirAccess.remove_absolute(path)
	var anchor := NaretSpatialAnchor.new()
	anchor.patient_anchor_axes = true
	anchor.patient_alignment_revision = 2
	anchor.sternum_at_marker_height = at_marker
	anchor.calibration_file = path
	var patient: Node3D = load("res://scenes/mannequin.tscn").instantiate()
	patient.name = "Mannequin"
	anchor.add_child(patient)
	tree.root.add_child(anchor)
	anchor.floor_locked = true
	anchor.floor_y = 0.0
	anchor.locked = true
	anchor.has_marker_pose = true
	anchor.locked_pose = Transform3D(Basis.IDENTITY, Vector3(0.3, 0.125, -0.9))
	anchor.refresh()
	if at_marker:
		check(patient.position.is_zero_approx(), "the patient pivot sits directly on the anchor")
		check(anchor.marker_to_mannequin.origin.is_equal_approx(Vector3(0, 0.002, 0)), "the alignment holds only the marker thickness: " + str(anchor.marker_to_mannequin.origin))
	var sternum: Vector3 = patient.sternum.global_position
	if at_marker:
		var ground := anchor.patient_bottom_y()
		check(ground < sternum.y - 0.1 and ground > sternum.y - 0.35, "the ground follows the placed patient, below its sternum: " + str(ground))
		anchor.locked_pose.origin.y += 0.1
		anchor.refresh()
		check(is_equal_approx(anchor.patient_bottom_y(), ground + 0.1), "the ground moves with the patient")
		anchor.locked_pose.origin.y -= 0.1
		anchor.refresh()
	anchor.free()
	return sternum

func run() -> Array[String]:
	failures.clear()
	var scene_text := FileAccess.get_file_as_string("res://scenes/main.tscn")
	check("marker_thickness_m = 0.0" in scene_text, "the main scene adds no marker thickness")
	var on_marker := _place(true)
	check(on_marker.distance_to(Vector3(0.3, 0.127, -0.9)) < 0.001, "sternum sits on the fused point in all three axes, plus marker thickness: " + str(on_marker))
	var on_floor := _place(false)
	check(on_floor.y > 0.15, "the floor-resting mode is unchanged for other scenes: " + str(on_floor))
	return failures
