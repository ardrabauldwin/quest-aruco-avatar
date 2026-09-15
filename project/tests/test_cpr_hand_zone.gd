extends SceneTree

const POS := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
const FULL := POS | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_TRACKED
var failures := 0
var zone
var origin: XROrigin3D
var centre: Vector3
var normal: Vector3
var sideways: Vector3
var left: XRHandTracker
var right: XRHandTracker

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func hand(name_value: StringName) -> XRHandTracker:
	var value := XRHandTracker.new()
	value.name = name_value
	value.has_tracking_data = true
	value.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
	value.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM, FULL)
	value.set_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST, POS)
	XRServer.add_tracker(value)
	return value

## Independent synthetic geometry: wrist/palm 60 mm apart; heel 18 mm from wrist
## and 8 mm toward the skin. Input is desired heel position in world coordinates.
func set_hand(value: XRHandTracker, heel: Vector3, facing: Vector3) -> void:
	var frame := origin.global_transform * XRServer.get_reference_frame()
	var raw_heel := (frame.affine_inverse() * heel) / XRServer.world_scale
	var fingers := (frame.basis.inverse() * sideways).normalized()
	var palm_normal := (frame.basis.inverse() * facing).normalized()
	var basis := Basis(fingers.cross(palm_normal).normalized(), fingers, palm_normal)
	var wrist := raw_heel - fingers * 0.018 - palm_normal * 0.008
	value.set_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST, Transform3D(basis, wrist))
	value.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, Transform3D(basis, wrist + fingers * 0.060))

func pair(left_offset: Vector3, right_offset: Vector3) -> void:
	set_hand(left, centre + left_offset, -normal)
	set_hand(right, centre + right_offset, -normal)
	zone._process(0.016)

func motion_pair(upper_left: bool, gap: float, travel: float) -> void:
	var units: float = zone._units_per_metre()
	var lower := centre - normal * travel * units
	var upper := lower + normal * gap * units
	set_hand(left, upper if upper_left else lower, -normal)
	set_hand(right, lower if upper_left else upper, -normal)
	zone._process(1.0 / 72.0)

func check_upper_hand_motion() -> void:
	var original_scale := XRServer.world_scale
	for world_scale in [1.0, 1.5]:
		XRServer.world_scale = world_scale
		for upper_left in [true, false]:
			for gap in [0.025, 0.055]:
				zone.reset_placement()
				motion_pair(upper_left, gap, 0.0)
				var expected: StringName = zone.left_tracker if upper_left else zone.right_tracker
				check(zone._motion_tracker == expected, "Select upper palm for either stack order and XR scale")
				for cycle in 3:
					for sample in 41:
						var travel := 0.055 * (1.0 - cos(TAU * float(sample) / 40.0)) * 0.5
						motion_pair(upper_left, gap, travel)
				check(zone.motion_session.count == 3, "Upper palm counts three complete strokes")
				check(absf(zone.motion_session.last_stroke_travel_m - 0.055) < 0.0001, "Hand spacing and XR scale do not add to 55 mm travel")
				# Switch references automatically without adding the hand gap to travel.
				motion_pair(upper_left, gap, 0.02)
				var upper_tracker := left if upper_left else right
				upper_tracker.has_tracking_data = false
				zone._process(1.0 / 72.0)
				var fallback: StringName = zone.right_tracker if upper_left else zone.left_tracker
				check(zone._motion_tracker == fallback and zone.motion_session.tracking_available, "Occlusion automatically selects the other tracked palm")
				check(is_zero_approx(zone.motion_session.travel_m), "Hand switch establishes a fresh baseline")
				check(zone.motion_session.count == 3, "Occlusion preserves completed counts")
				upper_tracker.has_tracking_data = true
				motion_pair(upper_left, gap, 0.0)
				check(zone._motion_tracker == fallback, "Returning upper hand does not interrupt the usable fallback")
				check(zone.motion_session.count == 3, "Reappearance cannot complete the discarded stroke")
				for sample in 41:
					motion_pair(upper_left, gap, 0.055 * (1.0 - cos(TAU * float(sample) / 40.0)) * 0.5)
				check(zone.motion_session.count == 4, "Fresh stroke continues automatically on the fallback hand")
				var fallback_tracker := right if upper_left else left
				fallback_tracker.has_tracking_data = false
				zone._process(1.0 / 72.0)
				check(zone._motion_tracker == expected and zone.motion_session.count == 4, "Switch back preserves counts without a manual reset")
				fallback_tracker.has_tracking_data = true
	XRServer.world_scale = original_scale
	zone.reset_placement()
	left.has_tracking_data = false
	motion_pair(false, 0.035, 0.0)
	check(zone._motion_tracker == zone.right_tracker, "One visible palm can start motion tracking")
	left.has_tracking_data = true
	motion_pair(false, 0.0, 0.0)
	check(zone._motion_tracker == zone.right_tracker, "Same-height palms keep the already selected hand")
	motion_pair(true, 0.035, 0.0)
	check(zone._motion_tracker == zone.right_tracker, "Visible selected palm remains continuous if hand order changes")
	zone.reset_placement()
	motion_pair(false, 0.035, 0.0)
	check(zone._motion_tracker == zone.right_tracker, "Reset allows selecting a different upper hand")

