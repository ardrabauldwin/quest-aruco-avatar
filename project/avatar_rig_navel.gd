extends Node3D
## Places the avatar from the newest fused ArUco result.
##
## Pipeline: newest markers -> common pose -> medoid/dead zones/smoothing/prior -> avatar.

@export var common_marker: Node3D
@export var chest_marker: Node3D
@export var torso_marker: Node3D

@export_group("Look")
@export_range(0.0, 0.95, 0.05) var avatar_transparency := 0.6
@export var avatar_tint := Color.WHITE

@export_group("Calibration")
@export var xr_controller_right: XRController3D
## Relearns the session rest pose without replacing the permanent marker offsets.
@export var relevel_button := "primary_click"

@export_group("Placement")
@export var enable_nudge := false
@export var target: Node3D
@export var nudge_speed := 0.05
## Saved manual alignment relative to the scene's original placement, in rig-local metres.
@export var default_nudge := Vector3.ZERO
## Rotation about the chest, in degrees around world up after floor locking.
@export var default_yaw_deg := 0.0
@export var nudge_yaw_speed_dps := 10.0
@export var xr_controller_left: XRController3D
## Supplies the Quest floor height (has_floor / floor_height_world).
## The actual mesh bottom, including manual translation, is placed on this floor.
@export var floor_provider: Node
## The viewer's head (XRCamera3D). Drives the viewer-motion gate: the marker error changes only
## while the head moves, the mannequin can move at any time. So while the head moves the avatar
## holds; once the head has settled, the difference between what the markers read from here and
## where the avatar stands is measured. A small difference (viewpoint bias) is subtracted from
## every measurement while the viewer stays there, so the avatar neither drifts nor jumps; a
## large one means the mannequin was moved, and the avatar follows. Null disables the gate.
@export var head: Node3D

# Version the writable copy so this build starts from the validated previous calibration instead
# of silently loading either of the older on-device calibration files.
const SAVE_PATH := "user://navel_calibration_20260905.cfg"
const DEFAULT_CALIBRATION_PATH := "res://default_navel_calibration.cfg"
const YAW_ALIGNMENT_PATH := "user://avatar_yaw_alignment.cfg"
const YAW_STICK_DEAD_ZONE := 0.2

# Runtime filter values selected by tune_filter.py on the 2026-09-04 labelled session
# (calibration 1788433311 + stationary 1788430472 + moving 1788431407 at 617.5 mm):
# movement retained 99.7%, endpoint error 4.8 mm, return error 10.4 mm.
const FILTER_WINDOW := 5
const FILTER_POSITION_DEAD_ZONE_M := 0.020
const FILTER_ROTATION_DEAD_ZONE_DEG := 0.3
const FILTER_SMOOTHING_TIME_S := 1.2
const FILTER_PRIOR_TIME_S := 2.0
# Endpoint stability is evaluated over a complete measurement-target window.
const ENDPOINT_STABLE_POSITION_M := 0.0015
const ENDPOINT_STABLE_ROTATION_DEG := 1.0
const ENDPOINT_STABLE_DETECTIONS := 3
# Re-anchoring adopts a stable measurement as the new rest, i.e. "the mannequin was moved".
# Viewpoint-dependent bias must stay below these floors or walking around the mannequin gets
# mistaken for moving it: on the headset (2026-09-15) side views rotated the avatar a few
# degrees "at times" and the far view crept toward the viewer -- both re-anchor events on the
# ~4-6 cm / few-degree residual that remains after the fx scale fix. Real slides in the recorded
# tests were 105-300 mm and mannequin rotations tens of degrees, so 80 mm / 8 deg keeps those.
const REANCHOR_MIN_POSITION_M := 0.080
const REANCHOR_MIN_ROTATION_DEG := 8.0

