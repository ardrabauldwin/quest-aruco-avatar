class_name NaretSimulatedManikinBackend
extends NaretQcprBackend
## Smart-Puppen-Simulator auf Protokollebene.
##
## Simuliert eine QCPR-Trainingspuppe exakt nach der CPRM-Protokollspezifikation:
## identische Message-IDs, Little-Endian Frame-Layouts, Auth-Handshake und Sensorik.
##
## Beinhaltet ein physiologisches Physik-Modell für Brustkorbkompressionen mit
## anpassbarem Rauschen, asymmetrischen Kompressionskurven und Szenario-Presets.

const Constants = preload("res://scripts/qcpr/qcpr_constants.gd")
const Packet = preload("res://scripts/qcpr/qcpr_packet.gd")

# Steuerungsmodi
enum ControlMode {
	MANUAL,    # Gesteuert über Hand-Tracking, Controller oder Tastatur
	AUTO_CPR   # Kontinuierliches Abspielen nach eingestelltem Preset / Szenario
}

# Presets für Qualitätsszenarien
enum Preset {
	GOOD_CPR,            # 55 mm, 110 bpm, vollständige Entlastung (ERC 2021)
	TOO_SHALLOW,         # 38 mm, 110 bpm (< 50 mm)
	TOO_SLOW,            # 54 mm, 75 bpm (< 100 bpm)
	TOO_FAST,            # 52 mm, 138 bpm (> 120 bpm)
	INCOMPLETE_RELEASE,  # 54 mm, 110 bpm, 12 mm Resttiefe (Leaning)
	EXHAUSTION           # Frequenz und Tiefe driften über Zeit ab (Ermüdung)
}

# Konfigurierbare Physik- und Sensorparameter
@export var control_mode: int = ControlMode.AUTO_CPR
@export var current_preset: int = Preset.GOOD_CPR:
	set(value):
		current_preset = value
		_apply_preset(value)

@export_range(60.0, 160.0, 1.0) var target_rate_bpm := 110.0
@export_range(10.0, 70.0, 1.0) var target_depth_mm := 55.0
@export_range(0.0, 25.0, 0.5) var residual_depth_mm := 0.0  # Unvollständige Entlastung
@export var noise_enabled := true
@export var cycle_30_2_enabled := false  # Nach 30 Kompressionen Pause für 2 Beatmungen

# Simulationstakt & Session-Status
var session_active := false
var session_time_ms := 0
var simulated_battery := 98

# Aktueller Hub-Zustand (Wellensimulation)
var _stroke_phase := 0.0          # 0.0 .. 1.0 im Kompressionszyklus
var _stroke_active := false
var _stroke_start_time_ms := 0
var _stroke_peak_time_ms := 0
var _stroke_current_depth := 0.0
var _stroke_max_depth := 0.0
var _last_stroke_completed_ms := 0
var _inactivity_ms := 0
var _exhaustion_timer := 0.0

# 30:2 Zyklen-Zähler
var compressions_in_cycle := 0
var ventilations_in_cycle := 0
var is_ventilating := false
var _ventilation_timer := 0.0

# Statistiken für QS_DATA (Session-Zusammenfassung)
var _stat_start_time_ms := 0
var _stat_total_compressions := 0
var _stat_adequate_depth := 0
var _stat_adequate_rate := 0
var _stat_correct_release := 0
var _stat_compressions_with_rate := 0
var _stat_no_errors := 0
var _stat_too_shallow := 0
var _stat_too_slow := 0
var _stat_too_fast := 0
var _stat_depth_sum := 0.0
var _stat_rate_sum := 0.0
var _stat_inactivity_periods := 0
var _stat_total_inactivity_sec := 0.0

# Sampling-Timer für CP_WAVE (ca. 25 Hz = 40 ms)
var _wave_sample_timer := 0.0
const WAVE_SAMPLE_INTERVAL := 0.04

func _init() -> void:
	device_name = "Simulated QCPR Manikin"
	_apply_preset(current_preset)
	connect_device("SIM:00:11:22:33:44:55")

func _ready() -> void:
	if state < State.READY:
		connect_device("SIM:00:11:22:33:44:55")

func get_backend_name() -> String:
	return "Smart-Puppen-Simulator (QCPR-CPRM)"

func is_simulated() -> bool:
	return true

