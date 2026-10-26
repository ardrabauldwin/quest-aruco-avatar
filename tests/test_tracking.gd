extends "res://tests/suite.gd"
## Verify frame composition, persisted calibration and the real provider API contract.

class FakeProvider extends Node:
	signal markers_updated(ids: Array)
	var pose := Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.4, 0.2, -1.0))
	var age := 0.0
	var default_marker_size := 0.05
	var marker_sizes: Array[float] = []
	var enabled := true
	func get_marker_world_pose(_id: int) -> Transform3D:
		return pose
	func marker_age_ms(_id: int) -> float:
		return age

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.background_color = Color(0.2, 0.3, 0.4, 1.0)
	NaretOpenXRSetup.prepare_passthrough_environment(environment)
	check(environment.background_mode == Environment.BG_COLOR and environment.background_color.a == 0.0, "passthrough environment cannot obscure camera background")
	var world := Node3D.new()
	tree.root.add_child(world)
	var anchor := NaretSpatialAnchor.new()
	anchor.calibration_file = "user://test_tracking_calibration.cfg"
	# An interrupted test must not leave marker settings for the next run.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(anchor.calibration_file))
	world.add_child(anchor)
	anchor.reset_calibration()
	var marker := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(1, 0.2, -2))
	anchor.update_pose(marker)
	var desired := marker * Transform3D(Basis.IDENTITY, Vector3(0.2, 0.1, 0))
	check(anchor.calibrate(desired) == OK, "calibration save")
	check(anchor.global_transform.is_equal_approx(desired), "offset is composed in marker space")
	var moved := Transform3D(Basis(Vector3.UP, -0.4), Vector3(-1, 0.5, -3))
	anchor.update_pose(moved)
	check(anchor.global_transform.is_equal_approx(moved * anchor.marker_to_mannequin), "moving marker carries calibrated mannequin")
	var reloaded := NaretSpatialAnchor.new()
	reloaded.calibration_file = anchor.calibration_file
	world.add_child(reloaded)
	check(reloaded.calibrated and reloaded.marker_to_mannequin.is_equal_approx(anchor.marker_to_mannequin), "calibration reload")
	var failed_save := NaretSpatialAnchor.new()
	failed_save.calibration_file = "user://missing_calibration_directory/alignment.cfg"
	world.add_child(failed_save)
	failed_save.update_pose(marker)
	check(failed_save.calibrate(desired) != OK, "unwritable calibration reports failure")
	check(not failed_save.calibrated, "failed persistence cannot allow exercise start")
	var provider := FakeProvider.new()
	world.add_child(provider)
	var tracker := NaretArucoTracker.new()
	tracker.desktop_preview = false
	tracker.calibration_file = anchor.calibration_file
	tracker.provider_path = NodePath("../FakeProvider")
	provider.name = "FakeProvider"
	world.add_child(tracker)
	check(tracker.bind_provider(provider), "upstream provider API accepted")
	tracker.pose_updated.connect(anchor.update_pose)
	provider.markers_updated.emit([0])
	check(tracker.tracked, "fresh provider signal sets tracked")
	check(tracker.latest_pose.is_equal_approx(provider.pose), "provider world pose consumed without double XR transform")
	provider.age = 900.0
	tracker._process(0.01)
	check(not tracker.tracked, "stale pose never reported tracked")
	check(tracker.latest_pose.is_equal_approx(provider.pose), "last pose held on occlusion")
	provider.enabled = false
	check(tracker.configure_marker(0.08, 7) == OK, "marker size and id save")
	check(provider.enabled, "marker reconfiguration wakes a provider paused outside the field of view")
	check(not tracker.tracked and is_equal_approx(provider.default_marker_size, 0.08), "marker geometry change invalidates old pose and updates native provider")
	check(provider.marker_sizes.size() == 50 and is_equal_approx(provider.marker_sizes[7], 0.08), "selected marker uses configured physical size")
	anchor.save_calibration()
	var profile := ConfigFile.new()
	profile.load(anchor.calibration_file)
	check(profile.get_value("marker", "id", -1) == 7, "offset saves preserve marker calibration")
	check(profile.has_section_key("calibration", "marker_to_mannequin"), "marker saves preserve mannequin offset")
	provider.age = 0.0
	provider.markers_updated.emit([7])
	check(not tracker.tracked, "discard old geometry result already in flight")
	provider.markers_updated.emit([7])
	check(tracker.tracked, "new marker geometry reacquires tracking")
	var motion_path := "res://addons/naret_upstream/avatar/cpr_motion_session.gd"
	if ResourceLoader.exists(motion_path):
		var motion: RefCounted = load(motion_path).new()
		motion.set("automatic_breathing_pause", false)
		motion.set("metronome_enabled", false)
		motion.call("update", 0.02, true, 0.10)
		for stroke in range(32):
			# Realistic full stroke, not a one-frame spike (new detector rejects those).
			for frame in range(1, 41):
				var height := 0.10 - 0.055 * (1.0 - cos(TAU * float(frame) / 40.0)) * 0.5
				motion.call("update", 1.0 / 72.0, true, height)
		check(motion.get("total_count") == 32, "stroke detector counts independently of standalone-demo beat alignment")
		check(motion.get("phase") == "compressions", "scenario owns the breathing pause after 30 strokes")
		motion.call("invalidate_tracking")
		motion.call("update", 0.02, true, 0.02)
		check(motion.get("total_count") == 32, "occlusion does not bridge into a false stroke")
	var interaction := NaretXRInteraction.new()
	world.add_child(interaction)
	var panel := Node3D.new()
	panel.position = Vector3(0, 0, -2)
	world.add_child(panel)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(200, 200)
	viewport.handle_input_locally = true
	world.add_child(viewport)
	var button := Button.new()
	button.position = Vector2(50, 50)
	button.size = Vector2(100, 100)
	viewport.add_child(button)
	var clicks := [0]
	button.pressed.connect(func(): clicks[0] += 1)
	interaction.register_ui_panel(panel, viewport, Vector2(1, 1))
	await tree.process_frame
	var hit: Dictionary = interaction.call("_pick_panel", Vector3.ZERO, Vector3.FORWARD)
	check(not hit.is_empty() and hit.pixel.is_equal_approx(Vector2(100, 100)), "XR ray maps the physical panel centre to viewport pixels")
	interaction.call("_send_pointer", hit, false, false)
	# A bare registered surface (the palm card) has no pointer handlers.
	var bare := Node3D.new()
	interaction.call("_send_pointer", {"viewport": null, "target": bare}, true, true)
	bare.free()
	interaction.call("_click_from_pose", Transform3D.IDENTITY, true, "test")
	# The controller can move away during a press; release still belongs to this button.
	interaction.call("_click_from_pose", Transform3D(Basis.IDENTITY, Vector3(9, 0, 0)), false, "test")
	await tree.process_frame
	check(clicks[0] == 1, "Pinch press/release activates a SubViewport button exactly once")
	# Near interaction: a fingertip crossing the panel presses, withdrawing releases.
	clicks[0] = 0
	interaction.call("_update_poke", 0, Vector3(0, 0, -1.94), "left")
	check(not interaction.call("_update_poke", 0, Vector3(0, 0, -1.5), "left"), "a distant fingertip does not claim the panel")
	interaction.call("_update_poke", 0, Vector3(0, 0, -1.94), "left")
	interaction.call("_update_poke", 0, Vector3(0, 0, -2.0), "left")
	interaction.call("_update_poke", 0, Vector3(0, 0, -1.96), "left")
	await tree.process_frame
	check(clicks[0] == 1, "Fingertip poke activates a panel button exactly once")
	clicks[0] = 0
	interaction.call("_update_poke", 0, Vector3(0.9, 0, -2.0), "left")
	await tree.process_frame
	check(clicks[0] == 0, "A poke outside the panel bounds presses nothing")
	_test_grab_gestures(interaction)
	_test_room_spots()
	_test_marker_on_sternum(tree)
	await _test_hand_menu(tree)
	await _test_cpr_stacked_hands(tree)
	await _test_aed_by_hand(tree)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(anchor.calibration_file))
	world.free()
	return failures