func _run() -> void:
	origin = XROrigin3D.new()
	root.add_child(origin)
	origin.position = Vector3(2, 0.5, -1)
	origin.rotation.y = 0.4
	var avatar := Node3D.new()
	root.add_child(avatar)
	avatar.transform = Transform3D(Basis.from_euler(Vector3(0.3, 0.6, -0.2)).scaled(Vector3.ONE * 0.77), Vector3(1, 2, 3))
	zone = load("res://cpr_hand_zone.tscn").instantiate()
	zone.guide_only = false
	zone.xr_origin = origin
	zone.left_tracker = &"/test/cpr/left"
	zone.right_tracker = &"/test/cpr/right"
	avatar.add_child(zone)
	zone.set_process(false)
	centre = zone._shape.global_position
	normal = zone._shape.global_basis.y.normalized()
	sideways = zone._shape.global_basis.x.normalized()
	check(zone.contains_world_point(centre), "Transformed contact centre inside")
	check(not zone.contains_world_point(centre + normal * 0.04), "Hovering heel outside contact slab")
	zone._process(0.016)
	check(not zone.correct_placement, "No trackers cannot pass")
	left = hand(zone.left_tracker)
	right = hand(zone.right_tracker)
	pair(Vector3.ZERO, normal * 0.035)
	check(zone.correct_placement and zone.lower_hand == &"left", "Left heel contact with right hand above passes")
	check(zone.left_hand_inside and not zone.right_hand_inside, "Only lower heel requires chest contact")
	check(zone._material.albedo_color.g > zone._material.albedo_color.r, "Valid stack green")
	check(not zone.is_cpr_started and zone._highlight.visible, "Placement does not auto-start CPR")
	check(zone._read_hand(zone.left_tracker).heel.distance_to(centre) < 0.00001, "Estimated heel equals synthetic contact")
	check(not zone.contains_world_point(centre + sideways * 0.042), "Correct heel can pass while palm is outside")
	pair(-sideways * 0.042, -sideways * 0.042 + normal * 0.035)
	check(not zone.correct_placement, "Palm centred but heel outside fails")
	pair(normal * 0.035, Vector3.ZERO)
	check(zone.correct_placement and zone.lower_hand == &"right", "Right hand may be lower")
	pair(Vector3.ZERO, Vector3.ZERO)
	check(not zone.correct_placement, "Hands at same height fail")
	pair(Vector3.ZERO, normal * 0.035 + sideways * 0.05)
	check(not zone.correct_placement, "Upper hand beside lower hand fails")
	pair(Vector3.ZERO, normal * 0.09)
	check(not zone.correct_placement, "Upper hand too high fails")
	pair(normal * 0.04, normal * 0.075)
	check(not zone.correct_placement, "Entire stack hovering fails")
	pair(Vector3.ZERO, normal * 0.035)
	set_hand(left, centre, normal)
	zone._process(0.016)
	check(not zone.correct_placement, "Lower hand facing away fails")
	pair(Vector3.ZERO, normal * 0.035)
	set_hand(right, centre + normal * 0.035, normal)
	zone._process(0.016)
	check(not zone.correct_placement, "Upper hand facing away fails")
	pair(Vector3.ZERO, normal * 0.035)
	# During real CPR the lower hand is hidden under the upper one, so losing it must not clear
	# the placement: the one visible hand over the target footprint (slab .. stack height) counts.
	left.has_tracking_data = false
	zone._process(0.016)
	check(zone.correct_placement and zone.lower_hand == &"right", "Lower hand hidden: the visible upper hand alone keeps placement")
	check(zone._material.albedo_color.g > zone._material.albedo_color.r, "Target stays green: it is an instruction colour, never orange")
	set_hand(right, centre + normal * 0.10, -normal)
	zone._process(0.016)
	check(not zone.correct_placement, "A single hand hovering above the stack height fails")
	set_hand(right, centre + sideways * 0.06 + normal * 0.03, -normal)
	zone._process(0.016)
	check(not zone.correct_placement, "A single hand beside the target fails")
	set_hand(right, centre + normal * 0.035, normal)
	zone._process(0.016)
	check(not zone.correct_placement, "A single hand facing away fails")
	set_hand(right, centre + normal * 0.035, -normal)
	right.has_tracking_data = false
	zone._process(0.016)
	check(not zone.correct_placement and zone.lower_hand == &"", "Both hands lost clears placement")
	right.has_tracking_data = true
	left.has_tracking_data = true
	left.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER
	zone._process(0.016)
	check(zone._read_hand(zone.left_tracker).is_empty() and zone.lower_hand == &"right", "Controller-inferred joints rejected; the tracked hand still counts")
	left.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
	# The Quest loses the wrist first during placement. A stale or missing wrist must not make a
	# tracked hand disappear: the heel is estimated from the palm along the finger axis instead.
	left.set_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
	zone._process(0.016)
	check(zone.correct_placement, "Stale wrist falls back to the palm-only heel and still passes")
	check(not zone._read_hand(zone.left_tracker).wrist_tracked, "Fallback reports the wrist as untracked")
	check(zone._read_hand(zone.left_tracker).heel.distance_to(centre) < 0.00001, "Palm-only heel lands on the synthetic heel")
	left.set_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST, 0)
	zone._process(0.016)
	check(zone.correct_placement, "Missing wrist joint with a fully tracked palm still passes")
	left.set_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST, POS)
	left.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM, POS)
	zone._process(0.016)
	check(zone.correct_placement, "Missing palm orientation still passes on position alone")
	check(not zone._read_hand(zone.left_tracker).has("palm_normal"), "No orientation means no palm normal is claimed")
	check(not zone._read_motion_hand(zone.left_tracker).is_empty(), "Motion accepts tracked palm without orientation")
	left.set_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST, 0)
	check(not zone._read_motion_hand(zone.left_tracker).is_empty(), "Motion does not require a wrist joint")
	left.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
	check(zone._read_motion_hand(zone.left_tracker).is_empty(), "Motion rejects stale palm positions")
	left.set_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST, POS)
	left.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM, FULL)
	var saved_scale := XRServer.world_scale
	XRServer.world_scale = 1.5
	pair(Vector3.ZERO, normal * 0.035 * XRServer.world_scale)
	check(zone.correct_placement, "XR origin and world scale preserve placement")
	check(zone._read_hand(zone.left_tracker).heel.distance_to(centre) < 0.00001, "XR origin and world scale applied exactly once")
	XRServer.world_scale = saved_scale
	pair(Vector3.ZERO, normal * 0.035)
	zone._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(not zone.correct_placement and not zone._highlight.visible, "Pause clears feedback")
	zone._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	zone._process(0.016)
	check(zone.correct_placement, "Fresh tracking restores placement")
	zone._on_start_button(&"by_button")
	check(zone.is_cpr_started and not zone._highlight.visible, "Start hides highlight")
	zone._process(0.016)
	check(not zone._highlight.visible, "Highlight stays hidden")
	zone._on_start_button(&"by_button")
	check(not zone.is_cpr_started and zone._highlight.visible, "Reset restores guide")
	# Exercise the actual XR joint reader through automatic start and continued counting.
	for cycle in 3:
		for sample in 41:
			var travel := 0.055 * (1.0 - cos(TAU * float(sample) / 40.0)) * 0.5
			set_hand(left, centre - normal * travel, -normal)
			set_hand(right, centre + normal * (0.035 - travel), -normal)
			zone._process(1.0 / 72.0)
		if cycle == 0:
			check(zone.is_cpr_started, "First complete stroke hides guide")
	check(zone.is_cpr_started and zone.motion_session.count == 3, "Joint tracking auto-starts and keeps counting after start")
	check(not zone._highlight.visible, "Automatic motion start hides guide")
	check(zone._metronome.stream is AudioStreamWAV and zone._metronome.stream.data.size() > 1000, "Actual PCM beep generated")
	zone.motion_session._beat_remaining = 0.0
	zone._process(1.0 / 72.0)
	check(zone._metronome.playing, "Session beat reaches audio playback")
	check(zone._metronome.bus == &"Master" and zone._metronome.volume_db == -3.0, "Beep uses audible master output level")
	var hud := Node3D.new()
	hud.set_script(preload("res://cpr_feedback_hud.gd"))
	hud.zone = zone
	root.add_child(hud)
	hud._process(0.016)
	check(hud._counter.text == "3 / 30", "HUD displays compression count")
	check("Estimated hand travel" in hud._depth["name"].text, "HUD labels motion estimate honestly")
	check(hud._coach.text == "Good press", "Three good 55 mm presses coach Good press (got %s)" % hud._coach.text)
	check(hud._depth["marker"].visible and "cm" in hud._depth["value"].text, "Depth gauge shows the completed press")
	zone.motion_session.phase = "breathing"
	zone.motion_session.breathing_remaining_s = 4.2
	hud._process(0.016)
	check(hud._title.text == "GIVE 2 BREATHS" and hud._counter.text == "4.2 s", "HUD displays breathing countdown")
	hud.free()
	check_upper_hand_motion()
	zone.reset_placement()
	avatar.hide()
	zone._process(0.016)
	check(not zone.correct_placement, "Hidden avatar cannot pass")
	XRServer.remove_tracker(left)
	XRServer.remove_tracker(right)
	var guide = load("res://cpr_hand_zone.tscn").instantiate()
	root.add_child(guide)
	guide._process(0.016)
	check(guide.guide_only and not guide.correct_placement, "Default guide makes no correctness claim")
	check(guide._highlight.material_override is ShaderMaterial, "Default guide uses green target ring")
	check(guide._highlight.visible, "Ring visible without tracking")
	guide.start_cpr()
	check(not guide._instruction.visible, "Start hides heel-placement label")
	check(not guide._highlight.visible, "Start hides ring together")
	guide.reset_placement()
	check(guide._instruction.visible and "Place hand heel here" in guide._instruction.text, "Reset restores heel-placement label")
	check(guide._highlight.visible, "Reset restores ring")
	guide.free()
	avatar.free()
	origin.free()
	# Let the audio mixer release stopped PCM playback before the test process exits.
	await create_timer(0.1).timeout
	print("CPR heel placement tests: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
