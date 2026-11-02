extends "res://tests/suite.gd"
## Confirmed checkpoints closer than 1.5 cm / 5 deg are marker noise: the patient holds.

class StubGate extends NaretViewerMotionGate:
	var next := {}
	func evaluate(_raw: Transform3D, _display: Transform3D, _ms: int, _full := true) -> Dictionary:
		return next

func run() -> Array[String]:
	failures.clear()
	var scene_text := FileAccess.get_file_as_string("res://scenes/main.tscn")
	check("checkpoint_updates = true" in scene_text, "the app places the patient by confirmed checkpoints only")
	var tree := Engine.get_main_loop() as SceneTree
	var anchor := NaretSpatialAnchor.new()
	anchor.calibration_file = "user://checkpoint_hold_missing.cfg"
	anchor.checkpoint_updates = true
	tree.root.add_child(anchor)
	var head := Node3D.new()
	tree.root.add_child(head)
	var gate := StubGate.new()
	anchor.viewer_head = head
	anchor.viewer_gate = gate
	var start := Transform3D(Basis.IDENTITY, Vector3(0.3, 0.2, -0.9))
	anchor.locked = true
	anchor.has_marker_pose = true
	anchor.locked_pose = start
	gate.next = {"pose": Transform3D(Basis(Vector3.UP, deg_to_rad(2.0)), start.origin + Vector3(0.01, 0, 0)), "samples": 30}
	anchor.update_pose(start, 1000)
	check(not anchor._checkpoint_transition, "a 1 cm / 2 deg checkpoint does not move the patient")
	gate.next = {"pose": Transform3D(Basis.IDENTITY, start.origin + Vector3(0.05, 0, 0)), "samples": 30}
	anchor.update_pose(start, 2000)
	check(anchor._checkpoint_transition and anchor._checkpoint_target.origin.is_equal_approx(start.origin + Vector3(0.05, 0, 0)), "a 5 cm move is followed")
	anchor.free()
	head.free()
	return failures
