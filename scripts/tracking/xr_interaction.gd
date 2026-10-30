class_name NaretXRInteraction
extends Node3D
## Connects the user's hand-zone/stroke detector to Denis's patient and scenario.
## It also handles existing hand interaction with menus and the patient.
## Counting is done in addons/naret_upstream/avatar/cpr_motion_session.gd,
## not by the menu-ray code below. This adapter forwards each new count.
## Reported depth is HAND EXCURSION, not independently measured chest compression.
## Hand joints start in XR tracking coordinates; multiply by XROrigin to get room coordinates.
signal compression_measured(depth_m: float, rate_bpm: float, correct_position: bool)
signal action_requested(action: String)
signal placement_changed(correct: bool)
signal head_tilt_gesture_detected
var head_tilt_gesture := NaretHeadTiltGesture.new()

const HAND_NAMES := [&"/user/hand_tracker/left", &"/user/hand_tracker/right"]
## Near interaction, MRTK style: a fingertip this close to a panel pokes it.
const POKE_RANGE_M := 0.06
const POKE_THROUGH_M := 0.04
const POKE_PRESS_M := 0.005
const POKE_RELEASE_M := 0.015
var cpr_enabled := false
var _audio_busy := false
var aed_active := false
## The AED is worked with the hands too: power button, electrodes.
var aed: NaretAED
var _mannequin: NaretMannequin
var _origin: XROrigin3D
var _zone: Area3D
var _rays: Array[MeshInstance3D] = []
var _panels: Array[Dictionary] = []
var _pinched := [false, false]
var _controller_pressed := [false, false]
var _poking := [false, false]
var _grabbing := [false, false]
var _ragdoll: NaretRagdoll
var _menu_hand := -1
var _last_count := 0
var _cpr_feedback_root: Node3D
const OriginalCPRHud = preload("res://addons/naret_upstream/avatar/cpr_feedback_hud.gd")
var _pointer_capture: Dictionary = {}
var _near_menu_until_ms := 0
var _contact_poll := 0.0
var _hands_on_chest := false

func configure(mannequin: NaretMannequin, xr_origin: XROrigin3D) -> void:
	# Create menu pointers, then load the existing user hand-zone scene.
	_mannequin = mannequin
	_origin = xr_origin
	_ragdoll = mannequin.ragdoll
	for index in range(2):
		var ray := MeshInstance3D.new()
		var line := CylinderMesh.new()
		line.top_radius = 0.0015
		line.bottom_radius = 0.0015
		line.height = 1.0
		ray.mesh = line
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.3, 0.95, 0.85)
		ray.material_override = material
		ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ray.visible = false
		add_child(ray)
		_rays.append(ray)
	var source := "res://addons/naret_upstream/avatar/cpr_hand_zone.tscn"
	if ResourceLoader.exists(source):
		_zone = load(source).instantiate()
		_zone.set("xr_origin", _origin)
		_zone.set("guide_only", false)
		_zone.set("enable_motion_practice", true)
		_zone.set("require_collision_contact", true)
		var motion: RefCounted = _zone.get("motion_session")
		# The scenario owns breathing pauses; disable the standalone demo scheduler.
		motion.set("automatic_breathing_pause", false)
		motion.set("metronome_enabled", true)
		_zone.get_node("CollisionShape3D").position = Vector3.ZERO
		# Keep the user's original hand-zone dimensions and acceptance logic.
		_zone.get_node("Highlight").position = Vector3(0, 0.004, 0)
		_zone.visible = false
		add_child(_zone)
		# The upstream ready() replaces the circular shader with its green quad
		# material. Keep that familiar guide, but do not let the curved chest
		# depth-clip half of it. Display only: collision and sternum stay unchanged.
		var guide_material := _zone.get_node("Highlight").material_override as StandardMaterial3D
		if guide_material != null:
			guide_material.no_depth_test = true
			guide_material.render_priority = 10
		# Headset review 2026-10-29: 14 x 14 cm reads better over the real chest than the
		# upstream 11 x 11 cm. Display only: the 8 x 7 cm contact slab is unchanged.
		var guide_mesh := _zone.get_node("Highlight").mesh as QuadMesh
		if guide_mesh != null:
			guide_mesh.size = Vector2(0.14, 0.14)
		var camera := _origin.find_child("*", true, false)
		for child in _origin.get_children():
			if child is XRCamera3D:
				camera = child
				break
		if camera is XRCamera3D:
			# The original HUD manages its own tracking visibility. A parent adds
			# exercise-step visibility without changing its gauges or detector.
			_cpr_feedback_root = Node3D.new()
			_cpr_feedback_root.visible = false
			camera.add_child(_cpr_feedback_root)
			var hud := OriginalCPRHud.new()
			hud.zone = _zone
			_cpr_feedback_root.add_child(hud)
			hud.position = Vector3(0.0, -0.22, -0.8)
			hud.process_priority = 30
		_zone.get_node("Instruction").text = ""
		_zone.set_process_unhandled_key_input(false)
		_zone.connect("placement_changed", func(correct: bool): placement_changed.emit(correct))
		set_cpr_enabled(false)