var _common_provider := CommonPoseProvider.new()
var _filter := SimplePoseStabilizer.new()
var _fresh := MarkerFreshness.new()
var _markers: Array = []
var _visible_now: Array = []
var _was_nudging := false
var _tracking_was_available := false
var _application_paused := false
var _runtime_initialized := false
var _mesh_floor_offset_ready := false
var _floor_placement_active := false
var _lowest_mesh_vertex_offset_y := 0.0
var _manual_nudge := Vector3.ZERO
var _manual_yaw := 0.0
var _held_height := 0.0
var _has_held_height := false
var _held_samples: Array[float] = []
var _held_last_ms := -1
var _common_seen_ms := -1
var _full_evidence_now := true
const HELD_HEIGHT_DETECTIONS := 12
const HELD_HEIGHT_MINIMUM := 5
const HELD_HEIGHT_TIMEOUT_S := 8.0
var _held_learning_s := 0.0
var _yaw_dirty := false

# --- Viewer-motion gate (see `head`) ---
const HEAD_STILL_SPEED_MPS := 0.15
const HEAD_STILL_TURN_DPS := 20.0
const HEAD_WINDOW_S := 0.3
const HEAD_SETTLE_S := 0.5
## Largest marker-vs-avatar difference still read as viewpoint bias. The 2026-09-15 recordings
## gave <= 5 cm / <= 3 deg at working distance, so this was 6 cm. On the headset it is bigger:
## 2026-09-24 11:34, mannequin untouched, the raw common-marker height alone swept 12.1 -> 18.2 cm
## as the user moved round, and the gate twice called that a 14-15 cm "move" and jumped the avatar
## from a side view. Set above the measured sweep so walking round is absorbed, not followed.
const VIEW_BIAS_MAX_M := 0.10
const VIEW_BIAS_MAX_DEG := 10.0
const VIEW_BIAS_SAMPLES := 5
## A difference this large is followed even while the head moves: no viewpoint bias is that big.
## Raised with VIEW_BIAS_MAX_M: a far side view can throw the raw pose 15 cm on its own, and on
## 2026-09-24 that fired "follow_big" with the mannequin untouched.
const FOLLOW_ANYWAY_M := 0.30
const FOLLOW_ANYWAY_DEG := 25.0
## From farther than this the marker error can exceed VIEW_BIAS_MAX_M (chest marker 9.5 cm at
## 2.2 m in the replay), so a small move is not judged from there: it is absorbed as bias and
## followed once the viewer is closer, or at once when it exceeds FOLLOW_ANYWAY_M.
const JUDGE_MOVE_MAX_RANGE_M := 1.8

var _head_samples: Array = []      # [time_s, position, yaw]
var _head_time_s := 0.0
var _head_still_s := 0.0
var _view_bias_ready := false
var _view_bias_position := Vector3.ZERO
var _view_bias_yaw := 0.0
var _view_bias_samples: Array = []
var _view_bias_last_ms := -1
var _follow_big_count := 0
var _window_partial := false   # a settle window that saw hidden markers or a hand on the chest
var _follow_big_last_ms := -1
const FOLLOW_ANYWAY_DETECTIONS := 3
var gate_state := "off"
var _diag_timer := 0.0


func _ready() -> void:
	visible = false
	if target != null:
		_align_chest_to_markers()
		_apply_manual_nudge(default_nudge)
		_apply_manual_yaw(deg_to_rad(_load_manual_yaw()))
	_markers = [common_marker, chest_marker, torso_marker]
	_filter.configure(
		FILTER_WINDOW,
		FILTER_POSITION_DEAD_ZONE_M,
		FILTER_ROTATION_DEAD_ZONE_DEG,
		FILTER_SMOOTHING_TIME_S,
		FILTER_PRIOR_TIME_S,
		ENDPOINT_STABLE_POSITION_M,
		ENDPOINT_STABLE_ROTATION_DEG,
		ENDPOINT_STABLE_DETECTIONS,
		REANCHOR_MIN_POSITION_M,
		REANCHOR_MIN_ROTATION_DEG
	)
	_apply_look()
	_common_provider.orientation_settled.connect(_on_orientation_settled)
	_load_calibration()
	if xr_controller_right != null:
		xr_controller_right.button_pressed.connect(_on_button)
	_runtime_initialized = true


