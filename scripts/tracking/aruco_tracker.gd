class_name NaretArucoTracker
extends Node3D
## Adapter for the pinned opencv_aruco addon's ArucoMarkerTracking node. All emitted poses are world poses.
signal pose_updated(pose: Transform3D)
signal status_changed(message: String)

@export_range(0, 49) var marker_id := 0
@export_range(0.01, 0.30, 0.001) var marker_size_m := 0.10
@export var desktop_preview := true
@export var preview_pose := Transform3D(Basis.IDENTITY, Vector3(0, 0, -1.2))
@export var provider_path: NodePath
@export var calibration_file := "user://calibration.cfg"
## Empty retains Denis's one-sternum-marker setup. A profile explicitly maps
## the older common marker to the virtual sternum marker expected by the anchor.
@export_file("*.cfg") var marker_layout_file := ""
var _layout: NaretMarkerLayout
var _layout_invalid := false
var _used_ids: Array[int] = []
var layout_position_spread_m := 0.0
var apply_temporal_filter := true

func has_full_marker_evidence() -> bool:
	if _layout != null:
		return _used_ids.size() == _layout.offsets.size()
	return _used_ids.has(marker_id)
const FRESHNESS_MS := 500.0

var tracked := false
var status := "initializing"
var latest_pose := Transform3D.IDENTITY
var _provider: Node
var _have_pose := false
var _last_detection_ms := -1
var _filter: RefCounted
var _camera: Camera3D
var _last_update_ms := 0
var _discard_next_detection := false
## Standby (camera off while the held pose is out of view) must never stick: the
## headset review 2026-10-29 found the camera closed for good after a reference-space
## update left a stale pose nowhere in view. Rescan briefly every few seconds.
const STANDBY_RESCAN_EVERY_S := 6.0
const STANDBY_RESCAN_FOR_S := 1.5
var _standby_s := 0.0
## Seconds since the marker was last seen; beyond this the camera never goes to standby.
const LOST_KEEP_SCANNING_S := 10.0
var _lost_s := 0.0

func _ready() -> void:
	_load_marker_configuration()
	# A recentre or stage update moves the world under the held pose: forget it and scan.
	if XRServer.has_signal("reference_frame_changed"):
		XRServer.reference_frame_changed.connect(forget_pose)
	if not marker_layout_file.is_empty():
		_layout = NaretMarkerLayout.new()
		_layout_invalid = _layout.load_profile(marker_layout_file) != OK
		if _layout_invalid:
			_set_status("marker_layout_invalid")
			return
		marker_size_m = _layout.marker_size_m
	var filter_path := "res://addons/naret_upstream/avatar/simple_pose_stabilizer.gd"
	if ResourceLoader.exists(filter_path):
		_filter = load(filter_path).new()
	if not provider_path.is_empty():
		bind_provider(get_node_or_null(provider_path))
		if _layout != null and _provider != null:
			_apply_marker_configuration(_provider)
	elif ClassDB.class_exists("OpenCVProcessor") and (not desktop_preview or OS.get_name() == "Android"):
		# Upstream's ArucoMarkerTracking node, unmodified: CameraX luma frames from passthrough
		# camera "50" at 640x480, ArucoNano, its own calibration. Loaded by path, never typed,
		# because desktop builds have no OpenCVProcessor class to parse it against.
		var path := "res://addons/opencv_aruco/aruco_marker_tracking.gd"
		if ResourceLoader.exists(path):
			var script: Script = load(path)
			var provider: Node = script.new()
			# The printed sternum marker is DICT_4X4_50; upstream defaults to ARUCO_MIP_36h12.
			provider.set("marker_dictionary", 1)
			_apply_marker_configuration(provider)
			provider.name = "ArucoMarkerTracking"
			bind_provider(provider)
			add_child(provider)
	if _provider == null:
		_set_status("desktop_preview" if desktop_preview and OS.get_name() != "Android" else "native_backend_missing")
		if desktop_preview and OS.get_name() != "Android":
			call_deferred("_publish_preview")

func bind_provider(provider: Node) -> bool:
	if provider == null or not provider.has_method("get_marker_world_pose") or not provider.has_method("marker_age_ms"):
		_set_status("provider_api_mismatch")
		return false
	if _provider != null and _provider.has_signal("markers_updated") and _provider.is_connected("markers_updated", _on_markers_updated):
		_provider.disconnect("markers_updated", _on_markers_updated)
	_provider = provider
	if _provider.has_signal("markers_updated"):
		_provider.connect("markers_updated", _on_markers_updated)
	_set_status("scanning_marker")
	return true

## The detector node, or null on the desktop preview. Debug overlays read raw poses from it.
func get_provider() -> Node:
	return _provider

func set_view_camera(camera: Camera3D) -> void:
	_camera = camera

