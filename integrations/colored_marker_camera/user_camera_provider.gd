extends Node3D
## Adapted from release/v61-no0937-20261001 camera worker.
## Explicit raw intrinsics; no focal, vector, or far-range scaling.
signal markers_updated(ids: Array)
var enabled := true
var default_marker_size := 0.10
var marker_sizes: Array[float] = []
var image_downscale_factor := 0.5

var processor
var _native_pose_correction := Transform3D.IDENTITY
var marker_nodes: Dictionary = {}
@export var show_marker_gizmos := true
const MarkerPoseGizmo = preload("res://scripts/tracking/marker_pose_gizmo.gd")

# Physical side length of the ArUco marker, in meters. Single source of truth: used as the
# solvePnP marker size (sets the pose's metric scale) AND as the rendered cuboid's side length
# (see _ready), so the two can never disagree.
var aruco_patch_size := 0.10


# Godot has a native CameraServer (Camera2) backend on Android since 4.5, so
# CameraServerExtension is only needed on desktop (Windows). Keep this var UNTYPED and
# instantiate via ClassDB so the script still parses on Android, where the
# CameraServerExtension class isn't registered.
var camera_extension
var cam_texture: CameraTexture
var _chroma_texture: CameraTexture
var _colour_viewport: SubViewport
var _capture_check_s := 0.0
var _prefer_luminance := false
var _detector_misses := 0
var cam_preview := TextureRect.new()
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D

# --- Detection worker thread (Teil B) ---
# On the Quest the OpenCV detection costs ~80ms, which run synchronously would cap the whole
# app at ~10fps. We move ONLY the detection (detectMarkers + solvePnP) onto a background thread;
# get_image() and all scene-tree writes stay on the main thread (neither is thread-safe).
var _detect_thread: Thread
var _detect_mutex: Mutex
var _detect_sem: Semaphore
var _detect_exit := false
# input slot (main -> worker), guarded by _detect_mutex; only the newest frame is kept (frame drop)
var _pending_image: Image
var _pending_cam_xform: Transform3D
var _has_pending := false
# output slot (worker -> main), guarded by _detect_mutex
var _result_markers: Dictionary = {}
var _result_cam_xform: Transform3D
var _has_result := false

# --- Capture-latency compensation ---
# The Image get_image() returns is OLDER than "now": sensor -> ISP -> CameraServer texture takes
# 1-2 camera frames (~30-100ms). Pairing those old pixels with the LIVE head pose bakes an error
# proportional to head speed, so a fresh detection first "drags" with the head, then settles.
# We keep a short timestamped head-pose history and pair each frame with the pose from
# CAMERA_LATENCY_MS ago instead. Tune on device: patch still drags WITH the head -> raise;
# patch lags behind the real marker during motion -> lower.
const CAMERA_LATENCY_MS := 50.0
var _pose_history: Array = []   # [t_usec, head Transform3D] pairs, newest last; main thread only

# Debug only: stream the camera image to a laptop viewer over adb reverse. Off in normal use --
# on the Quest nothing listens, so an always-on stream just reconnects every second, polls the
# socket every frame and spams logcat. Enable from the scene when you actually want the viewer.
@export var stream_camera_to_laptop := false
const TCP_HOST := "127.0.0.1"
const TCP_PORT := 7007			#view available ports with adb reverse --list

var stream_peer: StreamPeerTCP
var _tcp_reconnect_timer := 0.0
var _last_tcp_status := -1
var _tcp_send_timer := 0.0
const TCP_SEND_INTERVAL := 0.01

#######################################################################################################