func _test_marker_on_sternum(tree: SceneTree) -> void:
	## The marker on the sternum places the patient without calibration, settles,
	## ignores compressions and covered frames, and follows a moved mannequin.
	var anchor := NaretSpatialAnchor.new()
	anchor.calibration_file = "user://test_sternum_marker.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(anchor.calibration_file))
	var mannequin: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	mannequin.name = "Mannequin"
	anchor.add_child(mannequin)
	tree.root.add_child(anchor)
	var marker := Transform3D(Basis(Vector3.UP, 0.7) * Basis(Vector3.RIGHT, 0.1), Vector3(0.4, 0.3, -1.1))
	anchor.update_pose(marker, 0)
	var sternum := mannequin.sternum.global_transform
	check(sternum.origin.is_equal_approx(marker.origin - marker.basis.y * anchor.marker_thickness_m), "uncalibrated: the sternum sits under the marker")
	check(sternum.basis.y.is_equal_approx(marker.basis.y), "the chest normal follows the marker normal")
	check(not anchor.locked, "the first pose is shown but not yet settled")
	for i in range(1, 41):
		anchor.update_pose(marker, i * 30)
	check(not anchor.locked, "desktop uses robust startup, not a 1.5-second settling shortcut")
	anchor.update_pose(marker, 1230)
	check(anchor.locked, "desktop accepts the same 42-reading robust startup")
	var placed := anchor.global_transform
	# Compressions at 110/min: the marker sinks 5 cm and comes back, half the frames covered.
	var held := true
	for i in 60:
		if i % 2 == 0:
			anchor.update_pose(marker.translated(marker.basis.y * -0.05 * float(i % 4 == 0)), 1600 + i * 50)
			held = held and anchor.global_transform.is_equal_approx(placed)
	check(held, "compressions do not move the patient")
	var moved := marker.translated(Vector3(0.2, 0, 0))
	for t in [5000, 5800, 6600]:
		anchor.update_pose(moved, t)
	check(anchor.global_transform.is_equal_approx(placed), "desktop holds placement without a tracked viewer")
	anchor.unlock()
	for i in 42:
		anchor.update_pose(moved, 7000 + i * 30)
	check(anchor.global_transform.is_equal_approx(moved * anchor.marker_to_mannequin), "explicit reposition collects a fresh robust startup")
	var file := anchor.calibration_file
	anchor.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))

