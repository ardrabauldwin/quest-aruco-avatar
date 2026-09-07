extends Area3D
## Green visual placement guide by default. Experimental heel grading is opt-in.
## Auto-hides when correct hand placement is detected and held stable.

signal placement_changed(correct: bool)
signal cpr_started
signal placement_restarted

## Green marks the intended target; it does not indicate detected correct placement.
@export var guide_only := true
@export var xr_origin: XROrigin3D
@export var start_controller: XRController3D
@export var start_button: StringName = &"by_button"
@export var left_tracker: StringName = &"/user/hand_tracker/left"
@export var right_tracker: StringName = &"/user/hand_tracker/right"

@export_group("Heel estimate")
## Fraction from wrist centre toward palm centre; no heel joint exists in OpenXR.
@export_range(0.0, 1.0, 0.05) var heel_wrist_to_palm_fraction := 0.3
## Approximate joint-centre to skin offset toward the palm-facing side, in metres.
@export_range(0.0, 0.025, 0.001) var heel_surface_offset_m := 0.008
@export_group("Stack tolerances")
@export var stack_min_height_m := 0.008
@export var stack_max_height_m := 0.080
@export var stack_lateral_tolerance_m := 0.035
@export_range(0.0, 80.0, 1.0) var max_palm_tilt_degrees := 50.0

@export_group("Compression detection")
## Time in seconds that hands must stay in correct position before auto-starting CPR.
@export_range(0.1, 2.0, 0.1) var placement_confirm_time_s := 0.5

@export_group("CPR Feedback")
## Target compression rate in beats per minute.
@export_range(80.0, 140.0, 5.0) var target_bpm := 110.0
## Target compression depth in metres (5-6 cm for adults).
@export_range(0.03, 0.10, 0.01) var target_depth_m := 0.055
## Tolerance for depth feedback (±cm).
@export_range(0.005, 0.02, 0.005) var depth_tolerance_m := 0.010

var left_hand_inside := false
var right_hand_inside := false
var correct_placement: bool:
	get:
		return _placement_correct
## The hand whose estimated heel is in the chest contact slab, or empty when incorrect.
var lower_hand: StringName = &""
var _placement_correct := false
var is_cpr_started := false
var _paused := false
@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var _highlight: MeshInstance3D = $Highlight
@onready var _instruction: Label3D = $Instruction
@onready var _hand_illustration: Sprite3D = $HandIllustration
var _material: StandardMaterial3D

var _correct_placement_start_time: float = -1.0  # When correct placement began

# CPR feedback state
var _cpr_cycle_phase := "compressions"  # "compressions" or "breathing"
var _compression_count := 0  # 0-30
var _breathing_time_remaining_s: float = 0.0
var _last_hand_y: float = 0.0  # Previous frame's hand Y for motion detection
var _in_downstroke := false  # Hand currently moving downward
var _stroke_start_y: float = 0.0  # Hand Y when downstroke began
var _last_compression_time: float = -1.0  # Time of last detected compression
var _last_beep_time: float = -1.0  # Time of last metronome beep
var _beep_interval_s: float = 0.6  # 60 / 110 bpm = 0.545s, rounded to 0.6s


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not guide_only:
		_highlight.material_override = _material
	if start_controller != null:
		start_controller.button_pressed.connect(_on_start_button)
	_update_feedback()


