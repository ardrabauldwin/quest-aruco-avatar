extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var head := Node3D.new()
	tree.root.add_child(head)
	head.position = Vector3(0, 1, 0)
	var gate := NaretViewerMotionGate.new()
	gate.head = head
	var placed := Transform3D.IDENTITY
	var raw := Transform3D(Basis.IDENTITY, Vector3(0.04, 0, 0))
	check(gate.evaluate(raw, placed, 0).is_empty(), "initial head settling holds")
	for i in range(60): gate.tick(0.01)
	for i in range(4):
		check(gate.evaluate(raw, placed, 100+i).is_empty(), "wait for five fresh readings")
	check(gate.evaluate(raw, placed, 103).is_empty(), "duplicate reading cannot finish window")
	var result := gate.evaluate(raw, placed, 104)
	check(result.pose.origin.is_equal_approx(Vector3.ZERO), "initial 4 cm bias is cancelled")
	raw.origin.x = 0.06
	check(gate.evaluate(raw, placed, 105).pose.origin.is_equal_approx(Vector3(0.02, 0, 0)), "later 6 cm reading leaves 2 cm motion")
	var partial_pose := Transform3D(Basis.IDENTITY, Vector3(0.20, 0, 0))
	check(gate.evaluate(partial_pose, placed, 106, false).is_empty(), "partial evidence holds even after viewpoint bias is established")
	check(gate.gate_state == "hold_partial", "partial evidence exposes hold state after settling")
	check(gate.evaluate(raw, placed, 107, true).pose.origin.is_equal_approx(Vector3(0.02, 0, 0)), "full evidence resumes using preserved bias")
	head.position.x += 0.1
	gate.tick(0.01)
	check(gate.evaluate(raw, placed, 106).is_empty(), "head movement holds avatar")
	gate = NaretViewerMotionGate.new()
	gate.head = head
	raw.origin.x = 0.4
	check(gate.evaluate(raw, placed, 200, false).is_empty(), "partial markers cannot trigger large-move override")
	check(gate.evaluate(raw, placed, 201).is_empty(), "big move needs three detections")
	check(gate.evaluate(raw, placed, 202).is_empty(), "two detections still hold")
	check(not gate.evaluate(raw, placed, 203).is_empty(), "three full detections retain old large-move override")
	gate = NaretViewerMotionGate.new()
	gate.head = head
	for i in range(60): gate.tick(0.01)
	raw = Transform3D(Basis(Vector3.UP, deg_to_rad(4.0)), Vector3.ZERO)
	for i in range(4): gate.evaluate(raw, placed, 300+i)
	check(gate.evaluate(raw, placed, 304).pose.basis.is_equal_approx(Basis.IDENTITY), "patient -Z heading bias cancels with correct rotation sign")
	gate = NaretViewerMotionGate.new()
	gate.head = head
	for i in range(60): gate.tick(0.01)
	raw = Transform3D(Basis.IDENTITY, Vector3(0.15, 0, 0))
	for i in range(5): result = gate.evaluate(raw, placed, 400+i, false)
	check(result.is_empty() and gate.gate_state == "hold_partial", "partial evidence cannot establish a 15 cm move")
	var anchor := NaretSpatialAnchor.new()
	anchor.calibration_file = "user://viewer_gate_test_unused.cfg"
	tree.root.add_child(anchor)
	anchor.marker_to_mannequin = Transform3D.IDENTITY
	anchor.viewer_head = head
	anchor.locked = true
	anchor.locked_pose = placed
	for i in range(60): anchor._process(0.01)
	for i in range(5): anchor.update_pose(Transform3D(Basis.IDENTITY, Vector3(0.04, 0, 0)), 500+i)
	check(anchor.global_position.is_equal_approx(Vector3.ZERO), "anchor receives gate-corrected pose, not raw 4 cm shift")
	check(anchor._viewer_filter.get("window") == 5, "original five-pose filter configuration is restored")
	check(is_equal_approx(anchor._viewer_filter.get("position_dead_zone_m"), 0.020), "original twenty-millimetre dead zone is restored")
	check(is_equal_approx(anchor._viewer_filter.get("smoothing_time_s"), 1.2), "original smoothing duration is restored")
	for i in range(12):
		var jitter := 0.015 if i % 2 == 0 else -0.015
		anchor.update_pose(Transform3D(Basis.IDENTITY, Vector3(0.04 + jitter, 0, 0)), 600 + i * 120)
	check(anchor.global_position.is_equal_approx(Vector3.ZERO), "stationary fifteen-millimetre jitter does not move the patient")
	anchor.unlock()
	check(not anchor.locked and anchor._viewer_filter == null and anchor.viewer_gate.moving, "explicit reposition resets gate and smoothing")
	anchor.free()
	head.free()
	return failures
