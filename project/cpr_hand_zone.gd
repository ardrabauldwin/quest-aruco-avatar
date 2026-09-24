extends Area3D
## Green visual placement guide by default. Experimental heel grading is opt-in.
## Uses a complete tracked hand stroke to start a sensor-free practice cycle.

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
## Used when the wrist joint is not tracked (the Quest loses it first, under the other hand or at
## the edge of view): the heel is this far behind the palm centre along the finger axis.
@export_range(0.0, 0.08, 0.001) var palm_to_heel_fallback_m := 0.042
## Approximate joint-centre to skin offset toward the palm-facing side, in metres.
@export_range(0.0, 0.025, 0.001) var heel_surface_offset_m := 0.008
@export_group("Stack tolerances")
@export var stack_min_height_m := 0.008
@export var stack_max_height_m := 0.080
## Reach of the single-hand target above the contact slab. The slab sits where the user aligns
## the avatar visually, which has been 2-7 cm under the resting palm (2026-09-22/23); 12 cm
## keeps the one visible hand on target across that whole range.
@export var single_hand_reach_m := 0.120
@export var stack_lateral_tolerance_m := 0.035
@export_range(0.0, 80.0, 1.0) var max_palm_tilt_degrees := 50.0

@export_group("Hand-motion practice")
@export var enable_motion_practice := true
@export_range(100.0, 120.0, 5.0) var target_bpm := 110.0
## Configurable practice pause, not detection of breaths.
@export_range(2.0, 9.0, 0.5) var breathing_duration_s := 5.0

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
var _material: StandardMaterial3D

var motion_session = preload("res://cpr_motion_session.gd").new()
## True while a tracked palm is usable over the chest. The avatar rig reads it: hands hide
## markers, and a pose fused from the remaining ones must not be taken as a mannequin move.
var hand_over_chest := false
# Per-frame hand trace for offline replay of the counter (user://cpr_trace_<unix>.csv).
var _trace: FileAccess
var _trace_grace_s := 0.0
var _trace_unflushed := 0
var _motion_tracker: StringName = &""
var _last_chest_pose := Transform3D.IDENTITY
var _have_chest_pose := false
var hand_tracking_status := "Show your hands"
var _motion_reasons := {}
var _last_tracking_status := ""
var _metronome: AudioStreamPlayer
var _placement_diag_s := 0.0


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not guide_only:
		_highlight.material_override = _material
	if start_controller != null:
		start_controller.button_pressed.connect(_on_start_button)
	_metronome = preload("res://cpr_metronome.gd").new()
	add_child(_metronome)
	motion_session.beat_requested.connect(_metronome.play.bind(0.0))
	_update_feedback()


func _hand_diagnostic(hand: Dictionary) -> String:
	if hand.is_empty():
		return "unavailable"
	var local := _shape.to_local(hand.heel)
	return "heel_world=%s offset_cm=%s facing=%s contact=%s single=%s" % [
		str(hand.heel), str(local * _shape.global_basis.get_scale() / _units_per_metre() * 100.0),
		_faces_chest(hand), contains_world_point(hand.heel), _single_hand_on_target(hand)]


func _process(delta: float) -> void:
	var was_correct := correct_placement
	var available := not _paused and is_visible_in_tree()
	var read_hands := available and not guide_only
	var left := _read_hand(left_tracker) if read_hands else {}
	var right := _read_hand(right_tracker) if read_hands else {}
	left_hand_inside = not guide_only and _heel_on_target(left)
	right_hand_inside = not guide_only and _heel_on_target(right)
	lower_hand = &""
	if left_hand_inside and _is_stacked(left, right):
		lower_hand = &"left"
	elif right_hand_inside and _is_stacked(right, left):
		lower_hand = &"right"
	elif not guide_only and left.is_empty() != right.is_empty():
		# Only one hand is tracked. During real CPR the lower hand is hidden under the upper one,
		# so the headset normally sees the upper hand alone (2026-09-15 log: the left hand was
		# "not_tracked" in every status line). Accept that hand anywhere between the contact slab
		# and the stack height above the target footprint. With both hands visible the strict
		# heel-plus-stack check above still applies.
		var visible_hand := left if not left.is_empty() else right
		if _single_hand_on_target(visible_hand):
			lower_hand = &"left" if not left.is_empty() else &"right"
	_placement_correct = lower_hand != &""
	if correct_placement != was_correct:
		placement_changed.emit(correct_placement)
	if enable_motion_practice:
		var motion_left := _read_motion_hand(left_tracker) if available else {}
		var motion_right := _read_motion_hand(right_tracker) if available else {}
		_update_hand_motion(delta, available, motion_left, motion_right)
	_update_feedback()
	_placement_diag_s += delta
	if available and _placement_diag_s >= 1.0:
		_placement_diag_s = 0.0
		print("CPR placement: chest_world=%s left=%s right=%s correct=%s guide_visible=%s" % [
			str(_shape.global_position), _hand_diagnostic(left), _hand_diagnostic(right),
			correct_placement, _highlight.visible])


