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
@export var xr_controller_left: XRController3D
## Supplies the Quest floor height (has_floor / floor_height_world). The floor is a one-sided
## boundary only: it prevents penetration but never replaces the marker-measured height.
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
var _lowest_mesh_vertex_offset_y := 0.0
var _manual_nudge := Vector3.ZERO


func _ready() -> void:
	visible = false
	if target != null:
		_apply_manual_nudge(default_nudge)
		_align_chest_to_markers()
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
	if not _common_provider.is_ready():
		return
	if head != null and _filter.is_ready() and _common_provider.has_rest_pose():
		var gated := _gate_measurement(raw_pose, detection_ms, delta)
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
func _gate_measurement(raw_pose: Transform3D, detection_ms: int, delta: float) -> Dictionary:
	var moving := _head_moving(delta)
	var display := global_transform
	var offset := raw_pose.origin - display.origin
	offset.y = 0.0   # height is held separately
	var offset_deg := rad_to_deg(absf(wrapf(_yaw_of(raw_pose.basis) - _yaw_of(display.basis), -PI, PI)))
	if offset.length() > FOLLOW_ANYWAY_M or offset_deg > FOLLOW_ANYWAY_DEG:
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
		else:
			_view_bias_position = Vector3.ZERO
			_view_bias_yaw = 0.0
			gate_state = "follow_moved"
			print("Viewer gate: settled; markers moved %.1f cm / %.1f deg while the head was still - following." % [bias.length() * 100.0, rad_to_deg(bias_yaw)])
	var corrected := raw_pose
	corrected.origin -= _view_bias_position
	corrected.basis = Basis(Vector3.UP, -_view_bias_yaw) * corrected.basis
	return {"pose": corrected}


## Place the rig at the ArUco pose, then treat the Quest floor as a boundary: if the avatar's
## lowest mesh point would sink below the floor, raise the rig by exactly the penetration depth.
## An avatar above the floor is left untouched, preserving the marker-to-mannequin alignment.
func _apply_filtered_pose(pose: Transform3D) -> void:
	# The mannequin lies on the floor: its height never changes unless it is lifted, and a lift
	# re-anchors the rest pose anyway. The live marker height varies by ~5 cm with the viewpoint
	# (oblique range error has a vertical part; 2026-09-16 log), and a height change seen from
	# standing height reads as the avatar sliding towards or away from the viewer. So the height
	# is the rest anchor's, learned at placement from the front where the error is smallest.
	if _common_provider.has_rest_pose():
		# Learned once, when the session rest pose settles (front view, close, ~1 cm error).
		# Later re-anchors are ignored for the height: a far-view re-anchor carried that view's
		# 8-17 cm range error into the height (replay 2026-09-16). If the mannequin is lifted onto
		# a table mid-session, re-level (controller button) or restart; both relearn the height.
		if not _has_held_height:
			_held_height = _common_provider.rest_pose().origin.y
			_has_held_height = true
		pose.origin.y = _held_height
	global_transform = pose
	if floor_provider == null or target == null:
		return
	if not floor_provider.has_floor():
		return
	if not _mesh_floor_offset_ready:
		var measured_lowest := _lowest_mesh_world_y(target)
		if not is_finite(measured_lowest):
			return
		# Floor placement uses the original mesh position. Manual alignment is an
		# explicit offset from that placement and must not be cancelled by the floor.
		var manual_world_offset := global_basis * _manual_nudge
		_lowest_mesh_vertex_offset_y = measured_lowest - manual_world_offset.y - global_position.y
		_mesh_floor_offset_ready = true
		print(
			"Floor boundary: exact lowest-vertex offset %.3f m."
			% _lowest_mesh_vertex_offset_y
		)
	var lowest := global_position.y + _lowest_mesh_vertex_offset_y
	var floor_y: float = floor_provider.floor_height_world() - FLOOR_TOLERANCE_M
	if lowest < floor_y:
		global_position.y += floor_y - lowest


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
	print("Common pose: re-levelling; collecting 30+3 detection checkpoints.")


func _on_orientation_settled() -> void:
	# Save only marker-local offsets; the world-space rest pose is session-local.
	_common_provider.save_to(SAVE_PATH)
	# Show the robust rest first, but keep the genuine recent measurements collected while hidden.
	_filter.anchor_at(_common_provider.rest_pose())
	print("Common pose: session orientation settled; marker offsets saved.")


var _diag_timer := 0.0


