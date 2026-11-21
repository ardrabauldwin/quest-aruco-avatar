extends "res://tests/suite.gd"
const FootEnd = preload("res://scripts/tracking/foot_end_reacquisition.gd")

func patient_fixture() -> Node3D:
	var patient := Node3D.new()
	var sternum := Marker3D.new()
	sternum.name = "Sternum"
	patient.add_child(sternum)
	var model := Node3D.new()
	model.name = "Model"
	patient.add_child(model)
	var skeleton := Skeleton3D.new()
	model.add_child(skeleton)
	for side in [-1,1]:
		skeleton.add_bone("foot_l" if side == -1 else "foot_r")
		skeleton.set_bone_rest(skeleton.get_bone_count()-1,Transform3D(Basis.IDENTITY,Vector3(side*.1,0,1)))
	return patient

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var patient := patient_fixture()
	tree.root.add_child(patient)
	var head := Node3D.new()
	tree.root.add_child(head)
	var foot = FootEnd.new()
	var region: Dictionary = foot.geometry(patient)
	check((region.foot as Vector2).is_equal_approx(Vector2(0,1)),"foot plane comes from two actual foot bones")
	check(FootEnd.contains(Vector3(0,1.4,1.3),region,.5,.40),"shorter person is in standing region")
	check(FootEnd.contains(Vector3(0,2.1,1.3),region,.5,.40),"tall person has identical XZ eligibility above old 1.8m range")
	check(not FootEnd.contains(Vector3(.6,1.7,1.4),region,.5,.40),"sideways position outside half width rejected")
	check(not FootEnd.contains(Vector3(0,1.7,.8),region,.5,.40),"standing on torso side of foot plane rejected")
	check(not FootEnd.contains(Vector3(0,1.7,1.8),region,.5,.40),"standing too far beyond feet rejected")
	check(FootEnd.contains(Vector3(0,1.7,1.399),region,.5,.40), "39.9 cm beyond feet is inside")
	check(not FootEnd.contains(Vector3(0,1.7,1.401),region,.5,.40), "40.1 cm beyond feet is outside")
	var defaults := NaretSpatialAnchor.new()
	check(is_equal_approx(defaults.foot_end_depth_m,.40), "default foot-end depth is 40 cm")
	defaults.free()
	patient.rotation.y=PI/2
	region=foot.geometry(patient)
	check(FootEnd.contains(Vector3(1.3,2,0),region,.5,.40),"standing region follows accepted patient yaw")
	patient.rotation.y=0
	head.position=Vector3(0,2.1,1.3)
	for i in range(60):foot.tick(.01,head,patient,true,.5,.40)
	check(foot.eligible,"tall settled headset is eligible without 3D distance limit")
	var raw := Transform3D(Basis(Vector3.UP,deg_to_rad(6)),Vector3(.06,.25,0))
	for i in range(41):check(foot.evaluate(raw,Transform3D.IDENTITY,1000+i,true).is_empty(),"foot candidate holds before four comparisons")
	check(foot.evaluate(raw,Transform3D.IDENTITY,1040,true).is_empty(),"duplicate timestamp cannot confirm")
	var confirmed: Dictionary = foot.evaluate(raw,Transform3D.IDENTITY,1041,true)
	check(confirmed.get("confirmed",false) and confirmed.samples==42,"42 stable foot readings confirm a six cm / six degree move")
	check(confirmed.pose.origin.is_equal_approx(Vector3(.06,0,0)),"no small-bias subtraction and startup height retained")
	for i in range(30):foot.evaluate(raw,Transform3D.IDENTITY,2000+i,true)
	foot.tick(.01,head,patient,false,.5,.40)
	check(foot.checkpoint.candidate_readings==0,"missing evidence discards partial window")
	for i in range(60):foot.tick(.01,head,patient,true,.5,.40)
	for i in range(30):foot.evaluate(raw,Transform3D.IDENTITY,3000+i,true)
	head.position.x=.7
	foot.tick(.01,head,patient,true,.5,.40)
	check(not foot.in_region and foot.checkpoint.candidate_readings==0,"leaving region resets even between marker detections")
	head.position=Vector3(0,2.1,1.3)
	for i in range(100):foot.tick(.01,head,patient,true,.5,.40)
	for i in range(30):foot.evaluate(raw,Transform3D.IDENTITY,4000+i,true)
	head.rotation.x=.3
	foot.tick(.01,head,patient,true,.5,.40)
	check(not foot.eligible and foot.checkpoint.candidate_readings==0,"pitch movement resets foot acquisition")
	# An incoming pose must never redefine standing geometry.
	head.rotation.x=0
	for i in range(100):foot.tick(.01,head,patient,true,.5,.40)
	var large := Transform3D(Basis.IDENTITY,Vector3(20,0,0))
	foot.evaluate(large,Transform3D.IDENTITY,5000,true)
	check(foot.in_region and (foot._visit.foot as Vector2).is_equal_approx(Vector2(0,1)),"raw candidate cannot move its own standing region")
	foot.reset()
	check(not foot.in_region and not foot.eligible,"reset clears visit and checkpoint")
	# Exercise spatial-anchor integration with the old gate still enabled elsewhere.
	var anchor := NaretSpatialAnchor.new()
	anchor.manual_reposition_only = false
	anchor.calibration_file="user://foot_end_test_missing.cfg"
	anchor.foot_end_reacquisition=true
	patient.get_parent().remove_child(patient)
	patient.name="Mannequin"
	anchor.add_child(patient)
	tree.root.add_child(anchor)
	anchor.viewer_head=head
	anchor.locked=true
	anchor.locked_pose=Transform3D.IDENTITY
	anchor.marker_to_mannequin=Transform3D.IDENTITY
	for i in range(100):anchor._process(.01)
	for i in range(41):anchor.update_pose(raw,6000+i)
	check(anchor.locked_pose.origin.is_zero_approx(),"avatar holds throughout foot candidate collection")
	anchor.update_pose(raw,6041)
	check(anchor._foot_end_following and anchor._viewer_rest_pose.origin.is_equal_approx(Vector3(.06,0,0)), "foot confirmation uses the old confirmed-move rest hook")
	check(anchor.locked_pose.origin.is_zero_approx(), "old smoother starts from held placement without teleporting")
	check(anchor._viewer_filter != null and anchor._viewer_filter.window==1, "confirmed targets bypass multi-pose medoid")
	check(not anchor._viewer_filter.automatic_reanchor, "filtered readings cannot change confirmed rest")
	check(is_equal_approx(anchor._viewer_filter.position_dead_zone_m,.020) and is_equal_approx(anchor._viewer_filter.rotation_dead_zone_deg,.3), "old dead zones retained")
	check(is_equal_approx(anchor._viewer_filter.smoothing_time_s,1.2) and is_equal_approx(anchor._viewer_filter.prior_time_s,2.0), "old smoothing and rest pull retained")
	for i in range(1,101):
		anchor._process(.1)
		anchor.update_pose(raw,6041+i*100)
		check(anchor._viewer_rest_pose.origin.is_equal_approx(Vector3(.06,0,0)), "confirmed small destination remains rest during smoothing")
	check(absf(anchor.locked_pose.origin.x-.06)<.001, "accepted foot target continues through old smoothing between checkpoints")
	anchor.full_marker_evidence=false
	var held:=anchor.locked_pose
	anchor._process(.01)
	anchor.update_pose(raw,17000)
	check(not anchor._foot_end_following and anchor.locked_pose.is_equal_approx(held), "loss of evidence stops foot updates")
	anchor.full_marker_evidence=true
	head.position=Vector3(1,1,0)
	for i in range(100):anchor._process(.01)
	var baseline:=anchor.locked_pose
	var biased:=baseline
	biased.origin.x+=.04
	for i in range(5):anchor.update_pose(biased,18000+i)
	check(not anchor._foot_end.in_region and anchor.viewer_gate.gate_state=="hold_outside", "outside small changes hold without bias collection")
	check(anchor.locked_pose.is_equal_approx(baseline), "outside four-cm difference cannot move the patient")
	biased.origin.x+=.5
	biased.basis=Basis(Vector3.UP,deg_to_rad(30.0))
	for i in range(41):anchor.update_pose(biased,19000+i*100)
	check(anchor.viewer_gate.gate_state=="big_collecting", "old large outside route still requires checkpoints")
	anchor.update_pose(biased,23100)
	check(anchor.viewer_gate.gate_state=="follow_big", "old confirmed large move still passes")
	check(anchor._viewer_filter.measurement_target().origin.is_equal_approx(biased.origin), "new confirmed destination enters smoothing immediately without stale medoid history")
	check(anchor._viewer_filter != null and is_equal_approx(anchor._viewer_filter.prior_time_s,2.0), "large move still uses original filter and prior")
	for i in range(1,101):
		anchor._process(.1)
		anchor.update_pose(biased,23100+i*100)
		check(anchor._viewer_rest_pose.origin.is_equal_approx(biased.origin), "large confirmed rest cannot revert to old medoid history")
	check(anchor.locked_pose.origin.distance_to(biased.origin)<.002, "old large route converges through original filtering history")
	check(anchor._viewer_rest_pose.origin.distance_to(biased.origin)<.002, "old filter can adopt the stable large destination")
	anchor.unlock()
	check(not anchor._foot_end.in_region and not anchor._foot_end_following,"unlock clears foot transition and collection")
	anchor.free()
	var real_patient := load("res://scenes/mannequin.tscn").instantiate() as Node3D
	tree.root.add_child(real_patient)
	var real_gate = FootEnd.new()
	var real_region: Dictionary = real_gate.geometry(real_patient)
	check(not real_region.is_empty(), "shipped patient exposes usable scaled foot landmarks")
	if not real_region.is_empty():
		var forehead := real_patient.get_node("ForeheadZone") as Node3D
		var sternum := real_patient.get_node("Sternum") as Node3D
		var headward := Vector2(forehead.global_position.x-sternum.global_position.x, forehead.global_position.z-sternum.global_position.z)
		check(headward.dot(real_region.along)<0.0, "shipped asset foot direction is opposite its head")
		var standing: Vector2 = real_region.foot + real_region.along*.3
		check(FootEnd.contains(Vector3(standing.x,2.1,standing.y),real_region,.5,.40), "real patient geometry admits tall headset beyond feet")
	real_patient.free()
	head.free()
	return failures