func configure_marker(size_m: float, id: int) -> Error:
	# A layout's measured geometry must not be silently overwritten by the
	# single-marker controls. Edit/reload its profile as one calibrated unit.
	if _layout != null or _layout_invalid:
		return ERR_UNAVAILABLE
	if not is_finite(size_m) or size_m < 0.01 or size_m > 0.30 or id < 0 or id > 49:
		return ERR_INVALID_PARAMETER
	var changed := not is_equal_approx(marker_size_m, size_m) or marker_id != id
	marker_size_m = size_m
	marker_id = id
	if changed:
		_have_pose = false
		_set_tracked(false)
		_last_detection_ms = -1
		if _filter != null:
			_filter.call("reset")
		if _provider != null:
			_apply_marker_configuration(_provider)
			_provider.set("enabled", true)
			# One old-geometry worker result may still be in flight. Never apply it.
			_discard_next_detection = true
			_set_status("scanning_marker")
	var config := ConfigFile.new()
	config.load(calibration_file)
	config.set_value("marker", "size_m", marker_size_m)
	config.set_value("marker", "id", marker_id)
	return config.save(calibration_file)

func _load_marker_configuration() -> void:
	var config := ConfigFile.new()
	if config.load(calibration_file) != OK:
		return
	var size_m := float(config.get_value("marker", "size_m", marker_size_m))
	var id := int(config.get_value("marker", "id", marker_id))
	if is_finite(size_m) and size_m >= 0.01 and size_m <= 0.30 and id >= 0 and id <= 49:
		marker_size_m = size_m
		marker_id = id

func _apply_marker_configuration(provider: Node) -> void:
	provider.set("default_marker_size", marker_size_m)
	var sizes: Array[float] = []
	sizes.resize(50)
	sizes.fill(marker_size_m)
	provider.set("marker_sizes", sizes)

func _process(_delta: float) -> void:
	if _provider == null:
		return
	var fresh := false
	for id in _used_ids:
		var age := float(_provider.call("marker_age_ms", id))
		fresh = fresh or (_have_pose and age >= 0.0 and age <= FRESHNESS_MS)
	_set_tracked(fresh)
	if tracked:
		_lost_s = 0.0
	else:
		_lost_s += _delta
	var in_view := true
	if _camera != null and _have_pose:
		# Re-evaluate FOV every frame, so turning back toward the mannequin resumes scanning.
		in_view = _camera.is_position_in_frustum(latest_pose.origin)
		if in_view:
			_standby_s = 0.0
		else:
			_standby_s += _delta
		# While in standby, open the camera for a short rescan every few seconds. After a
		# long loss the held pose may be stale (mannequin moved): keep the camera on.
		var rescan := not in_view and fmod(_standby_s, STANDBY_RESCAN_EVERY_S) < STANDBY_RESCAN_FOR_S
		_provider.set("enabled", in_view or rescan or _lost_s > LOST_KEEP_SCANNING_S)
	# One status per frame (the old code set two, flickering the dashboard every frame).
	if tracked:
		_set_status("marker_tracked")
	elif _have_pose:
		_set_status("marker_lost_pose_held" if in_view or _lost_s > LOST_KEEP_SCANNING_S else "tracking_standby")

func _on_markers_updated(ids: Array) -> void:
	if _layout_invalid:
		return
	if _discard_next_detection:
		_discard_next_detection = false
		return
	var pose := Transform3D.IDENTITY
	if _layout != null:
		var poses := {}
		for id in ids:
			var age := float(_provider.call("marker_age_ms", id))
			if _layout.offsets.has(id) and age >= 0.0 and age <= FRESHNESS_MS:
				poses[id] = _provider.call("get_marker_world_pose", id)
		var result := _layout.fuse(poses)
		if result.is_empty():
			return
		pose = result.pose
		_used_ids.assign(result.ids)
		layout_position_spread_m = result.position_spread_m
	else:
		if not ids.has(marker_id):
			return
		var age := float(_provider.call("marker_age_ms", marker_id))
		if age < 0.0 or age > FRESHNESS_MS:
			return
		pose = _provider.call("get_marker_world_pose", marker_id)
		_used_ids.assign([marker_id])
	if not pose.is_finite() or absf(pose.basis.determinant()) < 0.001:
		return
	var now := Time.get_ticks_msec()
	var delta := clampf(float(now - _last_update_ms) / 1000.0, 0.001, 0.25)
	_last_update_ms = now
	_last_detection_ms = now
	if _filter != null and apply_temporal_filter:
		pose = _filter.call("update", pose, delta, now)
	latest_pose = pose
	_have_pose = true
	_set_tracked(true)
	pose_updated.emit(pose)

func forget_pose() -> void:
	## Drop the held pose (e.g. after a reference-frame change) and scan afresh.
	_have_pose = false
	_standby_s = 0.0
	_set_tracked(false)
	if _filter != null:
		_filter.call("reset")
	if _provider != null:
		_provider.set("enabled", true)
		_set_status("scanning_marker")
	print("NARET_TRACKING forget_pose: reference frame changed, scanning again")

func _publish_preview() -> void:
	latest_pose = preview_pose
	pose_updated.emit(preview_pose)
	# A preview pose must never masquerade as measured tracking.
	_set_tracked(false)

func _set_tracked(value: bool) -> void:
	if tracked == value:
		return
	tracked = value
	if not value and _filter != null:
		_filter.call("clear_measurement_history")

func _set_status(message: String) -> void:
	if status != message:
		status = message
		status_changed.emit(message)