func _notification(what: int) -> void:
	if not _runtime_initialized:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_application_paused = true
		visible = false
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_application_paused = false
		# The XR world frame and camera stream may have changed while the Quest menu owned focus.
		# Never display or interpolate from the pre-pause world pose.
		_visible_now.clear()
		_tracking_was_available = false
		_common_provider.recalibrate_orientation()
		_filter.reset()
		_has_held_height = false
		_held_samples.clear()
		_held_learning_s = 0.0
		visible = false
		print("Common pose: app resumed; collecting a fresh session rest pose.")


func _process(delta: float) -> void:
	var result := _newest_marker_result()
	var result_markers: Array = result["markers"]
	var result_timestamp_ms: int = result["timestamp_ms"]
	if result_markers.is_empty():
		_hold_after_tracking_loss()
	else:
		_update_tracking(result_markers, result_timestamp_ms, delta)
	if _common_provider.has_rest_pose() and not _has_held_height:
		_held_learning_s += delta
	_print_diagnostics(delta)

	# Once a pose is confirmed, keep it visible through marker loss and reacquisition.
	# Startup, app resume, and re-levelling still require a newly confirmed rest pose.
	visible = (
		not _application_paused
		and _filter.is_ready()
		and _common_provider.has_rest_pose()
	)
	_update_nudge(delta)


func _load_calibration() -> void:
	if _common_provider.load_from(SAVE_PATH, _markers):
		print("Common pose: calibration loaded from disk.")
	elif _common_provider.load_from(DEFAULT_CALIBRATION_PATH, _markers):
		print("Common pose: bundled default calibration loaded.")
	else:
		push_error("Common pose: no user or bundled marker calibration is available.")


## Finds fresh markers, then keeps only those sharing the newest result timestamp.
func _newest_marker_result() -> Dictionary:
	_visible_now = []
	var newest_timestamp_ms := -1

	for marker in _markers:
		if _fresh.age_ms(marker) <= _fresh.tracking_loss_timeout_ms:
			_visible_now.append(marker)
			newest_timestamp_ms = maxi(
				newest_timestamp_ms,
				int(marker.get_meta("last_detected_ms", -1))
			)

	var newest_markers: Array = []
	for marker in _visible_now:
		if int(marker.get_meta("last_detected_ms", -1)) == newest_timestamp_ms:
			newest_markers.append(marker)

	return {"markers": newest_markers, "timestamp_ms": newest_timestamp_ms}


func _update_tracking(markers: Array, detection_ms: int, delta: float) -> void:
	_tracking_was_available = true
	var raw_pose := _common_provider.get_pose(markers, detection_ms)
	_common_seen_ms = detection_ms if common_marker in markers else -1
	if not _common_provider.is_ready():
		return
	if head != null and _filter.is_ready() and _common_provider.has_rest_pose():
		_full_evidence_now = markers.size() >= 3 and not _hand_over_chest()
		var gated := _gate_measurement(raw_pose, detection_ms, delta, _full_evidence_now)
		if gated.is_empty():
			return
		raw_pose = gated["pose"]

	var filtered_pose := _filter.update(
		raw_pose,
		delta,
		detection_ms,
		_common_provider.rest_pose(),
		_common_provider.has_rest_pose()
	)
	# Re-anchor only after the complete measurement-only target window is stationary and its
	# displacement exceeds the separately configured relocation threshold.
	var reanchor_position := _filter.position_reanchor_ready()
	var reanchor_rotation := _filter.rotation_reanchor_ready()
	if _common_provider.reanchor_rest_from_stable_target(
		_filter.measurement_target(),
		detection_ms,
		reanchor_position,
		reanchor_rotation
	):
		_filter.complete_rest_reanchor(reanchor_position, reanchor_rotation)
	if _filter.is_ready() and _common_provider.has_rest_pose():
		_apply_filtered_pose(filtered_pose)


