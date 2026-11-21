extends "res://tests/suite.gd"
const DT := 1.0 / 72.0

func sample(height: float, usable := true, source := "wrist_oriented") -> Dictionary:
	return {"height":height,"in_zone":is_finite(height),"usable":usable,"source":source}

func hold(counter: NaretTwoHandPressCounter, left: float, right: float, frames := 60) -> void:
	for i in frames: counter.update(DT,sample(left),sample(right))

func run() -> Array[String]:
	var both := NaretTwoHandPressCounter.new()
	var counts := [0]
	both.pressed.connect(func(_d: float): counts[0] += 1)
	hold(both,0.03,0.07)
	check(both.hand=="right","upper calibrated palm is selected when acquiring both hands")
	for p in 30:
		for i in 40:
			var drop := 0.045 * sin(PI*i/40.0)
			both.update(DT,sample(0.03-drop),sample(0.07-drop))
	hold(both,0.03,0.07,3)
	check(counts[0] == 30,"two visible hands with only two tracked joints count 30 shared presses, never 60: "+str(counts[0]))
	# A hidden lower palm may become stable first, while the upper palm needs
	# a few more setup frames. It must not capture the entire session.
	var staggered := NaretTwoHandPressCounter.new()
	var staggered_counts := [0]
	staggered.pressed.connect(func(_d: float): staggered_counts[0] += 1)
	hold(staggered,NAN,0.02,45)
	check(staggered.hand=="right", "first available lower palm can complete initial setup")
	hold(staggered,0.07,0.02,45)
	check(staggered.hand=="left" and staggered_counts[0]==0, "upper saved resting palm takes priority before the first press without counting the selection change")
	for press in 30:
		for i in 40:
			var drop := 0.045*sin(PI*i/40.0)
			staggered.update(DT,sample(0.07-drop),sample(0.02))
	check(staggered_counts[0]==30, "a still-valid frozen lower palm cannot hide thirty upper-palm presses")
	check(is_equal_approx(staggered._counters.left.rest_m,0.07) and is_equal_approx(staggered._counters.right.rest_m,0.02), "upper-palm setup selection preserves both measured baselines")
	# A calibrated upper hand can return after the lower hand has taken over.
	# Its first reading may already be depressed: that switch cannot count it.
	var returning := NaretTwoHandPressCounter.new()
	var return_counts := [0]
	returning.pressed.connect(func(_d: float): return_counts[0] += 1)
	hold(returning,0.07,0.02)
	hold(returning,0.025,0.02,25)
	hold(returning,0.07,0.02,25)
	check(return_counts[0]==1, "return-source test begins with one completed press")
	hold(returning,NAN,0.02,60)
	check(returning.hand=="right", "lower calibrated palm covers an absent upper hand")
	hold(returning,0.03,0.02,60)
	check(returning.hand=="left" and return_counts[0]==1, "returned upper hand is preferred but its already-depressed reading cannot count")
	hold(returning,0.07,0.02,25)
	hold(returning,0.025,0.02,25)
	hold(returning,0.07,0.02,25)
	check(return_counts[0]==2, "fresh upper-hand motion counts after recovery while lower tracking remains frozen")
	var transfer := NaretTwoHandPressCounter.new()
	var transfers := [0]
	transfer.pressed.connect(func(_d: float): transfers[0] += 1)
	hold(transfer,0.03,0.07)
	for p in 8:
		for i in 40:
			var drop := 0.045*sin(PI*i/40.0)
			# Lose the active hand at the bottom; the other sees the same physical press.
			transfer.update(DT,sample(0.03-drop,i<20 or p%2==1),sample(0.07-drop,i<20 or p%2==0))
	hold(transfer,0.03,0.07,3)
	check(transfers[0] == 8,"mid-press handoff preserves one shared stroke, without duplicates or lost cycles: "+str(transfers[0]))
	var gap := NaretTwoHandPressCounter.new()
	var gaps := [0]
	gap.pressed.connect(func(_d: float): gaps[0] += 1)
	hold(gap,0.07,NAN)
	gap.update(DT,sample(0.04),sample(NAN)) # Interrupted downward movement.
	hold(gap,NAN,NAN)
	hold(gap,0.04,NAN,90) # Returned below original rest, but stationary.
	check(gaps[0] == 0 and is_equal_approx(gap._counters.left.rest_m,0.07),"reappearance below rest does not count or overwrite calibration")
	for p in 3:
		for i in 40:
			gap.update(DT,sample(0.04-0.025*sin(PI*i/40.0)),sample(NAN))
	hold(gap,0.04,NAN,3)
	check(gaps[0] == 3,"fresh downward/recoil movements count without requiring the old resting level: "+str(gaps[0]))
	var mode := NaretTwoHandPressCounter.new()
	var modes := [0]
	mode.pressed.connect(func(_d: float): modes[0] += 1)
	hold(mode,0.06,NAN)
	for p in 6:
		for i in 40:
			var fallback := i>=10 and i<30
			mode.update(DT,sample(0.06-0.045*sin(PI*i/40.0)+(0.012 if fallback else 0.0),true,"palm_oriented" if fallback else "wrist_oriented"),sample(NAN))
	hold(mode,0.06,NAN,3)
	check(modes[0] == 6,"wrist/fallback estimator changes do not count their coordinate jumps: "+str(modes[0]))
	var frozen := NaretTwoHandPressCounter.new()
	var short_depths: Array[float] = []
	frozen.pressed.connect(func(d: float): short_depths.append(d))
	hold(frozen,0.03,0.07)
	for p in 4:
		for i in 40:
			frozen.update(DT,sample(0.03),sample(0.07-0.03*sin(PI*i/40.0)))
	hold(frozen,0.03,0.07,3)
	check(short_depths.size()==4 and short_depths.all(func(d: float): return absf(d-0.03)<0.003),"a frozen hand yielding to the pressing hand preserves its shallow strokes and measured travel")
	var selection := NaretTwoHandPressCounter.new()
	hold(selection,0.03,0.07)
	selection.update(DT,sample(0.0),sample(0.07))
	check(selection.hand=="right" and not selection.pressing,"a deeper other hand cannot steal a usable upper palm")
	selection.update(DT,sample(0.03),sample(NAN))
	check(selection.hand=="left" and not selection.pressing,"a calibrated alternative takes over when the selected palm is unusable, without counting the switch")
	var lifted_hand := NaretTwoHandPressCounter.new()
	var false_counts := [0]
	lifted_hand.pressed.connect(func(_d: float): false_counts[0] += 1)
	hold(lifted_hand,0.04,NAN)
	for p in 4:
		for i in 40:
			# Every sample stays ABOVE the saved rest; no compression is possible.
			lifted_hand.update(DT,sample(0.04+0.02+0.03*absf(sin(PI*i/40.0))),sample(NAN))
	check(false_counts[0]==0,"raising and lowering a hand entirely above its saved rest cannot count")
	hold(lifted_hand,NAN,NAN)
	hold(lifted_hand,0.08,NAN)
	for p in 3:
		for i in 40:
			lifted_hand.update(DT,sample(0.08-0.03*sin(PI*i/40.0)),sample(NAN))
	check(false_counts[0]==0,"recovery above rest cannot turn elevated hand gestures into compressions")
	var bias := NaretTwoHandPressCounter.new()
	var bias_counts := [0]
	bias.pressed.connect(func(_d: float): bias_counts[0] += 1)
	hold(bias,0.04,0.08)
	hold(bias,0.09,0.08,60) # Selected hand is raised, never pressed.
	for i in 3: bias.update(DT,sample(0.09,false),sample(0.08))
	for p in 4:
		for i in 40:
			bias.update(DT,sample(0.09,false),sample(0.08-0.045*sin(PI*i/40.0)))
	for i in 3: bias.update(DT,sample(0.09,false),sample(0.08))
	check(bias_counts[0]==4 and is_zero_approx(bias._offset),"takeover from a raised/lost hand cannot carry a permanent offset that hides subsequent presses")
	var bounce := NaretTwoHandPressCounter.new()
	var bounce_counts := [0]
	bounce.pressed.connect(func(_d: float): bounce_counts[0] += 1)
	hold(bounce,0.07,NAN)
	hold(bounce,0.025,NAN,25) # One 4.5 cm press.
	hold(bounce,0.045,NAN,25) # Partial recoil by 2 cm.
	check(bounce_counts[0]==1 and not bounce.pressing,"partial recoil completes the final stroke without a subsequent descent")
	hold(bounce,0.040,NAN,25) # 5 mm belongs to a possible next stroke, not the previous one.
	check(bounce_counts[0]==1 and not bounce.pressing,"small renewed descent cannot arm the next stroke")
	hold(bounce,0.07,NAN,25)
	check(bounce_counts[0]==1,"partial recoil followed by a small bounce and release counts only once")
	var recoil := NaretTwoHandPressCounter.new()
	var recoil_counts := [0]
	recoil.pressed.connect(func(_d: float): recoil_counts[0] += 1)
	hold(recoil,0.07,NAN)
	hold(recoil,0.02,NAN,25) # Down 5 cm.
	hold(recoil,0.036,NAN,25) # Back to 3.4 cm drop: 1.6 cm recoil.
	check(recoil_counts[0]==1 and not recoil.pressing,"5 cm down then 1.6 cm recoil counts immediately")
	hold(recoil,0.031,NAN,25) # Down to 3.9 cm: only a 5 mm new descent.
	check(recoil_counts[0]==1 and not recoil.pressing,"next 5 mm descent neither recounts the old stroke nor qualifies a new one")
	hold(recoil,0.015,NAN,25) # Down to 5.5 cm: fresh descent 2.1 cm.
	check(recoil_counts[0]==1 and recoil.pressing,"fresh 2 cm descent arms the next stroke without counting it early")
	hold(recoil,0.031,NAN,25) # Second recoil by 1.6 cm.
	check(recoil_counts[0]==2 and not recoil.pressing,"second stroke counts once on its own recoil")
	hold(recoil,0.031,NAN,90)
	check(recoil_counts[0]==2 and is_equal_approx(recoil._counters.left.rest_m,0.07),"stopping after recoil preserves both the total and fixed palm rest")
	var uncapped := NaretTwoHandPressCounter.new()
	var uncapped_counts := [0]
	uncapped.pressed.connect(func(_d: float): uncapped_counts[0] += 1)
	hold(uncapped,0.07,NAN)
	hold(uncapped,-0.04,NAN,25) # Synthetic 11 cm hand travel; not a physical-depth claim.
	check(uncapped.pressing and uncapped_counts[0]==0,"shared detector does not cancel a tracked stroke at a hard-coded 10 cm cap")
	hold(uncapped,-0.02,NAN,25) # Recoil by 2 cm completes the observed movement.
	check(uncapped_counts[0]==1 and is_equal_approx(uncapped._counters.left.rest_m,0.07),"recoil after a large tracked excursion uses the normal stroke logic without changing rest")
	var tree := Engine.get_main_loop() as SceneTree
	var zone = load("res://addons/naret_upstream/avatar/cpr_hand_zone.tscn").instantiate()
	tree.root.add_child(zone)
	zone.set_process(false)
	var origin := XROrigin3D.new()
	tree.root.add_child(origin)
	zone.xr_origin = origin
	var tracker := XRHandTracker.new()
	tracker.name = &"/user/hand_tracker/test_counter"
	tracker.has_tracking_data = true
	for joint in XRHandTracker.HAND_JOINT_MAX: tracker.set_hand_joint_flags(joint,0)
	var position_flags := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
	var orientation_flags := XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_TRACKED
	tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM,position_flags|orientation_flags)
	tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM,Transform3D(Basis.IDENTITY,Vector3(0,0.02,0)))
	tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST,position_flags)
	tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST,Transform3D(Basis.IDENTITY,Vector3(0,-0.05,0)))
	XRServer.add_tracker(tracker)
	var read: Dictionary = zone._read_hand(tracker.name)
	check(read.get("heel_usable",false),"tracked palm and wrist are usable with all finger joints absent: "+str(read))
	tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST,0)
	read = zone._read_hand(tracker.name)
	check(read.get("heel_usable",false) and read.get("heel_source")=="palm_oriented","tracked palm position and orientation support the wrist-free fallback")
	tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM,position_flags)
	read = zone._read_hand(tracker.name)
	check(not read.get("heel_usable",true),"palm position alone without wrist or orientation cannot provide a usable heel")
	var direct: Dictionary = zone._read_counting_palm(tracker.name)
	check(not direct.is_empty() and direct.point.is_equal_approx(Vector3(0,0.02,0)),"counting reads exact palm position with wrist and orientation absent")
	tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM,position_flags|orientation_flags)
	tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM,Transform3D(Basis(Vector3.RIGHT,1.0),Vector3(0,0.02,0)))
	check(zone._read_counting_palm(tracker.name).point.is_equal_approx(direct.point),"rotating the palm cannot create a counting-position offset")
	tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM,XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
	check(zone._read_counting_palm(tracker.name).is_empty(),"valid but untracked palm cannot feed counting")
	tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM,0)
	check(zone._read_hand(tracker.name).is_empty(),"untracked palm position is rejected")
	zone.get_node("CollisionShape3D").position = Vector3.ZERO
	var highlight := zone.get_node("Highlight") as MeshInstance3D
	highlight.position = Vector3.ZERO
	highlight.mesh = highlight.mesh.duplicate()
	var guide := highlight.mesh as QuadMesh
	guide.size = Vector2(0.14,0.14)
	check(not zone._in_placed_zone(Vector3(0.09,0,0)),"point outside visible guide cannot arm counting")
	guide.size = Vector2(0.20,0.20)
	check(zone._in_placed_zone(Vector3(0.09,0,0)),"counting footprint follows visible guide size without separate lateral constants")
	check(not zone._in_placed_zone(Vector3(0,0.031,0)),"guide resize does not change the sternum height allowance")
	XRServer.remove_tracker(tracker)
	zone.free()
	origin.free()
	# The user-selected 1 cm start detects shallow full-return cycles once,
	# while smaller excursions never arm the shared detector.
	var sensitive := NaretTwoHandPressCounter.new()
	var sensitive_counts := [0]
	sensitive.pressed.connect(func(_d: float): sensitive_counts[0] += 1)
	hold(sensitive,0.07,NAN)
	for stroke in 5:
		for frame in 40:
			sensitive.update(DT,sample(0.07-0.009*sin(PI*frame/40.0)),sample(NAN))
	hold(sensitive,0.07,NAN,5)
	check(sensitive_counts[0]==0, "sub-centimetre cycles do not start a shared press")
	# Press start is 2 cm again (decision 9 Nov 2026): a 1 cm start equalled the 1 cm
	# return threshold and double-counted palm jitter. 1.5 cm cycles stay below it.
	for stroke in 5:
		for frame in 40:
			sensitive.update(DT,sample(0.07-0.015*sin(PI*frame/40.0)),sample(NAN))
	hold(sensitive,0.07,NAN,5)
	check(sensitive_counts[0]==0, "1.5 cm cycles stay below the 2 cm press start: "+str(sensitive_counts[0]))
	for stroke in 5:
		for frame in 40:
			sensitive.update(DT,sample(0.07-0.025*sin(PI*frame/40.0)),sample(NAN))
	hold(sensitive,0.07,NAN,5)
	check(sensitive_counts[0]==5, "five 2.5 cm full-return cycles produce five shared counts: "+str(sensitive_counts[0]))
	return failures

