extends Node
## Depth-probe experiment: compare the Quest environment-depth range with the ArUco range at the
## same marker. The two disagree by a constant ~6.3% in every recording; this says which side.
##
## Every sample_interval_s it snapshots the newest ArUco result, asks the Meta extension for the
## depth map (CPU readback, so never every frame), projects the marker's world position into the
## depth image, un-projects the sampled depth back to a world point and prints:
##   DEPTHPROBE aruco=<m> depth=<m> ratio=<depth/aruco> gap=<cm> ...
## ratio ~1.00 -> ArUco range is right (the 0.937 belongs to head tracking).
## ratio ~0.94 -> ArUco range was 6.7% long (the 0.937 belongs in fx). Runs in logcat + label.

## Experiment switch. Off = this node does nothing at all (no permission request, no depth).
@export var enabled := true
@export var detection_source: Node          # main_3d: owns _detect_mutex / _result_markers
@export var status_label: Label3D            # optional in-headset readout
@export var marker_id := 0                   # common / ID0
@export_range(0.25, 5.0, 0.25) var sample_interval_s := 1.0

const EXTENSION := "OpenXRMetaEnvironmentDepthExtension"
const SCENE_PERMISSION := "com.oculus.permission.USE_SCENE"
const HISTORY := 30
## Environment depth is started only after the XR session is FOCUSED (headset worn, app in front)
## plus this settle time. Starting it while the headset was asleep (2026-09-15 10:54 launch) made
## the Meta runtime abort the whole process inside xrCreateEnvironmentDepthSwapchainMETA
## ("Failed to import swapchain IPC textures"); the same call works fine once the MR services run.
const FOCUS_SETTLE_S := 3.0

var _ext: Object = null
var _permission_granted := false
var _session_focused := false
var _focus_settle_s := 0.0
var _started := false
var _since_sample_s := 0.0
var _pending := false
var _snap_marker_world := Vector3.ZERO
var _snap_head := Vector3.ZERO
var _ratios: Array[float] = []
var _samples := 0
var _reported_format := false


func _ready() -> void:
	if not enabled:
		return
	if not Engine.has_singleton(EXTENSION):
		_status("Depth probe: %s not available on this platform." % EXTENSION)
		return
	_ext = Engine.get_singleton(EXTENSION)
	_ext.connect("openxr_meta_environment_depth_started", _on_started)
	var xr := XRServer.find_interface("OpenXR")
	if xr != null:
		xr.session_focussed.connect(_on_session_focused)
		xr.session_visible.connect(_on_session_unfocused)
		xr.session_stopping.connect(_on_session_unfocused)
	# USE_SCENE is a runtime permission on Quest; environment depth stays unsupported until granted.
	get_tree().on_request_permissions_result.connect(_on_permission)
	if OS.request_permission(SCENE_PERMISSION):
		_permission_granted = true


func _on_session_focused() -> void:
	_session_focused = true
	_focus_settle_s = 0.0


func _on_session_unfocused() -> void:
	_session_focused = false


func _on_permission(permission: String, granted: bool) -> void:
	if permission == SCENE_PERMISSION:
		_permission_granted = granted
		_status("Depth probe: %s %s" % [permission, "granted" if granted else "DENIED"])
		_try_start()


func _try_start() -> void:
	if _ext == null or _started or not _session_focused or not _permission_granted:
		return
	if _focus_settle_s < FOCUS_SETTLE_S:
		return
	if not _ext.call("is_environment_depth_supported"):
		_status("Depth probe: environment depth not supported (permission? Quest 3?)")
		return
	_ext.call("start_environment_depth")


func _on_started() -> void:
	_started = true
	_status("Depth probe: environment depth started.")


func _process(delta: float) -> void:
	if not _started:
		if _session_focused and _permission_granted:
			_focus_settle_s += delta
			_try_start()
		return
	if _pending:
		return
	_since_sample_s += delta
	if _since_sample_s < sample_interval_s:
		return
	_since_sample_s = 0.0
	if not _snapshot_marker():
		return
	_pending = true
	_ext.call("get_environment_depth_map_async", _on_depth_map)


## Same copy protocol as aruco_csv_logger: lock the worker's mutex, copy, unlock.
func _snapshot_marker() -> bool:
	if detection_source == null:
		return false
	var mutex: Mutex = detection_source.get("_detect_mutex")
	if mutex == null:
		return false
	mutex.lock()
	var markers: Dictionary = detection_source.get("_result_markers")
	var cam_xform: Transform3D = detection_source.get("_result_cam_xform")
	var marker: Variant = markers.get(marker_id)
	mutex.unlock()
	if marker == null:
		return false
	# Marker pose is head-relative; the head transform sampled at capture bakes it to world.
	_snap_marker_world = cam_xform * (marker as Transform3D).origin
	_snap_head = cam_xform.origin
	return true


