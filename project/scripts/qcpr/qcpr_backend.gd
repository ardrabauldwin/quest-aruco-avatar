class_name NaretQcprBackend
extends Node
## Basisklasse / Interface für QCPR-Hardware- und Simulator-Backends.
##
## Entkoppelt die klinische Trainingslogik und das UI vom konkreten BLE-Transport.
## Ermöglicht nahtlosen Austausch zwischen Simulator und echtem BLE-Stack.

signal connected
signal disconnected
signal authenticated(success: bool)
signal compression_wave(session_time_ms: int, depth_mm: float)
signal compression_event(max_depth_mm: float, rate_bpm: float, recoil_ok: bool, duration_ms: float)
signal compression_rate(rate_bpm: float)
signal inactivity_reported(inactivity_ms: int, level: int)
signal feedback_event(feedback_type: String, feedback_level: int, message: String)
signal session_summary_received(summary: Dictionary)
signal battery_level_changed(percent: int)
signal status_message(message: String)

enum State {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	AUTHENTICATING,
	READY
}

var state: int = State.DISCONNECTED
var device_name := "QCPR Manikin"
var device_address := ""
var battery_percent := 100
var _seq_number := 0

func connect_device(_address: String = "") -> void:
	pass

func disconnect_device() -> void:
	pass

func is_device_connected() -> bool:
	return state >= State.CONNECTED

func is_device_authenticated() -> bool:
	return state == State.READY

func is_simulated() -> bool:
	return false

func get_backend_name() -> String:
	return "Generic QCPR Backend"

func send_command(_msg_id: int, _params: PackedByteArray = PackedByteArray()) -> bool:
	return false

func start_session() -> void:
	pass

func stop_session() -> void:
	pass

func get_next_sequence() -> int:
	var current := _seq_number
	_seq_number += 1
	if _seq_number > NaretQcprConstants.MAX_SEQUENCE_NUMBER:
		_seq_number = 0
	return current

func reset_sequence() -> void:
	_seq_number = 0
