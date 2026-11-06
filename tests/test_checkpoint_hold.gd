extends "res://tests/suite.gd"
## Confirmed checkpoints closer than 1.5 cm / 5 deg are marker noise: the patient holds. A
## larger move must be confirmed from a second viewpoint (2026-11-06).

class StubGate extends NaretViewerMotionGate:
	var next := {}
	func evaluate(_raw: Transform3D, _display: Transform3D, _ms: int, _full := true) -> Dictionary:
		return next

func run() -> Array[String]:
	failures.clear()
	var scene_text := FileAccess.get_file_as_string("res://scenes/main.tscn")
	# Quest build 2026-11-06: the viewer gate (10 cm / 10 deg viewpoint bias, rest pull, big moves
	# confirmed at 30/33/... readings) places the patient; checkpoint mode stays opt-in here.
	check("checkpoint_updates = false" in scene_text, "the Quest build follows the mannequin with the viewer gate")
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
	# A 5 cm move from one viewpoint waits; the same viewpoint again is no second opinion.
	var moved := Transform3D(Basis.IDENTITY, start.origin + Vector3(0.05, 0, 0))
	gate.next = {"pose": moved, "samples": 30}
	anchor.update_pose(start, 2000)
	check(not anchor._checkpoint_transition, "one viewpoint does not move the patient")
	anchor.update_pose(start, 3000)
	check(not anchor._checkpoint_transition, "the same viewpoint twice does not move the patient")
	# Another viewpoint that disagrees (a viewing error) holds.
	head.position = Vector3(0.5, 0, 0)
	gate.next = {"pose": Transform3D(Basis.IDENTITY, start.origin + Vector3(0.0, 0, 0.04)), "samples": 30}
	anchor.update_pose(start, 4000)
	check(not anchor._checkpoint_transition, "viewpoints that disagree hold the patient")
	# Two viewpoints that agree within 2.5 cm: a real move, followed.
	head.position = Vector3(-0.3, 0, 0)
	gate.next = {"pose": moved, "samples": 30}
	anchor.update_pose(start, 5000)
	head.position = Vector3(0.3, 0, 0.2)
	gate.next = {"pose": Transform3D(Basis.IDENTITY, start.origin + Vector3(0.06, 0, 0.01)), "samples": 30}
	anchor.update_pose(start, 6000)
	check(anchor._checkpoint_transition and anchor._checkpoint_target.origin.distance_to(start.origin + Vector3(0.055, 0, 0.005)) < 0.002, "a move confirmed from two viewpoints is followed")
	# A pending move that a later viewpoint does not see is dropped.
	anchor._checkpoint_transition = false
	head.position = Vector3(0.8, 0, 0)
	gate.next = {"pose": moved, "samples": 30}
	anchor.update_pose(start, 7000)
	head.position = Vector3(-0.8, 0, 0)
	gate.next = {"pose": Transform3D(Basis.IDENTITY, start.origin + Vector3(0.005, 0, 0)), "samples": 30}
	anchor.update_pose(start, 8000)
	check(anchor._pending_checkpoint.is_empty() and not anchor._checkpoint_transition, "a move not seen from the next viewpoint is dropped")
	anchor.free()
	head.free()
	return failures