func _on_depth_map(views: Array) -> void:
	_pending = false
	if views.is_empty():
		return
	var data: Dictionary = views[0]                       # left eye
	var img: Image = data["image"]
	var proj: Projection = data["depth_projection_view"]
	var inv: Projection = data["depth_inverse_projection_view"]
	if img == null or img.is_empty():
		return
	var w := img.get_width()
	var h := img.get_height()
	if not _reported_format:
		_reported_format = true
		print("DEPTHPROBE_FORMAT views=%d keys=%s image=%dx%d format=%d proj=%s" % [views.size(), str(data.keys()), w, h, img.get_format(), str(proj)])

	var clip := proj * Vector4(_snap_marker_world.x, _snap_marker_world.y, _snap_marker_world.z, 1.0)
	if clip.w <= 0.0:
		return
	var ndc := Vector3(clip.x, clip.y, clip.z) / clip.w
	if absf(ndc.x) > 1.0 or absf(ndc.y) > 1.0:
		_status("Depth probe: marker outside depth view (ndc %.2f, %.2f)" % [ndc.x, ndc.y])
		return
	var px := clampi(int((ndc.x * 0.5 + 0.5) * w), 1, w - 2)
	var py_up := clampi(int((ndc.y * 0.5 + 0.5) * h), 1, h - 2)   # NDC y up == image row 0 at bottom
	var py_dn := h - 1 - py_up                                    # image row 0 at top

	# The docs do not pin down the row order or whether raw D16 maps to NDC z in [0,1] or [-1,1].
	# Wrong choices are off by far more than the 6.7% under test, so pick the combination whose
	# un-projected point lands nearest the marker and report which one it was.
	var best_gap := INF
	var best := {}
	for flip in [false, true]:
		var raw := _median_depth(img, px, py_dn if flip else py_up)
		if raw <= 0.0 or raw >= 0.9999:
			continue
		for zmode in [0, 1]:
			var ndc_z := (raw * 2.0 - 1.0) if zmode == 0 else raw
			var p4 := inv * Vector4(ndc.x, ndc.y, ndc_z, 1.0)
			if absf(p4.w) < 1e-9:
				continue
			var world := Vector3(p4.x, p4.y, p4.z) / p4.w
			var gap := world.distance_to(_snap_marker_world)
			if gap < best_gap:
				best_gap = gap
				best = {"world": world, "raw": raw, "flip": flip, "zmode": zmode}
	if best.is_empty():
		# Diagnostics: what IS in the texture around both candidate rows, and overall.
		var centre_raw := img.get_pixel(w / 2, h / 2).r
		var valid := 0
		var lo := INF
		var hi := -INF
		for yy in range(0, h, 8):
			for xx in range(0, w, 8):
				var v := img.get_pixel(xx, yy).r
				lo = minf(lo, v)
				hi = maxf(hi, v)
				if v > 0.0 and v < 0.9999:
					valid += 1
		var sampled := (h / 8) * (w / 8)
		_status("Depth probe: no valid depth at marker px=%d rows(up=%d,down=%d) raw(up=%.4f,down=%.4f) ndc=(%.2f,%.2f) centre=%.4f img=%dx%d valid=%d/%d min=%.4f max=%.4f"
			% [px, py_up, py_dn, img.get_pixel(px, py_up).r, img.get_pixel(px, py_dn).r, ndc.x, ndc.y, centre_raw, w, h, valid, sampled, lo, hi])
		return

	var aruco_range := _snap_marker_world.distance_to(_snap_head)
	var depth_range := (best["world"] as Vector3).distance_to(_snap_head)
	var ratio := depth_range / aruco_range
	_ratios.append(ratio)
	if _ratios.size() > HISTORY:
		_ratios.pop_front()
	_samples += 1
	var sorted := _ratios.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2]

	print("DEPTHPROBE aruco=%.3f depth=%.3f ratio=%.3f gap=%.1fcm raw=%.4f px=(%d,%d) img=%dx%d yflip=%d zmode=%d n=%d median=%.3f"
		% [aruco_range, depth_range, ratio, best_gap * 100.0, best["raw"], px, py_dn if best["flip"] else py_up,
		   w, h, int(best["flip"]), best["zmode"], _samples, median])
	_status("depth/aruco %.3f  (median %.3f, n=%d)\naruco %.2f m  depth %.2f m" % [ratio, median, _samples, aruco_range, depth_range])


## 3x3 median of the raw depth around the pixel; ignores clear/far texels.
func _median_depth(img: Image, px: int, py: int) -> float:
	var vals: Array[float] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var v := img.get_pixel(px + dx, py + dy).r
			if v > 0.0 and v < 0.9999:
				vals.append(v)
	if vals.is_empty():
		return 0.0
	vals.sort()
	return vals[vals.size() / 2]


func _status(text: String) -> void:
	print(text)
	if status_label != null:
		status_label.text = text