func _apply_preset(preset_idx: int) -> void:
	match preset_idx:
		Preset.GOOD_CPR:
			target_depth_mm = Constants.TARGET_DEPTH_MM   # 55 mm (ERC 50-60 mm)
			target_rate_bpm = Constants.TARGET_RATE_BPM   # 110 bpm (ERC 100-120 bpm)
			residual_depth_mm = 0.0
		Preset.TOO_SHALLOW:
			target_depth_mm = 38.0
			target_rate_bpm = 110.0
			residual_depth_mm = 0.0
		Preset.TOO_SLOW:
			target_depth_mm = 54.0
			target_rate_bpm = 75.0
			residual_depth_mm = 0.0
		Preset.TOO_FAST:
			target_depth_mm = 52.0
			target_rate_bpm = 138.0
			residual_depth_mm = 0.0
		Preset.INCOMPLETE_RELEASE:
			target_depth_mm = 54.0
			target_rate_bpm = 108.0
			residual_depth_mm = 12.0  # 12 mm verbleibender Druck
		Preset.EXHAUSTION:
			target_depth_mm = 55.0
			target_rate_bpm = 112.0
			residual_depth_mm = 0.0
			_exhaustion_timer = 0.0

# --- Verbindung & Authentifizierung ---

func connect_device(address: String = "SIM:00:11:22:33:44:55") -> void:
	device_address = address
	state = State.CONNECTING
	status_message.emit("Simulator: Verbindungsaufbau...")
	# Simulierter Handshake: Connect -> Auth Key prüfen -> Ready
	state = State.CONNECTED
	connected.emit()
	simulate_auth_handshake(Constants.CPRM_AUTH_KEY)

func disconnect_device() -> void:
	if state == State.DISCONNECTED:
		return
	stop_session()
	state = State.DISCONNECTED
	disconnected.emit()
	status_message.emit("Simulator: Getrennt.")

func simulate_auth_handshake(key: PackedByteArray) -> bool:
	state = State.AUTHENTICATING
	var valid := (key == Constants.CPRM_AUTH_KEY)
	var auth_packet := Packet.build_auth_packet(get_next_sequence(), valid)
	_dispatch_raw_packet(auth_packet)

	if valid:
		state = State.READY
		authenticated.emit(true)
		status_message.emit("Simulator: Authentifiziert (CPRM Security Code OK).")
		start_session()
		return true
	else:
		state = State.CONNECTED
		authenticated.emit(false)
		status_message.emit("Simulator: Authentifizierung fehlgeschlagen.")
		return false

func send_command(msg_id: int, params: PackedByteArray = PackedByteArray()) -> bool:
	if state < State.CONNECTED:
		return false
	match msg_id:
		Constants.CommandId.SC_SECURITY_CODE:
			return simulate_auth_handshake(params)
		Constants.CommandId.LG_GET_BATTERY_LEVEL:
			var resp := Packet.build_battery_packet(get_next_sequence(), simulated_battery)
			_dispatch_raw_packet(resp)
			return true
		Constants.CommandId.LG_SET_RTC_TIME:
			var resp := Packet.encode_frame(Constants.ResponseId.LG_SET_RTC_TIME, get_next_sequence())
			_dispatch_raw_packet(resp)
			return true
		Constants.CommandId.DI_MODEL_NUMBER:
			var resp := Packet.encode_frame(Constants.ResponseId.DI_MODEL_NUMBER, get_next_sequence(), "QCPR Sim MK1".to_utf8_buffer())
			_dispatch_raw_packet(resp)
			return true
	return true

func start_session() -> void:
	session_active = true
	session_time_ms = 0
	_stroke_phase = 0.0
	_stroke_active = false
	_inactivity_ms = 0
	compressions_in_cycle = 0
	ventilations_in_cycle = 0
	is_ventilating = false
	_stat_start_time_ms = Time.get_ticks_msec()
	_stat_total_compressions = 0
	_stat_adequate_depth = 0
	_stat_adequate_rate = 0
	_stat_correct_release = 0
	_stat_compressions_with_rate = 0
	_stat_no_errors = 0
	_stat_too_shallow = 0
	_stat_too_slow = 0
	_stat_too_fast = 0
	_stat_depth_sum = 0.0
	_stat_rate_sum = 0.0
	_stat_inactivity_periods = 0
	_stat_total_inactivity_sec = 0.0
	status_message.emit("Simulator: CPR-Session gestartet.")