func _test_room_spots() -> void:
	# 5 x 4 m scanned room with one table; bystanders may use neither wall nor table.
	var outline := PackedVector2Array([Vector2(-2.5, -2), Vector2(2.5, -2), Vector2(2.5, 2), Vector2(-2.5, 2)])
	var table := Rect2(Vector2(1.0, -0.6), Vector2(1.2, 1.2))
	var spots := NaretRoomLayout.pick_spots(outline, [table], Vector2.ZERO, 2)
	check(spots.size() == 2, "room scan yields a standing spot per bystander")
	for spot in spots:
		check(absf(spot.x) <= 2.1 and absf(spot.y) <= 1.6, "standing spot keeps clear of the scanned walls")
		check(not table.grow(0.3).has_point(spot), "standing spot avoids scanned furniture")
	if spots.size() == 2:
		check(spots[0].distance_to(spots[1]) >= NaretRoomLayout.SPOT_SEPARATION, "bystanders do not share one spot")
	check(NaretRoomLayout.pick_spots(PackedVector2Array(), [], Vector2.ZERO, 2).is_empty(), "no room scan means no placement")
	# The patient lies on floor the scan reports as free; that rectangle is passed in.
	var patient := Rect2(Vector2(-0.35, -1.05), Vector2(0.7, 2.1))
	for spot in NaretRoomLayout.pick_spots(outline, [patient], Vector2.ZERO, 2):
		check(not patient.has_point(spot), "nobody is placed on the patient")
	# A room fully covered by furniture must place nobody rather than place badly.
	var narrow := PackedVector2Array([Vector2(-3, -0.2), Vector2(3, -0.2), Vector2(3, 0.2), Vector2(-3, 0.2)])
	check(NaretRoomLayout.pick_spots(narrow, [], Vector2.ZERO, 2).is_empty(), "narrow floor never bypasses wall clearance")
	var small_room := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	var compact_patient := Rect2(Vector2(-0.35, -1.05), Vector2(0.7, 2.1))
	var compact_people := NaretRoomLayout.pick_spots(small_room, [compact_patient], Vector2.ZERO, 2, 0.225, PackedVector2Array(), 0.5)
	check(compact_people.size() == 2, "two half-size speakers fit beside patient in 2m play area")
	for point in compact_people:
		check(absf(point.x) <= 0.775 and absf(point.y) <= 0.775, "compact speakers retain boundary clearance")

	var offset_room := PackedVector2Array([Vector2(9, 9), Vector2(12, 9), Vector2(12, 12), Vector2(9, 12)])
	check(NaretRoomLayout.pick_spots(offset_room, [], Vector2.ZERO, 2).size() == 2, "grid search finds safe floor missed by patient-centred rings")
	var allowed := PackedVector2Array([Vector2(-2.5, -2), Vector2(0, -2), Vector2(0, 2), Vector2(-2.5, 2)])
	var bounded := NaretRoomLayout.pick_spots(outline, [], Vector2.ZERO, 2, 0.6, allowed)
	check(bounded.size() == 2, "room and play-area constraints can both provide two spots")
	for point in bounded:
		check(point.x <= -0.6 and point.x >= -1.9 and absf(point.y) <= 1.4, "body envelope fits inside both scanned room and play area")
	if bounded.size() == 2:
		check(bounded[0].distance_to(bounded[1]) >= 1.2, "whole-body envelopes do not overlap")
	var blocked := Rect2(Vector2(-4, -4), Vector2(8, 8))
	check(NaretRoomLayout.pick_spots(outline, [blocked], Vector2.ZERO, 2).is_empty(), "no free floor means no placement")

