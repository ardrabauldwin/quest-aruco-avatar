class_name NaretSensorLogger
extends Node
## Full-take sensor log: every frame of hand tracking (both hands, 26 joints),
## body tracking (Meta, Godot humanoid joints), head pose, the mannequin's
## sternum and the scenario events, written as JSON lines to user://sensor_logs/.
##
## While it runs, a small web server on the local network (default port 8080)
## serves the live viewer (web/sensor_viewer.html: three.js character driven by
## the tracked bones), the live stream and the takes for download. Every request
## needs the PIN shown on the hand menu; nothing leaves the LAN, and it only runs
## while switched on (off at every start; Debug > Sensor log on the wrist menu).
## Taken from the team's merge/sensorlog branch (Dennis, Paul) on 17 Nov 2026; the PIN
## is random per headset instead of the fixed 1234. Poses are in tracking space (XROrigin3D): metres, Y up.
##
## Purpose: raw data to build a compression detector that does not depend on the
## trainee's body size. A take is started from the web page with the person's
## measurements and runs until it is stopped; the page also steers the scenario,
## a metronome and sets marks (ground truth) with a time stamp.
##
## File: first line {"type":"header", "meta":{...}, joint names...}; then one line
## per frame {"type":"frame","t":s,"head":J,"hands":[J*26|null, J*26|null],
## "body":[J*N]|null,"sternum":J,"det":{current detector state}} with
## J = [px,py,pz,qx,qy,qz,qw,flags]; other lines are {"type": event | mark |
## detected | placement | beat | qcpr | qcpr_wave | control, "t": s, ...}.

signal state_changed(active: bool, url: String)
signal control_requested(command: String, args: Dictionary)
signal take_changed(recording: bool)

const PORT := 8080
## Random per headset, kept in PIN_FILE so the address can still be bookmarked; the
## server only runs while switched on, in the LAN.
const PIN_FILE := "user://sensor_log_pin.txt"
const DIR := "user://sensor_logs/"
const LIVE_HZ := 30.0
const SEND_BUDGET := 262144 # bytes per client and frame, so a download never stalls the headset
const HAND_NAMES := ["/user/hand_tracker/left", "/user/hand_tracker/right"]

var active := false
var pin := ""
var take := ""
var frames := 0
var origin: Node3D
var sternum: Node3D
var meta := {}
## Per-frame extra fields ("det") and status fields, supplied by the scene.
var context := Callable()
var status_extra := Callable()

var _server := TCPServer.new()
var _clients: Array[Dictionary] = []
var _file: FileAccess
var _start_us := 0
var _last_live_us := 0
var _latest := ""
var _header := ""
var _hand_names := _joint_names("XRHandTracker", "HandJoint")
var _body_names := _joint_names("XRBodyTracker", "Joint")

func configure(xr_origin: Node3D, sternum_marker: Node3D, scenario: Node) -> void:
	origin = xr_origin
	sternum = sternum_marker
	if scenario and scenario.has_signal("event_recorded"):
		scenario.event_recorded.connect(_on_event)

func set_active(value: bool, port := PORT) -> Error:
	if value == active:
		return OK
	if value:
		var error := _server.listen(port)
		if error != OK:
			return error
		pin = headset_pin()
		active = true
		_start_us = Time.get_ticks_usec()
		_request_high_fidelity()
		_header = _make_header()
	else:
		stop_take()
		for client in _clients:
			client.peer.disconnect_from_host()
		_clients.clear()
		_server.stop()
		active = false
	state_changed.emit(active, url())
	return OK

## Six random digits, made once per installation and then reused.
static func headset_pin() -> String:
	var saved := FileAccess.get_file_as_string(PIN_FILE).strip_edges()
	if saved.length() == 6 and saved.is_valid_int():
		return saved
	var made := "%06d" % (randi() % 1000000)
	var file := FileAccess.open(PIN_FILE, FileAccess.WRITE)
	if file:
		file.store_string(made)
	return made

