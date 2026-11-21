extends "res://tests/suite.gd"

func run() -> Array[String]:
	failures.clear()
	var startup := NaretStartupPlacement.new()
	var pose := Transform3D(Basis.IDENTITY, Vector3(1, 0.2, -1))
	for i in range(41):
		check(startup.observe(pose, i).is_empty(), "startup cannot confirm before reading 42")
	check(startup.observe(pose, 40).is_empty(), "duplicate reading does not count")
	var result := startup.observe(pose, 41)
	check(not result.is_empty() and result.samples == 42 and not result.fallback, "four stable comparisons confirm at 42")
	check(result.pose.is_equal_approx(pose), "stable startup pose preserved")
	startup = NaretStartupPlacement.new()
	for i in range(99):
		pose.origin.x = i * 0.1
		check(startup.observe(pose, i).is_empty(), "moving estimates do not converge")
	pose.origin.x = 9.9
	result = startup.observe(pose, 99)
	check(result.fallback and result.samples == 100, "original fallback remains explicitly labelled at 100")
	check(is_equal_approx(result.pose.origin.x, 4.95), "fallback uses coordinate median over all samples")
	# A poor view: a reading every 0.7 s, each a few centimetres off the last.
	startup = NaretStartupPlacement.new()
	var slow: Dictionary = {}
	var at_ms := 0
	for i in range(40):
		pose.origin.x = 1.0 + 0.03 * sin(i * 1.7)
		slow = startup.observe(pose, i * 700)
		at_ms = i * 700
		if not slow.is_empty(): break
	check(not slow.is_empty() and slow.fallback, "a slow, unsettled view is placed by time, labelled as a fallback")
	check(at_ms >= NaretStartupPlacement.TIMED_FALLBACK_MS and at_ms < 9000 and slow.samples >= NaretStartupPlacement.TIMED_MIN_SAMPLES, "after the set time and number of readings (%d ms, %d readings)" % [at_ms, int(slow.get("samples", 0))])
	check(absf(slow.pose.origin.x - 1.0) < 0.03, "at the median of what was read")
	# Two quick glimpses are not enough, however long ago the first one was.
	startup = NaretStartupPlacement.new()
	var few: Dictionary = {}
	for i in range(4): few = startup.observe(pose, i * 3000)
	check(few.is_empty(), "four readings never place the patient, even over nine seconds")
	# 20 Nov 2026: a dim room gave about one reading a second; five over three seconds place him.
	few = startup.observe(pose, 12000)
	check(not few.is_empty() and few.fallback, "the fifth reading places the patient, labelled as a fallback")
	# Exercise the actual XR anchor, not only the estimator in isolation.
	var tree := Engine.get_main_loop() as SceneTree
	var head := Node3D.new()
	tree.root.add_child(head)
	var anchor := NaretSpatialAnchor.new()
	anchor.calibration_file = "user://startup_integration_unused.cfg"
	anchor.viewer_head = head
	var patient := Node3D.new()
	patient.name = "Mannequin"
	anchor.add_child(patient)
	tree.root.add_child(anchor)
	anchor.marker_to_mannequin = Transform3D(Basis.IDENTITY, Vector3(0.1, 0, 0))
	pose = Transform3D(Basis.IDENTITY, Vector3(1, 0.2, -1))
	for i in range(41):
		anchor.update_pose(pose, 1000 + i)
		anchor._process(0.01)
	check(not anchor.locked and not patient.visible, "XR anchor remains hidden until startup accepted")
	check(anchor.global_position.is_equal_approx(Vector3.ZERO), "unaccepted startup does not move anchor")
	anchor.update_pose(pose, 1041)
	anchor._process(0.01)
	check(anchor.locked and patient.visible, "accepted startup reveals patient")
	check(anchor.global_transform.is_equal_approx(pose * anchor.marker_to_mannequin), "startup applies calibrated model offset exactly once")
	anchor.unlock()
	anchor._process(0.01)
	check(not patient.visible and anchor.startup.samples.is_empty(), "reposition clears startup observations and hides patient")
	anchor.update_pose(pose, 2000)
	check(not anchor.locked, "reposition requires a fresh collection")
	anchor.free()
	head.free()
	return failures