func register_ui_panel(panel: Node3D, viewport: SubViewport, size_m: Vector2) -> void:
	## Pointer hits land in `viewport` as mouse events, or, without one, on the
	## node itself via pointer_hover(depth_m) / pointer_press(down) if it has them.
	## Registering a node again only updates its size.
	for item in _panels:
		if item.panel == panel:
			item.size = size_m
			return
	_panels.append({"panel": panel, "viewport": viewport, "size": size_m})

## The upstream gauge panel (speed dial, depth bar, count) in front of the face during
## compressions. Switched off and back on during the 2026-10-29 headset review: the
## trainee missed it as the "CPR window". Counting, pace and the beep do not depend on it.
const SHOW_CPR_GAUGES := true
## Chest dent under resting hands (NaretMannequin.set_hand_press). Off since 2026-10-29.
const SHOW_HAND_DENT := false

func set_cpr_feedback_visible(value: bool) -> void:
	if is_instance_valid(_cpr_feedback_root):
		_cpr_feedback_root.visible = value and SHOW_CPR_GAUGES

func set_cpr_enabled(value: bool) -> void:
	# Scenario stages enable/disable CPR. Reset rate history at each transition.
	if value == cpr_enabled:
		return
	cpr_enabled = value
	if _zone != null:
		if value:
			_zone.call("reset_placement")
		_last_count = 0

func set_aed_active(value: bool) -> void:
	aed_active = value
	_contact_poll = 0.0

func set_audio_busy(value: bool) -> void:
	_audio_busy = value
	if _zone == null: return
	_zone.get("motion_session").set("metronome_enabled", not value)
	if value:
		_zone.get("_metronome").stop()

func rearm_cpr_cycle() -> void:
	# Call after an explicitly completed ventilation pair, if the scene uses cycles.
	if _zone != null:
		var motion: RefCounted = _zone.get("motion_session")
		motion.call("invalidate_tracking")
		motion.set("count", 0)

func _process(delta: float) -> void:
	if _origin == null:
		return
	_update_hands(delta)
	_update_controller_menu()
	_update_head_tilt(delta)
	if aed_active:
		_contact_poll -= delta
		if _contact_poll <= 0.0:
			_contact_poll = 0.15
			if _patient_contact_detected():
				action_requested.emit("patient_contact")
	if _zone == null:
		return
	# The original practice display is available after patient placement, even
	# before the scenario reaches CPR. Only cpr_enabled grants exercise strokes.
	_zone.visible = _mannequin.is_visible_in_tree()
	# Keep the counting/contact zone on the calibrated model sternum.
	_zone.global_transform = _mannequin.get_sternum_transform()
	# Root UI provides bilingual labels; the upstream diagnostic label is suppressed.
	_zone.get_node("Instruction").visible = false
	var session: RefCounted = _zone.get("motion_session")
	var count: int = session.get("total_count")
	# Emit only when the upstream detector reports a new stroke, not each frame.
	if cpr_enabled and count > _last_count:
		# Same pace source as the original needle dial: four detector intervals,
		# at least two intervals, invalidated by the detector's 1.5-second pause.
		var bpm := OriginalCPRHud.measured_bpm(session.get("_bpm_samples"))
		# The original detector already accepted these completed strokes in its
		# target zone. Do not reject them using a later frame's hand position.
		for stroke in range(count - _last_count):
			compression_measured.emit(float(session.get("last_stroke_travel_m")), bpm, true)
	_last_count = count
	# Real hands on the chest push it down to their own height, in every step,
	# so they never sink into it. This is display only: counting and depth
	# feedback stay with the detector above. Letting go releases the chest once,
	# so a helper's compressions (NaretBystanderDirector) still show.
	# Headset review 2026-10-29: the dent is off. Counted compressions still sink the
	# chest through the compression morph (NaretMannequin.compress), as before the dent.
	var press: Variant = hand_press_point(_mannequin.get_sternum_transform().origin) if SHOW_HAND_DENT else null
	if press != null:
		_mannequin.set_hand_press(press)
	elif _hands_on_chest:
		_mannequin.release_hand_press()
	_hands_on_chest = press != null

