extends "res://tests/suite.gd"
## AED clearance: only a hand on the patient is contact. A learner kneeling beside the
## body or working the AED next to the shoulder must not revoke the clearance
## (the 9 Nov 2026 sessions never reached the shock advice because of that).

func run() -> Array[String]:
	var patient: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	var root := Node3D.new()
	root.add_child(patient)
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	var interaction := NaretXRInteraction.new()
	interaction._mannequin = patient
	var body: Transform3D = patient.get_body_transform()
	# Body frame: origin at back level under the sternum, +Y up, Z along the body.
	var cases := [
		[Vector3(0.0, 0.21, 0.0), true, "palm on the sternum is contact"],
		[Vector3(0.0, 0.26, 0.0), true, "palm 5 cm above the chest, hovering before a press, is contact"],
		[Vector3(0.08, 0.15, -0.3), true, "hand on the belly near the centre line is contact"],
		[Vector3(0.20, 0.15, -0.3), false, "hand beyond the 10 cm band beside the body is clear"],
		[Vector3(0.0, 0.34, 0.0), false, "hand 13 cm above the chest is clear"],
		[Vector3(0.30, 0.30, 0.0), false, "hand resting on the kneeling learner's thigh beside the body is clear"],
		[Vector3(0.33, 0.10, 0.6), false, "hand at the AED next to the shoulder is clear"],
		[Vector3(0.0, 0.20, 1.3), false, "hand beyond the head is clear"],
		[Vector3(0.0, -0.10, 0.0), false, "point under the floor is clear"],
	]
	for item in cases:
		var point: Vector3 = item[0]
		check(interaction._point_near_patient(body * point) == bool(item[1]), str(item[2]))
	check(interaction.CONTACT_POLLS_TO_REVOKE >= 2, "a single 0.15 s poll never revokes clearance")
	interaction.free()
	root.get_parent().remove_child(root)
	root.free()
	return failures