func _update_hand_motion(delta: float, available: bool, left: Dictionary, right: Dictionary) -> void:
	motion_session.target_bpm = target_bpm
	motion_session.breathing_duration_s = breathing_duration_s
	var sample := {}
	var chosen: StringName = &""
	var left_usable := available and _motion_hand_usable(left)
	var right_usable := available and _motion_hand_usable(right)
	_motion_time_s += delta
	_record_hand_height(left_tracker, left)
	_record_hand_height(right_tracker, right)
	# Keep a usable hand to avoid switching references when the other reappears.
	# On acquisition prefer the upper palm along the chest normal; a single visible
	# palm is also sufficient for motion, although its stack order is then unknown.
	if _motion_tracker == left_tracker and left_usable:
		sample = left
		chosen = left_tracker
	elif _motion_tracker == right_tracker and right_usable:
		sample = right
		chosen = right_tracker
	elif left_usable and right_usable:
		var separation: float = (left.point - right.point).dot(_shape.global_basis.y.normalized())
		chosen = left_tracker if separation > 0.0 else right_tracker
		sample = left if chosen == left_tracker else right
	elif left_usable:
		sample = left
		chosen = left_tracker
	elif right_usable:
		sample = right
		chosen = right_tracker
	# Hand over to the palm that is actually moving (see the file header for the device data).
	if chosen != &"" and left_usable and right_usable:
		var other: StringName = right_tracker if chosen == left_tracker else left_tracker
		var mine := _hand_movement(chosen)
		var theirs := _hand_movement(other)
		if motion_session.total_count == 0:
			# Before the first press there is nothing to lose by changing our mind, and waiting for
			# the frozen-hand evidence costs the opening seconds: on 2026-09-24 the app sat on the
			# hidden lower palm for 7 s and counted one press, while the upper palm was already
			# moving 5-8 cm. So until the first press simply follow whichever palm moves more.
			if theirs > mine + OPENING_MARGIN_M:
				_handover_s += delta
				if _handover_s >= OPENING_DWELL_S:
					_handover_s = 0.0
					chosen = other
					sample = left if other == left_tracker else right
			else:
				_handover_s = 0.0
		elif mine < FROZEN_HAND_M and theirs > mine + FROZEN_HAND_MARGIN_M:
			_handover_s += delta
			if _handover_s >= HANDOVER_DWELL_S:
				_handover_s = 0.0
				print("CPR hands: following the %s palm, it moves %.1f cm and the other %.1f cm"
					% ["left" if other == left_tracker else "right", theirs * 100.0, mine * 100.0])
				chosen = other
				sample = left if other == left_tracker else right
		else:
			_handover_s = 0.0
	else:
		_handover_s = 0.0
	if chosen != _motion_tracker:
		# Never interpret the gap between palms as hand travel. This clears only the
		# unfinished movement/baseline; completed counts and cycle progress survive.
		motion_session.invalidate_tracking()
		_motion_tracker = chosen
	var chest := _shape.global_transform
	var units := _units_per_metre()
	var jumped := _have_chest_pose and (
		chest.origin.distance_to(_last_chest_pose.origin) > 0.03 * units
		or chest.basis.orthonormalized().get_rotation_quaternion().angle_to(
			_last_chest_pose.basis.orthonormalized().get_rotation_quaternion()) > deg_to_rad(5.0))
	_last_chest_pose = chest
	_have_chest_pose = available
	var valid := available and not jumped and not sample.is_empty()
	hand_over_chest = not sample.is_empty()
	var height := 0.0
	if valid:
		height = (sample.point - chest.origin).dot(chest.basis.y.normalized()) / units
	if not sample.is_empty():
		hand_tracking_status = "Tracking %s palm" % ("left" if chosen == left_tracker else "right")
	elif not left.is_empty() or not right.is_empty():
		hand_tracking_status = "Move your hand over the target"
	elif _motion_reasons.values().has("controller"):
		hand_tracking_status = "Put controllers down to use hands"
	elif _motion_reasons.values().has("no_tracker"):
		hand_tracking_status = "Enable hand tracking on Quest"
	elif _session_paused():
		hand_tracking_status = "Headset paused input: press the Meta button"
	elif _hand_feed_dead_s > HAND_FEED_DEAD_S:
		# The headset routes hand data to one client at a time. When the system shell takes it
		# (a menu, a "tracking lost" dialog) and then closes without handing it back, this app's
		# hand feed stays switched off: the trackers exist, the headset tracks the hands, and
		# every joint reads "no data" (device log 2026-09-24 10:27, 45 s). Only a foreground
		# change gives it back, so say exactly that.
		hand_tracking_status = "Headset stopped sending hands to this app.