## A hand counts as on the chest within this distance of the compression point
## (sideways) and no higher than this above the resting chest surface.
const PRESS_REACH_M := 0.10
const PRESS_CONTACT_M := 0.015

func hand_press_point(sternum: Vector3) -> Variant:
	## Heel of the lowest tracked hand (midway between wrist and palm, minus the
	## joint radius) in world space, or null without a hand on the chest. With
	## stacked hands the lower one is the one touching the chest.
	var lowest: Variant = null
	for index in range(2):
		var hand := hand_tracker(index)
		if hand == null:
			continue
		var wrist: Variant = tracked_joint(hand, XRHandTracker.HAND_JOINT_WRIST)
		var palm: Variant = tracked_joint(hand, XRHandTracker.HAND_JOINT_PALM)
		if wrist == null or palm == null:
			continue
		var heel: Vector3 = _origin.global_transform * (((wrist as Transform3D).origin + (palm as Transform3D).origin) * 0.5)
		heel.y -= (hand.get_hand_joint_radius(XRHandTracker.HAND_JOINT_WRIST) + hand.get_hand_joint_radius(XRHandTracker.HAND_JOINT_PALM)) * 0.5
		var point: Variant = press_contact(heel, sternum)
		if point != null and (lowest == null or (point as Vector3).y < (lowest as Vector3).y):
			lowest = point
	return lowest

static func press_contact(heel: Vector3, sternum: Vector3) -> Variant:
	## Pure contact rule, testable without a headset.
	if Vector2(heel.x - sternum.x, heel.z - sternum.z).length() > PRESS_REACH_M or heel.y > sternum.y + PRESS_CONTACT_M:
		return null
	return heel

func _update_head_tilt(delta: float) -> void:
	var hands: Array = []
	for index in range(2):
		var hand := hand_tracker(index)
		var palm: Variant = tracked_joint(hand, XRHandTracker.HAND_JOINT_PALM) if hand else null
		var finger: Variant = tracked_joint(hand, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP) if hand else null
		hands.append({"palm": (_origin.global_transform * palm).origin, "finger": (_origin.global_transform * finger).origin} if palm != null and finger != null else {})
	var was_active := head_tilt_gesture.active
	var on := head_tilt_gesture.observe(hands, _mannequin.gesture_forehead(), _mannequin.gesture_chin(),
		_mannequin.global_basis.y.normalized(), -_mannequin.global_basis.z.normalized(), delta)
	_mannequin.set_head_tilt(on)
	if on and not was_active:
		print("NARET_HEAD_TILT gesture_detected technique_unverified")
		head_tilt_gesture_detected.emit()

func _patient_contact_detected() -> bool:
	if _mannequin == null:
		return false
	for index in range(2):
		var hand := hand_tracker(index)
		if hand == null:
			continue
		for joint: int in [XRHandTracker.HAND_JOINT_PALM, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP]:
			var local: Variant = tracked_joint(hand, joint)
			if local == null:
				continue
			if _point_near_patient((_origin.global_transform * (local as Transform3D)).origin):
				return true
	return false

func _point_near_patient(world_point: Vector3) -> bool:
	# Conservative contact envelope around the whole supine patient, not just sternum.
	# This can invalidate clearance; absence of tracked contact cannot prove clearance.
	var point := _mannequin.get_body_transform().affine_inverse() * world_point
	return absf(point.x) < 0.34 and point.y > -0.04 and point.y < 0.44 and point.z > -0.95 and point.z < 1.10