func _ready() -> void:
	add_child(cam_preview)
	cam_preview.visible = false
	if ClassDB.class_exists("OpenCVProcessor"):
		processor = ClassDB.instantiate("OpenCVProcessor")
		if processor.has_method("detect_markers"):
			processor.set("camera_intrinsics", Vector4(877.06583568, 878.33, 645.36226952, 642.24557861))
			processor.set("camera_distortion", PackedFloat64Array())
			processor.set("image_downscale_factor", 1.0)
			processor.set("lens_rotation_raw", Quaternion(-0.99519097805023, 0.00269138417207, 0.00294101587497, 0.09787271916866))
			processor.set("lens_translation", Vector3(-0.03237725794315, -0.01770938560367, -0.06345107406378))
			processor.set("aruco_patch_size", aruco_patch_size)
			processor.set("aruco_patch_sizes", PackedFloat64Array(marker_sizes))
			processor.set("marker_dictionary", 1) # Existing DICT_4X4_50 print, not MIP36h12.
			# Match the previous provider's lens transform exactly. The addon builds
			# its own lens pose from the raw quaternion; the old path used an inverse.
			# Remove the addon's lens pose before applying the old one, rather than
			# compensating for this convention change with a new saved model offset.
			if processor.has_method("get_lens_pose"):
				var native_lens: Transform3D = processor.call("get_lens_pose")
				var raw := Quaternion(-0.99519097805023, 0.00269138417207, 0.00294101587497, 0.09787271916866)
				var old_rotation := (raw * Quaternion(1, 0, 0, 0)).inverse()
				var old_lens := Transform3D(Basis(old_rotation), Vector3(-0.03237725794315, -0.01770938560367, -0.06345107406378))
				_native_pose_correction = old_lens * native_lens.affine_inverse()
				print("NARET_NATIVE_LENS compatibility correction=", _native_pose_correction)
			else:
				push_error("New detector lacks get_lens_pose; lens compatibility cannot be verified.")
				return
	else:
		push_warning("OpenCVProcessor is unavailable on this platform.")
		return

	for id in range(3):
		var patch := Node3D.new()
		patch.name = "aruco_patch%d" % id
		xr_origin.add_child(patch)
		marker_nodes[id] = patch
		MarkerPoseGizmo.attach_to(patch, id)
	# Spin up the detection worker. processor and marker_nodes are ready by now; the loop only
	# needs the processor (no scene-tree access), so it is safe to start before any feed exists.
	_detect_mutex = Mutex.new()
	_detect_sem = Semaphore.new()
	_detect_thread = Thread.new()
	_detect_thread.start(_detection_loop)

	if OS.get_name() == "Android":
		# Quest: request camera access; the native CameraServer surfaces feeds once granted.
		OS.request_permission("android.permission.CAMERA")
		OS.request_permission("horizonos.permission.HEADSET_CAMERA")
	elif ClassDB.class_exists("CameraServerExtension"):
		# Desktop (Windows): custom backend that registers the webcam as a feed.
		camera_extension = ClassDB.instantiate("CameraServerExtension")  # keep reference alive

	# Since Godot 4.5, monitoring_feeds must be true before feeds are enumerated.
	CameraServer.monitoring_feeds = true
	CameraServer.camera_feeds_updated.connect(_on_camera_feeds_updated)
	_on_camera_feeds_updated()                          # in case a feed is already present

	if stream_camera_to_laptop:
		_connect_tcp()

func _on_camera_feeds_updated() -> void:
	if cam_texture != null:
		return                                          # already initialised
	var feed_count := CameraServer.get_feed_count()
	if feed_count == 0:
		return

	# log every available feed so we can see which index is the (passthrough) camera on Quest
	for i in range(feed_count):
		var f := CameraServer.get_feed(i)
		print("camera feed index ", i, " id ", f.get_id(), " name ", f.get_name())

	# Quest exposes 3 feeds: "1 | FRONT" plus the passthrough pair "50 | BACK" / "51 | BACK".
	# The world-facing ("BACK") cameras are the passthrough ones we want; feed 0 (FRONT) is the
	# wrong camera. Desktop has a single feed, so it falls through to 0.
	var feed: CameraFeed = null
	for i in range(feed_count):
		var f := CameraServer.get_feed(i)
		if "BACK" in f.get_name():
			feed = f
			break
	if feed == null:
		feed = CameraServer.get_feed(0)

	# Format MUST be chosen before activating, else "format index -1" and no frames.
	var formats := feed.get_formats()
	for j in range(formats.size()):
		print("feed format ", j, ": ", formats[j])
	if formats.size() > 10:
		feed.set_format(10, {})        # feed format:2 640x480 YUV_420_888 (for now, choice can be altered) (good ArUco res, light on CPU)
	elif formats.size() > 0:
		feed.set_format(0, {})

	feed.set_active(true)                               # start delivering frames
	cam_texture = CameraTexture.new()
	cam_texture.camera_feed_id = feed.get_id()
	cam_texture.which_feed = CameraServer.FEED_RGBA_IMAGE
	cam_preview.texture = cam_texture
	if OS.get_name() == "Android" and orange_blue_markers:
		_chroma_texture = CameraTexture.new()
		_chroma_texture.camera_feed_id = feed.get_id()
		_chroma_texture.which_feed = CameraServer.FEED_CBCR_IMAGE
		_colour_viewport = SubViewport.new()
		_colour_viewport.disable_3d = true
		_colour_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_colour_viewport.size = Vector2i(1280, 1280)
		add_child(_colour_viewport)
		var surface := TextureRect.new()
		surface.texture = cam_texture
		surface.size = Vector2(1280, 1280)
		var material := ShaderMaterial.new()
		material.shader = preload("res://scripts/tracking/colored_camera.gdshader")
		material.set_shader_parameter("chroma_texture", _chroma_texture)
		surface.material = material
		_colour_viewport.add_child(surface)
	print("camera feeds: ", feed_count)

