extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	# The chin measurement is the chest's flat hand, held longer and allowed to be less flat.
	var samples: Array = []
	var face := PackedFloat32Array([0.30, 0.30, 0.31, 0.32, 0.33, 0.30, 0.31])
	var result := NAN
	for step in 31:
		result = NaretChestTouch.feed(samples, face, Vector3.ZERO, step * 0.1, 3.5, 0.04)
	check(not is_finite(result), "the chin hold is not accepted after 3 s")
	for step in range(31, 37):
		result = NaretChestTouch.feed(samples, face, Vector3.ZERO, step * 0.1, 3.5, 0.04)
	check(is_finite(result), "the chin hold is accepted after 3.5 s")
	samples.clear()
	check(not is_finite(NaretChestTouch.feed(samples, face, Vector3.ZERO, 0.0)) and samples.is_empty(), "a 3 cm spread is too uneven for the chest")
	var patient: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	tree.root.add_child(patient)
	# Measured from a normal neck, whatever the scene has tuned.
	patient.neck_shorten_m = 0.0
	await tree.process_frame
	await tree.process_frame
	var mouth := patient.get_node("Model").find_child("Mouth", true, false) as Node3D
	var at_mouth := mouth.global_position
	var lift := patient.head_lift_for(at_mouth)
	check(is_finite(lift) and absf(lift) < 0.05, "the face top under a hand on the mouth lies near the mouth, got %s" % lift)
	check(is_equal_approx(patient.head_lift_for(at_mouth + Vector3(0, 0.02, 0)), lift + 0.02), "a hand 2 cm higher lifts the head 2 cm more")
	var mouth_zone := (patient.get_node("MouthZone") as Node3D).position
	var chin_marker := patient.gesture_chin()
	patient.set_head_lift(0.03)
	await tree.process_frame
	await tree.process_frame
	check(is_equal_approx(mouth.global_position.y - at_mouth.y, 0.03), "the lift raises the full-body mouth, got %s" % (mouth.global_position.y - at_mouth.y))
	check((patient.get_node("MouthZone") as Node3D).position.is_equal_approx(mouth_zone + Vector3(0, 0.03, 0)), "the mouth touch zone follows the head")
	check(patient.gesture_chin().is_equal_approx(chin_marker + Vector3(0, 0.03, 0)), "the head-tilt chin zone follows the head")
	check(is_equal_approx(patient.head_lift_for(at_mouth), lift), "a second measurement does not see the first lift")
	patient.set_head_lift(0.0)
	await tree.process_frame
	await tree.process_frame
	check(mouth.global_position.is_equal_approx(at_mouth), "a zero lift returns the head")
	# A shortened neck moves the head toward the feet (+Z); the zones follow it too.
	patient.neck_shorten_m = 0.02
	await tree.process_frame
	await tree.process_frame
	check((mouth.global_position - at_mouth).is_equal_approx(patient.global_basis * Vector3(0, 0, 0.02)), "a shortened neck moves the mouth toward the feet")
	check((patient.get_node("MouthZone") as Node3D).position.is_equal_approx(mouth_zone + Vector3(0, 0, 0.02)), "the mouth touch zone follows the shorter neck")
	check(is_equal_approx(patient.head_lift_for(mouth.global_position), lift), "the chin measurement looks for the face where the shorter neck put it")
	patient.free()
	return failures
