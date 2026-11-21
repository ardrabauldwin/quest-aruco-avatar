extends "res://tests/suite.gd"
## Bag-valve-mask (12 Nov 2026): offered beside the head, placed by release over the mouth,
## squeezed with a sealing palm at the mask; each counted squeeze is one breath and the
## scenario takes it as a hand-tracked ventilation. A sentence alone never passes.
const BVM = preload("res://scripts/mannequin/bvm_device.gd")
const Scenario = preload("res://scripts/scenario/scenario_controller.gd")

func run() -> Array[String]:
	failures.clear()
	check(ResourceLoader.exists(BVM.MODEL_PATH), "the bag-valve-mask model is bundled")
	# Target geometry for the release.
	check(BVM.mask_on_target(Vector3(0.0, 0.04, 0.0)), "rim 4 cm above the mouth is on target")
	check(BVM.mask_on_target(Vector3(0.05, 0.07, -0.05)), "rim 5 cm aside, 7 cm up, 5 cm toward the crown is on target")
	check(not BVM.mask_on_target(Vector3(0.0, 0.12, 0.0)), "rim 12 cm above the mouth is not yet on the face")
	check(not BVM.mask_on_target(Vector3(0.12, 0.04, 0.0)), "rim 12 cm beside the mouth misses")
	check(not BVM.mask_on_target(Vector3(0.0, 0.20, 0.0)), "rim 20 cm above the mouth is still in the air")
	check(not BVM.mask_on_target(Vector3(0.0, 0.04, 0.20)), "rim on the chest misses")
	var unplaced := BVM.new()
	var spot: Transform3D = unplaced.spot_transform()
	unplaced.free()
	check(spot.origin.z < -0.2 and spot.origin.x > 0.3, "the spot lies beside the head")
	check(is_equal_approx(spot.basis.determinant(), 1.0), "the spot pose is a proper rotation")

	var patient: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	var root := Node3D.new()
	root.add_child(patient)
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	var device: Node3D = BVM.new()
	patient.add_child(device)
	device.configure(patient)
	check(device.state == BVM.State.HIDDEN and not device.visible, "hidden until offered")
	device.offer()
	check(device.state == BVM.State.OFFERED and device.visible, "offered on the spot")
	var placed_pose: Transform3D = device.placed_transform()
	check(placed_pose.origin.distance_to(device.mouth_local()) < 0.04, "placed pose puts the mask over mouth and nose")
	check(placed_pose.basis.y.is_equal_approx(Vector3.UP), "the mask's rim lies flat on the face")
	var bag_at: Vector3 = placed_pose * BVM.BAG_OFFSET
	check(Vector2(bag_at.x - placed_pose.origin.x, bag_at.z - placed_pose.origin.z).length() < 0.01 and bag_at.y > placed_pose.origin.y + 0.20, "the bag stands straight up over the mask")
	check(is_equal_approx(placed_pose.basis.determinant(), 1.0), "placed pose is a proper rotation")
	# Grab from the spot, carry, release over the mouth.
	var to_world: Transform3D = patient.global_transform
	var far_palm := Transform3D(Basis(), to_world * (BVM.SPOT_LOCAL + Vector3(0.5, 0.0, 0.0)))
	check(not device.touch("left", far_palm, true, false), "a grab half a metre away does not take the device")
	var near_palm := Transform3D(Basis(), to_world * (BVM.SPOT_LOCAL + Vector3(0.05, 0.05, 0.0)))
	check(device.touch("left", near_palm, true, false), "a grab at the spot takes the device")
	check(device.state == BVM.State.HELD and device.holder == "left", "held by that hand")
	# The palm that puts the mask's rim at a given point (the device hangs from the hold).
	var rim_from_palm: Vector3 = device._hold_offset.origin
	check(device._hold_offset.basis.is_equal_approx(device.spot_transform().basis), "taken with an unturned hand, it keeps the turn it had on the stool")
	check((device._hold_offset * BVM.BAG_OFFSET).distance_to(Vector3(0, -BVM.GRIP_OUT_M, 0)) < 0.001, "the bag's middle sits just in front of the palm")
	var over_chest := Transform3D(Basis(), to_world * (Vector3(0.0, 0.3, 0.0) - rim_from_palm))
	device.touch("left", over_chest, true, true)
	device.touch("left", over_chest, false, true) # hand opened over the chest
	check(device.state == BVM.State.HELD, "an open hand keeps the device: nothing has to be held")
	device._held_seen_s = device._clock - 10.0 # the hand is no longer tracked
	device.tick(0.02)
	check(device.state == BVM.State.OFFERED, "a lost hand returns the device to its spot")
	device.touch("left", near_palm, true, false)
	var over_mouth := Transform3D(Basis(), to_world * (device.placed_transform().origin + Vector3(0.02, 0.05, 0.0) - rim_from_palm))
	check(is_equal_approx(device._hold_offset.basis.determinant(), 1.0), "the hold is a proper rotation")
	# A turned hand turns the device with it, the bag staying in the palm.
	var turned_palm := Transform3D(Basis(Vector3.UP, 0.7), near_palm.origin)
	device.touch("left", turned_palm, true, true)
	check(device.global_transform.basis.is_equal_approx(turned_palm.basis * device._hold_offset.basis), "the device turns with the hand that holds it")
	device.touch("left", over_mouth, false, false)
	check(device.state == BVM.State.PLACED, "brought to the face, the mask seats itself")
	# Squeezes: seal palm at the mask, the other hand gripping the bag.
	var breaths := [0]
	device.breath_given.connect(func(): breaths[0] += 1)
	var no_seal := [0]
	device.squeeze_without_seal.connect(func(): no_seal[0] += 1)
	var placed: Transform3D = device.transform
	var mask_palm: Vector3 = placed * Vector3(0.0, 0.03, 0.0) + Vector3(0.04, 0.0, 0.0)
	var bag_palm: Vector3 = placed * BVM.BAG_OFFSET + Vector3(0.05, 0.0, 0.0)
	for i in 50: device.feed(mask_palm, bag_palm, true, 0.02)   # 1 s grip
	for i in 30: device.feed(mask_palm, bag_palm, false, 0.02)  # release, 0.6 s open
	check(breaths[0] == 1, "a one-second squeeze with the mask held is one breath")
	# One squeeze with a tracking glitch in the middle (the hand seen open for 0.2 s) is
	# still one breath (headset 14 Nov 2026: one squeeze was counted as two).
	for i in 40: device.feed(mask_palm, bag_palm, false, 0.02)
	for i in 30: device.feed(mask_palm, bag_palm, true, 0.02)
	for i in 10: device.feed(mask_palm, bag_palm, false, 0.02)  # glitch
	for i in 30: device.feed(mask_palm, bag_palm, true, 0.02)
	for i in 30: device.feed(mask_palm, bag_palm, false, 0.02)
	check(breaths[0] == 2, "a squeeze with a 0.2 s glitch in it is one breath, not two (%d)" % breaths[0])
	breaths[0] = 1
	device._breaths.pop_back()
	for i in 5: device.feed(mask_palm, bag_palm, true, 0.02)    # 0.1 s twitch
	for i in 50: device.feed(mask_palm, bag_palm, false, 0.02)
	check(breaths[0] == 1, "a 0.1 s twitch is not a breath")
	for i in 50: device.feed(mask_palm, bag_palm, true, 0.02)
	for i in 30: device.feed(mask_palm, bag_palm, false, 0.02)
	check(breaths[0] == 2, "the second squeeze is the second breath")
	check(device.breaths_recent() == 2, "both breaths are recent evidence")
	# Two breaths given: it stays where the trainee put it until the trainee takes it off.
	for i in 60: device.feed(null, null, false, 0.02)            # 1.2 s
	check(device.state == BVM.State.PLACED, "after two breaths the mask stays on the face; nothing moves by itself")
	# Taking it off: a hand closes on the bag and moves away with it.
	var at_bag := Transform3D(Basis(), to_world * bag_palm)
	check(device.touch("right", at_bag, true, false) and device.state == BVM.State.PLACED, "a hand closing on the bag does not take it off by that alone")
	var lifted := Transform3D(Basis(), to_world * (bag_palm + Vector3(0.0, 0.20, 0.0)))
	device.touch("right", lifted, true, true)
	check(device.state == BVM.State.HELD and device.holder == "right", "moving away with the bag takes the device off the face")
	check(breaths[0] == 2, "taking it off is not a breath")
	# Putting it back: the mask brought to its place on the stool.
	var at_stool := Transform3D(Basis(), to_world * (device.spot_transform().origin + Vector3(0.03, 0.04, 0.0) - device._hold_offset.origin))
	device.touch("right", at_stool, false, true)
	check(device.state == BVM.State.OFFERED and device.transform.origin.distance_to(device.spot_transform().origin) < 0.001, "brought to the stool, it is put down on its place")
	# The next cycle: taken and seated again, and a squeeze alone counts.
	device.touch("left", near_palm, true, false)
	check(device.state == BVM.State.HELD, "it is taken from the stool again and does not drop straight back")
	device.touch("left", over_mouth, false, false)
	check(device.state == BVM.State.PLACED, "it is seated again for the next breaths")
	for i in 50: device.feed(null, bag_palm, true, 0.02)        # squeeze with no hand at the mask
	for i in 30: device.feed(null, bag_palm, false, 0.02)
	check(breaths[0] == 3 and no_seal[0] == 0, "with the mask seated, a squeeze alone is a breath too")
	device.reset()
	check(device.state == BVM.State.HIDDEN and device.breaths_recent() == 0, "reset hides the device and clears the evidence")
	root.get_parent().remove_child(root)
	root.free()

	# The scenario takes hand-tracked ventilations after thirty compressions.
	var scenario := Scenario.new()
	scenario.submit_action("start")
	scenario.submit_action("begin_check")
	scenario.submit_action("check_responsiveness")
	scenario.submit_action("call_emergency")
	scenario.submit_action("check_breathing")
	check(not scenario.submit_action("ventilation", {"source": "hand_tracking"}), "no breath before thirty compressions")
	for i in 30: scenario.submit_action("compression", {"source": "hand_tracking"})
	check(scenario.submit_action("ventilation", {"source": "hand_tracking"}) and scenario.submit_action("ventilation", {"source": "hand_tracking"}), "two hand-tracked breaths are accepted")
	check(scenario.cycles == 1 and scenario.cycle_compressions == 0, "the pair closes the cycle")
	scenario.free()
	for key in ["error.breaths_not_seen", "coach.bvm_place_mask", "coach.bvm_squeeze", "coach.bvm_hold_mask"]:
		for lang in ["en", "de", "pl"]:
			var text := NaretLanguage.text(key, lang)
			check(not text.is_empty() and text != key, "text %s exists in %s" % [key, lang])
	return failures