func _process(_delta: float) -> void:
	var was_correct := correct_placement
	var can_check := not guide_only and not _paused and is_visible_in_tree() and not is_cpr_started
	var left := _read_hand(left_tracker) if can_check else {}
	var right := _read_hand(right_tracker) if can_check else {}
	# These per-hand flags now mean heel contact with the chest, not palm containment.
	left_hand_inside = _heel_on_target(left)
	right_hand_inside = _heel_on_target(right)
	lower_hand = &""
	if left_hand_inside and _is_stacked(left, right):
		lower_hand = &"left"
	elif right_hand_inside and _is_stacked(right, left):
		lower_hand = &"right"
	_placement_correct = lower_hand != &""
	_update_feedback()
	if correct_placement != was_correct:
		placement_changed.emit(correct_placement)

	# Auto-start CPR when correct placement is held stable.
	if can_check and not guide_only and correct_placement and not is_cpr_started:
		var now: float = Time.get_ticks_msec() / 1000.0
		if _correct_placement_start_time < 0:
			_correct_placement_start_time = now
		elif now - _correct_placement_start_time >= placement_confirm_time_s:
			# Correct placement held for the threshold time; auto-start CPR (hides guide).
			start_cpr()
	elif not correct_placement:
		_correct_placement_start_time = -1.0

	# CPR feedback: track compression depth and cycle.
	if is_cpr_started and can_check:
		var hand_to_track: Dictionary = left if lower_hand == &"left" else right
		if not hand_to_track.is_empty():
			_update_cpr_feedback(_delta, hand_to_track)


func _read_hand(tracker_name: StringName) -> Dictionary:
	if xr_origin == null:
		return {}
	var hand := XRServer.get_tracker(tracker_name) as XRHandTracker
	if hand == null or not hand.has_tracking_data:
		return {}
	if hand.hand_tracking_source in [XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER, XRHandTracker.HAND_TRACKING_SOURCE_NOT_TRACKED]:
		return {}
	var position_flags := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
	var palm_flags := position_flags | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_TRACKED
	if (hand.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM) & palm_flags) != palm_flags:
		return {}
	if (hand.get_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST) & position_flags) != position_flags:
		return {}
	var palm := hand.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
	var wrist := hand.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST)
	if not palm.is_finite() or not wrist.origin.is_finite() or absf(palm.basis.determinant()) < 0.001:
		return {}
	var wrist_to_palm := wrist.origin.distance_to(palm.origin)
	if wrist_to_palm < 0.010 or wrist_to_palm > 0.150:
		return {}
	# Godot's OpenXR Humanoid conversion makes -Z face out the back of the hand:
	# +Z therefore points toward the palm skin/contact surface (both left and right).
	var heel := wrist.origin.lerp(palm.origin, heel_wrist_to_palm_fraction)
	heel += palm.basis.z.normalized() * heel_surface_offset_m
	var pose := XRPose.new()
	pose.transform = Transform3D(palm.basis.orthonormalized(), heel)
	# Apply the same reference frame and world scale as XRNode3D, then the scene origin.
	var world := xr_origin.global_transform * pose.get_adjusted_transform()
	return {"heel": world.origin, "palm_normal": world.basis.z.normalized()}


func _heel_on_target(hand: Dictionary) -> bool:
	return not hand.is_empty() and contains_world_point(hand.heel) and _faces_chest(hand)


func _faces_chest(hand: Dictionary) -> bool:
	var chest_normal := _shape.global_basis.y.normalized()
	return hand.palm_normal.dot(-chest_normal) >= cos(deg_to_rad(max_palm_tilt_degrees))


func _is_stacked(lower: Dictionary, upper: Dictionary) -> bool:
	if upper.is_empty() or not _faces_chest(upper):
		return false
	var chest_normal := _shape.global_basis.y.normalized()
	var separation: Vector3 = upper.heel - lower.heel
	var height := separation.dot(chest_normal)
	# Distances are specified in physical metres, independent of the mannequin's 0.77 scale.
	var units_per_metre := XRServer.world_scale * xr_origin.global_basis.get_scale().length() / sqrt(3.0)
	if height < stack_min_height_m * units_per_metre or height > stack_max_height_m * units_per_metre:
		return false
	var lateral := (separation - chest_normal * height).length()
	return lateral <= stack_lateral_tolerance_m * units_per_metre


func contains_world_point(world_position: Vector3) -> bool:
	var box := _shape.shape as BoxShape3D
	if box == null or _shape.disabled or not world_position.is_finite():
		return false
	var local := _shape.to_local(world_position)
	var half := box.size * 0.5
	return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z