####################################################################################################

func _process(_delta: float) -> void:
	# A hidden/lost marker must not leave a misleading old diagnostic gizmo.
	for id in marker_nodes:
		marker_nodes[id].visible = show_marker_gizmos and marker_age_ms(id) <= 500.0
	if stream_camera_to_laptop:
		_poll_tcp(_delta)

	if cam_texture == null:
		return

	# (a) Apply the latest finished detection (main thread -> scene-tree writes are safe here).
	# markers + cam_xform come from the worker; cam_xform was sampled at the frame's CAPTURE time
	# (not now), so the world bake matches the frame the markers were detected in -- using the
	# live head pose here would re-introduce the ~80ms of head motion as swim.
	_detect_mutex.lock()
	var have_result := _has_result
	var markers: Dictionary = _result_markers
	var cam_xform: Transform3D = _result_cam_xform
	_has_result = false
	_detect_mutex.unlock()
	if have_result:
		# One OpenCV result comes from one camera image, so every marker in it must carry the same
		# result timestamp. Calling the clock separately inside the loop could give same-frame
		# markers adjacent millisecond values and force downstream code to guess a tolerance.
		var result_timestamp_ms := Time.get_ticks_msec()
		for id in markers:
			if marker_nodes.has(id):
				# markers[id] is the marker pose in CAMERA space; cam_xform is the head pose at
				# capture time. Bake to world space and freeze it there, so the head can move
				# between detections without dragging the patch along.
				var marker_cam: Transform3D = markers[id]
				marker_nodes[id].global_transform = cam_xform * marker_cam
				marker_nodes[id].set_meta("last_detected_ms", result_timestamp_ms)
				marker_nodes[id].visible = show_marker_gizmos

		markers_updated.emit(markers.keys())

	# (b) Hand the newest camera frame to the worker. get_image() (the GPU->CPU readback) and the
	# head-pose snapshot must happen on the main thread; the worker only does the OpenCV work.
	var img := cam_texture.get_image()
	# USB diagnostics are opt-in and one-shot, never a continuous image logger.
	_capture_check_s += _delta
	var capture_requested := false
	if _capture_check_s >= 1.0:
		_capture_check_s = 0.0
		capture_requested = FileAccess.file_exists("user://marker_capture.request")
	if capture_requested and img != null and img.get_width() > 4:
		img.save_png("user://marker_capture_input.png")
	if _colour_viewport != null and img != null and img.get_width() > 4:
		# Search both input modes when no markers are found. Warm room lighting
		# can make white paper look orange; raw luminance preserves that print.
		var camera_material := (_colour_viewport.get_child(0) as TextureRect).material as ShaderMaterial
		camera_material.set_shader_parameter("luminance_only", _prefer_luminance)
		if _colour_viewport.size != img.get_size():
			_colour_viewport.size = img.get_size()
			(_colour_viewport.get_child(0) as TextureRect).size = Vector2(img.get_size())
			return # wait for a render at the new resolution
		img = _colour_viewport.get_texture().get_image()
	if img == null:
		return
	if capture_requested and img.get_width() > 4:
		var capture_error := img.save_png("user://marker_capture_detector.png")
		if capture_error == OK:
			DirAccess.remove_absolute("user://marker_capture.request")
		print("NARET_CAPTURE result=", capture_error, " size=", img.get_size(), " format=", img.get_format())
	if stream_camera_to_laptop:
		_tcp_send_timer += _delta
		if _tcp_send_timer >= TCP_SEND_INTERVAL:
			_tcp_send_timer = 0.0
			if stream_peer != null and stream_peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				_send_frame_tcp(img)

	# Head pose AT capture time: NOT the live pose -- the pixels in img are ~CAMERA_LATENCY_MS old
	# (passthrough pipeline), so look that far back in the pose history (see _head_pose_at).
	var now_usec := Time.get_ticks_usec()
	_pose_history.append([now_usec, xr_camera.global_transform])
	while _pose_history.size() > 1 and _pose_history[0][0] < now_usec - 500_000:
		_pose_history.pop_front()
	var cap_cam_xform := _head_pose_at(now_usec - int(CAMERA_LATENCY_MS * 1000.0))

	_detect_mutex.lock()
	var was_pending := _has_pending
	_pending_image = img                                # overwrites any unconsumed frame -> frame drop
	_pending_cam_xform = cap_cam_xform
	_has_pending = true
	_detect_mutex.unlock()
	if not was_pending:
		_detect_sem.post()                                 # only wake once per pending frame (bounded sem)