func has_active_menu_press() -> bool:
	# Hold the wrist controls still during approach as well as during contact.
	return not _pointer_capture.is_empty() or Time.get_ticks_msec() < _near_menu_until_ms

func _update_controller_menu() -> void:
	# Controllers operate menus only; they cannot generate tracked-hand CPR strokes.
	for index in range(2):
		var controller := _origin.get_node_or_null("LeftHand" if index == 0 else "RightHand") as XRController3D
		var pointer_id := "controller_menu_%d" % index
		if hand_tracker(index) != null:
			# Hands can also expose a synthetic controller pose. The hand pointer
			# already handled it; do not overwrite its ray or create a second click.
			if _pointer_capture.has(pointer_id): _click_hit({}, false, pointer_id)
			_controller_pressed[index] = false
			continue
		if controller == null or not controller.get_has_tracking_data():
			if _pointer_capture.has(pointer_id): _click_from_pose(Transform3D.IDENTITY, false, pointer_id)
			_controller_pressed[index] = false
			continue
		var pose := controller.global_transform
		var tracker := XRServer.get_tracker(controller.tracker) as XRPositionalTracker
		var aim: XRPose = tracker.get_pose("aim") if tracker else null
		if aim != null and aim.has_tracking_data:
			pose = _origin.global_transform * aim.get_adjusted_transform()
		var hit := _pick_panel(pose.origin, -pose.basis.z.normalized())
		if index < _rays.size():
			_rays[index].visible = not hit.is_empty()
			if not hit.is_empty():
				var length_m := float(hit.distance)
				_rays[index].global_transform = Transform3D(pose.basis * Basis(Vector3.RIGHT, PI * 0.5), pose.origin - pose.basis.z.normalized() * length_m * 0.5)
				_rays[index].scale = Vector3(1, length_m, 1)
		if not hit.is_empty():
			_send_pointer(hit, false, false)
		# Hold the captured target until trigger release, as for hand pinching.
		var pressed := controller.get_float("trigger") > 0.5
		if pressed != _controller_pressed[index]:
			_click_hit(hit, pressed, pointer_id)
		_controller_pressed[index] = pressed

func _pick_panel(from: Vector3, direction: Vector3) -> Dictionary:
	# Intersect a room-space ray with each panel in its local coordinates.
	# Keep the nearest visible panel hit inside its rectangular bounds.
	var best: Dictionary = {}
	var nearest := 6.0
	for item in _panels:
		var panel: Node3D = item.panel
		if not is_instance_valid(panel) or not panel.is_visible_in_tree():
			continue
		var inverse := panel.global_transform.affine_inverse()
		var local_from := inverse * from
		var local_direction := inverse.basis * direction
		if absf(local_direction.z) < 0.0001:
			continue
		var distance := -local_from.z / local_direction.z
		if distance <= 0.0 or distance >= nearest:
			continue
		var position := local_from + local_direction * distance
		var size: Vector2 = item.size
		if absf(position.x) > size.x * 0.5 or absf(position.y) > size.y * 0.5:
			continue
		best = {"target": panel, "viewport": item.viewport, "pixel": _pixel(item, position), "distance": distance}
		nearest = distance
	return best

func _pixel(item: Dictionary, local: Vector3) -> Vector2:
	# Convert metres on a centred panel into viewport pixels (top-left origin).
	var viewport: SubViewport = item.viewport
	if viewport == null:
		return Vector2.ZERO
	var size: Vector2 = item.size
	return Vector2((local.x / size.x + 0.5) * viewport.size.x, (0.5 - local.y / size.y) * viewport.size.y)

func _send_pointer(hit: Dictionary, click: bool, pressed: bool) -> void:
	var viewport: SubViewport = hit.viewport
	if viewport == null:
		var target: Node3D = hit.target
		# A bare surface (the palm card) only stops the ray; it has no handlers.
		if not is_instance_valid(target) or not target.has_method("pointer_hover"):
			return
		if click:
			target.pointer_press(pressed)
		else:
			target.pointer_hover(float(hit.get("depth", 0.02)))
		return
	if click:
		var event := InputEventMouseButton.new()
		event.position = hit.pixel
		event.global_position = hit.pixel
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)
	else:
		var event := InputEventMouseMotion.new()
		event.position = hit.pixel
		event.global_position = hit.pixel
		viewport.push_input(event, true)

