extends "res://main_3d.gd"
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
		var t0 := Time.get_ticks_usec()
		var image_downscale_factor=0.5 #1 is original image, 0.5 means half width and half height
		var fx=877.06583568*image_downscale_factor
		var fy=878.33004836*image_downscale_factor
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

		var markers: Dictionary = processor.get_6dof_of_all_aruco_patches_from_godot_image(img, aruco_patch_size,image_downscale_factor,fx,fy,cx,cy,lens_rotation,lens_translation)

		_detect_mutex.lock()
		_result_markers = markers
		_result_cam_xform = cam_xform
		_has_result = true
		_detect_mutex.unlock()




func _log_marker_range(id: int, ray_cam: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if now-int(_range_log_ms.get(id,-1000)) < 1000:
		return
	_range_log_ms[id]=now
	print("NO0937 marker id=%d head_origin_m=%.5f fx=877.06583568 fy=878.33004836" % [id,ray_cam.length()])