func stop_session() -> void:
	if not session_active:
		return
	session_active = false
	# Erzeuge QS_DATA Zusammenfassungsframe (MsgId 208)
	var stop_time := Time.get_ticks_msec()
	var avg_depth := int(_stat_depth_sum / maxf(1.0, float(_stat_total_compressions)))
	var avg_rate := int(_stat_rate_sum / maxf(1.0, float(_stat_compressions_with_rate)))

	var summary_data := {
		"session_start_time_ms": _stat_start_time_ms,
		"session_stop_time_ms": stop_time,
		"session_start_sec": _stat_start_time_ms / 1000,
		"session_stop_sec": stop_time / 1000,
		"adequate_rate_compressions": _stat_adequate_rate,
		"compressions_with_rate": _stat_compressions_with_rate,
		"correct_release_compressions": _stat_correct_release,
		"adequate_depth_compressions": _stat_adequate_depth,
		"inactivity_time_sec": int(_stat_total_inactivity_sec),
		"total_compressions": _stat_total_compressions,
		"inactivity_periods": _stat_inactivity_periods,
		"compressions_no_errors": _stat_no_errors,
		"average_depth_mm": avg_depth,
		"compressions_too_shallow": _stat_too_shallow,
		"average_rate_bpm": avg_rate,
		"compressions_too_slow": _stat_too_slow,
		"compressions_too_fast": _stat_too_fast
	}

	var packet := Packet.build_session_data_packet(get_next_sequence(), summary_data)
	_dispatch_raw_packet(packet)
	status_message.emit("Simulator: Session beendet (QS_DATA generiert).")

# --- Manuelle Steuerung (Hand-Tracking / Controller / Keyboard) ---

## Wird von XR-Interaktion oder Tastatur aufgerufen, um eine manuelle Kompression einzuspeisen
func trigger_manual_compression(depth_mm: float, custom_rate_bpm: float = 0.0) -> void:
	if not session_active:
		start_session()

	var actual_depth := depth_mm
	if noise_enabled:
		actual_depth += randf_range(-1.2, 1.2)
	actual_depth = maxf(0.0, actual_depth)

	var now := session_time_ms
	var rate := custom_rate_bpm
	if rate <= 0.0:
		if _last_stroke_completed_ms > 0 and now > _last_stroke_completed_ms:
			var interval_sec := float(now - _last_stroke_completed_ms) / 1000.0
			if interval_sec > 0.15 and interval_sec < 2.5:
				rate = 60.0 / interval_sec
		if rate <= 0.0:
			rate = target_rate_bpm

	var duration_ms := int(60000.0 / maxf(1.0, rate))
	var peak_ms := int(duration_ms * 0.4)
	var stop_ms := duration_ms
	var start_ms := maxi(0, now - duration_ms)

	var incomplete := (residual_depth_mm > 4.0)
	_complete_compression_stroke(start_ms, peak_ms, actual_depth, stop_ms, rate, incomplete)

## Manuelle Beatmung auslösen
func trigger_manual_ventilation(volume_ml: float = 500.0) -> void:
	feedback_event.emit("ventilation", Constants.FeedbackLevel.OK, "Beatmung: %.0f ml" % volume_ml)

# --- Physik-Engine & Ticking ---

func _process(delta: float) -> void:
	if not session_active or state != State.READY:
		return

	session_time_ms += int(delta * 1000.0)

	# Ermüdungs-Drift für Preset EXHAUSTION
	if current_preset == Preset.EXHAUSTION:
		_exhaustion_timer += delta
		# Nach 10 s beginnt Drift: Frequenz fällt auf 82 bpm, Tiefe auf 36 mm nach 50 s
		if _exhaustion_timer > 10.0:
			var factor := clampf((_exhaustion_timer - 10.0) / 40.0, 0.0, 1.0)
			target_rate_bpm = lerpf(112.0, 82.0, factor)
			target_depth_mm = lerpf(55.0, 36.0, factor)

	# Beatmungspause im 30:2 Modus
	if cycle_30_2_enabled and is_ventilating:
		_ventilation_timer += delta
		_stroke_current_depth = 0.0
		if _ventilation_timer >= 4.0: # ca. 4 Sekunden für 2 Beatmungen
			is_ventilating = false
			compressions_in_cycle = 0
			_ventilation_timer = 0.0
			feedback_event.emit("resume_cpr", Constants.FeedbackLevel.OK, "Beatmung abgeschlossen · CPR fortsetzen")
		return

	# Inaktivitätsüberwachung
	var since_last := session_time_ms - _last_stroke_completed_ms
	if since_last > 1500 and not _stroke_active:
		_inactivity_ms = since_last
		if _inactivity_ms > Constants.MAX_INACTIVITY_WARNING_MS:
			var inact_packet := Packet.build_inactivity_packet(get_next_sequence(), _inactivity_ms, Constants.FeedbackLevel.ALERT)
			_dispatch_raw_packet(inact_packet)
			_stat_inactivity_periods += 1
			_stat_total_inactivity_sec += delta

	# AUTO-Modus Ausführung
	if control_mode == ControlMode.AUTO_CPR:
		_step_auto_cpr(delta)

	# Wave-Sampling-Timer (25 Hz Datenstream an App)
	_wave_sample_timer += delta
	if _wave_sample_timer >= WAVE_SAMPLE_INTERVAL:
		_wave_sample_timer = 0.0
		var wave_depth := int(round(_stroke_current_depth))
		var wave_packet := Packet.build_wave_packet(get_next_sequence(), session_time_ms, wave_depth)
		_dispatch_raw_packet(wave_packet)