static func _yaw_of(basis: Basis) -> float:
	return atan2(basis.y.x, basis.y.z)


static func _head_yaw(basis: Basis) -> float:
	return atan2(-basis.z.x, -basis.z.z)


## True while the head is moving or has been still for less than HEAD_SETTLE_S. Speed and turn
## are taken over a HEAD_WINDOW_S window, so a head updated only ~10x per second (replay) and a
## head updated every frame (device) read the same.
func _head_moving(delta: float) -> bool:
	_head_time_s += delta
	var t: Transform3D = head.global_transform
	var yaw := _head_yaw(t.basis)
	_head_samples.append([_head_time_s, t.origin, yaw])
	while _head_samples.size() > 1 and float(_head_samples[0][0]) < _head_time_s - HEAD_WINDOW_S:
		_head_samples.pop_front()
	var first: Array = _head_samples[0]
	var span := _head_time_s - float(first[0])
	var moving := false
	if span > 0.05:
		var speed := t.origin.distance_to(first[1]) / span
		var turn := rad_to_deg(absf(wrapf(yaw - float(first[2]), -PI, PI))) / span
		moving = speed > HEAD_STILL_SPEED_MPS or turn > HEAD_STILL_TURN_DPS
	if moving:
		_head_still_s = 0.0
	else:
		_head_still_s += delta
	return _head_still_s < HEAD_SETTLE_S


## Returns {} to hold the avatar this frame, or {"pose": measurement to feed the stabilizer}.
## A hand over the chest hides markers; the zone reports it (see CPRHandZone.hand_over_chest).
func _hand_over_chest() -> bool:
	if target == null:
		return false
	var zone := target.get_node_or_null("CPRHandZone")
	return zone != null and bool(zone.get("hand_over_chest"))


## full_evidence: all markers visible and no hand over the chest. Only then may a difference be
## read as the mannequin having moved (device log 2026-09-22: partial marker sets shifted the
## fused pose 9-15 cm while hands were being placed, and the avatar followed five times).
func _gate_measurement(raw_pose: Transform3D, detection_ms: int, delta: float, full_evidence: bool = true) -> Dictionary:
	var moving := _head_moving(delta)
	if not full_evidence:
		_window_partial = true
	var display := global_transform
	var offset := raw_pose.origin - display.origin
	offset.y = 0.0   # height is held separately
	var offset_deg := rad_to_deg(absf(wrapf(_yaw_of(raw_pose.basis) - _yaw_of(display.basis), -PI, PI)))
	if (offset.length() > FOLLOW_ANYWAY_M or offset_deg > FOLLOW_ANYWAY_DEG) and full_evidence:
		# A single far-range spike must not count: the move has to persist over detections.
		if detection_ms != _follow_big_last_ms:
			_follow_big_last_ms = detection_ms
			_follow_big_count += 1
		if _follow_big_count >= FOLLOW_ANYWAY_DETECTIONS:
			_view_bias_ready = false
			_view_bias_samples.clear()
			gate_state = "follow_big"
			return {"pose": raw_pose}
	else:
		_follow_big_count = 0
	if moving:
		_view_bias_ready = false
		_view_bias_samples.clear()
		_window_partial = false
		gate_state = "hold_moving"
		return {}
	if head.global_position.distance_to(display.origin) > JUDGE_MOVE_MAX_RANGE_M:
		# Too far to trust the markers for anything but a big move: hold. Smaller moves are
		# picked up when the viewer comes closer (the near settle then reads them as a move).
		_view_bias_ready = false
		_view_bias_samples.clear()
		gate_state = "hold_far"
		return {}
	if not _view_bias_ready:
		if detection_ms != _view_bias_last_ms:
			_view_bias_last_ms = detection_ms
			_view_bias_samples.append(raw_pose)
		if _view_bias_samples.size() < VIEW_BIAS_SAMPLES:
			gate_state = "settling"
			return {}
		var xs: Array[float] = []
		var zs: Array[float] = []
		var yaws: Array[float] = []
		var display_yaw := _yaw_of(display.basis)
		for sample in _view_bias_samples:
			xs.append((sample as Transform3D).origin.x - display.origin.x)
			zs.append((sample as Transform3D).origin.z - display.origin.z)
			yaws.append(wrapf(_yaw_of((sample as Transform3D).basis) - display_yaw, -PI, PI))
		xs.sort()
		zs.sort()
		yaws.sort()
		var mid := VIEW_BIAS_SAMPLES / 2
		var bias := Vector3(xs[mid], 0.0, zs[mid])
		var bias_yaw: float = yaws[mid]
		_view_bias_samples.clear()
		_view_bias_ready = true
		if bias.length() <= VIEW_BIAS_MAX_M and rad_to_deg(absf(bias_yaw)) <= VIEW_BIAS_MAX_DEG:
			_view_bias_position = bias
			_view_bias_yaw = bias_yaw
			gate_state = "biased"
			print("Viewer gate: settled; viewpoint bias %.1f cm / %.1f deg absorbed." % [bias.length() * 100.0, rad_to_deg(bias_yaw)])
		elif _window_partial:
			# Not enough evidence for a move: markers were hidden or a hand was on the chest during
			# the window. Hold the avatar and judge again from the next full window.
			_view_bias_ready = false
			_window_partial = false
			gate_state = "hold_partial"
			print("Viewer gate: %.1f cm / %.1f deg difference with markers hidden or hands on the chest - holding." % [bias.length() * 100.0, rad_to_deg(bias_yaw)])
			return {}
		else:
			_view_bias_position = Vector3.ZERO
			_view_bias_yaw = 0.0
			gate_state = "follow_moved"
			print("Viewer gate: settled; markers moved %.1f cm / %.1f deg while the head was still - following." % [bias.length() * 100.0, rad_to_deg(bias_yaw)])
	var corrected := raw_pose
	corrected.origin -= _view_bias_position
	corrected.basis = Basis(Vector3.UP, -_view_bias_yaw) * corrected.basis
	return {"pose": corrected}


