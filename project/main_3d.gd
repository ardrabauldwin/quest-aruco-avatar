# Scene root.
#
# This file used to BE the detection pipeline: ~340 lines of camera-feed selection, the GPU->CPU
# readback, a hand-rolled Thread with its mutex and semaphore, the pose history with its
# CAMERA_LATENCY_MS guess, the nine-argument OpenCV call with its inlined intrinsics, and a TCP
# frame streamer. All of that is the opencv_aruco addon now -- ArucoMarkerTracking, a sibling node
# in this scene -- including two things this code could not do at all:
#
#   * the CameraX push path: Y-plane bytes arrive on the CPU with the frame's real SENSOR
#     timestamp, so there is no GPU->CPU readback on the main thread any more, and
#   * the head pose at that timestamp, asked of the OpenXR runtime via xrLocateSpace, which for a
#     time in the past is its fused MEASURED estimate -- not a 50 ms guess into a pose history.
#
# Detection itself also got faster: ArucoNano's detector replaced OpenCV's (~20 ms instead of
# ~60 ms per detectMarkers on the Quest).
#
# EVERYTHING DOWNSTREAM IS DELIBERATELY UNCHANGED. The aruco_patch* nodes still exist, are still
# reparented out of the camera into XROrigin3D, still carry the last_detected_ms meta, and still
# receive the same world-space poses with range_correct applied -- so avatar_rig_navel.gd,
# marker_gizmo.gd, marker_freshness.gd and aruco_csv_logger.gd did not have to be touched. The
# three members aruco_csv_logger.gd reads out of this node keep their exact old meaning:
#
#   _detect_mutex       guards the two below
#   _result_markers     id -> marker pose in CAMERA space, UNCORRECTED by range_correct
#                       (main_3d.gd never stored the corrected pose either; the replay applies
#                       the correction itself, so the recorded CSVs stay comparable)
#   _result_cam_xform   head pose in WORLD space at the frame's capture time
#
# The calibration moved from the constants that used to sit in _detection_loop into the
# ArucoMarkerTracking node's inspector, where it can be edited in the remote inspector of a
# running deploy. The values there are this project's, not the addon's defaults: fx/fy scaled by
# 0.937, DICT_4X4_50, zero distortion, 0.10 m markers.
extends Node3D

@onready var cam_preview: TextureRect = $CameraLayer/CameraPreview
@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var marker_tracking: ArucoMarkerTracking = $ArucoMarkerTracking

var marker_nodes: Dictionary = {}

# --- The surface aruco_csv_logger.gd reads (see the header) -------------------------------------
var _detect_mutex := Mutex.new()
var _result_markers: Dictionary = {}
var _result_cam_xform := Transform3D.IDENTITY

# Play space -> world space. The addon hands its own conversion over as a Callable when OpenXR is
# up, which is what keeps this file from carrying a second copy of that formula.
var _to_world := Callable()
# Last derived play->world transform, for the desktop case and for frames that saw no marker.
var _play_to_world := Transform3D.IDENTITY


func _ready() -> void:
	# Find the patch nodes the scene authored under the camera, exactly as before.
	for child in xr_camera.get_children():
		var n: String = child.name
		if n.begins_with("aruco_patch"):
			var id_str: String = n.substr(11)
			if id_str.is_valid_int():
				marker_nodes[id_str.to_int()] = child

	# Reparent the patches out of the camera and into the (stationary) tracking origin.
	# A marker pose is baked ONCE at detection time; as a child of XRCamera3D it would be
	# re-multiplied by the LIVE head transform every frame, so a stale detection would ride the
	# head and "swim" when you move.
	for id in marker_nodes:
		var patch: Node3D = marker_nodes[id]
		# Size the rendered cuboid to the real marker: x/y from the size solvePnP actually used,
		# keeping the authored thickness (z). Asking the addon rather than repeating the number
		# here means the box cannot disagree with the pose's metric scale.
		var size: float = marker_tracking.get_marker_size(id)
		for c in patch.get_children():
			if c is MeshInstance3D:
				c.scale = Vector3(size, size, c.scale.z)
		patch.reparent(xr_origin, false)

	marker_tracking.xr_locator_ready.connect(_on_xr_locator_ready)
	marker_tracking.detection_applied.connect(_on_detection_applied)

	# The texture is created once the camera feed is up; the getter covers the case where that
	# already happened before this _ready ran (children are readied before their parent).
	marker_tracking.camera_feed_started.connect(_on_camera_feed_started)
	if marker_tracking.get_camera_texture() != null:
		_on_camera_feed_started(marker_tracking.get_camera_texture())


# Texture2D, not CameraTexture: the addon has two camera backends and they hand over different
# things -- the CameraServer path a live CameraTexture, the CameraX path an ImageTexture it updates
# per frame (and only while its camera_preview_enabled is on).
func _on_camera_feed_started(texture: Texture2D) -> void:
	cam_preview.texture = texture


func _on_xr_locator_ready(_locator: OpenXRHeadLocator, _xr_api: OpenXRAPIExtension, to_world: Callable) -> void:
	_to_world = to_world


# One finished detection. Runs on the main thread (the addon marshals its camera callback onto the
# engine loop), so writing the scene tree here is safe.
func _on_detection_applied(
		_image: Image, _corners: Dictionary, poses: Dictionary, head_pose: Transform3D) -> void:
	var ids := poses.keys()
	var head_world := _head_pose_to_world(head_pose, ids)
	var head_inv := head_pose.affine_inverse()
	# One OpenCV result comes from one camera image, so every marker in it must carry the same
	# timestamp -- calling the clock inside the loop would give same-frame markers adjacent
	# millisecond values and force downstream code to guess a tolerance.
	var result_timestamp_ms := Time.get_ticks_msec()

	var markers_cam: Dictionary = {}
	for id in ids:
		# Back to camera space, which is what the old nine-argument call returned and what the
		# recordings contain. head_pose and poses[id] are both play space, so whatever transform
		# would take them to world cancels here -- this is independent of where XROrigin3D sits.
		var marker_cam: Transform3D = head_inv * poses[id]
		markers_cam[id] = marker_cam
		if marker_nodes.has(id):
			var corrected := marker_cam
			corrected.origin = CommonPoseProvider.range_correct(corrected.origin)
			marker_nodes[id].global_transform = head_world * corrected
			marker_nodes[id].set_meta("last_detected_ms", result_timestamp_ms)

	_detect_mutex.lock()
	_result_markers = markers_cam
	_result_cam_xform = head_world
	_detect_mutex.unlock()


# The head pose the addon reports is PLAY space; the patches are placed with global_transform and
# the recordings hold world space, so it has to be converted. Two sources, neither of which is a
# second copy of the formula: the Callable the addon hands over, or -- without OpenXR, i.e. on the
# desktop -- the ratio of the addon's own two getters, since get_marker_world_pose(id) IS
# get_marker_pose(id) run through that same conversion.
func _head_pose_to_world(head_pose: Transform3D, ids: Array) -> Transform3D:
	if _to_world.is_valid():
		return _to_world.call(head_pose)
	if not ids.is_empty():
		var id: int = ids[0]
		var play: Transform3D = marker_tracking.get_marker_pose(id)
		_play_to_world = marker_tracking.get_marker_world_pose(id) * play.affine_inverse()
	return _play_to_world * head_pose
