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
## A mirrored marker keeps its own last good pose this long. The mannequin is static, and this
## stops the average collapsing onto whichever marker happens not to flip from this viewpoint.
const FLIP_HOLD_MS := 1000
var rejected_flips := 0
var held_flips := 0
var _last_good := {}   # id -> {pose, ms}
var _marker_log_ms := -1000

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

## The ids the printed layout really uses; empty without a layout.
func get_layout_ids() -> Array:
	return _layout.offsets.keys() if _layout != null else []

## Detections per second at most (0 = unlimited). Applied to the provider when it has the
## property; the desktop preview provider has none.
var detection_rate := 0.0

func set_detection_rate(per_second: float) -> void:
	if is_equal_approx(per_second, detection_rate):
		return
	detection_rate = per_second
	if _provider != null and _provider.get("max_detections_per_second") != null:
		_provider.set("max_detections_per_second", per_second)
		print("NARET_DETECTION_RATE max_per_second=", per_second)

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

## What the camera sees while no marker is found (14 Nov 2026). The log of a session
## without any marker reading showed the camera delivering 60 frames a second and the
## detector looking at 35 of them, with no error anywhere: nothing in it says WHY no
## marker was in those frames. So while there has been no reading for 3 s, every 5 s
## one frame is measured (size, brightness, contrast) and saved as a picture next to
## the log, and one frame is saved while the marker IS tracked, to compare with.
const VIEW_AFTER_MS := 3000
const VIEW_EVERY_MS := 5000
const VIEW_KEEP := 24
var _view_count := 0
var _view_connected := false
var _view_ms := -100000
var _view_tracked_saved := false
var _other_ids_ms := -100000

func _connect_camera_view() -> void:
	var cam: Variant = _provider.get("_android_cam")
	if cam == null or not (cam is Object) or not cam.has_signal("camera_frame"): return
	cam.connect("camera_frame", _on_camera_view)
	_view_connected = true

func _on_camera_view(_timestamp_ns: int, data: PackedByteArray, width: int, height: int) -> void:
	var now := Time.get_ticks_msec()
	var searching := _last_detection_ms < 0 or now - _last_detection_ms >= VIEW_AFTER_MS
	if searching:
		if now - _view_ms < VIEW_EVERY_MS: return
	elif _view_tracked_saved: return
	if width <= 0 or height <= 0 or data.size() < width * height: return
	var total := 0
	var count := 0
	var darkest := 255
	var brightest := 0
	var dark := 0
	var bright := 0
	for y in range(0, height, 8):
		for x in range(0, width, 8):
			var value := data[y * width + x]
			total += value
			count += 1
			darkest = mini(darkest, value)
			brightest = maxi(brightest, value)
			if value < 40: dark += 1
			if value > 215: bright += 1
	var picture := Image.create_from_data(width, height, false, Image.FORMAT_L8, data.slice(0, width * height))
	if searching:
		_view_ms = now
		# The last VIEW_KEEP pictures are kept: a single file was overwritten by the
		# view of the bed once the headset was put down.
		picture.save_png("user://logs/camera_view_searching_%02d.png" % (_view_count % VIEW_KEEP))
		_view_count += 1
		print("NARET_CAMERA_VIEW searching picture=%02d size=%dx%d mean=%d darkest=%d brightest=%d dark_pct=%d bright_pct=%d enabled=%s" % [(_view_count - 1) % VIEW_KEEP, width, height, total / count, darkest, brightest, dark * 100 / count, bright * 100 / count, str(_provider.get("enabled"))])
	else:
		_view_tracked_saved = true
		picture.save_png("user://logs/camera_view_tracked.png")
		print("NARET_CAMERA_VIEW tracked size=%dx%d mean=%d darkest=%d brightest=%d dark_pct=%d bright_pct=%d" % [width, height, total / count, darkest, brightest, dark * 100 / count, bright * 100 / count])

func _process(_delta: float) -> void:
	if _provider == null:
		return
	if not _view_connected: _connect_camera_view()
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
		var now_ms := Time.get_ticks_msec()
		if now_ms - _other_ids_ms >= 2000:
			for id in ids:
				if not _layout.offsets.has(id):
					# A marker is seen, but not one of this patient's: say which.
					_other_ids_ms = now_ms
					var where: Transform3D = _provider.call("get_marker_world_pose", id)
					print("NARET_MARKER_OTHER seen=", ids, " expected=", _layout.offsets.keys(), " at=", where.origin)
					break
		for id in ids:
			var age := float(_provider.call("marker_age_ms", id))
			if _layout.offsets.has(id) and age >= 0.0 and age <= FRESHNESS_MS:
				var raw: Transform3D = _provider.call("get_marker_world_pose", id)
				var good := _usable_pose(id, raw)
				if not good.is_empty():
					poses[id] = good.pose
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

func _usable_pose(id: int, raw: Transform3D) -> Dictionary:
	## {pose} for this reading, its last good pose if it is mirrored, or {} to leave it out.
	var now := Time.get_ticks_msec()
	var flipped := _layout.is_flipped(id, raw)
	if now - _marker_log_ms >= 1000:
		_marker_log_ms = now
	if now - _marker_log_ms < 100:
		# One burst per second: each marker's own estimate, so a disagreeing one can be named.
		print("NARET_MARKER_EST id=%d est=%s tilt_deg=%.0f flipped=%s rejected=%d held=%d" % [id, (raw * _layout.offsets[id]).origin, _layout.tilt_deg(id, raw), flipped, rejected_flips, held_flips])
	if not flipped:
		_last_good[id] = {"pose": raw, "ms": now}
		return {"pose": raw}
	rejected_flips += 1
	var last: Dictionary = _last_good.get(id, {})
	if not last.is_empty() and now - int(last.ms) <= FLIP_HOLD_MS:
		held_flips += 1
		return {"pose": last.pose}
	return {}

func set_camera_streaming(active: bool) -> void:
	## Stop or restart the Android camera stream itself. The provider's `enabled` flag only
	## drops frames in GDScript; the Java side keeps capturing and queues every frame for
	## the engine loop. Three out-of-memory crashes (2026-11-03) filled 512 MB in ~45 s while
	## the headset session was not focused and rendering had stopped consuming that queue.
	if _provider == null:
		return
	var cam: Variant = _provider.get("_android_cam")
	if cam == null:
		return
	var started := bool(_provider.get("_android_cam_started"))
	if active and not started:
		_provider.call("_start_android_camera")
	elif not active and started:
		cam.call("stop_camera")
		_provider.set("_android_cam_started", false)
	print("NARET_CAMERA streaming=", active)

## Called from the watchdog THREAD while the main loop is stalled (headset asleep or
## session paused): stop the Java camera directly through its singleton, bypassing the
## scene tree. The frames would otherwise queue in Java memory until the process dies.
func stop_camera_from_thread() -> void:
	if not Engine.has_singleton("GodotAndroidCamera"):
		return
	Engine.get_singleton("GodotAndroidCamera").stopCamera()
	print("NARET_CAMERA stopped by watchdog (main loop stalled)")

## Main-thread follow-up after a watchdog stop: restart the stream unless it is parked.
func restart_camera_after_stall() -> void:
	if _provider == null:
		return
	_provider.set("_android_cam_started", false)
	set_camera_streaming(true)

func forget_pose() -> void:
	_last_good.clear()
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