## Markers supply horizontal placement and heading; a valid floor supplies mesh-bottom height.
## Marker height remains the fallback when a floor-based XR reference space is unavailable.
func _apply_filtered_pose(pose: Transform3D) -> void:
	# The mannequin lies on the floor: its height never changes unless it is lifted, and a lift
	# re-anchors the rest pose anyway. The live marker height varies by ~5 cm with the viewpoint
	# (the oblique range error has a vertical part), and a height change seen from standing
	# height reads as the avatar sliding towards or away from the viewer. So the height is the
	# rest anchor's, learned once at placement from the front where the error is smallest.
	# Learned from the common marker's OWN detections, not from the fused rest pose: the fused
	# y carries the chest/navel calibration error (2026-09-22 22:55: rest pose 0.129 m, common
	# marker 0.162-0.176 m, avatar chest 5-6 cm below the real chest). Median of the first
	# HELD_HEIGHT_DETECTIONS detections after placement; the live marker y until then.
	if _common_provider.has_rest_pose():
		# Only clean detections teach the height: 2026-09-24 09:59 a marker half covered by hands
		# read 7-8 cm instead of 17 and the height was held there. The guard is "no hand over the
		# chest", NOT "all three markers": the height is read from the common marker's own node, so
		# the other two are irrelevant, and requiring them made clean samples so rare (23 % of
		# frames carry three markers) that learning never finished - every session after v44 sat at
		# learning(1..15) and the avatar's height stayed a median of a handful of noisy samples.
		if not _has_held_height and _common_seen_ms >= 0 and _common_seen_ms != _held_last_ms and not _hand_over_chest():
			_held_last_ms = _common_seen_ms
			_held_samples.append(common_marker.global_position.y)
			# Finish on enough samples, or on the timeout with at least a usable few, so the height
			# can never stay half-learned while the user is already compressing.
			if _held_samples.size() >= HELD_HEIGHT_DETECTIONS or (
				_held_learning_s >= HELD_HEIGHT_TIMEOUT_S and _held_samples.size() >= HELD_HEIGHT_MINIMUM):
				_held_samples.sort()
				_held_height = _held_samples[_held_samples.size() / 2]
				_has_held_height = true
				print("Avatar vertical: height held at %.3f m from %d common-marker detections." % [_held_height, _held_samples.size()])
		if _has_held_height:
			pose.origin.y = _held_height
		elif not _held_samples.is_empty():
			# Running median while learning, so the height converges instead of stepping.
			var sorted := _held_samples.duplicate()
			sorted.sort()
			pose.origin.y = sorted[sorted.size() / 2]
	if not global_basis.is_equal_approx(pose.basis):
		_mesh_floor_offset_ready = false
	global_transform = pose
	_floor_placement_active = true
	_enforce_floor_boundary()


