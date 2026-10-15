class_name NaretQcprBleRealBackend
extends NaretQcprBackend
## Reales BLE-Backend für physische QCPR-Trainingspuppen.
##
## Implementiert die Protokollabstraktion und den Integrationspunkt für
## native BLE-Plugins (Android / Meta Quest 3 JNI-Plugin oder Desktop-Bridge).
##
## Integrationsanleitung für Meta Quest 3:
## 1. Android-Export-Permissions: BLUETOOTH_SCAN, BLUETOOTH_CONNECT, ACCESS_FINE_LOCATION
## 2. Scan nach Geräten mit Service-UUID 00001001-D746-4092-84E7-DAD34863FE4A
## 3. Nach Verbindung: MTU auf 247 anfordern und Benachrichtigungen aktivieren:
##    - CPRM Response (00001003-D746-4092-84E7-DAD34863FE4A)
##    - CPRM Auth Response (00001033-D746-4092-84E7-DAD34863FE4A)
## 4. Auth-Handshake: 18-Byte CPRM-Schlüssel an 00001032 senden.

const Constants = preload("res://scripts/qcpr/qcpr_constants.gd")
const Packet = preload("res://scripts/qcpr/qcpr_packet.gd")

var _plugin_singleton: Object = null
var _scanning := false

func _init() -> void:
	_detect_native_plugin()

func _detect_native_plugin() -> void:
	for singleton_name: String in ["GodotBLE", "BlePlugin", "NaretBle"]:
		if Engine.has_singleton(singleton_name):
			_plugin_singleton = Engine.get_singleton(singleton_name)
			_bind_plugin_signals()
			break

func _bind_plugin_signals() -> void:
	if not _plugin_singleton:
		return
	if _plugin_singleton.has_signal("device_connected"):
		_plugin_singleton.connect("device_connected", _on_native_device_connected)
	if _plugin_singleton.has_signal("device_disconnected"):
		_plugin_singleton.connect("device_disconnected", _on_native_device_disconnected)
	if _plugin_singleton.has_signal("characteristic_notified"):
		_plugin_singleton.connect("characteristic_notified", _on_native_characteristic_notified)

func is_native_plugin_available() -> bool:
	return _plugin_singleton != null

func get_backend_name() -> String:
	return "Real QCPR BLE Stack"

func is_simulated() -> bool:
	return false

func connect_device(address: String = "") -> void:
	device_address = address
	if not is_native_plugin_available():
		status_message.emit("Kein natives BLE-Plugin gefunden. Wechsle zu Simulator.")
		return

	state = State.CONNECTING
	status_message.emit("Verbinde mit QCPR-Puppe (%s)..." % address)
	if _plugin_singleton.has_method("connect_gatt"):
		_plugin_singleton.call("connect_gatt", address)

func disconnect_device() -> void:
	if state == State.DISCONNECTED:
		return
	if _plugin_singleton and _plugin_singleton.has_method("disconnect_gatt"):
		_plugin_singleton.call("disconnect_gatt")
	state = State.DISCONNECTED
	disconnected.emit()

func send_command(msg_id: int, params: PackedByteArray = PackedByteArray()) -> bool:
	if state < State.CONNECTED or not _plugin_singleton:
		return false
	var frame := Packet.encode_frame(msg_id, get_next_sequence(), params)
	if _plugin_singleton.has_method("write_characteristic"):
		_plugin_singleton.call("write_characteristic", Constants.UUID_SERVICE_CPRM_COMMAND, Constants.UUID_CHAR_CPRM_COMMAND, frame)
		return true
	return false

func send_auth_key() -> bool:
	if not _plugin_singleton:
		return false
	state = State.AUTHENTICATING
	if _plugin_singleton.has_method("write_characteristic"):
		_plugin_singleton.call("write_characteristic", Constants.UUID_SERVICE_CPRM_AUTH, Constants.UUID_CHAR_CPRM_AUTH_COMMAND, Constants.CPRM_AUTH_KEY)
		return true
	return false

# --- Native Callbacks ---

func _on_native_device_connected(addr: String) -> void:
	device_address = addr
	state = State.CONNECTED
	connected.emit()
	status_message.emit("BLE verbunden. Starte QCPR-Authentifizierung...")
	send_auth_key()

func _on_native_device_disconnected(_addr: String) -> void:
	state = State.DISCONNECTED
	disconnected.emit()
	status_message.emit("QCPR-BLE getrennt.")

func _on_native_characteristic_notified(char_uuid: String, raw_bytes: PackedByteArray) -> void:
	if raw_bytes.size() < 2:
		return

	var decoded := Packet.decode_frame(raw_bytes)
	if not decoded.valid:
		return

	var msg_id: int = decoded.msg_id
	var params: PackedByteArray = decoded.params

	if msg_id == Constants.ResponseId.SC_SECURITY_CODE:
		var success := Packet.parse_auth(params)
		if success:
			state = State.READY
			authenticated.emit(true)
			status_message.emit("QCPR-Authentifizierung erfolgreich.")
			# RTC synchronisieren und Akkustand abfragen
			send_command(Constants.CommandId.LG_GET_BATTERY_LEVEL)
		else:
			authenticated.emit(false)
			status_message.emit("QCPR-Authentifizierung abgelehnt.")

	elif msg_id == Constants.ResponseId.CP_WAVE:
		var wave := Packet.parse_wave(params)
		if wave.valid:
			compression_wave.emit(wave.session_time_ms, wave.depth_mm)

	elif msg_id == Constants.ResponseId.CP_EVENT:
		var event := Packet.parse_event(params)
		if event.valid:
			var duration := float(event.time_to_stop_ms)
			var recoil_ok: bool = not event.incomplete_release
			compression_event.emit(event.max_depth_mm, 0.0, recoil_ok, duration)

	elif msg_id == Constants.ResponseId.CP_RATE:
		var rate := Packet.parse_rate(params)
		compression_rate.emit(float(rate))

	elif msg_id == Constants.ResponseId.CP_INACTIVITY:
		var inact := Packet.parse_inactivity(params)
		if inact.valid:
			inactivity_reported.emit(inact.inactivity_ms, inact.level)

	elif msg_id == Constants.ResponseId.QF_COMP_SHALLOW:
		feedback_event.emit("shallow", Packet.parse_feedback(params, msg_id), "Zu flach drücken (mind. 50 mm)")

	elif msg_id == Constants.ResponseId.QF_COMP_SLOW:
		feedback_event.emit("slow", Packet.parse_feedback(params, msg_id), "Schneller drücken (100–120/min)")

	elif msg_id == Constants.ResponseId.QF_COMP_FAST:
		feedback_event.emit("fast", Packet.parse_feedback(params, msg_id), "Langsamer drücken (100–120/min)")

	elif msg_id == Constants.ResponseId.QF_INCOMP_RELEASE:
		feedback_event.emit("incomplete_release", Packet.parse_feedback(params, msg_id), "Brustkorb vollständig entlasten")

	elif msg_id == Constants.ResponseId.QF_INACTIVITY:
		feedback_event.emit("inactivity", Packet.parse_feedback(params, msg_id), "Kompressionen fortsetzen")

	elif msg_id == Constants.ResponseId.LG_GET_BATTERY_LEVEL:
		battery_percent = Packet.parse_battery(params)
		battery_level_changed.emit(battery_percent)

	elif msg_id == Constants.ResponseId.QS_DATA:
		var summary := Packet.parse_session_data(params)
		if summary.valid:
			session_summary_received.emit(summary)
