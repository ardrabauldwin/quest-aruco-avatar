class_name TestQcpr
extends "res://tests/suite.gd"
## Testsuite für QCPR-BLE-Stack, CPRM-Protokoll-Frames und Smart-Puppen-Simulator.

const Constants = preload("res://scripts/qcpr/qcpr_constants.gd")
const Packet = preload("res://scripts/qcpr/qcpr_packet.gd")
const SimBackend = preload("res://scripts/qcpr/simulated_manikin_backend.gd")
const RealBackend = preload("res://scripts/qcpr/qcpr_ble_real_backend.gd")
const Manager = preload("res://scripts/qcpr/qcpr_manager.gd")
const Scenario = preload("res://scripts/scenario/scenario_controller.gd")
const Score = preload("res://scripts/feedback/score_tracker.gd")

func run() -> Array[String]:
	_test_constants()
	_test_packet_roundtrips()
	_test_simulated_backend()
	_test_manager_integration()
	return failures

func _test_constants() -> void:
	check(Constants.CPRM_AUTH_KEY.size() == 18, "CPRM Auth Key must be 18 bytes")
	check(Constants.UUID_SERVICE_CPRM_COMMAND.begins_with("00001001"), "CPRM Command Service UUID")
	check(Constants.UUID_CHAR_CPRM_COMMAND.begins_with("00001002"), "CPRM Command Char UUID")
	check(Constants.UUID_CHAR_CPRM_RESPONSE.begins_with("00001003"), "CPRM Response Char UUID")
	check(Constants.UUID_SERVICE_CPRM_AUTH.begins_with("00001031"), "CPRM Auth Service UUID")
	check(Constants.UUID_CHAR_CPRM_AUTH_COMMAND.begins_with("00001032"), "CPRM Auth Command Char UUID")
	check(Constants.UUID_CHAR_CPRM_AUTH_RESPONSE.begins_with("00001033"), "CPRM Auth Response Char UUID")
	check(Constants.ADULT_DEPTH_MIN_MM == 50.0 and Constants.ADULT_DEPTH_MAX_MM == 60.0, "ERC 2021 depth bounds 50-60 mm")
	check(Constants.ADULT_RATE_MIN_BPM == 100.0 and Constants.ADULT_RATE_MAX_BPM == 120.0, "ERC 2021 rate bounds 100-120 bpm")

