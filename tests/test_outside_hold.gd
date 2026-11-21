extends "res://tests/suite.gd"

func run() -> Array[String]:
	var gate := NaretViewerMotionGate.new()
	gate.moving = false
	var display := Transform3D.IDENTITY
	# Sustained side-view errors must never accumulate into accepted small moves.
	for distance in [.04, .10, .1499, .15]:
		gate.reset_pose_evidence()
		var raw := display
		raw.origin.x = distance
		for i in range(110):
			check(gate.evaluate(raw,display,1000+i).is_empty(), "outside <=15 cm holds indefinitely")
		check(gate.gate_state=="hold_outside", "no small-change bias state")
	var angles := [0.0,10.0,14.99,15.0]
	for j in range(angles.size()):
		gate.reset_pose_evidence()
		var rotated := display
		rotated.basis=Basis(Vector3.UP,deg_to_rad(float(angles[j])))
		for i in range(110):
			check(gate.evaluate(rotated,display,2000+j*150+i).is_empty(), "heading within15degrees holds without translation")
	# User rule: either component within its limit holds, even if the other exceeds.
	var holds := [[.20,5.0],[.05,20.0],[.15,20.0],[.20,15.0],[.20,14.99]]
	for j in range(holds.size()):
		gate.reset_pose_evidence()
		var raw := Transform3D(Basis(Vector3.UP,deg_to_rad(float(holds[j][1]))),Vector3(float(holds[j][0]),0,0))
		for i in range(110):
			check(gate.evaluate(raw,display,2700+j*150+i).is_empty(), "distance within15cm OR heading within15degrees holds indefinitely")
		check(gate._big_readings==0, "held OR cases never start automatic confirmation")
	gate.reset_pose_evidence()
	var wrapped_display := Transform3D(Basis(Vector3.UP,deg_to_rad(179.0)),Vector3.ZERO)
	var wrapped_raw := Transform3D(Basis(Vector3.UP,deg_to_rad(-179.0)),Vector3.ZERO)
	for i in range(45):
		check(gate.evaluate(wrapped_raw,wrapped_display,3600+i).is_empty(), "heading wraparound is two degrees, not358")
	gate.reset_pose_evidence()
	var large := display
	large.origin=Vector3(.12,0,.12)
	large.basis=Basis(Vector3.UP,deg_to_rad(20.0))
	for i in range(41):
		check(gate.evaluate(large,display,4000+i).is_empty(), "large XZ displacement waits for four comparisons")
	var result := gate.evaluate(large,display,4041)
	check(result.get("confirmed",false), "both translation and heading above limits confirm at42")
	check((result.pose as Transform3D).is_equal_approx(large), "confirmed target is not bias-corrected")
	check(not gate.evaluate(large,display,4042).is_empty(), "confirmed destination continues gliding below trigger")
	var jitter := large
	jitter.origin.x += .08
	var continued := gate.evaluate(jitter,display,4042)
	check((continued.pose as Transform3D).is_equal_approx(large), "later raw readings cannot drag confirmed destination")
	var near_display := large
	near_display.origin.x -= .01
	check((gate.evaluate(jitter,near_display,4042).pose as Transform3D).is_equal_approx(large), "fixed target continues near arrival without five-cm allowance")
	for i in range(41):
		var pending := gate.evaluate(jitter,display,4100+i)
		check((pending.pose as Transform3D).is_equal_approx(large), "new candidate cannot replace fixed target before confirmation")
	var replacement := gate.evaluate(jitter,display,4141)
	check(replacement.get("confirmed",false) and (replacement.pose as Transform3D).is_equal_approx(jitter), "a newly confirmed destination replaces the fixed target")
	check(gate.evaluate(large,display,4043,false).is_empty(), "missing evidence interrupts following")
	check(gate.evaluate(large,display,4044).is_empty(), "evidence return requires fresh confirmation")
	# Movement interrupts both a candidate and a confirmed following stream.
	gate.moving = true
	for i in range(50):
		check(gate.evaluate(large,display,4000+i).is_empty(), "motion blocks even >15cm displacement")
	check(gate._big_readings==0 and not gate._big_following, "motion clears confirmation and following")
	gate.moving = false
	for i in range(41):
		check(gate.evaluate(large,display,5000+i).is_empty(), "after motion requires fresh checkpoints")
	check(gate.evaluate(large,display,5041).get("confirmed",false), "settled large move can confirm again")
	gate.moving = true
	check(gate.evaluate(large,display,5042).is_empty(), "motion pauses confirmed following")
	var tree := Engine.get_main_loop() as SceneTree
	var head := Node3D.new()
	tree.root.add_child(head)
	var live := NaretViewerMotionGate.new()
	live.head = head
	for i in range(100):live.tick(.01)
	check(not live.moving, "stationary head settles")
	head.rotation.x=deg_to_rad(15.0)
	live.tick(.01)
	check(live.moving, "pitch-only movement also holds updates")
	for i in range(100):live.tick(.01)
	check(not live.moving, "head settles after pitch stops")
	head.free()
	return failures