func _enforce_floor_boundary() -> void:
	if floor_provider == null or target == null:
		return
	if not floor_provider.has_floor():
		return
	if not _mesh_floor_offset_ready:
		var measured_lowest := _lowest_mesh_world_y(target)
		if not is_finite(measured_lowest):
			return
		# Cache geometry without manual translation; add its current world-space value below.
		var manual_world_offset := global_basis * _manual_nudge
		_lowest_mesh_vertex_offset_y = measured_lowest - manual_world_offset.y - global_position.y
		_mesh_floor_offset_ready = true
		print(
			"Floor boundary: exact lowest-vertex offset %.3f m."
			% _lowest_mesh_vertex_offset_y
		)
	var floor_y: float = floor_provider.floor_height_world()
	if not is_finite(floor_y):
		return
	var actual_lowest := global_position.y + _lowest_mesh_vertex_offset_y + (global_basis * _manual_nudge).y
	# Correct either sign: a boundary-only clamp left floating meshes untouched.
	global_position.y += floor_y - actual_lowest


## World-space bottom from actual triangle vertices. Transforming an AABB's eight corners is
## conservative and included empty space in this rotated GLB, causing an unnecessary ~18 mm lift.
func _lowest_mesh_world_y(node: Node3D) -> float:
	var lowest := INF
	var instances := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		instances.append(node)
	for instance in instances:
		var mesh_instance := instance as MeshInstance3D
		if mesh_instance.has_meta("cpr_feedback"):
			continue
		if mesh_instance.mesh == null:
			continue
		for vertex in mesh_instance.mesh.get_faces():
			lowest = minf(lowest, (mesh_instance.global_transform * vertex).y)
	return lowest


## On complete loss, freeze the avatar and discard measurements from before the gap.
func _hold_after_tracking_loss() -> void:
	if not _tracking_was_available:
		return
	_tracking_was_available = false
	_filter.clear_measurement_history()


func _on_button(button_name: String) -> void:
	print("Right controller: ", button_name)
	if button_name != relevel_button:
		return
	if not _visible_now.has(common_marker):
		print("Common pose: calibration needs common visibly.")
		return

	_common_provider.recalibrate_orientation()
	visible = false
	_filter.reset()
	_has_held_height = false
	_held_samples.clear()
	_held_learning_s = 0.0
	print("Common pose: re-levelling; collecting 30+3 detection checkpoints.")


func _on_orientation_settled() -> void:
	# Save only marker-local offsets; the world-space rest pose is session-local.
	_common_provider.save_to(SAVE_PATH)
	# Show the robust rest first, but keep the genuine recent measurements collected while hidden.
	_filter.anchor_at(_common_provider.rest_pose())
	print("Common pose: session orientation settled; marker offsets saved.")