func _click_from_pose(pose: Transform3D, pressed: bool, pointer_id: String) -> bool:
	return _click_hit(_pick_panel(pose.origin, -pose.basis.z.normalized()) if pressed else {}, pressed, pointer_id)


func _click_hit(hit: Dictionary, pressed: bool, pointer_id: String) -> bool:
	## A press is captured so its release reaches the same button even if the hand
	## has drifted off the panel in between.
	if pressed:
		if not hit.is_empty():
			_pointer_capture[pointer_id] = hit
	else:
		hit = _pointer_capture.get(pointer_id, {})
		_pointer_capture.erase(pointer_id)
	if hit.is_empty():
		return false
	_send_pointer(hit, true, pressed)
	return true


func _poke_panel(point: Vector3) -> Dictionary:
	## Fingertip-in-panel test for near interaction; `depth` is metres in front of
	## the surface, negative once the fingertip has pushed through it.
	var best: Dictionary = {}
	var nearest := POKE_RANGE_M
	for item in _panels:
		var panel: Node3D = item.panel
		if not is_instance_valid(panel) or not panel.is_visible_in_tree():
			continue
		var local := panel.global_transform.affine_inverse() * point
		var size: Vector2 = item.size
		if absf(local.x) > size.x * 0.5 or absf(local.y) > size.y * 0.5:
			continue
		if local.z < -POKE_THROUGH_M or local.z > nearest:
			continue
		best = {"target": panel, "viewport": item.viewport, "pixel": _pixel(item, local), "distance": absf(local.z), "depth": local.z}
		nearest = local.z
	return best

static func hand_tracker(index: int) -> XRHandTracker:
	## Null unless this hand is really tracked by hands, not by a held controller.
	var hand := XRServer.get_tracker(HAND_NAMES[index]) as XRHandTracker
	if hand == null or not hand.has_tracking_data:
		return null
	if hand.hand_tracking_source in [XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER, XRHandTracker.HAND_TRACKING_SOURCE_NOT_TRACKED]:
		return null
	return hand


static func tracked_joint(hand: XRHandTracker, joint: int, need_orientation := false) -> Variant:
	## Tracker-space transform, or null while that joint is only inferred.
	var required := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
	if need_orientation:
		required |= XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_TRACKED
	if (hand.get_hand_joint_flags(joint) & required) != required:
		return null
	var pose := XRPose.new()
	pose.transform = hand.get_hand_joint_transform(joint)
	return pose.get_adjusted_transform()


func set_menu_hand(index: int) -> void:
	## The hand carrying the menu points at nothing; its ray would fight the panel.
	_menu_hand = index


func _is_hand_grabbing(hand: XRHandTracker, palm_pos: Vector3, currently_grabbing: bool) -> bool:
	if hand == null:
		return false
	# Different grab/release distances prevent flickering at a single threshold.
	var thresh := 0.082 if currently_grabbing else 0.068
	var curled_count := 0
	var check_joints: Array[int] = [
		XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP,
		XRHandTracker.HAND_JOINT_RING_FINGER_TIP,
		XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP,
		XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP
	]
	var origin_xform := _origin.global_transform if _origin != null else Transform3D.IDENTITY
	for joint_id: int in check_joints:
		var joint_t: Variant = tracked_joint(hand, joint_id)
		if joint_t != null:
			var joint_pos := (origin_xform * (joint_t as Transform3D)).origin
			if joint_pos.distance_to(palm_pos) < thresh:
				curled_count += 1
	return curled_count >= 2