func url() -> String:
	if not active:
		return ""
	# The WLAN address: a private IPv4 range, not loopback or a VPN's 100.64/10.
	var address := "127.0.0.1"
	for candidate in IP.get_local_addresses():
		if candidate.begins_with("192.168.") or candidate.begins_with("10.") or (candidate.begins_with("172.") and int(candidate.get_slice(".", 1)) in range(16, 32)):
			address = candidate
			break
	return "http://%s:%d/?pin=%s" % [address, _server.get_local_port(), pin]

func new_take(take_meta := {}) -> void:
	_close_take()
	DirAccess.make_dir_recursive_absolute(DIR)
	var person := str(take_meta.get("person", "")).validate_filename().replace(" ", "_")
	take = "take-%s%s.jsonl" % [Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_"), ("-" + person) if person else ""]
	_file = FileAccess.open(DIR + take, FileAccess.WRITE)
	_start_us = Time.get_ticks_usec()
	frames = 0
	meta = take_meta
	_header = _make_header()
	_write(_header)
	take_changed.emit(true)

func stop_take() -> void:
	_close_take()
	take = ""
	take_changed.emit(false)

func recording() -> bool:
	return _file != null

func log_line(type: String, data := {}) -> void:
	## Anything with a time stamp besides the frames: marks, detector output, beats.
	if not active:
		return
	var line := {"type": type, "t": snappedf((Time.get_ticks_usec() - _start_us) / 1e6, 0.0001)}
	line.merge(data)
	var text := JSON.stringify(line)
	_write(text)
	_broadcast("event: log\ndata: " + text + "\n\n")

func body_tracking_info() -> Dictionary:
	## What Meta's body tracking delivers here: full body means generated legs
	## (joints without the POSITION_TRACKED flag), high fidelity = inside-out upper body.
	if not Engine.has_singleton("OpenXRFbBodyTrackingExtension"):
		return {"available": false}
	var ext: Object = Engine.get_singleton("OpenXRFbBodyTrackingExtension")
	# Fidelity arrived after OpenXR Vendors 5.1; older builds only know full body.
	var info := {"available": true, "full_body": ext.has_method("is_full_body_tracking_supported") and ext.call("is_full_body_tracking_supported"),
		"fidelity_supported": ext.has_method("is_body_tracking_fidelity_supported") and ext.call("is_body_tracking_fidelity_supported")}
	if info.fidelity_supported:
		info["fidelity"] = ["unknown", "low", "high"][clampi(int(ext.call("get_body_tracking_fidelity_status")), 0, 2)]
	return info

func _request_high_fidelity() -> void:
	if Engine.has_singleton("OpenXRFbBodyTrackingExtension"):
		var ext: Object = Engine.get_singleton("OpenXRFbBodyTrackingExtension")
		if ext.has_method("is_body_tracking_fidelity_supported") and ext.call("is_body_tracking_fidelity_supported"):
			ext.call("request_body_tracking_fidelity", 2) # BODY_TRACKING_FIDELITY_HIGH

func _make_header() -> String:
	return JSON.stringify({"type": "header", "take": take, "meta": meta, "started": Time.get_datetime_string_from_system(true),
		"body_tracking": body_tracking_info(),
		"space": "XROrigin3D tracking space, metres, Y up, -Z forward",
		"joint": ["px", "py", "pz", "qx", "qy", "qz", "qw", "flags"],
		"hand_joints": _hand_names, "body_joints": _body_names})

func _process(_delta: float) -> void:
	if not active:
		return
	_sample()
	_serve()

func _sample() -> void:
	var now := Time.get_ticks_usec()
	var hands := []
	for name in HAND_NAMES:
		var hand := XRServer.get_tracker(name) as XRHandTracker
		hands.append(_hand(hand) if hand and hand.has_tracking_data else null)
	var body_tracker := XRServer.get_tracker("/user/body_tracker") as XRBodyTracker
	var frame := {"type": "frame", "t": snappedf((now - _start_us) / 1e6, 0.0001),
		"head": _joint(XRServer.get_hmd_transform(), 0), "hands": hands,
		"body": _body(body_tracker) if body_tracker and body_tracker.has_tracking_data else null}
	if origin and sternum and is_instance_valid(sternum):
		frame["sternum"] = _joint(origin.global_transform.affine_inverse() * sternum.global_transform, 0)
	if context.is_valid():
		frame["det"] = context.call()
	# ponytail: one JSON line per rendered frame (~70 KB/s per joint set); a binary format if takes get too big.
	_latest = JSON.stringify(frame)
	if _file:
		_write(_latest)
		frames += 1
	if now - _last_live_us >= 1e6 / LIVE_HZ:
		_last_live_us = now
		_broadcast("data: " + _latest + "\n\n")

func _hand(hand: XRHandTracker) -> Array:
	var joints := []
	for i in _hand_names.size():
		joints.append(_joint(hand.get_hand_joint_transform(i), hand.get_hand_joint_flags(i)))
	return joints

func _body(body: XRBodyTracker) -> Array:
	var joints := []
	for i in _body_names.size():
		# Joints the runtime does not provide carry uninitialised flags; keep the 4 defined bits.
		joints.append(_joint(body.get_joint_transform(i), body.get_joint_flags(i) & 15))
	return joints

static func _joint(pose: Transform3D, flags: int) -> Array:
	var q := pose.basis.get_rotation_quaternion()
	var p := pose.origin
	return [snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001),
		snappedf(q.x, 0.0001), snappedf(q.y, 0.0001), snappedf(q.z, 0.0001), snappedf(q.w, 0.0001), flags]