func _update_nudge(delta: float) -> void:
	if not enable_nudge or target == null:
		return

	var nudge := _read_nudge(delta)
	var yaw := _read_yaw(delta)
	if nudge != Vector3.ZERO or not is_zero_approx(yaw):
		if nudge != Vector3.ZERO:
			_apply_manual_nudge(nudge)
		if not is_zero_approx(yaw):
			_apply_manual_yaw(yaw)
			_yaw_dirty = true
		_was_nudging = true
	elif _was_nudging:
		print("Final mannequin offset: ", target.position)
		if _yaw_dirty:
			var error := _save_manual_yaw()
			if error != OK:
				push_warning("Could not save avatar angle: %s" % error_string(error))
			print("Final mannequin yaw: %.2f deg (saved=%s)" % [manual_yaw_degrees(), error == OK])
			_yaw_dirty = false
		_was_nudging = false


func _apply_manual_nudge(nudge: Vector3) -> void:
	target.position += nudge
	_manual_nudge += nudge
	# The cached baseline excludes this translation, so it remains valid.
	if _floor_placement_active:
		_enforce_floor_boundary()


## Vertical placement from the markers, not from the floor. The markers are glued to the real
## chest; the hand target's contact slab lies on the avatar's chest surface. Shift the mesh
## along the rig's down axis so that slab sits exactly in the marker plane. The slab, not the
## zone origin: the origin is ~6.8 zone units (~4.5 cm) above the slab, and aligning it on
## 2026-09-16 put the slab inside the mannequin, where a resting heel fell outside the +-0.9 cm
## box and placement, count, depth and rate all failed (2026-09-17).
func _align_chest_to_markers() -> void:
	if target == null:
		return
	var zone: Node3D = target.get_node_or_null("CPRHandZone")
	if zone == null:
		return
	var contact: Node3D = zone.get_node_or_null("CollisionShape3D")
	var contact_in_zone: Vector3 = contact.position if contact != null else Vector3.ZERO
	var contact_in_rig: Vector3 = target.transform * (zone.transform * contact_in_zone)
	target.position.z -= contact_in_rig.z
	_mesh_floor_offset_ready = false
	print("Avatar vertical: hand target aligned to the marker plane (mesh shifted %.3f m)." % -contact_in_rig.z)


## Once a second while placed: the numbers behind the height. zone_y - marker_y is the avatar's
## chest above the real chest in the same frame. Read with: adb logcat -d | grep "Avatar diag"
func _print_diagnostics(delta: float) -> void:
	_diag_timer += delta
	if _diag_timer < 1.0:
		return
	_diag_timer = 0.0
	# Floor check: everything below is in the headset's LOCAL_FLOOR frame. A controller lying on
	# the real floor should read ~0.03 m; anything more is the headset's floor sitting below the
	# real one (tape: marker 10-11 cm above the floor; app read 18 cm on 22 Sep, 24 cm on 24 Sep).
	var left_y: float = xr_controller_left.global_position.y if xr_controller_left != null and xr_controller_left.get_is_active() else NAN
	var right_y: float = xr_controller_right.global_position.y if xr_controller_right != null and xr_controller_right.get_is_active() else NAN
	var head_y: float = head.global_position.y if head != null else NAN
	var common_y: float = common_marker.global_position.y if common_marker != null else NAN
	print("Floor check: left controller y=%.3f right controller y=%.3f head y=%.3f common marker y=%.3f (headset floor = 0)" % [left_y, right_y, head_y, common_y])
	if not visible or target == null:
		return
	var floor_y: float = floor_provider.floor_height_world() if floor_provider != null and floor_provider.has_floor() else NAN
	var lowest: float = global_position.y + _lowest_mesh_vertex_offset_y + (global_basis * _manual_nudge).y if _mesh_floor_offset_ready else NAN
	var zone: Node3D = target.get_node_or_null("CPRHandZone")
	var contact: Node3D = zone.get_node_or_null("CollisionShape3D") if zone != null else null
	var slab_y: float = contact.global_position.y if contact != null else NAN
	var marker_y: float = common_marker.global_position.y if common_marker != null else NAN
	print("Avatar diag: gate=%s floor_y=%.3f avatar_y=%.3f held=%s lowest_y=%.3f (lowest-floor=%.1f cm) slab_y=%.3f marker_y=%.3f (avatar chest above real chest=%.1f cm) nudge=%s yaw=%.1f"
		% [gate_state, floor_y, global_position.y, ("%.3f" % _held_height) if _has_held_height else "learning(%d)" % _held_samples.size(), lowest, (lowest - floor_y) * 100.0, slab_y, marker_y, (slab_y - marker_y) * 100.0,
		   str(_manual_nudge), manual_yaw_degrees()])


