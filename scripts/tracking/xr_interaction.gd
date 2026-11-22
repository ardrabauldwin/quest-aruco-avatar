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
## Each beep of the compression metronome, for the sensor log.
signal metronome_beat(bpm: int)
signal head_tilt_gesture_detected
## Both hands pinching: the distance between the two index fingertips (metres) and the
## fingertips' world heights, a tape-measure check of hand tracking (9 Nov 2026).
signal ruler_measured(distance_m: float, left_tip_y: float, right_tip_y: float)
const RULER_INTERVAL_S := 0.25
var _ruler_timer := 0.0
var head_tilt_gesture := NaretHeadTiltGesture.new()
## Response check: a palm at a shoulder (NaretShoulderCheck), shown as two soft patches.
signal shoulders_touched(shaken: bool)
const ShoulderCheck = preload("res://scripts/tracking/shoulder_check.gd")
var shoulder_check: RefCounted = ShoulderCheck.new()
var _shoulder_patches: Array[Node3D] = []
var _shoulder_materials: Array[StandardMaterial3D] = []
var _hands_seen_ms := 0
const PATCH_WAITING := Color(1.0, 0.62, 0.15)
const PATCH_TOUCHED := Color(0.25, 0.95, 0.40)

const HAND_NAMES := [&"/user/hand_tracker/left", &"/user/hand_tracker/right"]
## Near interaction, MRTK style: a fingertip this close to a panel pokes it.
const POKE_RANGE_M := 0.06
const POKE_THROUGH_M := 0.04
const POKE_PRESS_M := 0.005
const POKE_RELEASE_M := 0.015
var cpr_enabled := false
var _audio_busy := false
var aed_active := false
## Consecutive 0.15 s polls with a hand in the contact envelope; two are needed
## before clearance is revoked, so a tracking flicker at the edge cannot do it.
var _contact_hits := 0
const CONTACT_POLLS_TO_REVOKE := 2
## The AED is worked with the hands too: power button, electrodes.
var aed: NaretAED
## Bag-valve-mask for the breaths (scripts/mannequin/bvm_device.gd), set by main in XR.
var bvm: Node3D
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
## Which compression counter feeds compression_measured (17 Nov 2026): "zone" is this
## app's placed palm counter, "detector" Dennis's NaretCprDetector (wrists, forearms,
## palms, head; team branch merge/sensorlog). Both run every frame; only one counts.
## A build exported with the feature tag "detector_counter" uses the detector.
const COUNTER_MODES := ["zone", "detector"]
var counter_mode := "detector" if OS.has_feature("detector_counter") else "zone"
var detector := NaretCprDetector.new()
## The detector's view of the hands this frame (for the HUD in detector mode).
var chest_contact := false
var hands_seen := false
var _last_frame_ms := 0
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
	if _ragdoll: _ragdoll.enabled_parts = PATIENT_GRAB_PARTS
	_build_shoulder_patches()
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
		# 2026-11-03, checked against a QCPR manikin: count from where the hands rest in the green
		# square instead of from palm motion (false presses at rest, wrong-hand switches).
		_zone.set("placed_counting", true)
		var motion: RefCounted = _zone.get("motion_session")
		# The scenario owns breathing pauses; disable the standalone demo scheduler.
		motion.set("automatic_breathing_pause", false)
		motion.set("metronome_enabled", true)
		motion.connect("beat_requested", func(): metronome_beat.emit(int(motion.get("target_bpm"))))
		_zone.get_node("CollisionShape3D").position = Vector3.ZERO
		# Keep the user's original hand-zone dimensions and acceptance logic.
		_zone.get_node("Highlight").position = Vector3.ZERO
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
			hud.interaction = self
			_cpr_feedback_root.add_child(hud)
			hud.position = Vector3(0.0, -0.22, -0.8)
			hud.process_priority = 30
		_zone.get_node("Instruction").text = ""
		_zone.set_process_unhandled_key_input(false)
		_zone.connect("placement_changed", func(correct: bool): placement_changed.emit(correct))
		set_cpr_enabled(false)

