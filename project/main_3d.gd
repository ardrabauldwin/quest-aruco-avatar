# Scene root for the CPR trainer.
#
# This file used to BE the detection pipeline: ~340 lines of camera-feed selection, the GPU->CPU
# readback, a hand-rolled Thread with its mutex and semaphore, the pose history with its
# CAMERA_LATENCY_MS guess, the nine-argument OpenCV call with its inlined intrinsics, the baking of
# camera-space poses into the aruco_patch nodes, and a TCP frame streamer. All of that is the
# opencv_aruco addon now -- ArucoMarkerTracking, a sibling node in this scene -- including two
# things this code could not do at all:
#
#   * the CameraX push path: Y-plane bytes arrive on the CPU with the frame's real SENSOR
#     timestamp, so there is no GPU->CPU readback on the main thread any more, and
#   * the head pose at that timestamp, asked of the OpenXR runtime via xrLocateSpace, which for a
#     time in the past is its fused MEASURED estimate -- not a 50 ms guess into a pose history.
#
# Detection itself also got faster: ArucoNano's detector replaced OpenCV's (~20 ms instead of
# ~60 ms per detectMarkers on the Quest).
#
# What is left here is the debug camera preview. The app's own consumers -- AvatarRig,
# MarkerGizmos, ArucoCsvLogger, DepthProbe -- talk to the addon node directly through an exported
# reference, so nothing routes through this script any more. The range correction main_3d.gd used
# to apply while baking the patch nodes lives in MarkerFreshness now, which the rig and the gizmo
# share.
#
# The calibration moved from the constants that used to sit in _detection_loop into the
# ArucoMarkerTracking node's inspector, where it can be edited in the remote inspector of a
# running deploy. The values there are this project's, not the addon's defaults: fx/fy scaled by
# 0.937, DICT_4X4_50, zero distortion, 0.10 m markers.
extends Node3D

@onready var cam_preview: TextureRect = $CameraLayer/CameraPreview
@onready var marker_tracking: ArucoMarkerTracking = $ArucoMarkerTracking


func _ready() -> void:
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