func _step_auto_cpr(delta: float) -> void:
	var current_rate := target_rate_bpm
	if noise_enabled:
		current_rate += sin(session_time_ms * 0.003) * 1.8

	var stroke_duration := 60.0 / maxf(1.0, current_rate) # Dauer in Sekunden

	if not _stroke_active:
		_stroke_active = true
		_stroke_phase = 0.0
		_stroke_start_time_ms = session_time_ms
		_stroke_max_depth = target_depth_mm
		if noise_enabled:
			_stroke_max_depth += randf_range(-1.5, 1.5)
		_stroke_peak_time_ms = int(stroke_duration * 0.38 * 1000.0)

	_stroke_phase += delta / stroke_duration

	# Physiologische Kompressionskurve:
	# Phase 0.0 bis 0.38 = Abwärtskompression (Sinus-Viertelwelle 0 -> 1)
	# Phase 0.38 bis 1.0 = Aufwärtsentlastung (Sinus-Viertelwelle 1 -> Resttiefe)
	if _stroke_phase < 0.38:
		var norm := _stroke_phase / 0.38
		var curve := sin(norm * PI * 0.5)
		_stroke_current_depth = curve * _stroke_max_depth
	elif _stroke_phase < 1.0:
		var norm := (_stroke_phase - 0.38) / 0.62
		var curve := cos(norm * PI * 0.5)
		_stroke_current_depth = residual_depth_mm + curve * (_stroke_max_depth - residual_depth_mm)
	else:
		# Stroke abgeschlossen
		_stroke_current_depth = residual_depth_mm
		_stroke_active = false
		var duration_ms := int(stroke_duration * 1000.0)
		var incomplete := (residual_depth_mm > 4.0)

		_complete_compression_stroke(
			_stroke_start_time_ms,
			_stroke_peak_time_ms,
			_stroke_max_depth,
			duration_ms,
			current_rate,
			incomplete
		)

		compressions_in_cycle += 1
		if cycle_30_2_enabled and compressions_in_cycle >= 30:
			is_ventilating = true
			_ventilation_timer = 0.0
			feedback_event.emit("ventilate", Constants.FeedbackLevel.OK, "30 Kompressionen erreicht · 2 Beatmungen durchführen")