func manual_yaw_degrees() -> float:
	return rad_to_deg(_manual_yaw)


## Rotate in the rig's horizontal plane: local -Z is world up. Pre-multiplication
## preserves the mesh's authored import rotation and non-uniform scale. Keep the
## chest contact point fixed, rather than swinging the chest around the mesh origin.
func _apply_manual_yaw(angle: float) -> void:
	if target == null or not is_finite(angle) or is_zero_approx(angle):
		return
	var pivot_local := Vector3.ZERO
	var zone := target.get_node_or_null("CPRHandZone") as Node3D
	if zone != null:
		var contact := zone.get_node_or_null("CollisionShape3D") as Node3D
		pivot_local = zone.transform * contact.position if contact != null else zone.position
	var pivot := target.transform * pivot_local
	var rotated := Basis(Vector3.FORWARD, angle) * target.basis
	target.transform = Transform3D(rotated, pivot - rotated * pivot_local)
	_manual_yaw = wrapf(_manual_yaw + angle, -PI, PI)
	# Horizontal yaw leaves every vertex height unchanged. Avoid scanning the
	# complete mesh every input frame while the floor-locked avatar is turning.
	if not _floor_placement_active or not global_basis.z.normalized().is_equal_approx(Vector3.DOWN):
		_mesh_floor_offset_ready = false
	if _floor_placement_active:
		_enforce_floor_boundary()


func _read_yaw(delta: float) -> float:
	if xr_controller_right == null or not visible or _application_paused:
		return 0.0
	var axis := xr_controller_right.get_vector2("primary").x
	if absf(axis) <= YAW_STICK_DEAD_ZONE:
		return 0.0
	axis = signf(axis) * (absf(axis) - YAW_STICK_DEAD_ZONE) / (1.0 - YAW_STICK_DEAD_ZONE)
	return -axis * deg_to_rad(nudge_yaw_speed_dps) * delta


func _load_manual_yaw(path: String = YAW_ALIGNMENT_PATH) -> float:
	var config := ConfigFile.new()
	if config.load(path) == OK:
		var value: Variant = config.get_value("alignment", "yaw_degrees", default_yaw_deg)
		if (value is float or value is int) and is_finite(float(value)):
			return wrapf(float(value), -180.0, 180.0)
	return default_yaw_deg


func _save_manual_yaw(path: String = YAW_ALIGNMENT_PATH) -> Error:
	var config := ConfigFile.new()
	config.set_value("alignment", "yaw_degrees", manual_yaw_degrees())
	return config.save(path)


func _read_nudge(delta: float) -> Vector3:
	var direction := Vector3.ZERO
	if xr_controller_left != null:
		var left_stick: Vector2 = xr_controller_left.get_vector2("primary")
		direction.x += left_stick.x
		direction.y += left_stick.y
	if xr_controller_right != null:
		direction.z += -xr_controller_right.get_vector2("primary").y
	return direction * nudge_speed * delta


func _apply_look() -> void:
	var alpha := clampf(1.0 - avatar_transparency, 0.05, 1.0)
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.has_meta("cpr_feedback"):
			continue
		for surface in mesh_instance.get_surface_override_material_count():
			var material := mesh_instance.get_active_material(surface)
			if material is BaseMaterial3D:
				var copy := material.duplicate() as BaseMaterial3D
				copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				copy.albedo_color = Color(avatar_tint, alpha)
				mesh_instance.set_surface_override_material(surface, copy)