Press the Meta button, then close the menu."
	else:
		hand_tracking_status = "Keep your hands in view"
	# How long the headset has been refusing to deliver hand data while this app is focused and
	# its trackers exist. Distinguishes "hands out of view" (normal, brief) from the stuck feed.
	# An empty reasons dict means the hands were never read this frame (avatar not placed yet),
	# which is not a dead feed: Array.all() is true for an empty array, so test that explicitly.
	var feed_dead := (
		available
		and not _motion_reasons.is_empty()
		and not _session_paused()
		and _motion_reasons.values().all(func(reason): return reason == "not_tracked")
	)
	_hand_feed_dead_s = (_hand_feed_dead_s + delta) if feed_dead else 0.0
	_raw_print_s += delta
	if _raw_print_s >= 2.0 and sample.is_empty() and not _motion_reasons.is_empty():
		_raw_print_s = 0.0
		print("CPR hand feed: %s | dead %.1f s | session_focused=%s" % [
			str(_motion_reasons), _hand_feed_dead_s, not _session_paused()])
	# Once a second while a palm is tracked but not accepted: where it is relative to the slab.
	_reject_print_s += delta
	if sample.is_empty() and _rejected_palm != "" and _reject_print_s >= 1.0:
		_reject_print_s = 0.0
		print("CPR palm rejected: ", _rejected_palm)
	_rejected_palm = ""
	if available and hand_tracking_status != _last_tracking_status:
		_last_tracking_status = hand_tracking_status
		print("CPR hands: ", hand_tracking_status, " | ", _motion_reasons)
	var count_before: int = motion_session.total_count
	motion_session.update(delta, valid, height, not available)
	_write_cpr_trace(delta, available, valid, sample.is_empty(), chosen, height)
	if motion_session.total_count != count_before:
		# One line per counted press: proves on the headset log that the counter fires and shows
		# what it measured. ~2 lines/s at most, only while pressing.
		print("CPR press #%d  travel=%.1f cm  %s  interval=%.2f s  hand=%s" % [
			motion_session.total_count, motion_session.last_stroke_travel_m * 100.0,
			motion_session.last_stroke_quality,
			motion_session.last_interval_s,
			"left" if _motion_tracker == left_tracker else "right"])
	if motion_session.active and not is_cpr_started:
		is_cpr_started = true
		cpr_started.emit()
	if not available:
		_metronome.stop()