func _palm_basis(looking_at: Vector3) -> Basis:
	# +Z is the palm surface, matching Godot's OpenXR humanoid hand conversion.
	var z_axis := looking_at.normalized()
	var x_axis := Vector3.UP.cross(z_axis)
	x_axis = x_axis.normalized() if x_axis.length_squared() > 0.001 else Vector3.RIGHT
	return Basis(x_axis, z_axis.cross(x_axis).normalized(), z_axis)

static func synth_hand(palm: Transform3D) -> XRHandTracker:
	## A tracked left hand laid out open around `palm` (+Z palm surface, +Y fingers),
	## enough joints for the hand menu: palm, wrist, thumb and four fingertips.
	var hand := XRHandTracker.new()
	hand.name = &"/user/hand_tracker/left"
	hand.has_tracking_data = true
	var flags := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED \
		| XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_TRACKED
	var joints := {
		XRHandTracker.HAND_JOINT_PALM: Vector2.ZERO, XRHandTracker.HAND_JOINT_WRIST: Vector2(0, -0.07),
		XRHandTracker.HAND_JOINT_THUMB_TIP: Vector2(0.055, 0.03), XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP: Vector2(0.02, 0.085),
		XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP: Vector2(0, 0.092), XRHandTracker.HAND_JOINT_RING_FINGER_TIP: Vector2(-0.02, 0.085),
		XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP: Vector2(-0.04, 0.07)}
	for joint in joints:
		var offset: Vector2 = joints[joint]
		hand.set_hand_joint_flags(joint, flags)
		hand.set_hand_joint_transform(joint, Transform3D(palm.basis, palm * Vector3(offset.x, offset.y, 0)))
	return hand

