extends "res://tests/suite.gd"
## The LAN sensor logger: records a tracked hand, serves the take only with the PIN.

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var hand := XRHandTracker.new()
	hand.name = "/user/hand_tracker/left"
	hand.has_tracking_data = true
	hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST, Transform3D(Basis.IDENTITY, Vector3(0.1, 1.2, -0.3)))
	hand.set_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
	XRServer.add_tracker(hand)
	var logger := NaretSensorLogger.new()
	tree.root.add_child(logger)
	check(logger.set_active(true, 0) == OK, "logger opens a port")
	var port := int(logger.url().get_slice(":", 2).get_slice("/", 0))
	check(port > 0 and logger.pin.length() == 6 and logger.pin != "123456", "url carries the port and a 6-digit PIN")
	check(NaretSensorLogger.headset_pin() == logger.pin, "the PIN stays the same on this headset")
	check(not logger.recording(), "switching on serves live data but records nothing yet")
	var commands := []
	logger.control_requested.connect(func(command: String, args: Dictionary): commands.append([command, args]))
	var started := await _http(tree, port, "/api/take?pin=%s&person=P%%2007&height_cm=182" % logger.pin, "POST")
	check(started.begins_with("HTTP/1.1 200") and logger.recording() and logger.take.ends_with("-P_07.jsonl"), "a take starts from the web page, named after the person")
	for i in 5:
		await tree.process_frame
	check(logger.frames >= 4, "every frame is logged")

	var refused := await _http(tree, port, "/api/status")
	check(refused.begins_with("HTTP/1.1 403"), "requests without the PIN are refused")
	var status := await _http(tree, port, "/api/status?pin=" + logger.pin)
	check(status.begins_with("HTTP/1.1 200") and logger.take in status, "status names the running take")
	var page := await _http(tree, port, "/?pin=" + logger.pin)
	check("three" in page and "EventSource" in page, "the live viewer page is served")
	var take := await _http(tree, port, "/takes/%s?pin=%s" % [logger.take, logger.pin])
	var lines := take.get_slice("\r\n\r\n", 1).strip_edges().split("\n")
	var header: Dictionary = JSON.parse_string(lines[0]) if lines.size() > 1 else {}
	var frame: Dictionary = JSON.parse_string(lines[1]) if lines.size() > 1 else {}
	check(header.get("type") == "header" and header.get("hand_joints", []).size() == 26, "take starts with the joint names")
	var wrist: Array = frame.get("hands", [null])[0][XRHandTracker.HAND_JOINT_WRIST] if frame.get("hands", [null])[0] else []
	check(wrist.size() == 8 and is_equal_approx(wrist[1], 1.2), "the left wrist is logged where it was tracked")
	check(frame.get("hands", [null, 0])[1] == null, "an untracked hand is logged as null")
	check(header.get("meta", {}).get("height_cm") == "182", "the person's measurements are in the take header")
	await _http(tree, port, "/api/mark?pin=%s&label=zu+flach" % logger.pin, "POST")
	await _http(tree, port, "/api/control?pin=%s&cmd=metronome&bpm=110" % logger.pin, "POST")
	check(commands == [["metronome", {"bpm": "110"}]], "controls reach the scene")
	await _http(tree, port, "/api/take/stop?pin=" + logger.pin, "POST")
	check(not logger.recording(), "the take stops from the web page")
	var traversal := await _http(tree, port, "/takes/..%2Fproject.godot?pin=" + logger.pin)
	check(traversal.begins_with("HTTP/1.1 404"), "only take files can be downloaded")

	logger.set_active(false)
	check(not logger.active, "logger stops")
	logger.queue_free()
	XRServer.remove_tracker(hand)
	var found := 0
	for name in DirAccess.get_files_at(NaretSensorLogger.DIR):
		if name.ends_with("-P_07.jsonl"):
			found += 1
			var text := FileAccess.get_file_as_string(NaretSensorLogger.DIR + name)
			check('"type":"mark"' in text and '"label":"zu flach"' in text, "marks are written to the take")
			check('"type":"control"' in text, "controls are written to the take")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(NaretSensorLogger.DIR + name))
	check(found == 1, "exactly one take file was written")
	return failures

func _http(tree: SceneTree, port: int, target: String, method := "GET") -> String:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", port)
	var sent := false
	var response := PackedByteArray()
	for i in 300:
		await tree.process_frame
		peer.poll()
		var state := peer.get_status()
		if state == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				peer.put_data(("%s %s HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" % [method, target]).to_utf8_buffer())
				sent = true
			var available := peer.get_available_bytes()
			if available > 0:
				response.append_array(peer.get_data(available)[1])
		elif sent and state != StreamPeerTCP.STATUS_CONNECTING:
			break
	peer.disconnect_from_host()
	return response.get_string_from_utf8()