## One CSV row per frame while a palm is usable over the chest, and for 1 s after it is lost,
## so dropouts are visible. Columns are the counter's inputs and its internal state, enough to
## replay cpr_motion_session.gd on a PC with other thresholds against the real hand signal.
func _write_cpr_trace(delta: float, available: bool, valid: bool, no_sample: bool, chosen: StringName, height: float) -> void:
	if not available:
		return
	if no_sample:
		_trace_grace_s -= delta
		if _trace_grace_s <= 0.0:
			return
	else:
		_trace_grace_s = 1.0
	if _trace == null:
		var path := "user://cpr_trace_%d.csv" % int(Time.get_unix_time_from_system())
		_trace = FileAccess.open(path, FileAccess.WRITE)
		if _trace == null:
			return
		_trace.store_line("t_ms,valid,hand,height_m,top_m,bottom_m,recoil_peak_m,descending,travel_m,count,since_stroke_s,left_move_m,right_move_m")
		print("CPR trace: ", path)
	var hand := "none"
	if chosen == left_tracker:
		hand = "left"
	elif chosen == right_tracker:
		hand = "right"
	_trace.store_line("%d,%d,%s,%.4f,%.4f,%.4f,%.4f,%d,%.4f,%d,%.2f,%.4f,%.4f" % [
		Time.get_ticks_msec(), int(valid), hand, height,
		motion_session._top, motion_session._bottom, motion_session._recoil_peak,
		int(motion_session._descending), motion_session.travel_m,
		motion_session.total_count, motion_session._since_stroke,
		_hand_movement(left_tracker), _hand_movement(right_tracker)])
	_trace_unflushed += 1
	if _trace_unflushed >= 36:
		_trace.flush()
		_trace_unflushed = 0


## Height of a palm above the contact slab, in metres, or NAN when that palm is not tracked.
func _palm_height(hand: Dictionary) -> float:
	if hand.is_empty():
		return NAN
	var chest := _shape.global_transform
	return (hand.point - chest.origin).dot(chest.basis.y.normalized()) / _units_per_metre()


func _record_hand_height(tracker_name: StringName, hand: Dictionary) -> void:
	var history: Array = _hand_history.get(tracker_name, [])
	var height := _palm_height(hand)
	if is_finite(height):
		history.append([_motion_time_s, height])
	while not history.is_empty() and float(history[0][0]) < _motion_time_s - MOVEMENT_WINDOW_S:
		history.pop_front()
	_hand_history[tracker_name] = history


## How far this palm travelled over the last MOVEMENT_WINDOW_S, peak to trough.
func _hand_movement(tracker_name: StringName) -> float:
	var history: Array = _hand_history.get(tracker_name, [])
	if history.size() < 10:
		return 0.0
	var lowest := INF
	var highest := -INF
	for entry in history:
		lowest = minf(lowest, float(entry[1]))
		highest = maxf(highest, float(entry[1]))
	return highest - lowest


func _units_per_metre() -> float:
	if xr_origin == null:
		return 1.0
	return maxf(0.001, XRServer.world_scale * xr_origin.global_basis.get_scale().length() / sqrt(3.0))


const MOTION_REACH_M := 0.15
## A palm moving less than this over MOVEMENT_WINDOW_S is not compressing; when the other
## palm is moving at least FROZEN_HAND_MARGIN_M more, the damped one is the hidden lower hand.
const MOVEMENT_WINDOW_S := 1.5
## Tuned on device trace 1790251203 by replaying the recorded left_move_m/right_move_m columns:
## the shipped 2 cm / 1.5 cm / 0.75 s handed over at 7.1 s, exactly as the headset did, and the
## first seven seconds counted one press. 3 cm / 2 cm / 0.5 s hands over at 4.2 s with no extra
## switching; loosening either the margin or the freeze alone adds two needless switches.
const FROZEN_HAND_M := 0.030
const FROZEN_HAND_MARGIN_M := 0.020
## Hold the condition this long before handing over: a switch costs the press in progress.
const HANDOVER_DWELL_S := 0.50
## Before the first counted press: no press is at stake, so switch on a plain difference in
## movement and after a short confirmation, to be on the right palm by the opening compression.
const OPENING_MARGIN_M := 0.010
const OPENING_DWELL_S := 0.30
const SESSION_FOCUSED := 5   # OpenXR session state; below it the runtime delivers no hands
var _openxr: OpenXRInterface


func _session_paused() -> bool:
	if _openxr == null:
		_openxr = XRServer.find_interface("OpenXR") as OpenXRInterface
	return _openxr != null and _openxr.is_initialized() and _openxr.get_session_state() != SESSION_FOCUSED

