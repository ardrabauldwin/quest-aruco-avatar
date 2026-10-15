class_name NaretQcprManager
extends Node
## Zentraler Koordinator für QCPR-Puppen-Integration und Smart-Puppen-Simulator.
##
## Bindet das aktive Backend (Echt-BLE oder Simulator) an das Szenario und die UI an.
## Beinhaltet automatischen Fallback auf den Simulator, falls keine reale Puppe
## verfügbar oder verbunden ist, und bewertet Qualität klinisch nach ERC 2021.

signal compression_measured(depth_mm: float, rate_bpm: float, recoil_ok: bool, quality: Dictionary)
signal ventilation_measured(volume_ml: float)
signal live_wave_sample(session_time_ms: int, depth_mm: float)
signal quality_feedback(type: String, message_de: String, message_pl: String, is_good: bool)
signal backend_changed(backend_name: String, is_sim: bool)
signal status_changed(status_text: String)

const Constants = preload("res://scripts/qcpr/qcpr_constants.gd")
const RealBackend = preload("res://scripts/qcpr/qcpr_ble_real_backend.gd")
const SimBackend = preload("res://scripts/qcpr/simulated_manikin_backend.gd")

var active_backend: NaretQcprBackend
var real_backend: NaretQcprBleRealBackend
var sim_backend: NaretSimulatedManikinBackend

var prefer_real_hardware := false
var scenario: NaretScenario = null
var current_depth_mm := 0.0
var current_rate_bpm := 0.0
var last_feedback_message := ""
var is_active := true

func _ready() -> void:
	_setup_backends()

func _setup_backends() -> void:
	real_backend = RealBackend.new()
	real_backend.name = "RealBleBackend"
	add_child(real_backend)

	sim_backend = SimBackend.new()
	sim_backend.name = "SimulatedBackend"
	add_child(sim_backend)

	# Auto-Fallback: Wenn reale Hardware gewünscht und Plugin da ist, versuchen.
	# Standardmäßig ist der Simulator aktiv (Dennis hat die Hardware nicht zur Hand).
	if prefer_real_hardware and real_backend.is_native_plugin_available():
		set_active_backend(real_backend)
	else:
		set_active_backend(sim_backend)

func set_active_backend(new_backend: NaretQcprBackend) -> void:
	if active_backend == new_backend:
		return

	if active_backend:
		_disconnect_backend_signals(active_backend)
		active_backend.stop_session()

	active_backend = new_backend
	if active_backend:
		_connect_backend_signals(active_backend)
		backend_changed.emit(active_backend.get_backend_name(), active_backend.is_simulated())
		status_changed.emit("Aktiv: %s" % active_backend.get_backend_name())

func _connect_backend_signals(backend: NaretQcprBackend) -> void:
	backend.compression_wave.connect(_on_backend_wave)
	backend.compression_event.connect(_on_backend_compression_event)
	backend.compression_rate.connect(_on_backend_compression_rate)
	backend.feedback_event.connect(_on_backend_feedback)
	backend.status_message.connect(func(msg: String): status_changed.emit(msg))

func _disconnect_backend_signals(backend: NaretQcprBackend) -> void:
	if backend.compression_wave.is_connected(_on_backend_wave):
		backend.compression_wave.disconnect(_on_backend_wave)
	if backend.compression_event.is_connected(_on_backend_compression_event):
		backend.compression_event.disconnect(_on_backend_compression_event)
	if backend.compression_rate.is_connected(_on_backend_compression_rate):
		backend.compression_rate.disconnect(_on_backend_compression_rate)
	if backend.feedback_event.is_connected(_on_backend_feedback):
		backend.feedback_event.disconnect(_on_backend_feedback)

# --- Signal-Handling vom Backend ---

func _on_backend_wave(time_ms: int, depth_mm: float) -> void:
	current_depth_mm = depth_mm
	live_wave_sample.emit(time_ms, depth_mm)

func _on_backend_compression_rate(rate_bpm: float) -> void:
	current_rate_bpm = rate_bpm