## The CPR HUD's wording follows the trainee's language (en, de or pl).
func set_hud_language(language: String) -> void:
	OriginalCPRHud.language = language

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
	if value:
		off_target.reset()
	if _zone != null:
		if value:
			_zone.call("reset_placement")
		_last_count = 0
	detector.reset()
	_last_frame_ms = 0

var _metronome_off := false

## The beep's pace, or 0 when it is switched off (sensor log web page).
func metronome_bpm() -> int:
	if _zone == null or _metronome_off: return 0
	return int(_zone.get("motion_session").get("target_bpm"))

## 100-120/min from the sensor log web page; 0 switches the beep off.
func set_metronome_bpm(bpm: int) -> void:
	if _zone == null: return
	var motion: RefCounted = _zone.get("motion_session")
	_metronome_off = bpm <= 0
	if not _metronome_off:
		motion.set("target_bpm", clampf(float(bpm), 100.0, 120.0))
	motion.set("metronome_enabled", not _audio_busy and not _metronome_off)

func set_aed_active(value: bool) -> void:
	aed_active = value
	_contact_poll = 0.0

func set_audio_busy(value: bool) -> void:
	_audio_busy = value
	if _zone == null: return
	_zone.get("motion_session").set("metronome_enabled", not value and not _metronome_off)
	if value:
		_zone.get("_metronome").stop()

func rearm_cpr_cycle() -> void:
	# Call after an explicitly completed ventilation pair, if the scene uses cycles.
	if _zone != null:
		var motion: RefCounted = _zone.get("motion_session")
		motion.call("invalidate_tracking")
		motion.set("count", 0)
	detector.reset()

func _process(delta: float) -> void:
	if _origin == null:
		return
	_update_hands(delta)
	_update_controller_menu()
	_update_head_tilt(delta)
	_update_shoulders(delta)
	_update_face(delta)
	_update_off_target(delta)
	if bvm: bvm.tick(delta)
	if aed_active:
		_contact_poll -= delta
		if _contact_poll <= 0.0:
			_contact_poll = 0.15
			# The avatar's whole body shape counts during analysis and shock (18 Nov 2026).
			_contact_hits = _contact_hits + 1 if (_patient_contact_detected() or hands_touch_body()) else 0
			if _contact_hits >= CONTACT_POLLS_TO_REVOKE:
				action_requested.emit("patient_contact")
	else:
		_contact_hits = 0
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
	if cpr_enabled and count > _last_count and counter_mode == "zone":
		# Same pace source as the original needle dial: four detector intervals,
		# at least two intervals, invalidated by the detector's 1.5-second pause.
		var bpm := OriginalCPRHud.measured_bpm(session.get("_bpm_samples"))
		# The original detector already accepted these completed strokes in its
		# target zone. Do not reject them using a later frame's hand position.
		for stroke in range(count - _last_count):
			compression_measured.emit(float(session.get("last_stroke_travel_m")), bpm, true)
	_last_count = count
	if cpr_enabled:
		_update_detector()
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

## Each shoulder zone is drawn as a square frame the size of its tolerance box, on the
## calibrated mannequin, not on the drawn avatar: what the trainee sees is exactly what is
## counted, and a few centimetres of avatar offset stay invisible inside a 16 x 16 cm frame.
## Headset 12 Nov 2026: a translucent patch never showed. The real-world depth occlusion
## (OpenXRMetaEnvironmentDepth) hides transparent surfaces at the real manikin, and
## transparent materials cannot be moved before its depth pass. So the frame is opaque,
## unshaded and emissive like the AED pad guides, rendered before the depth pass
## (render_priority -60, as the patient overlay does) and lifted 4 cm above the shoulder.
func _build_shoulder_patches() -> void:
	for side in 2:
		var frame := Node3D.new()
		frame.name = "ShoulderZone%d" % side
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = PATCH_WAITING
		material.emission_enabled = true
		material.emission = PATCH_WAITING
		material.emission_energy_multiplier = 1.0
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.render_priority = -60
		var width := ShoulderCheck.HALF_X_M * 2.0
		var length := ShoulderCheck.HALF_Z_M * 2.0
		const BAR := 0.012
		for bar in [[Vector3(width, 0.004, BAR), Vector3(0.0, 0.0, length * 0.5)], [Vector3(width, 0.004, BAR), Vector3(0.0, 0.0, -length * 0.5)],
				[Vector3(BAR, 0.004, length), Vector3(width * 0.5, 0.0, 0.0)], [Vector3(BAR, 0.004, length), Vector3(-width * 0.5, 0.0, 0.0)]]:
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = bar[0]
			mesh.mesh = box
			mesh.material_override = material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.position = bar[1]
			frame.add_child(mesh)
		frame.position = ShoulderCheck.zone_centre(side) + Vector3(0.0, 0.04, 0.0)
		frame.visible = false
		_mannequin.add_child(frame)
		_shoulder_patches.append(frame)
		_shoulder_materials.append(material)

