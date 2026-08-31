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
@export var xr_controller_left: XRController3D

const SAVE_PATH := "user://navel_calibration.cfg"
const DEFAULT_CALIBRATION_PATH := "res://default_navel_calibration.cfg"

# Runtime filter values. Provisional values are replaced after the labelled experiment.
const FILTER_WINDOW := 7
const FILTER_POSITION_DEAD_ZONE_M := 0.006
const FILTER_ROTATION_DEAD_ZONE_DEG := 0.5
const FILTER_SMOOTHING_TIME_S := 0.8
const FILTER_PRIOR_TIME_S := 8.0
# Endpoint stability is evaluated over a complete measurement-target window.
const ENDPOINT_STABLE_POSITION_M := 0.002
const ENDPOINT_STABLE_ROTATION_DEG := 0.5
const ENDPOINT_STABLE_DETECTIONS := 7

var _common_provider := CommonPoseProvider.new()
var _filter := SimplePoseStabilizer.new()
var _fresh := MarkerFreshness.new()
var _markers: Array = []
var _visible_now: Array = []
var _was_nudging := false
var _tracking_was_available := false
var _application_paused := false
var _runtime_initialized := false


func _ready() -> void:
	visible = false
	_markers = [common_marker, chest_marker, torso_marker]
	_filter.configure(
		FILTER_WINDOW,
		FILTER_POSITION_DEAD_ZONE_M,
		FILTER_ROTATION_DEAD_ZONE_DEG,
		FILTER_SMOOTHING_TIME_S,
		FILTER_PRIOR_TIME_S,
		ENDPOINT_STABLE_POSITION_M,
		ENDPOINT_STABLE_ROTATION_DEG,
		ENDPOINT_STABLE_DETECTIONS
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

	# Do not reveal a stale held pose. After startup, resume, or a complete tracking gap, show the
	# avatar only after the required fresh measurements have produced a confirmed pose.
	visible = (
		not _application_paused
		and _tracking_was_available
		and _filter.is_ready()
		and not _filter.is_reacquiring()
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

	var filtered_pose := _filter.update(
		raw_pose,
		delta,
		detection_ms,
		_common_provider.rest_pose(),
		_common_provider.has_rest_pose()
	)
	# Any movement can become the new rest; there is no minimum relocation distance. Re-anchor only
	# after the complete measurement-only target window is stationary.
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
		global_transform = filtered_pose


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
	print("Common pose: re-levelling; collecting 20+5 detection checkpoints.")


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
	if nudge != Vector3.ZERO:
		target.position += nudge
		_was_nudging = true
	elif _was_nudging:
		print("Final mannequin offset: ", target.position)
		_was_nudging = false


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
		for surface in mesh_instance.get_surface_override_material_count():
			var material := mesh_instance.get_active_material(surface)
			if material is BaseMaterial3D:
				var copy := material.duplicate() as BaseMaterial3D
				copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				copy.albedo_color = Color(avatar_tint, alpha)
				mesh_instance.set_surface_override_material(surface, copy)