func _test_packet_roundtrips() -> void:
	# 1. Little-Endian Primitives
	var u16_encoded := Packet.encode_u16_le(0x1234)
	check(u16_encoded[0] == 0x34 and u16_encoded[1] == 0x12, "U16 Little-Endian encoding")
	check(Packet.decode_u16_le(u16_encoded) == 0x1234, "U16 Little-Endian decoding")

	var u32_encoded := Packet.encode_u32_le(0x12345678)
	check(u32_encoded[0] == 0x78 and u32_encoded[1] == 0x56 and u32_encoded[2] == 0x34 and u32_encoded[3] == 0x12, "U32 Little-Endian encoding")
	check(Packet.decode_u32_le(u32_encoded) == 0x12345678, "U32 Little-Endian decoding")

	# 2. CP_WAVE (192, 0xC0)
	var wave_raw := Packet.build_wave_packet(5, 1250, 54)
	var decoded_wave_frame := Packet.decode_frame(wave_raw)
	check(decoded_wave_frame.msg_id == Constants.ResponseId.CP_WAVE, "CP_WAVE message ID 192")
	check(decoded_wave_frame.seq == 5, "CP_WAVE sequence number")
	var parsed_wave := Packet.parse_wave(decoded_wave_frame.params)
	check(parsed_wave.session_time_ms == 1250 and parsed_wave.depth_mm == 54.0, "CP_WAVE payload roundtrip")

	# 3. CP_EVENT (193, 0xC1)
	var event_raw := Packet.build_event_packet(12, 10000, 220, 56, 540, false)
	var decoded_ev_frame := Packet.decode_frame(event_raw)
	check(decoded_ev_frame.msg_id == Constants.ResponseId.CP_EVENT, "CP_EVENT message ID 193")
	var parsed_ev := Packet.parse_event(decoded_ev_frame.params)
	check(parsed_ev.start_time_ms == 10000, "CP_EVENT StartTime")
	check(parsed_ev.time_to_peak_ms == 220, "CP_EVENT TimeToPeak")
	check(parsed_ev.max_depth_mm == 56.0, "CP_EVENT MaxDepth")
	check(parsed_ev.time_to_stop_ms == 540, "CP_EVENT TimeToStop")
	check(not parsed_ev.incomplete_release, "CP_EVENT Release status")

	# 4. CP_RATE (194, 0xC2)
	var rate_raw := Packet.build_rate_packet(20, 112)
	var decoded_rate_frame := Packet.decode_frame(rate_raw)
	check(decoded_rate_frame.msg_id == Constants.ResponseId.CP_RATE, "CP_RATE message ID 194")
	check(Packet.parse_rate(decoded_rate_frame.params) == 112, "CP_RATE payload roundtrip")

	# 5. QF Feedback Events (3-Byte-Payload)
	var qf_shallow := Packet.build_feedback_packet(30, Constants.ResponseId.QF_COMP_SHALLOW, Constants.FeedbackLevel.ALERT)
	var dec_shallow := Packet.decode_frame(qf_shallow)
	check(dec_shallow.msg_id == Constants.ResponseId.QF_COMP_SHALLOW, "QF_COMP_SHALLOW ID 226")
	check(dec_shallow.params.size() == 3, "QF Feedback 3-Byte payload")
	check(dec_shallow.params[0] == Constants.FeedbackLevel.ALERT, "QF Feedback level at pos 0")
	check(dec_shallow.params[1] == 0 and dec_shallow.params[2] == 0, "QF Feedback reserve bytes zero")
	check(Packet.parse_feedback(dec_shallow.params, dec_shallow.msg_id) == Constants.FeedbackLevel.ALERT, "parse_feedback shallow level")

	# QF_INACTIVITY: Level an Position 2, Position 0 = 0
	var qf_inact := Packet.build_feedback_packet(31, Constants.ResponseId.QF_INACTIVITY, Constants.FeedbackLevel.HIGH_ALERT)
	var dec_inact := Packet.decode_frame(qf_inact)
	check(dec_inact.msg_id == Constants.ResponseId.QF_INACTIVITY, "QF_INACTIVITY ID 224")
	check(dec_inact.params.size() == 3, "QF_INACTIVITY 3-Byte payload")
	check(dec_inact.params[0] == 0 and dec_inact.params[1] == 0, "QF_INACTIVITY pos 0/1 zero")
	check(dec_inact.params[2] == Constants.FeedbackLevel.HIGH_ALERT, "QF_INACTIVITY level at pos 2")
	check(Packet.parse_feedback(dec_inact.params, dec_inact.msg_id) == Constants.FeedbackLevel.HIGH_ALERT, "parse_feedback inactivity level")

	# QF_INCOMP_RELEASE, QF_COMP_SLOW, QF_COMP_FAST
	var qf_incomp := Packet.build_feedback_packet(32, Constants.ResponseId.QF_INCOMP_RELEASE, Constants.FeedbackLevel.WARNING)
	var dec_incomp := Packet.decode_frame(qf_incomp)
	check(dec_incomp.msg_id == Constants.ResponseId.QF_INCOMP_RELEASE and dec_incomp.params.size() == 3, "QF_INCOMP_RELEASE ID 225, 3 bytes")
	check(dec_incomp.params[0] == Constants.FeedbackLevel.WARNING and dec_incomp.params[2] == 0, "QF_INCOMP_RELEASE level at pos 0")

	var qf_slow := Packet.build_feedback_packet(33, Constants.ResponseId.QF_COMP_SLOW, Constants.FeedbackLevel.WARNING)
	var dec_slow := Packet.decode_frame(qf_slow)
	check(dec_slow.msg_id == Constants.ResponseId.QF_COMP_SLOW and dec_slow.params[0] == Constants.FeedbackLevel.WARNING, "QF_COMP_SLOW ID 227 level")

	var qf_fast := Packet.build_feedback_packet(34, Constants.ResponseId.QF_COMP_FAST, Constants.FeedbackLevel.HIGH_ALERT)
	var dec_fast := Packet.decode_frame(qf_fast)
	check(dec_fast.msg_id == Constants.ResponseId.QF_COMP_FAST and dec_fast.params[0] == Constants.FeedbackLevel.HIGH_ALERT, "QF_COMP_FAST ID 228 level")

	# 6. Auth Packet (MsgId 232, 0xE8)
	var auth_raw := Packet.build_auth_packet(40, true)
	var dec_auth := Packet.decode_frame(auth_raw)
	check(dec_auth.msg_id == Constants.ResponseId.SC_SECURITY_CODE, "SC_SECURITY_CODE ID 232")
	check(Packet.parse_auth(dec_auth.params) == true, "Auth success payload")

	# 7. Session Data (QS_DATA 208)
	var test_summary := {
		"session_start_time_ms": 1000,
		"session_stop_time_ms": 61000,
		"session_start_sec": 1,
		"session_stop_sec": 61,
		"adequate_rate_compressions": 95,
		"compressions_with_rate": 100,
		"correct_release_compressions": 98,
		"adequate_depth_compressions": 96,
		"inactivity_time_sec": 4,
		"total_compressions": 100,
		"inactivity_periods": 1,
		"compressions_no_errors": 92,
		"average_depth_mm": 55,
		"compressions_too_shallow": 2,
		"average_rate_bpm": 110,
		"compressions_too_slow": 3,
		"compressions_too_fast": 2
	}
	var qs_raw := Packet.build_session_data_packet(50, test_summary)
	var dec_qs := Packet.decode_frame(qs_raw)
	check(dec_qs.msg_id == Constants.ResponseId.QS_DATA, "QS_DATA ID 208")
	check(dec_qs.params.size() == 36, "QS_DATA 36 byte payload")
	var parsed_qs := Packet.parse_session_data(dec_qs.params)
	check(parsed_qs.total_compressions == 100, "QS_DATA total compressions")
	check(parsed_qs.adequate_depth_compressions == 96, "QS_DATA adequate depth")
	check(parsed_qs.average_depth_mm == 55, "QS_DATA average depth")
	check(parsed_qs.average_rate_bpm == 110, "QS_DATA average rate")

