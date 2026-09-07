extends Area3D
## Green visual placement guide by default. Experimental heel grading is opt-in.
## Auto-detects compression strokes from hand motion when guide_only = false.

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
@export var stack_min_height_m := 0.012
@export var stack_max_height_m := 0.060
@export var stack_lateral_tolerance_m := 0.025
@export_range(0.0, 80.0, 1.0) var max_palm_tilt_degrees := 40.0

@export_group("Compression detection")
## Minimum depth of motion in one stroke, in metres.
@export_range(0.01, 0.15, 0.01) var compression_min_depth_m := 0.04
## Expected strokes per minute; detection looks for rates in this ±50% band.
@export_range(60.0, 200.0, 5.0) var compression_target_bpm := 100.0
## Consecutive detected strokes before confirming compression has started.
@export_range(1, 10, 1) var compression_confirm_strokes := 3

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

var _hand_positions: Array = []  # History of [time, lower_hand_y] during correct placement
var _detected_strokes := 0  # Count of consecutive valid strokes
var _last_peak_time: float = -1.0  # Time of the most recent detected upstroke peak
var _was_placement_correct := false  # Track if placement was valid last frame, for detection window


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


func _process(delta: float) -> void:
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

	# Auto-detect compressions from hand motion when in detector mode (not guide_only).
	# Once placement is established, keep detection running through brief losses (pumping motion).
	# Need to read raw hand data even when not in contact, to track the motion.
	if can_check and not guide_only:
		if correct_placement:
			_was_placement_correct = true
		elif _was_placement_correct:
			# Keep tracking for up to 0.5s after placement is lost, to detect strokes.
			if not _hand_positions.is_empty():
				var time_since_last: float = Time.get_ticks_msec() / 1000.0 - _hand_positions[-1][0]
				if time_since_last > 0.5:
					_was_placement_correct = false

		if _was_placement_correct:
			# During correct placement, remember which hand was lower.
			# After it leaves the zone (during pumping), keep reading that hand's motion.
			if correct_placement:
				if lower_hand == &"left":
					_detect_compression(delta, left)
				elif lower_hand == &"right":
					_detect_compression(delta, right)
			else:
				# Placement momentarily lost; try to track the hand that was lower.
				# Fall back to trying both if we're not sure.
				if not left.is_empty():
					_detect_compression(delta, left)
				elif not right.is_empty():
					_detect_compression(delta, right)


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
	if wrist_to_palm < 0.015 or wrist_to_palm > 0.12:
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
	cpr_started.emit()


func reset_placement() -> void:
	is_cpr_started = false
	_clear_placement()
	_update_feedback()
	placement_restarted.emit()


func _clear_placement() -> void:
	var was_correct := correct_placement
	left_hand_inside = false
	right_hand_inside = false
	_placement_correct = false
	lower_hand = &""
	_hand_positions.clear()
	_detected_strokes = 0
	_last_peak_time = -1.0
	_was_placement_correct = false
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


func _detect_compression(_delta: float, lower_hand_data: Dictionary) -> void:
	## Track the Y position (chest normal direction) of the lower hand and look for
	## repeated down-up strokes (peaks). Each stroke must be at least compression_min_depth_m deep
	## and the time between peaks must fall within a ±50% band around compression_target_bpm.
	if lower_hand_data.is_empty():
		return
	var chest_normal := _shape.global_basis.y.normalized()
	var hand_y: float = lower_hand_data.heel.dot(chest_normal)
	var now: float = Time.get_ticks_msec() / 1000.0  # seconds since engine start

	# Maintain a sliding window of recent positions for stroke detection.
	_hand_positions.append([now, hand_y])
	# Keep only the last 3 seconds of data to limit memory and detect multi-stroke rhythm.
	while _hand_positions.size() > 0 and now - _hand_positions[0][0] > 3.0:
		_hand_positions.pop_front()

	if _hand_positions.size() < 4:
		# Need minimum samples to detect a stroke reliably.
		return

	# Find the range of motion in the last ~1 second (recent motion).
	var recent_window_start: float = now - 1.0
	var recent_lowest: float = hand_y
	var recent_highest: float = hand_y
	for entry in _hand_positions:
		if entry[0] >= recent_window_start:
			recent_lowest = minf(recent_lowest, entry[1])
			recent_highest = maxf(recent_highest, entry[1])

	var recent_depth: float = recent_highest - recent_lowest
	if recent_depth < compression_min_depth_m:
		# Not deep enough to be a compression stroke.
		_detected_strokes = 0
		_last_peak_time = -1.0
		return

	# Detect an upstroke peak: hand rising back up after a compression.
	# A peak is when hand_y is near the recent_highest and was lower moments ago.
	var peak_threshold: float = recent_highest - recent_depth * 0.15  # Within 15% of highest
	var is_at_peak: bool = hand_y >= peak_threshold

	if not is_at_peak:
		return

	# Check if we've detected a new peak (not just hovering at the top).
	if _last_peak_time > 0 and now - _last_peak_time < 0.1:
		# Still in the same peak; wait for the hand to drop and rise again.
		return

	# Valid peak detected. Check the rhythm if we have a previous peak.
	var min_interval_s: float = 60.0 / (compression_target_bpm * 1.5)  # ±50% band
	var max_interval_s: float = 60.0 / (compression_target_bpm * 0.5)
	var time_since_last: float = now - _last_peak_time

	if _last_peak_time < 0:
		# First peak; initialize.
		_detected_strokes = 1
		_last_peak_time = now
	elif time_since_last >= min_interval_s and time_since_last <= max_interval_s:
		# Peak timing is in the valid BPM range.
		_detected_strokes += 1
		_last_peak_time = now
		if _detected_strokes >= compression_confirm_strokes:
			print("CPR compression detected: %d peaks in valid rhythm (~%.0f bpm)" % [
				compression_confirm_strokes, 60.0 / time_since_last
			])
			start_cpr()
	else:
		# Rhythm broken; reset.
		_detected_strokes = 1
		_last_peak_time = now


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
		_hand_positions.clear()
		_detected_strokes = 0
		_last_peak_time = -1.0
		_clear_placement()
		_update_feedback()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_paused = false
		_hand_positions.clear()
		_detected_strokes = 0
		_last_peak_time = -1.0
		_clear_placement()
		_update_feedback()