static func _joint_names(klass: String, enum_name: String) -> Array[String]:
	## Joint names in index order, from the engine itself (no hand-kept table).
	var names: Array[String] = []
	for constant in ClassDB.class_get_enum_constants(klass, enum_name):
		var index := ClassDB.class_get_integer_constant(klass, constant)
		if constant.ends_with("_MAX"):
			continue
		if names.size() <= index:
			names.resize(index + 1)
		names[index] = constant.trim_prefix("HAND_JOINT_").trim_prefix("JOINT_").to_lower()
	return names

func _on_event(event: Dictionary) -> void:
	log_line("event", {"action": event.get("action", ""), "accepted": event.get("accepted", false),
		"state": event.get("state", ""), "source": event.get("details", {}).get("source", "")})

func _write(line: String) -> void:
	if _file:
		_file.store_line(line)

func _close_take() -> void:
	if _file:
		_file.close()
		_file = null

## --- web server ---------------------------------------------------------------

func _serve() -> void:
	while _server.is_connection_available():
		_clients.append({"peer": _server.take_connection(), "request": "", "out": PackedByteArray(), "file": null, "live": false, "close": false})
	for client in _clients.duplicate():
		var peer: StreamPeerTCP = client.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(client)
			continue
		if client.request.is_empty() or not client.request.contains("\r\n\r\n"):
			var available := peer.get_available_bytes()
			if available > 0:
				client.request += peer.get_utf8_string(available)
			if client.request.contains("\r\n\r\n"):
				_respond(client)
		_flush(client)
		if client.close and client.out.is_empty() and client.file == null:
			peer.disconnect_from_host()
			_clients.erase(client)

