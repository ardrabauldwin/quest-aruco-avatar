extends "res://tests/suite.gd"

func run() -> Array[String]:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var shipped := scene.get_node("SpatialAnchor") as NaretSpatialAnchor
	check(not shipped.manual_reposition_only and not shipped.foot_end_reacquisition and not shipped.checkpoint_updates, "shipped scene combines the Reposition button with gated >15cm following")
	scene.free()
	var tree := Engine.get_main_loop() as SceneTree
	var head := Node3D.new()
	tree.root.add_child(head)
	var anchor := NaretSpatialAnchor.new()
	anchor.calibration_file="user://manual_placement_missing.cfg"
	anchor.viewer_head=head
	var patient := Node3D.new()
	patient.name="Mannequin"
	anchor.add_child(patient)
	tree.root.add_child(anchor)
	anchor.marker_to_mannequin=Transform3D(Basis.IDENTITY,Vector3(.1,0,0))
	anchor.calibrated=true
	anchor.floor_touch_offset_m=.02
	anchor.chest_height_m=.25
	var alignment := anchor.marker_to_mannequin
	var first := Transform3D(Basis.IDENTITY,Vector3(1,.2,-1))
	for i in range(41):anchor.update_pose(first,1000+i)
	check(not anchor.locked, "manual mode still waits for42startup readings")
	anchor.update_pose(first,1041)
	anchor._process(.01)
	check(anchor.locked and patient.visible, "first robust placement becomes visible")
	var held := anchor.global_transform
	var moved := Transform3D(Basis(Vector3.UP,deg_to_rad(90)),Vector3(2,.4,2))
	for i in range(160):
		head.position=Vector3(float(i)*.02,1.7,0)
		anchor.update_pose(moved,2000+i)
		anchor._process(.01)
		check(anchor.global_transform.is_equal_approx(held) and anchor.locked_pose.is_equal_approx(first), "all later detections and head movements leave accepted placement unchanged")
	check(anchor._viewer_filter==null and not anchor._foot_end_following, "manual mode never enters automatic filter or foot-end following")
	anchor.full_marker_evidence=false
	anchor._process(.2)
	check(patient.visible and anchor.global_transform.is_equal_approx(held), "marker loss keeps accepted patient visible and fixed")
	var main = load("res://scripts/main.gd").new()
	main.anchor=anchor
	main.scenario=NaretScenario.new()
	main.scenario.start()
	var progress: Dictionary=main.scenario.get_summary().duplicate(true)
	main._update_controller_alignment(.1)
	check(anchor.global_transform.is_equal_approx(held), "controller nudges cannot bypass manual placement mode")
	main._reposition_patient()
	check(not anchor.locked and not patient.visible and anchor.startup.samples.is_empty(), "Reposition hides patient and starts a fresh collection")
	check(anchor.calibrated and anchor.marker_to_mannequin.is_equal_approx(alignment), "Reposition retains saved model alignment")
	check(is_equal_approx(anchor.floor_touch_offset_m,.02) and is_equal_approx(anchor.chest_height_m,.25), "Reposition preserves floor and chest measurements")
	check(main.scenario.get_summary()==progress, "Reposition preserves training progress")
	for i in range(41):anchor.update_pose(moved,4000+i)
	check(not anchor.locked and anchor.global_transform.is_equal_approx(held), "unconfirmed reposition cannot move or reveal patient")
	anchor.update_pose(moved,4041)
	anchor._process(.01)
	check(anchor.locked and patient.visible and anchor.locked_pose.is_equal_approx(moved), "fresh42reading confirmation accepts requested new placement")
	check(anchor.global_transform.is_equal_approx(moved*alignment), "reposition applies retained model alignment exactly once")
	held=anchor.global_transform
	for i in range(110):anchor.update_pose(first,5000+i)
	check(anchor.global_transform.is_equal_approx(held), "replacement placement also stays fixed until next button request")
	main.scenario.free()
	main.free()
	anchor.free()
	head.free()
	return failures
