extends SceneTree
func _initialize() -> void:
	var detector = ClassDB.instantiate("OpenCVProcessor")
	if detector == null or not detector.has_method("detect_markers"):
		push_error("addon-port detector API unavailable")
		quit(1)
		return
	detector.camera_intrinsics = Vector4(877.06583568, 878.33, 256, 256)
	detector.camera_distortion = PackedFloat64Array()
	detector.image_downscale_factor = 1.0
	detector.marker_dictionary = 1
	detector.aruco_patch_size = 0.10
	var img := Image.load_from_file("res://build/nano_test_marker.png")
	img.convert(Image.FORMAT_L8)
	var corners := {}
	var poses: Dictionary = detector.detect_markers(img, Transform3D.IDENTITY, corners)
	print("NANO_PROBE ids=", poses.keys(), " pose=", poses.get(0))
	detector.free()
	quit(0 if poses.has(0) else 1)