func _test_simulated_backend() -> void:
	var sim := SimBackend.new()
	check(sim.is_simulated() == true, "Backend identifies as simulated")
	check(sim.state == SimBackend.State.READY, "Initial state after ready is READY")

	# Preset-Prüfung
	sim.current_preset = SimBackend.Preset.GOOD_CPR
	check(sim.target_depth_mm == 55.0 and sim.target_rate_bpm == 110.0, "Preset GOOD_CPR matches ERC 2021")

	sim.current_preset = SimBackend.Preset.TOO_SHALLOW
	check(sim.target_depth_mm == 38.0, "Preset TOO_SHALLOW sets <50 mm")

	sim.current_preset = SimBackend.Preset.TOO_SLOW
	check(sim.target_rate_bpm == 75.0, "Preset TOO_SLOW sets <100 bpm")

	sim.current_preset = SimBackend.Preset.TOO_FAST
	check(sim.target_rate_bpm == 138.0, "Preset TOO_FAST sets >120 bpm")

	sim.current_preset = SimBackend.Preset.INCOMPLETE_RELEASE
	check(sim.residual_depth_mm == 12.0, "Preset INCOMPLETE_RELEASE sets residual depth")

	# Auth-Handshake Prüfung
	var bad_key := PackedByteArray([1, 2, 3, 4])
	var bad_result := sim.simulate_auth_handshake(bad_key)
	check(bad_result == false, "Invalid key rejects authentication")

	var good_result := sim.simulate_auth_handshake(Constants.CPRM_AUTH_KEY)
	check(good_result == true, "Valid CPRM key accepts authentication")
	check(sim.state == SimBackend.State.READY, "State after valid auth is READY")

	# Manuelle Kompression auslösen & Signale prüfen
	var waves: Array = []
	var events: Array = []

	sim.compression_wave.connect(func(time_ms: int, depth: float): waves.append({"time": time_ms, "depth": depth}))
	sim.compression_event.connect(func(depth: float, rate: float, recoil: bool, dur: float):
		events.append({"depth": depth, "rate": rate, "recoil": recoil, "duration": dur}))

	sim.trigger_manual_compression(55.0, 110.0)
	check(events.size() > 0, "Manual compression triggers compression_event signal")
	if events.size() > 0:
		var measured_depth: float = events[0].depth
		check(measured_depth >= 50.0 and measured_depth <= 60.0, "Manual compression depth in ERC 2021 range")

	# Test Auto-CPR Ticking & Physik
	var auto_events: Array = []
	sim.compression_event.connect(func(d: float, r: float, rec: bool, dur: float):
		auto_events.append({"depth": d, "rate": r, "recoil": rec, "duration": dur}))

	sim.control_mode = SimBackend.ControlMode.AUTO_CPR
	sim.current_preset = SimBackend.Preset.GOOD_CPR
	sim.noise_enabled = false
	# Bei 110 bpm dauert ein Hub ca. 0.545 s. 6 Ticks à 0.1 s = 0.6 s -> mind. 1 Hub
	for i in 6:
		sim._process(0.1)
	check(auto_events.size() >= 1, "Auto-CPR generates strokes via physics process")
	if auto_events.size() >= 1:
		check(auto_events[0].depth >= 50.0 and auto_events[0].depth <= 60.0, "Auto stroke depth in ERC range")

	# Test Exhaustion Preset Drift
	sim.current_preset = SimBackend.Preset.EXHAUSTION
	sim.noise_enabled = false
	var initial_rate := sim.target_rate_bpm
	var initial_depth := sim.target_depth_mm
	# 40 Sekunden simulieren
	for i in 40:
		sim._process(1.0)
	check(sim.target_rate_bpm < initial_rate, "Exhaustion preset drifts rate downwards")
	check(sim.target_depth_mm < initial_depth, "Exhaustion preset drifts depth downwards")

	# Test Session Stop & QS_DATA Frame
	var summaries: Array = []
	sim.session_summary_received.connect(func(s: Dictionary): summaries.append(s))
	sim.stop_session()
	check(summaries.size() == 1, "stop_session generates QS_DATA summary")

	sim.free()

