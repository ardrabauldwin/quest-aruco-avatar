extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var head := Node3D.new()
	tree.root.add_child(head)
	head.position = Vector3(0, 1, 0)
	var gate := NaretViewerMotionGate.new()
	gate.moving = false
	gate.head = head
	var placed := Transform3D.IDENTITY
	var raw := Transform3D(Basis.IDENTITY, Vector3(0.04, 0, 0))
	check(gate.evaluate(raw, placed, 0).is_empty(), "initial head settling holds")
	for i in range(60): gate.tick(0.01)
	for i in range(20):
		check(gate.evaluate(raw,placed,100+i).is_empty(), "small outside offset holds without bias collection")
	raw.origin.x = 0.06
	check(gate.evaluate(raw,placed,125).is_empty(), "later six-cm offset also holds")
	check(gate.evaluate(raw,placed,126,false).is_empty() and gate.gate_state=="hold_partial", "partial evidence holds")
	check(gate.evaluate(raw,placed,127,true).is_empty(), "evidence return does not release small displacement")
	head.position.x += 0.1
	gate.tick(0.01)
	check(gate.evaluate(raw, placed, 106).is_empty(), "head movement holds avatar")
	gate = NaretViewerMotionGate.new()
	gate.moving = false
	gate.head = head
	raw.origin.x = 0.4
	raw.basis = Basis(Vector3.UP,deg_to_rad(20.0))
	check(gate.evaluate(raw, placed, 200, false).is_empty(), "partial markers cannot trigger large-move override")
	# Since 2026-11-06 a big move is confirmed like the startup placement: 30, 33, ... readings
	# whose robust estimate holds four times in a row (earliest at 42), so a few mirrored or
	# stray readings cannot move the patient.
	var held := true
	for i in range(41):
		held = held and gate.evaluate(raw, placed, 201 + i).is_empty()
	check(held and gate.gate_state == "big_collecting", "41 agreeing big readings still hold")
	var big := gate.evaluate(raw, placed, 242)
	check(not big.is_empty() and big.get("confirmed", false) and big.pose.origin.is_equal_approx(Vector3(0.4, 0, 0)), "42 agreeing big readings confirm the move")
	check(not gate.evaluate(raw, placed, 243).is_empty(), "readings near the confirmed pose keep passing while the patient glides")
	gate = NaretViewerMotionGate.new()
	gate.moving = false
	gate.head = head
	for i in range(20):
		gate.evaluate(raw, placed, 250 + i)
	var spike := Transform3D(Basis(Vector3.UP,deg_to_rad(20.0)), Vector3(0.0, 0, 0.35))
	for i in range(3):
		gate.evaluate(spike, placed, 270 + i)
	var went_to_spike := false
	var confirmed_pose := Transform3D.IDENTITY
	for i in range(30):
		var r := gate.evaluate(raw, placed, 280 + i)
		if not r.is_empty():
			went_to_spike = went_to_spike or r.pose.origin.distance_to(spike.origin) < 0.05
			confirmed_pose = r.pose
	check(not went_to_spike and confirmed_pose.origin.is_equal_approx(Vector3(0.4, 0, 0)), "three stray readings neither move the patient to them nor block the real move")
	gate = NaretViewerMotionGate.new()
	gate.moving = false
	gate.head = head
	for i in range(60): gate.tick(0.01)
	raw = Transform3D(Basis(Vector3.UP, deg_to_rad(4.0)), Vector3.ZERO)
	for i in range(4): gate.evaluate(raw, placed, 300+i)
	check(gate.evaluate(raw, placed, 304).is_empty(), "yaw-only change holds without heading bias")
	gate = NaretViewerMotionGate.new()
	gate.moving = false
	gate.head = head
	for i in range(60): gate.tick(0.01)
	raw = Transform3D(Basis.IDENTITY, Vector3(0.15, 0, 0))
	var result: Dictionary = {}
	for i in range(5): result = gate.evaluate(raw, placed, 400+i, false)
	check(result.is_empty() and gate.gate_state == "hold_partial", "partial evidence cannot establish a 15 cm move")
	var anchor := NaretSpatialAnchor.new()
	anchor.manual_reposition_only = false
	anchor.calibration_file = "user://viewer_gate_test_unused.cfg"
	tree.root.add_child(anchor)
	anchor.marker_to_mannequin = Transform3D.IDENTITY
	anchor.viewer_head = head
	anchor.locked = true
	anchor.locked_pose = placed
	for i in range(60): anchor._process(0.01)
	for i in range(5): anchor.update_pose(Transform3D(Basis.IDENTITY, Vector3(0.04, 0, 0)), 500+i)
	check(anchor.global_position.is_equal_approx(Vector3.ZERO), "anchor receives gate-corrected pose, not raw 4 cm shift")
	check(anchor._viewer_filter == null, "held outside estimates never initialize the movement filter")
	for i in range(12):
		var jitter := 0.015 if i % 2 == 0 else -0.015
		anchor.update_pose(Transform3D(Basis.IDENTITY, Vector3(0.04 + jitter, 0, 0)), 600 + i * 120)
	check(anchor.global_position.is_equal_approx(Vector3.ZERO), "stationary fifteen-millimetre jitter does not move the patient")
	anchor.unlock()
	check(not anchor.locked and anchor._viewer_filter == null and anchor.viewer_gate.moving, "explicit reposition resets gate and smoothing")
	anchor.free()
	head.free()
	return failures