func _complete_compression_stroke(start_ms: int, peak_ms: int, depth: float, stop_ms: int, rate: float, incomplete_release: bool) -> void:
	_last_stroke_completed_ms = session_time_ms
	_inactivity_ms = 0

	# 1. CP_EVENT Frame erzeugen und senden
	var event_packet := Packet.build_event_packet(
		get_next_sequence(),
		start_ms,
		peak_ms,
		int(round(depth)),
		stop_ms,
		incomplete_release
	)
	_dispatch_raw_packet(event_packet)

	# 2. CP_RATE Frame erzeugen und senden
	var rate_packet := Packet.build_rate_packet(get_next_sequence(), int(round(rate)))
	_dispatch_raw_packet(rate_packet)

	# 3. Qualitätsanalyse & QF_* Feedback-Frames erzeugen
	var is_depth_ok := (depth >= Constants.ADULT_DEPTH_MIN_MM and depth <= Constants.ADULT_DEPTH_MAX_MM)
	var is_rate_ok := (rate >= Constants.ADULT_RATE_MIN_BPM and rate <= Constants.ADULT_RATE_MAX_BPM)
	var is_release_ok := not incomplete_release

	if depth < Constants.ADULT_DEPTH_MIN_MM:
		var qf := Packet.build_feedback_packet(get_next_sequence(), Constants.ResponseId.QF_COMP_SHALLOW, Constants.FeedbackLevel.ALERT)
		_dispatch_raw_packet(qf)
		_stat_too_shallow += 1
	elif depth > Constants.ADULT_DEPTH_MAX_MM:
		# Tiefenwarnung
		feedback_event.emit("too_deep", Constants.FeedbackLevel.WARNING, "Etwas weniger tief drücken (max. 60 mm)")

	if rate < Constants.ADULT_RATE_MIN_BPM:
		var qf := Packet.build_feedback_packet(get_next_sequence(), Constants.ResponseId.QF_COMP_SLOW, Constants.FeedbackLevel.ALERT)
		_dispatch_raw_packet(qf)
		_stat_too_slow += 1
	elif rate > Constants.ADULT_RATE_MAX_BPM:
		var qf := Packet.build_feedback_packet(get_next_sequence(), Constants.ResponseId.QF_COMP_FAST, Constants.FeedbackLevel.ALERT)
		_dispatch_raw_packet(qf)
		_stat_too_fast += 1

	if incomplete_release:
		var qf := Packet.build_feedback_packet(get_next_sequence(), Constants.ResponseId.QF_INCOMP_RELEASE, Constants.FeedbackLevel.ALERT)
		_dispatch_raw_packet(qf)

	# Statistik aktualisieren
	_stat_total_compressions += 1
	_stat_depth_sum += depth
	_stat_rate_sum += rate
	_stat_compressions_with_rate += 1
	if is_depth_ok: _stat_adequate_depth += 1
	if is_rate_ok: _stat_adequate_rate += 1
	if is_release_ok: _stat_correct_release += 1
	if is_depth_ok and is_rate_ok and is_release_ok:
		_stat_no_errors += 1

# --- Frame-Dispatch (entspricht dem Empfang über GATT Notify) ---

func _dispatch_raw_packet(data: PackedByteArray) -> void:
	var decoded := Packet.decode_frame(data)
	if not decoded.valid:
		return

	var msg_id: int = decoded.msg_id
	var params: PackedByteArray = decoded.params

	if msg_id == Constants.ResponseId.SC_SECURITY_CODE:
		var ok := Packet.parse_auth(params)
		authenticated.emit(ok)
	elif msg_id == Constants.ResponseId.CP_WAVE:
		var wave := Packet.parse_wave(params)
		if wave.valid:
			compression_wave.emit(wave.session_time_ms, wave.depth_mm)
	elif msg_id == Constants.ResponseId.CP_EVENT:
		var ev := Packet.parse_event(params)
		if ev.valid:
			compression_event.emit(ev.max_depth_mm, target_rate_bpm, not ev.incomplete_release, float(ev.time_to_stop_ms))
	elif msg_id == Constants.ResponseId.CP_RATE:
		var r := Packet.parse_rate(params)
		compression_rate.emit(float(r))
	elif msg_id == Constants.ResponseId.CP_INACTIVITY:
		var inact := Packet.parse_inactivity(params)
		if inact.valid:
			inactivity_reported.emit(inact.inactivity_ms, inact.level)
	elif msg_id == Constants.ResponseId.QF_COMP_SHALLOW:
		feedback_event.emit("shallow", Packet.parse_feedback(params, msg_id), "Zu flach (< 50 mm)")
	elif msg_id == Constants.ResponseId.QF_COMP_SLOW:
		feedback_event.emit("slow", Packet.parse_feedback(params, msg_id), "Zu langsam (< 100/min)")
	elif msg_id == Constants.ResponseId.QF_COMP_FAST:
		feedback_event.emit("fast", Packet.parse_feedback(params, msg_id), "Zu schnell (> 120/min)")
	elif msg_id == Constants.ResponseId.QF_INCOMP_RELEASE:
		feedback_event.emit("incomplete_release", Packet.parse_feedback(params, msg_id), "Unvollständige Entlastung")
	elif msg_id == Constants.ResponseId.QF_INACTIVITY:
		feedback_event.emit("inactivity", Packet.parse_feedback(params, msg_id), "Pause zu lang")
	elif msg_id == Constants.ResponseId.LG_GET_BATTERY_LEVEL:
		battery_percent = Packet.parse_battery(params)
		battery_level_changed.emit(battery_percent)
	elif msg_id == Constants.ResponseId.QS_DATA:
		var summary := Packet.parse_session_data(params)
		if summary.valid:
			session_summary_received.emit(summary)