func _test_hand_menu(tree: SceneTree) -> void:
	var stage := Node3D.new()
	tree.root.add_child(stage)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.6, 0)
	stage.add_child(camera)
	camera.make_current()
	var origin := XROrigin3D.new()
	stage.add_child(origin)
	var palm_position := Vector3(0, 1.3, -0.4)
	var hand := synth_hand(Transform3D(_palm_basis(camera.position - palm_position), palm_position))
	XRServer.add_tracker(hand)
	var menu := NaretHandMenu.new()
	stage.add_child(menu)
	var interaction := NaretXRInteraction.new()
	stage.add_child(interaction)
	menu.configure(origin, 0, interaction)
	var shown: Array[bool] = []
	menu.menu_shown_changed.connect(func(value: bool): shown.append(value))
	var scenario := NaretScenario.new()
	stage.add_child(scenario)
	menu.update_session(scenario)
	var actions: Array[String] = []
	menu.action_requested.connect(func(action: String): actions.append(action))
	await tree.process_frame
	await tree.process_frame
	check(menu.palm_panel.is_visible_in_tree(), "palm turned to the face opens the hand menu")
	check(shown == [true], "opening reports exactly one visibility change")
	check(menu.palm_panel.global_position.distance_to(palm_position) < 0.03, "the readout hugs the palm it belongs to")
	# Actions are real 3D targets above the fingertips: the other hand's poke must reach the scenario.
	var start_node: Node3D = menu._large_start
	var index_tip := hand.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
	check(start_node.visible and start_node.label.text == "Start training", "idle scenario offers the start node")
	check(not menu._action_keys[0].visible, "Start is not duplicated in the dynamic action list")
	var hit: Dictionary = interaction._poke_panel(start_node.global_transform * Vector3(0, 0, 0.002))
	check(hit.get("target") == start_node, "fingertip in front of the start node pokes that node, not the palm panel")
	interaction._send_pointer(hit, true, true)
	interaction._send_pointer(hit, true, false)
	check(actions == ["start"], "releasing a poked node requests its action")
	# Same hand: thumb touching the index fingertip taps that node.
	hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP, Transform3D(Basis.IDENTITY, index_tip + Vector3(0.01, 0, 0)))
	await tree.process_frame
	hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP, Transform3D(Basis.IDENTITY, index_tip + Vector3(0.06, 0, 0)))
	await tree.process_frame
	check(actions == ["start"], "hidden duplicate Start cannot be triggered by a fingertip tap")
	# Turning the palm away from the wearer must give both hands back to the patient.
	hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM,
		Transform3D(_palm_basis(palm_position - camera.position), palm_position))
	await tree.process_frame
	await tree.process_frame
	check(not menu.palm_panel.is_visible_in_tree(), "palm turned away closes the hand menu")
	hand.has_tracking_data = false
	await tree.process_frame
	check(not menu.palm_panel.is_visible_in_tree(), "an untracked hand shows no menu")
	XRServer.remove_tracker(hand)
	stage.free()