## Call from the explicit Start action or a future compression detector.
func start_cpr() -> void:
	if is_cpr_started or _paused or not is_visible_in_tree():
		return
	is_cpr_started = true
	_clear_placement()
	_update_feedback()
	# Reset CPR feedback state.
	_cpr_cycle_phase = "compressions"
	_compression_count = 0
	_breathing_time_remaining_s = 0.0
	_last_hand_y = 0.0
	_in_downstroke = false
	_last_compression_time = -1.0
	_last_beep_time = -1.0
	cpr_started.emit()


func reset_placement() -> void:
	is_cpr_started = false
	_clear_placement()
	_update_feedback()
	# Reset CPR feedback state.
	_cpr_cycle_phase = "compressions"
	_compression_count = 0
	_breathing_time_remaining_s = 0.0
	_last_hand_y = 0.0
	_in_downstroke = false
	_last_compression_time = -1.0
	_last_beep_time = -1.0
	placement_restarted.emit()


func _clear_placement() -> void:
	var was_correct := correct_placement
	left_hand_inside = false
	right_hand_inside = false
	_placement_correct = false
	lower_hand = &""
	_correct_placement_start_time = -1.0
	if was_correct:
		placement_changed.emit(false)


func _update_feedback() -> void:
	if _highlight == null or _material == null:
		return
	_highlight.visible = not is_cpr_started and not _paused
	_instruction.visible = _highlight.visible
	_hand_illustration.visible = _highlight.visible
	if not guide_only:
		_material.albedo_color = Color(0.1, 0.9, 0.25, 0.75) if correct_placement else Color(1.0, 0.35, 0.05, 0.75)


func _update_cpr_feedback(delta: float, hand: Dictionary) -> void:
	## Track compression depth, count strokes, and manage 30:2 cycle.
	var chest_normal := _shape.global_basis.y.normalized()
	var hand_y: float = hand.heel.dot(chest_normal)
	var now: float = Time.get_ticks_msec() / 1000.0

	# Manage breathing phase timer.
	if _cpr_cycle_phase == "breathing":
		_breathing_time_remaining_s -= delta
		if _breathing_time_remaining_s <= 0:
			_cpr_cycle_phase = "compressions"
			_compression_count = 0
		return  # Don't track compressions during breathing phase.

	# Track downstroke and detect compression.
	if _last_hand_y == 0:
		_last_hand_y = hand_y
		return

	var hand_moved_down := hand_y < _last_hand_y - 0.005  # Moved down >5mm
	var hand_moved_up := hand_y > _last_hand_y + 0.005    # Moved up >5mm

	if hand_moved_down and not _in_downstroke:
		# Start of new downstroke.
		_in_downstroke = true
		_stroke_start_y = _last_hand_y
	elif hand_moved_up and _in_downstroke:
		# End of downstroke (upstroke begun). Calculate compression depth.
		_in_downstroke = false
		var depth: float = _stroke_start_y - hand_y
		if depth > 0.015:  # Minimum 1.5cm to count as compression.
			_compression_count += 1
			_last_compression_time = now
			# Audio beep for each compression (if timed correctly for BPM).
			_try_metronome_beep(now)

		# Check if 30 compressions reached.
		if _compression_count >= 30:
			_cpr_cycle_phase = "breathing"
			_breathing_time_remaining_s = 5.0  # 5 seconds for 2 breaths.

	_last_hand_y = hand_y


func _try_metronome_beep(now: float) -> void:
	## Emit audio beep if it's time (based on target BPM).
	_beep_interval_s = 60.0 / target_bpm
	if now - _last_beep_time >= _beep_interval_s:
		# Play beep sound here (placeholder).
		print("beep")  # TODO: play actual audio
		_last_beep_time = now


func _on_start_button(button: StringName) -> void:
	if button == start_button:
		if is_cpr_started:
			reset_placement()
		else:
			start_cpr()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		_on_start_button(start_button)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_paused = true
		_clear_placement()
		_update_feedback()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_paused = false
		_clear_placement()
		_update_feedback()