# Worker thread: blocks on the semaphore, runs OpenCV detection off the main thread, and parks the
# result for _process to apply. Touches only `processor` and value types -- never the scene tree.
@export var orange_blue_markers := true
@export var colour_diagnostics := false
const ColoredMarkerImage = preload("res://scripts/tracking/colored_marker_image.gd")
var _colour_debug_last_ms := -10000
var _detector_log_last_ms := -10000

func _detection_loop() -> void:
	while true:
		_detect_sem.wait()
		if _detect_exit:
			return
		_detect_mutex.lock()
		var img: Image = _pending_image
		var cam_xform: Transform3D = _pending_cam_xform
		_has_pending = false
		_pending_image = null
		_detect_mutex.unlock()
		if img == null:
			continue
		# No conversion: the C++ side handles 1ch (Quest Y-plane), 3ch (RGB), and 4ch (RGBA).
		# Captured orange/blue frame decoded ID 0 at 1280px; 640px lost it.
		# Intrinsics below use the same factor, preserving metric pose scale.
		var image_downscale_factor = 1.0 if orange_blue_markers else 0.5
		# Raw calibrated intrinsics: range scaling disabled for this build.
		var fx=877.06583568*image_downscale_factor
		var fy=878.33*image_downscale_factor
		var cx=645.36226952*image_downscale_factor #approxiamte cx is fx/2
		var cy=642.24557861*image_downscale_factor #approxiamte cy is fy/2
		# Physical passthrough-camera pose relative to the gyro/IMU reference, from the Quest's
		# ACAMERA_LENS_POSE_ROTATION / _TRANSLATION (LENS_POSE_REFERENCE == GYROSCOPE).
		# The raw quaternion is ~168.8deg about X = the Android sensor->camera-optical 180deg X-flip
		# PLUS the camera's real ~11deg pitch. The C++ marker pose already contains that same 180deg
		# flip (its negate-Y/Z change of basis), so multiply by Quaternion(1,0,0,0) (=180deg about X)
		# to cancel the flip and keep ONLY the physical mounting tilt.
		# The translation is in the sensor frame (X right, Y up, Z toward viewer), which matches Godot
		# camera axes -> use raw values, no sign flips.
		var lens_q_raw := Quaternion(-0.99519097805023, 0.00269138417207, 0.00294101587497, 0.09787271916866)
		var lens_rotation := (lens_q_raw * Quaternion(1, 0, 0, 0)).inverse() # if visibly worse, try appending .inverse()
		var lens_translation := Vector3(-0.03237725794315, -0.01770938560367, -0.06345107406378) # raw LENS_POSE_TRANSLATION

		if orange_blue_markers and colour_diagnostics:
			var debug_now := Time.get_ticks_msec()
			var capture_debug := debug_now - _colour_debug_last_ms >= 5000
			if capture_debug:
				_colour_debug_last_ms = debug_now
				img.save_png("user://marker_colour_raw.png")
				print("NARET_MARKER_IMAGE format=", img.get_format(), " size=", img.get_size())
			if capture_debug: img.save_png("user://marker_colour_processed.png")
		if orange_blue_markers and _colour_viewport == null:
			img = ColoredMarkerImage.convert(img)
		var markers: Dictionary
		var began := Time.get_ticks_usec()
		if processor.has_method("detect_markers"):
			# Configuration can be loaded after _ready(). Apply it in the worker,
			# which is the only thread that calls the native detector.
			processor.set("aruco_patch_size", default_marker_size)
			processor.set("aruco_patch_sizes", PackedFloat64Array(marker_sizes))
			processor.set("image_downscale_factor", image_downscale_factor)
			# Identity head pose returns camera-reference poses including lens offset.
			# The existing capture-time world bake below applies cam_xform exactly once.
			img.convert(Image.FORMAT_L8)
			var corners := {}
			markers = processor.call("detect_markers", img, Transform3D.IDENTITY, corners)
			for id in markers:
				markers[id] = _native_pose_correction * markers[id]
		else:
			markers = processor.get_6dof_of_all_aruco_patches_from_godot_image(img, aruco_patch_size,image_downscale_factor,fx,fy,cx,cy,lens_rotation,lens_translation)
		if _colour_viewport != null:
			if markers.is_empty():
				_detector_misses += 1
				if _detector_misses >= 5:
					_prefer_luminance = not _prefer_luminance
					_detector_misses = 0
					print("NARET_INPUT_MODE luminance_only=", _prefer_luminance)
			else:
				_detector_misses = 0
		if Time.get_ticks_msec() - _detector_log_last_ms >= 2000:
			_detector_log_last_ms = Time.get_ticks_msec()
			print("NARET_DETECTOR ms=", (Time.get_ticks_usec() - began) / 1000.0, " ids=", markers.keys())
		_detect_mutex.lock()
		_result_markers = markers
		_result_cam_xform = cam_xform
		_has_result = true
		_detect_mutex.unlock()