## Once a second while placed: the numbers behind "is it below the floor" and "do the sticks
## do anything". Read with: adb logcat -d | grep -E "Avatar diag|Nudge"
func _print_diagnostics(delta: float) -> void:
	_diag_timer += delta
	if _diag_timer < 1.0 or not visible or target == null:
		return
	_diag_timer = 0.0
	var floor_y: float = floor_provider.floor_height_world() if floor_provider != null and floor_provider.has_floor() else NAN
	var lowest: float = global_position.y + _lowest_mesh_vertex_offset_y if _mesh_floor_offset_ready else NAN
	var left: Vector2 = xr_controller_left.get_vector2("primary") if xr_controller_left != null else Vector2.ZERO
	var right: Vector2 = xr_controller_right.get_vector2("primary") if xr_controller_right != null else Vector2.ZERO
	# Vertical truth check: the hand target lies on the avatar's chest surface, the common marker
	# node on the real chest. Same frame, so zone_y - marker_y is the avatar's height error.
	var zone: Node3D = target.get_node_or_null("CPRHandZone")
	var zone_y: float = zone.global_position.y if zone != null else NAN
	var marker_y: float = common_marker.global_position.y if common_marker != null else NAN
	print("Avatar diag: gate=%s floor_y=%.3f avatar_y=%.3f lowest_y=%.3f (lowest-floor=%.1f cm) chest_zone_y=%.3f marker_y=%.3f (avatar chest above real chest=%.1f cm) nudge=%s sticks L=%s R=%s"
		% [gate_state, floor_y, global_position.y, lowest, (lowest - floor_y) * 100.0, zone_y, marker_y, (zone_y - marker_y) * 100.0,
		   str(target.position), str(left), str(right)])


func _update_nudge(delta: float) -> void:
	_print_diagnostics(delta)
	if not enable_nudge or target == null:
		return

	var nudge := _read_nudge(delta)
	if nudge != Vector3.ZERO:
		_apply_manual_nudge(nudge)
		_was_nudging = true
	elif _was_nudging:
		print("Final mannequin offset: ", target.position)
		_was_nudging = false


const MANUAL_NUDGE_LIMIT_M := 0.15


## Vertical placement from the markers, not from the floor. The markers are glued to the
## real chest; the hand target lies on the avatar's chest surface. Shift the mesh along the
## rig's down axis so the hand target sits exactly in the marker plane. Until 2026-09-16 the
## mesh was baked ~50 cm below the common point and the floor rule lifted it back onto the
## headset's floor, so the avatar's height came from the floor estimate - which moved by
## 5-10 cm between sessions (markers read 12 cm above it one day, 17-22 cm the next), putting
## the avatar's chest first 2 cm above, then 4-7 cm below the real chest.
const CHEST_ZONE_NODE := "CPRHandZone"
## Sink allowed below the reported floor before the safety lift acts: the floor estimate is
## that uncertain, and the scanned mesh is ~1.5 cm thicker below the chest than the mannequin.
const FLOOR_TOLERANCE_M := 0.05

# --- Viewer-motion gate (see `head`) ---
const HEAD_STILL_SPEED_MPS := 0.15
const HEAD_STILL_TURN_DPS := 20.0
const HEAD_WINDOW_S := 0.3
const HEAD_SETTLE_S := 0.5
## Largest marker-vs-avatar difference still read as viewpoint bias (recordings 2026-09-15:
## <= 5 cm / <= 3 deg at working distance after the flip gate and range correction).
const VIEW_BIAS_MAX_M := 0.06
const VIEW_BIAS_MAX_DEG := 6.0
const VIEW_BIAS_SAMPLES := 5
## A difference this large is followed even while the head moves: no viewpoint bias is that big.
const FOLLOW_ANYWAY_M := 0.15
const FOLLOW_ANYWAY_DEG := 15.0
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
var _follow_big_last_ms := -1
const FOLLOW_ANYWAY_DETECTIONS := 3
var gate_state := "off"
var _held_height := 0.0
var _has_held_height := false


func _align_chest_to_markers() -> void:
	if target == null:
		return
	var zone: Node3D = target.get_node_or_null(CHEST_ZONE_NODE)
	if zone == null:
		return
	var zone_in_rig: Vector3 = target.transform * zone.position
	target.position.z -= zone_in_rig.z
	_mesh_floor_offset_ready = false
	print("Avatar vertical: chest surface aligned to the marker plane (mesh shifted %.3f m)." % -zone_in_rig.z)


func _apply_manual_nudge(nudge: Vector3) -> void:
	# A manual alignment is a few centimetres; anything larger is a stuck stick, not intent.
	var limited := (_manual_nudge + nudge).limit_length(MANUAL_NUDGE_LIMIT_M)
	nudge = limited - _manual_nudge
	target.position += nudge
	_manual_nudge = limited
	_mesh_floor_offset_ready = false


## Left stick only: x = across the body, y = along the body (head <-> feet). The avatar's local
## z is DOWN (floor lock), so a z nudge only pushes the mesh into the floor, where the floor rule
## lifts it straight back - invisible, and on 2026-09-16 it silently accumulated 58 cm while the
## user held the right stick believing nothing happened. Height is the floor rule's job.
func _read_nudge(delta: float) -> Vector3:
	var direction := Vector3.ZERO
	if xr_controller_left != null:
		var left_stick: Vector2 = xr_controller_left.get_vector2("primary")
		direction.x += left_stick.x
		direction.y += left_stick.y
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