func _test_manager_integration() -> void:
	var manager := Manager.new()
	manager._setup_backends()
	check(manager.active_backend != null, "Manager has active backend")
	check(manager.active_backend.is_simulated(), "Default backend falls back to simulator")

	var feedbacks: Array = []
	manager.quality_feedback.connect(func(type: String, de: String, pl: String, good: bool):
		feedbacks.append({"type": type, "de": de, "good": good}))

	var scenario := Scenario.new()
	var score := Score.new()
	scenario.event_recorded.connect(score.record)
	manager.scenario = scenario

	# Szenario in CPR-Zustand überführen
	scenario.start()
	scenario.submit_action("begin_check")
	scenario.submit_action("check_responsiveness")
	scenario.submit_action("call_emergency")  # ERC 2025: 112 before the breathing check
	scenario.submit_action("check_breathing")
	check(scenario.state == Scenario.State.CPR, "Scenario entered CPR state")

	# Gute Kompression einspeisen (55 mm, 110 bpm)
	manager.trigger_manual_compression(55.0, 110.0)
	check(scenario.compressions == 1, "Scenario accepted simulated compression")
	check(score.measured_compressions == 1, "Score recorded verified measurement")
	check(score.depth_in_range == 1, "Verified depth 55 mm is in ERC range [5.0, 6.0] cm")
	check(score.rate_in_range == 1, "Verified rate 110 bpm is in ERC range [100, 120] bpm")

	# Zu flache Kompression einspeisen (38 mm, 110 bpm) -> löst shallow Feedback aus
	manager.trigger_manual_compression(38.0, 110.0)
	check(scenario.compressions == 2, "Scenario accepted 2nd compression")
	check(score.measured_compressions == 2, "Score recorded 2nd verified measurement")
	check(score.depth_in_range == 1, "Too shallow compression (38 mm) not in range")
	check(feedbacks.any(func(f): return f.type == "shallow"), "Manager emitted shallow feedback")

	# Zu langsame Kompression einspeisen (55 mm, 75 bpm) -> löst slow Feedback aus
	manager.trigger_manual_compression(55.0, 75.0)
	check(feedbacks.any(func(f): return f.type == "slow"), "Manager emitted slow feedback")

	# Beatmung testen
	manager.trigger_manual_ventilation(500.0)
	check(manager.active_backend.is_simulated(), "Backend remains simulated")

	# Umschalten auf reales Backend und zurück testen
	var sim_ref := manager.sim_backend
	manager.set_active_backend(manager.real_backend)
	check(manager.active_backend == manager.real_backend, "Switched to real BLE backend")
	manager.set_active_backend(sim_ref)
	check(manager.active_backend == sim_ref, "Switched back to simulated backend")

	manager.free()
	scenario.free()
