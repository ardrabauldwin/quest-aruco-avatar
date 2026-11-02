extends "res://tests/suite.gd"
const Gate = preload("res://scripts/tracking/checkpoint_motion_gate.gd")


func run() -> Array[String]:
	failures.clear()
	var head := Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(head)
	head.position.y = 1.0
	var gate = Gate.new()
	gate.head = head
	gate.moving = false
	var pose := Transform3D(Basis.IDENTITY, Vector3(0.12, 0, 0))
	for i in range(41):
		check(gate.evaluate(pose, Transform3D.IDENTITY, i).is_empty(), "candidate must not pass before 42 detections")
	check(gate.evaluate(pose, Transform3D.IDENTITY, 40).is_empty(), "duplicate cannot complete confirmation")
	var accepted: Dictionary = gate.evaluate(pose, Transform3D.IDENTITY, 41)
	check(accepted.get("samples", 0) == 42, "four stable comparisons accept at 42")
	check(accepted.get("pose", Transform3D.IDENTITY).origin.is_equal_approx(pose.origin), "confirmed 12 cm move is not subtracted as bias")
	for i in range(42, 72): gate.evaluate(pose, Transform3D.IDENTITY, i)
	gate.evaluate(pose, Transform3D.IDENTITY, 72, false)
	check(gate.candidate_readings == 0, "missing evidence discards candidate history")
	gate.moving = true
	var large := Transform3D(Basis.IDENTITY, Vector3(0.5, 0, 0))
	for i in range(73, 80):
		check(gate.evaluate(large, Transform3D.IDENTITY, i).is_empty(), "no large-change bypass during movement")
	gate.moving = false
	# Contradictory recent readings must not pass just because an accumulated median is stable.
	for i in range(80, 200):
		pose.origin.x = 0.1 if i % 2 == 0 else 0.2
		check(gate.evaluate(pose, Transform3D.IDENTITY, i).is_empty(), "inconsistent candidate cannot force acceptance at 100")
	check(gate.candidate.samples.size() <= 100, "long uncertainty has bounded memory")
	gate = Gate.new()
	gate.head = head
	for i in range(60): gate.tick(0.01)
	head.rotation.x = 0.3
	gate.tick(0.01)
	check(gate.moving, "pitch movement closes experimental gate")
	for i in range(90): gate.tick(0.01)
	check(not gate.moving, "head can settle after pitch motion")
	head.rotation.z = 0.3
	gate.tick(0.01)
	check(gate.moving, "roll movement closes experimental gate")
	head.rotation = Vector3.ZERO
	var anchor := NaretSpatialAnchor.new()
	anchor.checkpoint_updates = true
	anchor.calibration_file = "user://checkpoint_test_unused.cfg"
	(Engine.get_main_loop() as SceneTree).root.add_child(anchor)
	anchor.marker_to_mannequin = Transform3D.IDENTITY
	anchor.viewer_head = head
	anchor.locked = true
	anchor.locked_pose = Transform3D.IDENTITY
	for i in range(60): anchor._process(0.01)
	pose.origin.x = 0.12
	for i in range(42): anchor.update_pose(pose, 1000 + i)
	check(anchor.locked_pose.origin.is_zero_approx(), "confirmation does not teleport patient")
	check(anchor._viewer_rest_pose.origin.is_equal_approx(pose.origin), "confirmed target becomes new rest immediately")
	for i in range(120): anchor._process(0.01)
	check(anchor.locked_pose.origin.x > 0.05 and anchor.locked_pose.origin.x < 0.12, "frame-time smoothing moves toward confirmed rest")
	anchor.full_marker_evidence = false
	var held := anchor.locked_pose
	anchor._process(0.01)
	check(anchor.locked_pose.is_equal_approx(held), "loss of evidence stops transition")
	anchor.unlock()
	check(anchor.viewer_gate.get_script() == Gate and not anchor._checkpoint_transition, "unlock keeps experiment and clears transition")
	anchor.free()
	head.free()
	return failures