func _test_grab_gestures(interaction: NaretXRInteraction) -> void:
	var hand := XRHandTracker.new()
	hand.name = &"/user/hand_tracker/left"
	hand.has_tracking_data = true
	var flags := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
	var palm_p := Vector3(0, 1.2, -0.4)
	hand.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM, flags)
	hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM, Transform3D(Basis.IDENTITY, palm_p))

	# 1. Open hand: all fingers extended
	for j in [XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP,
			  XRHandTracker.HAND_JOINT_RING_FINGER_TIP, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP]:
		hand.set_hand_joint_flags(j, flags)
		hand.set_hand_joint_transform(j, Transform3D(Basis.IDENTITY, palm_p + Vector3(0, 0.11, 0)))
	check(not interaction._is_hand_grabbing(hand, palm_p, false), "open hand does not trigger grab")

	# 2. Pinch gesture: index close to palm/thumb, but middle, ring, pinky extended (>0.10m)
	hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, Transform3D(Basis.IDENTITY, palm_p + Vector3(0, 0.05, 0)))
	hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, Transform3D(Basis.IDENTITY, palm_p + Vector3(0, 0.11, 0)))
	hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_RING_FINGER_TIP, Transform3D(Basis.IDENTITY, palm_p + Vector3(0, 0.11, 0)))
	hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP, Transform3D(Basis.IDENTITY, palm_p + Vector3(0, 0.11, 0)))
	check(not interaction._is_hand_grabbing(hand, palm_p, false), "pinch gesture does not trigger patient grab")

	# 3. Whole-hand grab / fist: middle and ring curled towards palm (<0.068m)
	hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, Transform3D(Basis.IDENTITY, palm_p + Vector3(0, 0.05, 0)))
	hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_RING_FINGER_TIP, Transform3D(Basis.IDENTITY, palm_p + Vector3(0, 0.05, 0)))
	check(interaction._is_hand_grabbing(hand, palm_p, false), "whole-hand grab gesture triggers patient grab")

	# 4. Hysteresis hold at 0.075m
	hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, Transform3D(Basis.IDENTITY, palm_p + Vector3(0, 0.075, 0)))
	hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_RING_FINGER_TIP, Transform3D(Basis.IDENTITY, palm_p + Vector3(0, 0.075, 0)))
	check(interaction._is_hand_grabbing(hand, palm_p, true), "hysteresis holds grab active")

	# 5. Full release at 0.09m (>0.082m)
	hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, Transform3D(Basis.IDENTITY, palm_p + Vector3(0, 0.09, 0)))
	hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_RING_FINGER_TIP, Transform3D(Basis.IDENTITY, palm_p + Vector3(0, 0.09, 0)))
	check(not interaction._is_hand_grabbing(hand, palm_p, true), "fingers opening releases grab")

func _test_cpr_stacked_hands(tree: SceneTree) -> void:
	var stage := Node3D.new()
	tree.root.add_child(stage)
	var origin := XROrigin3D.new()
	stage.add_child(origin)
	var mannequin: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	stage.add_child(mannequin)
	var interaction := NaretXRInteraction.new()
	stage.add_child(interaction)
	interaction.configure(mannequin, origin)
	interaction.set_cpr_enabled(true)
	await tree.process_frame
	await tree.process_frame
	
	var zone: Area3D = interaction.get("_zone")
	check(zone != null, "CPR hand zone instantiated")
	if zone != null:
		var sternum_pos: Vector3 = mannequin.get_sternum_transform().origin
		check(zone.call("contains_world_point", sternum_pos), "Sternum rest position is in CPR contact zone")
		check(bool(zone.get("require_collision_contact")), "Merged app requires collision contact before counting")
		check(zone.call("contact_overlaps", sternum_pos), "Heel sphere overlaps chest collision box")
		var joint_points: Array[Vector3] = [sternum_pos + Vector3(0.2, 0, 0), sternum_pos]
		check(zone.call("_points_touch_chest", joint_points), "A finger or palm point can contact without heel overlap")
		check((zone.call("_closest_contact_point", joint_points) as Vector3).is_equal_approx(sternum_pos), "Contact retention uses nearest hand part, not heel alone")
		var no_points: Array[Vector3] = []
		check(not zone.call("_points_touch_chest", no_points), "Missing tracked joints cannot supply contact")
		check(not zone.call("contact_overlaps", sternum_pos + Vector3(0.2, 0, 0)), "Nearby lateral movement is not contact")
		check(not zone.call("contact_overlaps", Vector3.INF), "Invalid tracked contact is rejected")
		var contact_shape := zone.get_node("CollisionShape3D") as CollisionShape3D
		check(zone.call("_within_contact_stroke", contact_shape.to_global(Vector3(0, -0.04, 0))), "Contact can continue through compression travel")
		check(not zone.call("_within_contact_stroke", contact_shape.to_global(Vector3(0, 0.3, 0))), "Lifting away disarms contact")
		var stacked_heel := contact_shape.to_global(Vector3(0, 0.04, 0))
		check(zone.call("_contact_allows_stroke", stacked_heel, true, true), "Lower-hand contact arms upper-hand movement")
		check(zone.call("_contact_allows_stroke", contact_shape.to_global(Vector3(0, -0.04, 0)), false, true), "Contact persists through compression travel")
		check(not zone.call("_contact_allows_stroke", stacked_heel, false, false), "Tracking loss disarms contact")
		check(not zone.call("_contact_allows_stroke", stacked_heel, false, true), "Air movement cannot rearm without new contact")
		var contact := zone.get_node("CollisionShape3D") as CollisionShape3D
		check(is_equal_approx((contact.shape as BoxShape3D).size.y, 0.026), "user original placement slab is preserved")
		check(not zone.call("contains_world_point", sternum_pos - Vector3(0, 0.05, 0)), "5 cm below original placement slab is rejected")
		check(not zone.call("contains_world_point", sternum_pos - Vector3(0, 0.15, 0)), "15 cm below sternum is rejected")
		check(not zone.call("contains_world_point", sternum_pos + Vector3(0, 0.10, 0)), "10 cm above sternum is rejected")
	stage.free()
	await tree.process_frame