func _respond(client: Dictionary) -> void:
	var line: String = client.request.get_slice("\r\n", 0)
	var method := line.get_slice(" ", 0)
	var target := line.get_slice(" ", 1)
	var path := target.get_slice("?", 0).uri_decode()
	var args := {}
	if target.contains("?"):
		for pair in target.get_slice("?", 1).split("&", false):
			args[pair.get_slice("=", 0).uri_decode()] = pair.get_slice("=", 1).replace("+", " ").uri_decode()
	if args.get("pin", "") != pin:
		_reply(client, 403, "text/plain; charset=utf-8", "PIN fehlt oder falsch / brak lub błędny PIN".to_utf8_buffer())
		return
	match [method, path]:
		["GET", "/"]:
			_reply(client, 200, "text/html; charset=utf-8", FileAccess.get_file_as_bytes("res://web/sensor_viewer.html"))
		["GET", "/api/status"]:
			var status := {"take": take, "recording": recording(), "meta": meta, "frames": frames, "body_tracking": body_tracking_info(),
				"seconds": snappedf((Time.get_ticks_usec() - _start_us) / 1e6, 0.1), "clients": _clients.size()}
			if status_extra.is_valid():
				status.merge(status_extra.call())
			_reply(client, 200, "application/json", JSON.stringify(status).to_utf8_buffer())
		["GET", "/api/takes"]:
			var takes := []
			for name in DirAccess.get_files_at(DIR) if DirAccess.dir_exists_absolute(DIR) else PackedStringArray():
				if name.ends_with(".jsonl"):
					takes.append({"name": name, "bytes": _size(DIR + name)})
			takes.sort_custom(func(a, b): return a.name > b.name)
			_reply(client, 200, "application/json", JSON.stringify(takes).to_utf8_buffer())
		["POST", "/api/take"]:
			args.erase("pin")
			new_take(args)
			_reply(client, 200, "application/json", JSON.stringify({"take": take}).to_utf8_buffer())
		["POST", "/api/take/stop"]:
			stop_take()
			_reply(client, 200, "application/json", "{}".to_utf8_buffer())
		["POST", "/api/mark"]:
			log_line("mark", {"label": args.get("label", ""), "note": args.get("note", "")})
			_reply(client, 200, "application/json", "{}".to_utf8_buffer())
		["POST", "/api/control"]:
			args.erase("pin")
			var command: String = args.get("cmd", "")
			args.erase("cmd")
			log_line("control", {"cmd": command, "args": args})
			control_requested.emit(command, args)
			_reply(client, 200, "application/json", "{}".to_utf8_buffer())
		["GET", "/live"]:
			client.live = true
			client.out.append_array(("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\n"
				+ "Connection: keep-alive\r\n\r\nevent: header\ndata: " + _header + "\n\n").to_utf8_buffer())
		_:
			var name := path.trim_prefix("/takes/")
			if method == "GET" and path.begins_with("/takes/") and name.is_valid_filename() and name.ends_with(".jsonl") and FileAccess.file_exists(DIR + name):
				if _file and name == take:
					_file.flush()
				client.out.append_array(("HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nContent-Length: %d\r\n" % _size(DIR + name)
					+ "Content-Disposition: attachment; filename=\"%s\"\r\nConnection: close\r\n\r\n" % name).to_utf8_buffer())
				client.file = FileAccess.open(DIR + name, FileAccess.READ)
				client.close = true
			else:
				_reply(client, 404, "text/plain", "not found".to_utf8_buffer())

func _reply(client: Dictionary, status: int, type: String, body: PackedByteArray) -> void:
	var reason: String = {200: "OK", 403: "Forbidden", 404: "Not Found"}[status]
	client.out.append_array(("HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
		% [status, reason, type, body.size()]).to_utf8_buffer())
	client.out.append_array(body)
	client.close = true

func _flush(client: Dictionary) -> void:
	var peer: StreamPeerTCP = client.peer
	var budget := SEND_BUDGET
	while budget > 0:
		if client.out.is_empty():
			if client.file == null:
				return
			var chunk: PackedByteArray = client.file.get_buffer(65536)
			if chunk.is_empty():
				client.file.close()
				client.file = null
				return
			client.out = chunk
		var result := peer.put_partial_data(client.out.slice(0, budget))
		var sent: int = result[1] if result[0] == OK else 0
		if sent <= 0:
			return
		client.out = client.out.slice(sent)
		budget -= sent

func _broadcast(message: String) -> void:
	var bytes := message.to_utf8_buffer()
	for client in _clients:
		# A viewer that falls behind gets the next frame, not a growing backlog.
		if client.live and client.out.size() < SEND_BUDGET:
			client.out.append_array(bytes)

static func _size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_length() if file else 0

func _exit_tree() -> void:
	set_active(false)