var _rejected_palm := ""
var _reject_print_s := 0.0
var _raw_print_s := 0.0
var _motion_time_s := 0.0
var _hand_history := {}          # tracker name -> Array of [time_s, height_m]
var _handover_s := 0.0
## Seconds the headset has delivered no hand data at all while this app is focused.
var _hand_feed_dead_s := 0.0
const HAND_FEED_DEAD_S := 3.0


func _motion_hand_usable(hand: Dictionary) -> bool:
	if hand.is_empty():
		return false
	var offset: Vector3 = hand.point - _shape.global_position
	var units := _units_per_metre()
	var height := offset.dot(_shape.global_basis.y.normalized()) / units
	var sideways := offset.dot(_shape.global_basis.x.normalized()) / units
	var lengthwise := offset.dot(_shape.global_basis.z.normalized()) / units
	# 15 cm: the palm joint sits 5-7 cm from the heel on the slab and the visual placement is a
	# few cm off; 8 cm rejected every palm on 2026-09-24 morning after passing the night before.
	var usable := absf(sideways) < MOTION_REACH_M and absf(lengthwise) < MOTION_REACH_M and height > -0.12 and height < 0.15
	if not usable:
		_rejected_palm = "side %+.1f cm, along %+.1f cm, height %+.1f cm" % [sideways * 100.0, lengthwise * 100.0, height * 100.0]
	return usable

## Motion needs only an actively tracked palm position, not a wrist or orientation.
## Keep the stricter heel/orientation checks exclusively in the experimental placement grader.
func _read_motion_hand(tracker_name: StringName) -> Dictionary:
	_motion_reasons[tracker_name] = "no_tracker"
	if xr_origin == null:
		return {}
	var hand := XRServer.get_tracker(tracker_name) as XRHandTracker
	if hand == null:
		return {}
	if hand.hand_tracking_source == XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER:
		_motion_reasons[tracker_name] = "controller"
		return {}
	_motion_reasons[tracker_name] = "not_tracked"
	if not hand.has_tracking_data or hand.hand_tracking_source == XRHandTracker.HAND_TRACKING_SOURCE_NOT_TRACKED:
		return {}
	var flags := hand.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
	var required := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
	if (flags & required) != required:
		_motion_reasons[tracker_name] = "palm_not_tracked (flags=%d)" % flags
		return {}
	var palm := hand.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
	if not palm.origin.is_finite():
		return {}
	var pose := XRPose.new()
	pose.transform = Transform3D(Basis.IDENTITY, palm.origin)
	var position_world := xr_origin.global_transform * pose.get_adjusted_transform().origin
	_motion_reasons[tracker_name] = "tracked"
	return {"point": position_world}


## Only a tracked palm POSITION is required. The wrist joint and the palm orientation improve
## the heel estimate when they are tracked, but their loss must not make a real hand "disappear":
## on the Quest the wrist is the first joint lost during placement (under the other hand, or at
## the edge of view), and orientation can settle a frame or two after position.
func _read_hand(tracker_name: StringName) -> Dictionary:
	if xr_origin == null:
		return {}
	var hand := XRServer.get_tracker(tracker_name) as XRHandTracker
	if hand == null or not hand.has_tracking_data:
		return {}
	if hand.hand_tracking_source in [XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER, XRHandTracker.HAND_TRACKING_SOURCE_NOT_TRACKED]:
		return {}
	var position_flags := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
	var orientation_flags := XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_TRACKED
	var palm_joint_flags := hand.get_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM)
	if (palm_joint_flags & position_flags) != position_flags:
		return {}
	var palm := hand.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM)
	if not palm.origin.is_finite():
		return {}
	var orientation_ok := (
		(palm_joint_flags & orientation_flags) == orientation_flags
		and palm.basis.is_finite() and absf(palm.basis.determinant()) > 0.001
	)
	var wrist := hand.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST)
	var wrist_to_palm := wrist.origin.distance_to(palm.origin) if wrist.origin.is_finite() else 0.0
	var wrist_ok := (
		(hand.get_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST) & position_flags) == position_flags
		and wrist_to_palm >= 0.010 and wrist_to_palm <= 0.150
	)
	# Godot's OpenXR Humanoid conversion: +Y runs along the fingers, -Z faces out the back of the
	# hand, so +Z points toward the palm skin/contact surface (both left and right).
	var heel := palm.origin
	if wrist_ok:
		heel = wrist.origin.lerp(palm.origin, heel_wrist_to_palm_fraction)
	elif orientation_ok:
		heel = palm.origin - palm.basis.y.normalized() * palm_to_heel_fallback_m
	if orientation_ok:
		heel += palm.basis.z.normalized() * heel_surface_offset_m
	var pose := XRPose.new()
	pose.transform = Transform3D(palm.basis.orthonormalized() if orientation_ok else Basis.IDENTITY, heel)
	# Apply the same reference frame and world scale as XRNode3D, then the scene origin.
	var world := xr_origin.global_transform * pose.get_adjusted_transform()
	var result := {"heel": world.origin, "wrist_tracked": wrist_ok}
	if orientation_ok:
		result["palm_normal"] = world.basis.z.normalized()
	return result