# Newest recorded head pose that is not newer than t_usec (nearest-older sample; at 72fps the
# history has ~14ms granularity). Falls back to the oldest entry (or the live pose) while the
# history is still filling up.
func _head_pose_at(t_usec: int) -> Transform3D:
	for i in range(_pose_history.size() - 1, -1, -1):
		if _pose_history[i][0] <= t_usec:
			return _pose_history[i][1]
	if _pose_history.is_empty():
		return xr_camera.global_transform
	return _pose_history[0][1]



func _exit_tree() -> void:
	# Wake the worker out of its wait() and join it, so the thread doesn't outlive the scene.
	if _detect_thread != null and _detect_thread.is_started():
		_detect_mutex.lock()
		_detect_exit = true
		_detect_mutex.unlock()
		_detect_sem.post()
		_detect_thread.wait_to_finish()

func _send_frame_tcp(img: Image) -> void:
	if stream_peer == null:
		return

	stream_peer.poll()

	if stream_peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return

	var bytes: PackedByteArray = img.get_data()

	stream_peer.put_u32(img.get_width())
	stream_peer.put_u32(img.get_height())
	stream_peer.put_u32(img.get_format())
	stream_peer.put_u32(bytes.size())

	var err := stream_peer.put_data(bytes)
	if err != OK:
		print("TCP put_data error: ", err)

func _connect_tcp() -> void:
	stream_peer = StreamPeerTCP.new()
	stream_peer.big_endian = true

	var err := stream_peer.connect_to_host(TCP_HOST, TCP_PORT)
	print("TCP connect_to_host err: ", err)

	if err != OK:
		print("TCP connect_to_host failed immediately: ", err)


func _poll_tcp(delta: float) -> void:
	if stream_peer == null:
		_connect_tcp()
		return

	stream_peer.poll()

	var status := stream_peer.get_status()

	if status != _last_tcp_status:
		print("TCP status changed: ", _last_tcp_status, " -> ", status)
		_last_tcp_status = status

	if status == StreamPeerTCP.STATUS_CONNECTED:
		_tcp_reconnect_timer = 0.0
		return

	if status == StreamPeerTCP.STATUS_CONNECTING:
		return

	if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
		_tcp_reconnect_timer += delta
		if _tcp_reconnect_timer >= 1.0:
			_tcp_reconnect_timer = 0.0
			print("TCP reconnecting...")
			_connect_tcp()
#command to stop (once adb is added to PATH)
# adb shell am force-stop com.example.godotcpptemplate

func get_marker_world_pose(id: int) -> Transform3D:
	return marker_nodes[id].global_transform if marker_nodes.has(id) else Transform3D.IDENTITY

func marker_age_ms(id: int) -> float:
	if not marker_nodes.has(id) or not marker_nodes[id].has_meta("last_detected_ms"): return INF
	return float(Time.get_ticks_msec() - int(marker_nodes[id].get_meta("last_detected_ms")))