func _test_aed_by_hand(tree: SceneTree) -> void:
	## Fingertip on the power button, pinch an electrode, let go on the chest: the
	## device connects itself once both are on, and never takes a pad dropped off target.
	var stage := Node3D.new()
	tree.root.add_child(stage)
	var mannequin: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	stage.add_child(mannequin)
	var model: Node3D = load("res://assets/models/aed.glb").instantiate()
	stage.add_child(model)
	model.position = Vector3(-0.45, 0, 0.3)
	var aed := NaretAED.new()
	stage.add_child(aed)
	aed.configure(model, mannequin)
	model.visible = true
	await tree.process_frame
	var requests: Array[String] = []
	aed.requested.connect(func(action: String): requests.append(action))
	var far := Vector3(0, 2, 0)
	var power: Vector3 = aed._power.global_position
	aed.touch("h", power, far, false)
	check(aed.powered, "AED: a fingertip on the power button switches it on")
	aed.touch("h", far, far, false)
	var names := ["PadRight", "PadLeft"]
	for i in 2:
		var pad: Node3D = aed._pads[names[i]]
		var rest := pad.global_position
		check(aed.touch("h", far, rest, true), "AED: pinch takes %s" % names[i])
		if i == 0:
			# Let go in mid-air first: the electrode goes back to the device.
			aed.touch("h", far, rest + Vector3(0, 0.3, 0), true)
			aed.touch("h", far, rest + Vector3(0, 0.3, 0), false)
			check(aed._placed.is_empty(), "AED: a pad dropped off target does not stick")
			await tree.create_timer(0.4).timeout
			aed.touch("h", far, rest, true)
		var target: Vector3 = aed._pad_target(names[i]).origin + Vector3(0.02, 0.01, 0)
		aed.touch("h", far, target, true)
		aed.touch("h", far, target, false)
	check(aed._placed.size() == 2, "AED: both electrodes stick on the chest")
	var scenario := NaretScenario.new()
	stage.add_child(scenario)
	scenario.start()
	for action in ["begin_check", "check_responsiveness", "check_breathing", "call_emergency"]:
		scenario.submit_action(action)
	aed.sync(scenario, "de")
	check(requests.has("attach_aed"), "AED: powered with both pads, the device connects itself")
	stage.queue_free()
	await tree.process_frame