## Breathing check: the headset in the face box (NaretFaceCheck). No drawing, nothing
## about the hands here: the airway hint only asks whether the head-tilt animation played.
const FaceCheck = preload("res://scripts/tracking/face_check.gd")
signal face_checked
signal face_check_long
var face_check: RefCounted = FaceCheck.new()
var head_tilt_played := false

func set_face_check(enabled: bool) -> void:
	if enabled and not face_check.active:
		face_check.reset()
		head_tilt_played = false
	face_check.active = enabled

func _update_face(delta: float) -> void:
	if not face_check.active or _mannequin == null:
		return
	var camera := get_viewport().get_camera_3d()
	var mouth := _mannequin.get_node_or_null("MouthZone") as Node3D
	if camera == null or mouth == null:
		return
	var offset: Vector3 = _mannequin.global_transform.affine_inverse() * camera.global_position - mouth.position
	if face_check.observe(offset, delta):
		print("NARET_FACE checked at_face_s=%.1f head_tilt_played=%s" % [face_check.seconds_at_face(), head_tilt_played])
		face_checked.emit()
	if face_check.too_long():
		print("NARET_FACE too_long at_face_s=%.1f" % face_check.seconds_at_face())
		face_check_long.emit()

## Pressing beside the green box (12 Nov 2026): detected here, spoken once by main.
const OffTarget = preload("res://scripts/tracking/off_target_press.gd")
signal off_target_press
var off_target: RefCounted = OffTarget.new()

func _update_off_target(delta: float) -> void:
	if not cpr_enabled or _mannequin == null or _zone == null:
		return
	var to_local := _mannequin.global_transform.affine_inverse()
	var palms: Array = []
	for index in range(2):
		var hand := hand_tracker(index)
		var palm: Variant = tracked_joint(hand, XRHandTracker.HAND_JOINT_PALM) if hand else null
		palms.append(to_local * (_origin.global_transform * palm).origin if palm != null else null)
	if off_target.observe(palms, bool(_zone.get("correct_placement")), delta):
		print("NARET_HANDS off_target_press")
		off_target_press.emit()

## Headset 13 Nov 2026: the yellow frames hung in the air beside the manikin (they sit
## on the calibrated sternum, 4 cm above a shoulder height taken from an adult manikin),
## and a hand closing near the patient pulled his arm or shoulder along. The frames are
## off (the check itself stays), and only the head can still be taken hold of: that is
## the head tilt of the breathing check.
const SHOW_SHOULDER_FRAMES := false
const PATIENT_GRAB_PARTS := ["head"]

func set_shoulder_check(enabled: bool) -> void:
	## On from the scenario start until the response step is accepted (the trainee often
	## reaches for the shoulders while "the scene is safe" is still being transcribed).
	if enabled and not shoulder_check.active:
		shoulder_check.reset()
	shoulder_check.active = enabled
	for i in _shoulder_patches.size():
		_shoulder_patches[i].visible = enabled and SHOW_SHOULDER_FRAMES
		_shoulder_materials[i].albedo_color = PATCH_WAITING
		_shoulder_materials[i].emission = PATCH_WAITING

func hands_seen_recently() -> bool:
	## A tracked hand within the last 10 s: only then can the shoulder gate be applied.
	return _hands_seen_ms > 0 and Time.get_ticks_msec() - _hands_seen_ms < 10000