func _on_backend_compression_event(max_depth_mm: float, rate_bpm: float, recoil_ok: bool, duration_ms: float) -> void:
	if not is_active:
		return

	current_depth_mm = max_depth_mm
	if rate_bpm > 0.0:
		current_rate_bpm = rate_bpm

	# ERC 2021 Qualitätsprüfung
	var depth_ok := (max_depth_mm >= Constants.ADULT_DEPTH_MIN_MM and max_depth_mm <= Constants.ADULT_DEPTH_MAX_MM)
	var rate_ok := (current_rate_bpm >= Constants.ADULT_RATE_MIN_BPM and current_rate_bpm <= Constants.ADULT_RATE_MAX_BPM)
	var all_ok := depth_ok and rate_ok and recoil_ok

	var quality := {
		"depth_mm": max_depth_mm,
		"rate_bpm": current_rate_bpm,
		"recoil_ok": recoil_ok,
		"depth_ok": depth_ok,
		"rate_ok": rate_ok,
		"duration_ms": duration_ms,
		"is_good": all_ok,
		"depth_status": "good" if depth_ok else ("shallow" if max_depth_mm < Constants.ADULT_DEPTH_MIN_MM else "deep"),
		"rate_status": "good" if rate_ok else ("slow" if current_rate_bpm < Constants.ADULT_RATE_MIN_BPM else "fast")
	}

	compression_measured.emit(max_depth_mm, current_rate_bpm, recoil_ok, quality)

	# Direkt an das Szenario weiterleiten (sofern im CPR-Zustand)
	if scenario and scenario.state == NaretScenario.State.CPR:
		var details := {
			"source": "mannequin_sensor",
			"measurement_verified": true,
			"depth_cm": max_depth_mm / 10.0,
			"rate_bpm": current_rate_bpm,
			"recoil": recoil_ok,
			"correct_position": true
		}
		scenario.submit_action("compression", details)

func _on_backend_feedback(type: String, _level: int, raw_message: String) -> void:
	var msg_de := raw_message
	var msg_pl := raw_message
	var is_good := false

	match type:
		"shallow":
			msg_de = "Tiefer drücken (50–60 mm)"
			msg_pl = "Uciskaj głębiej (50–60 mm)"
		"too_deep":
			msg_de = "Weniger tief drücken (max. 60 mm)"
			msg_pl = "Uciskaj płycej (maks. 60 mm)"
		"slow":
			msg_de = "Schneller drücken (100–120/min)"
			msg_pl = "Uciskaj szybciej (100–120/min)"
		"fast":
			msg_de = "Langsamer drücken (100–120/min)"
			msg_pl = "Uciskaj wolniej (100–120/min)"
		"incomplete_release":
			msg_de = "Vollständig entlasten"
			msg_pl = "Zwolnij nacisk całkowicie"
		"inactivity":
			msg_de = "Kompressionen fortsetzen!"
			msg_pl = "Wznów uciskanie klatki!"
		"ventilate":
			msg_de = "30 Kompressionen erreicht · 2x Beatmen"
			msg_pl = "30 uciśnięć · wykonaj 2 oddechy"
		"resume_cpr":
			msg_de = "Beatmung beendet · Sofort CPR fortsetzen"
			msg_pl = "Oddechy zakończone · wznów uciskanie"
			is_good = true

	last_feedback_message = msg_de
	quality_feedback.emit(type, msg_de, msg_pl, is_good)

# --- Öffentliche Steuerungsmethoden ---

func select_simulator_preset(preset_index: int) -> void:
	if sim_backend:
		sim_backend.current_preset = preset_index
		status_changed.emit("Simulator-Preset: %s" % get_preset_name(preset_index))

func set_simulator_auto_mode(enabled: bool) -> void:
	if sim_backend:
		sim_backend.control_mode = SimBackend.ControlMode.AUTO_CPR if enabled else SimBackend.ControlMode.MANUAL
		status_changed.emit("Simulator-Modus: %s" % ("Auto-CPR" if enabled else "Manuell / Hand-Tracking"))

func trigger_manual_compression(depth_mm: float, custom_rate: float = 0.0) -> void:
	if sim_backend and active_backend == sim_backend:
		sim_backend.trigger_manual_compression(depth_mm, custom_rate)

func trigger_manual_ventilation(volume_ml: float = 500.0) -> void:
	ventilation_measured.emit(volume_ml)
	if sim_backend and active_backend == sim_backend:
		sim_backend.trigger_manual_ventilation(volume_ml)
	if scenario and scenario.state == NaretScenario.State.CPR:
		scenario.submit_action("ventilation", {"source": "mannequin_sensor", "measurement_verified": true})

func get_preset_name(preset_index: int) -> String:
	match preset_index:
		SimBackend.Preset.GOOD_CPR: return "Gute CPR (55 mm, 110/min, ERC 2021)"
		SimBackend.Preset.TOO_SHALLOW: return "Zu flach (38 mm)"
		SimBackend.Preset.TOO_SLOW: return "Zu langsam (75/min)"
		SimBackend.Preset.TOO_FAST: return "Zu schnell (138/min)"
		SimBackend.Preset.INCOMPLETE_RELEASE: return "Unvollständige Entlastung (Leaning)"
		SimBackend.Preset.EXHAUSTION: return "Erschöpfung (Drift über Zeit)"
		_: return "Benutzerdefiniert"