func _update_hands(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	for index in range(2):
		var pointer_id := String(HAND_NAMES[index])
		var hand := hand_tracker(index)
		var palm: Variant = tracked_joint(hand, XRHandTracker.HAND_JOINT_PALM) if hand != null else null
		var thumb: Variant = tracked_joint(hand, XRHandTracker.HAND_JOINT_THUMB_TIP) if hand != null else null
		var finger: Variant = tracked_joint(hand, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP) if hand != null else null
		if palm == null or thumb == null or finger == null or index == _menu_hand or camera == null:
			_rays[index].visible = false
			if _pinched[index]:
				_click_from_pose(Transform3D.IDENTITY, false, pointer_id)
			if _ragdoll: _ragdoll.release(pointer_id)
			_pinched[index] = false
			_grabbing[index] = false
			continue
		var palm_world := _origin.global_transform * (palm as Transform3D)
		var palm_pos := palm_world.origin
		var tip := (_origin.global_transform * (finger as Transform3D)).origin
		var thumb_tip := (_origin.global_transform * (thumb as Transform3D)).origin
		var gap := tip.distance_to(thumb_tip)
		var pinched := gap < (0.035 if _pinched[index] else 0.022)
		var grabbing := _is_hand_grabbing(hand, palm_pos, _grabbing[index])
		if aed and aed.touch(pointer_id, tip, (tip + thumb_tip) * 0.5, pinched):
			_rays[index].visible = false
			if _pinched[index]:
				_click_from_pose(Transform3D.IDENTITY, false, pointer_id)
			_pinched[index] = false
			continue

		# Whole-hand grab gesture on the patient holds limbs or lifts the torso using palm position.
		# Holding outranks both the near poke and far ray.
		if _update_grab(pointer_id, palm_pos, grabbing, _grabbing[index], delta):
			_rays[index].visible = false
			if _poking[index]:
				_click_hit({}, false, "poke:" + pointer_id)
				_poking[index] = false
			if _pinched[index]:
				_click_from_pose(Transform3D.IDENTITY, false, pointer_id)
				_pinched[index] = false
			_grabbing[index] = grabbing
			continue
		_grabbing[index] = grabbing

		if _update_poke(index, tip, pointer_id):
			_rays[index].visible = false
			if _pinched[index]:
				_click_from_pose(Transform3D.IDENTITY, false, pointer_id)
			_pinched[index] = false
			continue
		var world := palm_world
		# A head-to-palm ray is stable across palm orientation changes while selecting.
		var direction := (world.origin - camera.global_position).normalized()
		if direction.length_squared() > 0.5:
			world.basis = Basis.looking_at(direction, Vector3.UP)
		var hit := _pick_panel(world.origin, -world.basis.z.normalized())
		var length_m := float(hit.get("distance", 1.2))
		# The ray only shows while it points at something it can operate.
		_rays[index].visible = not hit.is_empty()
		_rays[index].global_transform = Transform3D(world.basis * Basis(Vector3.RIGHT, PI * 0.5), world.origin + -world.basis.z.normalized() * length_m * 0.5)
		_rays[index].scale = Vector3(1, length_m, 1)
		if not hit.is_empty():
			_send_pointer(hit, false, false)
		if pinched != _pinched[index]:
			_click_from_pose(world, pinched, pointer_id)
		_pinched[index] = pinched


func _update_poke(index: int, tip: Vector3, pointer_id: String) -> bool:
	## True while this hand is close enough to a panel that the far ray must yield.
	var poke_id := "poke:" + pointer_id
	var hit := _poke_panel(tip)
	if hit.is_empty():
		if _poking[index]:
			_click_hit({}, false, poke_id)
		_poking[index] = false
		return false
	_send_pointer(hit, false, false)
	var depth := float(hit.depth)
	if hit.get("viewport") == null and hit.target.has_method("pointer_press"):
		_near_menu_until_ms = Time.get_ticks_msec() + 200
	if not _poking[index] and depth <= POKE_PRESS_M:
		_poking[index] = true
		_click_hit(hit, true, poke_id)
	elif _poking[index] and depth >= POKE_RELEASE_M:
		_poking[index] = false
		_click_hit({}, false, poke_id)
	return true


func _update_grab(pointer_id: String, point: Vector3, grabbing: bool, was_grabbing: bool, delta: float) -> bool:
	## True while this hand is holding a limb, so the caller yields its pointer.
	if _ragdoll == null or not _ragdoll.is_active():
		return false
	if _ragdoll.holds(pointer_id):
		if grabbing:
			_ragdoll.move(pointer_id, point)
			return true
		_ragdoll.release(pointer_id)
		return false
	if grabbing and not was_grabbing:
		return _ragdoll.grab(pointer_id, point)
	return false