func _heel_on_target(hand: Dictionary) -> bool:
	return not hand.is_empty() and contains_world_point(hand.heel) and _faces_chest(hand)


## Unknown orientation is not evidence of a wrong orientation: a palm whose rotation the runtime
## has not settled yet still counts as facing the chest.
## The one visible hand counts when its heel is over the target footprint, from the contact slab
## up to the maximum stack height, and it faces the chest (if its orientation is known).
func _single_hand_on_target(hand: Dictionary) -> bool:
	if hand.is_empty() or not _faces_chest(hand):
		return false
	var box := _shape.shape as BoxShape3D
	if box == null or _shape.disabled or not hand.heel.is_finite():
		return false
	var local := _shape.to_local(hand.heel)
	var half := box.size * 0.5
	# to_local() returns SHAPE-local units, which carry the mannequin's ~0.7 scale, so a limit in
	# metres has to be divided by the world size of one local unit. Without that the stack height
	# acted as ~5 cm and a hand 7 cm above the slab was rejected (2026-09-23 08:45).
	var unit_m := _shape.global_basis.y.length()
	var top := single_hand_reach_m * _units_per_metre() / maxf(unit_m, 0.001)
	return absf(local.x) <= half.x and absf(local.z) <= half.z and local.y >= -half.y and local.y <= top


func _faces_chest(hand: Dictionary) -> bool:
	if not hand.has("palm_normal"):
		return true
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
	motion_session.start()
	_motion_tracker = &""
	_clear_placement()
	_update_feedback()
	cpr_started.emit()

func reset_placement() -> void:
	is_cpr_started = false
	motion_session.reset()
	_motion_tracker = &""
	# Movement history belongs to the session that produced it: kept across a reset it can show a
	# difference between the palms that is only the jump from the old placement, and hand the
	# tracking to the wrong palm on the first frames of the new one.
	_hand_history.clear()
	_handover_s = 0.0
	_have_chest_pose = false
	if _metronome != null:
		_metronome.stop()
	_clear_placement()
	_update_feedback()
	placement_restarted.emit()

func _clear_placement() -> void:
	var was_correct := correct_placement
	left_hand_inside = false
	right_hand_inside = false
	_placement_correct = false
	lower_hand = &""
	if was_correct:
		placement_changed.emit(false)


func _update_feedback() -> void:
	if _highlight == null or _material == null:
		return
	# The green target is the placement instruction: shown whenever the avatar is placed and the
	# hands are not yet on it, hidden while they are, back the moment they leave. It no longer
	# depends on the session having started (2026-09-22: B toggled the session and the user was
	# left without a target after a restart).
	_highlight.visible = not _paused and not correct_placement
	_instruction.visible = _highlight.visible
	if not guide_only:
		# Green is the instruction colour ("put your hands here"), brighter once the hands are on it.
		# Never orange: an orange box read as an error, not as a target (headset review 2026-09-15).
		_material.albedo_color = Color(0.10, 0.95, 0.30, 0.90) if correct_placement else Color(0.15, 0.80, 0.35, 0.60)


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
		motion_session.invalidate_tracking()
		if _metronome != null:
			_metronome.stop()
		_clear_placement()
		_update_feedback()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_paused = false
		motion_session.invalidate_tracking()
		_have_chest_pose = false
		_clear_placement()
		_update_feedback()
