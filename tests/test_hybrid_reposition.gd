extends "res://tests/suite.gd"

func run() -> Array[String]:
	var tree := Engine.get_main_loop() as SceneTree
	var head := Node3D.new()
	tree.root.add_child(head)
	var anchor := NaretSpatialAnchor.new()
	anchor.manual_reposition_only=false
	anchor.calibration_file="user://hybrid_reposition_missing.cfg"
	anchor.viewer_head=head
	var patient := Node3D.new()
	patient.name="Mannequin"
	anchor.add_child(patient)
	tree.root.add_child(anchor)
	var initial := Transform3D.IDENTITY
	for i in range(42):anchor.update_pose(initial,1000+i)
	for i in range(100):anchor._process(.01)
	check(anchor.locked, "hybrid mode retains initial42reading placement")
	var small := initial
	small.origin.x=.10
	for i in range(110):anchor.update_pose(small,2000+i)
	check(anchor.locked_pose.is_equal_approx(initial), "small displacement never moves automatically")
	var main = load("res://scripts/main.gd").new()
	main.anchor=anchor
	main._reposition_patient()
	check(not anchor.locked and not patient.visible and anchor.global_transform.is_equal_approx(initial), "button opens collection without applying pending ten-cm raw pose")
	for i in range(41):anchor.update_pose(small,3000+i)
	check(not anchor.locked, "button requested small move needs fresh confirmation")
	anchor.update_pose(small,3041)
	for i in range(100):anchor._process(.01)
	check(anchor.locked_pose.is_equal_approx(small), "button can accept a small ten-cm change")
	var large := small
	large.origin.x+=.20
	large.basis=Basis(Vector3.UP,deg_to_rad(20.0))
	for i in range(41):anchor.update_pose(large,4000+i)
	check(anchor.locked_pose.is_equal_approx(small), "twenty-cm move waits for automatic confirmation")
	anchor.update_pose(large,4041)
	check(anchor.viewer_gate.gate_state=="follow_big", "above15cm confirms without pressing a button")
	check(anchor.locked_pose.is_equal_approx(small), "automatic confirmation does not teleport the displayed patient")
	check(anchor._viewer_rest_pose.is_equal_approx(large) and anchor._viewer_filter.window==1 and not anchor._viewer_filter.automatic_reanchor, "new automatic destination owns rest without post-medoid or endpoint reanchor")
	check(is_equal_approx(anchor._viewer_filter.smoothing_time_s,1.2) and is_equal_approx(anchor._viewer_filter.prior_time_s,2.0), "automatic move retains smoothing and rest pull")
	for i in range(1,101):
		anchor._process(.1)
		anchor.update_pose(large,4041+i*100)
	check(anchor.locked_pose.origin.distance_to(large.origin)<.002, "confirmed automatic movement smoothly converges")
	var heading := large
	heading.basis=Basis(Vector3.UP,deg_to_rad(40.0))
	for i in range(60):anchor.update_pose(heading,14500+i)
	check(anchor._viewer_rest_pose.is_equal_approx(large), "rotation-only change cannot replace destination when distance is within15cm")
	var translation := large
	translation.origin.x+=.20
	for i in range(60):anchor.update_pose(translation,14600+i)
	check(anchor._viewer_rest_pose.is_equal_approx(large), "translation-only change cannot replace destination when heading is within15degrees")
	var combined := heading
	combined.origin.x+=.20
	for i in range(41):anchor.update_pose(combined,14700+i)
	check(anchor._viewer_rest_pose.is_equal_approx(large), "combined candidate still needs checkpoint confirmation")
	anchor.update_pose(combined,14741)
	check(anchor._viewer_rest_pose.is_equal_approx(combined), "both components above15 can confirm the next fixed destination")
	check(anchor._viewer_filter.measurement_target().is_equal_approx(combined), "confirmed combined target goes directly to smoothing")
	var held := anchor.locked_pose
	head.position.x+=.20
	anchor._process(.01)
	large.origin.x+=.40
	for i in range(20):
		anchor.update_pose(large,15000+i)
		anchor._process(.01)
	check(anchor.locked_pose.is_equal_approx(held), "head movement still holds above15cm")
	main.free()
	anchor.free()
	head.free()
	return failures