func _update_shoulders(delta: float) -> void:
	if not shoulder_check.active or _mannequin == null:
		return
	var to_local := _mannequin.global_transform.affine_inverse()
	var palms: Array = []
	for index in range(2):
		var hand := hand_tracker(index)
		var palm: Variant = tracked_joint(hand, XRHandTracker.HAND_JOINT_PALM) if hand else null
		if hand != null:
			_hands_seen_ms = Time.get_ticks_msec()
		palms.append(to_local * (_origin.global_transform * palm).origin if palm != null else null)
	if shoulder_check.observe(palms, delta):
		var side: int = shoulder_check.touched_side()
		if side >= 0 and side < _shoulder_materials.size():
			_shoulder_materials[side].albedo_color = PATCH_TOUCHED
			_shoulder_materials[side].emission = PATCH_TOUCHED
		print("NARET_SHOULDERS touched side=", side, " shaken=", shoulder_check.shaken())
		shoulders_touched.emit(shoulder_check.shaken())

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
		head_tilt_played = true
		print("NARET_HEAD_TILT gesture_detected technique_unverified")
		head_tilt_gesture_detected.emit()

## Any tracked hand (palm or a fingertip) touching the avatar's body shape (step-back gate).
func hands_touch_body() -> bool:
	if _mannequin == null or not _mannequin.has_method("body_contains"):
		return false
	for index in range(2):
		var hand := hand_tracker(index)
		if hand == null:
			continue
		for joint: int in [XRHandTracker.HAND_JOINT_PALM, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP, XRHandTracker.HAND_JOINT_THUMB_TIP]:
			var local: Variant = tracked_joint(hand, joint)
			if local == null:
				continue
			if _mannequin.body_contains((_origin.global_transform * (local as Transform3D)).origin):
				return true
	return false

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

## Body-frame contact envelope: a 10 cm band each side of the patient's centre line
## (the requested width, 9 Nov 2026: shoulders and arms lie outside it), from 4 cm below
## the back to 7 cm above the chest (the frame origin is 20.7 cm below the sternum),
## over the whole length. Kneeling beside the patient or working the AED next to the
## shoulder is not contact; the earlier 34 cm / 44 cm box took both as contact and
## revoked every clearance before the AED could finish its 5 s analysis.
## This can invalidate clearance; absence of tracked contact cannot prove clearance.
const CONTACT_HALF_WIDTH_M := 0.10
const CONTACT_BELOW_BACK_M := 0.04
const CONTACT_ABOVE_BACK_M := 0.28
const CONTACT_TOWARD_FEET_M := 0.95
const CONTACT_TOWARD_HEAD_M := 1.10

func _point_near_patient(world_point: Vector3) -> bool:
	var point := _mannequin.get_body_transform().affine_inverse() * world_point
	return absf(point.x) < CONTACT_HALF_WIDTH_M and point.y > -CONTACT_BELOW_BACK_M and point.y < CONTACT_ABOVE_BACK_M \
		and point.z > -CONTACT_TOWARD_FEET_M and point.z < CONTACT_TOWARD_HEAD_M

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

func _update_detector() -> void:
	## Dennis's detector (as wired on merge/sensorlog): palms from hand tracking,
	## wrists and forearms from body tracking, the head; heights along the chest normal.
	var now := Time.get_ticks_msec()
	var dt := 0.0 if _last_frame_ms == 0 else (now - _last_frame_ms) / 1000.0
	_last_frame_ms = now
	var palms := []
	for i in 2:
		var hand := hand_tracker(i)
		var flags := hand.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM) if hand else 0
		var tracked := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
		palms.append(_origin.global_transform * hand.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin if hand and (flags & tracked) == tracked else null)
	var wrists := []
	var forearms := []
	var body := XRServer.get_tracker("/user/body_tracker") as XRBodyTracker
	if body and body.has_tracking_data:
		var joint := func(j: int) -> Variant:
			return _origin.global_transform * body.get_joint_transform(j).origin if body.get_joint_flags(j) & XRBodyTracker.JOINT_FLAG_POSITION_VALID else null
		wrists = [joint.call(XRBodyTracker.JOINT_LEFT_WRIST), joint.call(XRBodyTracker.JOINT_RIGHT_WRIST)]
		forearms = [joint.call(XRBodyTracker.JOINT_LEFT_LOWER_ARM), joint.call(XRBodyTracker.JOINT_RIGHT_LOWER_ARM)]
	var head := (_origin.global_transform * XRServer.get_hmd_transform()).origin.y
	var m := NaretCprDetector.measure(_mannequin.get_sternum_transform(), palms, wrists, forearms, head)
	chest_contact = m.on_chest
	hands_seen = palms.any(func(p): return p != null) or wrists.any(func(p): return p != null)
	for stroke in detector.step(now / 1000.0, dt, m.channels, m.on_chest, m.depth):
		if counter_mode == "detector":
			compression_measured.emit(stroke.depth_m, stroke.rate_bpm, m.on_chest)

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


