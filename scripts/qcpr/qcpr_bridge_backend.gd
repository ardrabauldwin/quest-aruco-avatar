class_name NaretQcprBridgeBackend
extends NaretQcprBackend
## QCPR manikin data over the laptop bridge (9 Nov 2026). The app has no native Bluetooth
## plugin yet; tools/qcpr_probe.py reads the manikin over Bluetooth on a PC and forwards
## every finished compression as one UDP datagram with a JSON object:
##   {"type":"compression","depth_mm":28,"rate_bpm":110,"full_release":true,
##    "session_ms":587654,"unix_ms":1794248167019}
## Listens on PORT; whichever sender arrives first is the manikin. For experiments with
## the laptop in the room; the PC-free path is a native plugin.

const PORT := 8767
const LIVE_S := 3.0
var _udp := PacketPeerUDP.new()
var _listening := false
var _last_packet_ms := -1_000_000
var sender := ""
var packets := 0

func start_listening(port: int = PORT) -> bool:
	if _listening:
		return true
	var error := _udp.bind(port)
	_listening = error == OK
	if _listening:
		status_message.emit("QCPR bridge listening on UDP %d" % port)
	else:
		status_message.emit("QCPR bridge cannot listen on UDP %d (%s)" % [port, error_string(error)])
	return _listening

func _process(_delta: float) -> void:
	poll()

func poll() -> void:
	if not _listening:
		return
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		var from := _udp.get_packet_ip()
		_handle_packet(packet.get_string_from_utf8(), from)

func _handle_packet(text: String, from: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	if sender.is_empty():
		sender = from
		state = State.READY
		device_name = "QCPR manikin via %s" % from
		connected.emit()
		authenticated.emit(true)
		status_message.emit("QCPR manikin data arriving from %s" % from)
		print("NARET_QCPR_BRIDGE first packet from ", from)
	_last_packet_ms = Time.get_ticks_msec()
	packets += 1
	match str(data.get("type", "")):
		"compression":
			var depth := float(data.get("depth_mm", 0.0))
			var rate := float(data.get("rate_bpm", 0.0))
			var full_release := bool(data.get("full_release", true))
			var duration := float(data.get("time_to_stop_ms", 0.0))
			print("NARET_QCPR_BRIDGE compression depth_mm=%.0f rate_bpm=%.0f full_release=%s" % [depth, rate, full_release])
			compression_event.emit(depth, rate, full_release, duration)
		"wave":
			compression_wave.emit(int(data.get("session_ms", 0)), float(data.get("depth_mm", 0.0)))
		"battery":
			battery_percent = int(data.get("percent", battery_percent))
			battery_level_changed.emit(battery_percent)

func is_live() -> bool:
	return not sender.is_empty() and Time.get_ticks_msec() - _last_packet_ms <= int(LIVE_S * 1000.0)

func is_simulated() -> bool:
	return false

func get_backend_name() -> String:
	return "QCPR via PC bridge (UDP %d)" % PORT

func disconnect_device() -> void:
	if _listening:
		_udp.close()
		_listening = false
	sender = ""
	state = State.DISCONNECTED
	disconnected.emit()