func _update_ruler(delta: float) -> void:
	## Tape-measure check: while both hands pinch, report the fingertip distance.
	if not (_pinched[0] and _pinched[1]):
		_ruler_timer = 0.0
		return
	_ruler_timer -= delta
	if _ruler_timer > 0.0:
		return
	_ruler_timer = RULER_INTERVAL_S
	var tips: Array[Vector3] = []
	for index in range(2):
		var hand := hand_tracker(index)
		var finger: Variant = tracked_joint(hand, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP) if hand != null else null
		if finger == null:
			return
		tips.append((_origin.global_transform * (finger as Transform3D)).origin)
	ruler_measured.emit(tips[0].distance_to(tips[1]), tips[0].y, tips[1].y)

func _update_hands(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	_update_ruler(delta)
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
		# The bag-valve-mask takes a whole-hand grab before the patient does.
		if bvm and bvm.touch(pointer_id, palm_world, grabbing, _grabbing[index]):
			_rays[index].visible = false
			if _pinched[index]:
				_click_from_pose(Transform3D.IDENTITY, false, pointer_id)
			_pinched[index] = false
			_grabbing[index] = grabbing
			continue
		if aed and aed.touch(pointer_id, tip, (tip + thumb_tip) * 0.5, pinched, palm_pos, grabbing):
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


var _poke_blocked := [false, false]

func _cancel_poke(poke_id: String) -> void:
	## Ends a poke without its click. Wrist keys (pointer_cancel) only light down; a 2D
	## panel still gets its mouse release, as before.
	var hit: Dictionary = _pointer_capture.get(poke_id, {})
	_pointer_capture.erase(poke_id)
	if hit.is_empty(): return
	var target: Variant = hit.get("target")
	if hit.get("viewport") == null and is_instance_valid(target) and target.has_method("pointer_cancel"):
		target.pointer_cancel()
	else:
		_send_pointer(hit, true, false)

func _update_poke(index: int, tip: Vector3, pointer_id: String) -> bool:
	## True while this hand is close enough to a panel that the far ray must yield.
	var poke_id := "poke:" + pointer_id
	var hit := _poke_panel(tip)
	if hit.is_empty():
		# Slid off the key's edge: no click (19 Nov 2026, headset log: one sweeping reach
		# fired Start training, Save calibration and Reposition within 0.1 s).
		if _poking[index]:
			_cancel_poke(poke_id)
		_poking[index] = false
		_poke_blocked[index] = false
		return false
	_send_pointer(hit, false, false)
	var depth := float(hit.depth)
	if hit.get("viewport") == null and hit.target.has_method("pointer_press"):
		_near_menu_until_ms = Time.get_ticks_msec() + 200
	if _poking[index] and _pointer_capture.has(poke_id) and _pointer_capture[poke_id].get("target") != hit.target:
		# Slid onto the next key while pressed in: neither key fires, and a new press
		# needs the fingertip to come back out first.
		_cancel_poke(poke_id)
		_poking[index] = false
		_poke_blocked[index] = true
	if _poke_blocked[index]:
		if depth >= POKE_RELEASE_M: _poke_blocked[index] = false
		return true
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
		if not _ragdoll.grab(pointer_id, point): return false
		# Only the head can be held: this is the trainee tilting it.
		if not head_tilt_played: print("NARET_HEAD_TILT head_held")
		head_tilt_played = true
		return true
	return false
