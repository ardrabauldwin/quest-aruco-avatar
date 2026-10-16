class_name NaretQcprPacket
extends RefCounted
## Serialisierung und Deserialisierung von CPRM-Binärframes im Little-Endian-Format.
##
## Ein CPRM-Frame hat immer folgendes Basisformat:
##   Byte 0:    MsgId (uint8)
##   Byte 1:    SeqNo (uint8, 0..254)
##   Byte 2..N: Parameter (nutzlastabhängig, little-endian)

const Constants = preload("res://scripts/qcpr/qcpr_constants.gd")

# --- Little-Endian Hilfsfunktionen ---

static func encode_u16_le(value: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(2)
	bytes[0] = value & 0xFF
	bytes[1] = (value >> 8) & 0xFF
	return bytes

static func decode_u16_le(data: PackedByteArray, offset: int = 0) -> int:
	if data.size() < offset + 2:
		return 0
	return int(data[offset]) | (int(data[offset + 1]) << 8)

static func encode_u32_le(value: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes[0] = value & 0xFF
	bytes[1] = (value >> 8) & 0xFF
	bytes[2] = (value >> 16) & 0xFF
	bytes[3] = (value >> 24) & 0xFF
	return bytes

static func decode_u32_le(data: PackedByteArray, offset: int = 0) -> int:
	if data.size() < offset + 4:
		return 0
	return int(data[offset]) | (int(data[offset + 1]) << 8) | (int(data[offset + 2]) << 16) | (int(data[offset + 3]) << 24)

# --- Frame Basis-Operationen ---

static func encode_frame(msg_id: int, seq: int, params: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var frame := PackedByteArray()
	frame.resize(2 + params.size())
	frame[0] = msg_id & 0xFF
	frame[1] = seq & 0xFF
	for i in range(params.size()):
		frame[2 + i] = params[i]
	return frame

static func decode_frame(data: PackedByteArray) -> Dictionary:
	if data.size() < 2:
		return {"valid": false, "msg_id": 0, "seq": 0, "params": PackedByteArray()}
	var msg_id := int(data[0])
	var seq := int(data[1])
	var params := data.slice(2)
	return {
		"valid": true,
		"msg_id": msg_id,
		"seq": seq,
		"params": params
	}

# --- Spezifische Packet-Encoder (Puppe -> App) ---

## CP_WAVE (MsgId 192, 0xC0): Laufende Kompressionstiefe
## Payload: [0..3] SessionTime (uint32 ms), [4] CompressionDepth (uint8 mm)
static func build_wave_packet(seq: int, session_time_ms: int, depth_mm: int) -> PackedByteArray:
	var params := PackedByteArray()
	params.resize(5)
	var time_bytes := encode_u32_le(session_time_ms)
	for i in 4: params[i] = time_bytes[i]
	params[4] = clampi(depth_mm, 0, 255)
	return encode_frame(Constants.ResponseId.CP_WAVE, seq, params)

## CP_EVENT (MsgId 193, 0xC1): Abgeschlossener Einzel-Kompressionshub
## Payload:
##   [0..3] StartTime (uint32 ms)
##   [4..5] TimeToPeak (uint16 ms)
##   [6]    MaxDepth (uint8 mm)
##   [7..8] TimeToStop (uint16 ms)
##   [9]    IsIncompleteRelease (uint8 bool: 0 oder 1)
static func build_event_packet(seq: int, start_time_ms: int, time_to_peak_ms: int, max_depth_mm: int, time_to_stop_ms: int, incomplete_release: bool) -> PackedByteArray:
	var params := PackedByteArray()
	params.resize(10)
	var start_bytes := encode_u32_le(start_time_ms)
	for i in 4: params[i] = start_bytes[i]
	var peak_bytes := encode_u16_le(time_to_peak_ms)
	params[4] = peak_bytes[0]
	params[5] = peak_bytes[1]
	params[6] = clampi(max_depth_mm, 0, 255)
	var stop_bytes := encode_u16_le(time_to_stop_ms)
	params[7] = stop_bytes[0]
	params[8] = stop_bytes[1]
	params[9] = 1 if incomplete_release else 0
	return encode_frame(Constants.ResponseId.CP_EVENT, seq, params)

## CP_RATE (MsgId 194, 0xC2): Aktuelle Frequenz
## Payload: [0..1] CompressionRate (uint16 bpm)
static func build_rate_packet(seq: int, rate_bpm: int) -> PackedByteArray:
	var params := encode_u16_le(clampi(rate_bpm, 0, 65535))
	return encode_frame(Constants.ResponseId.CP_RATE, seq, params)

## CP_INACTIVITY (MsgId 195, 0xC3): Inaktivitätswarnung
## Payload: [0..1] Inactivity (uint16 ms), [2] Level (uint8)
static func build_inactivity_packet(seq: int, inactivity_ms: int, level: int = Constants.FeedbackLevel.WARNING) -> PackedByteArray:
	var params := PackedByteArray()
	params.resize(3)
	var ms_bytes := encode_u16_le(clampi(inactivity_ms, 0, 65535))
	params[0] = ms_bytes[0]
	params[1] = ms_bytes[1]
	params[2] = clampi(level, 0, 255)
	return encode_frame(Constants.ResponseId.CP_INACTIVITY, seq, params)

## QF_* Feedback-Events (MsgId 224..228)
## Payload (3 Byte): [0] FeedbackLevel, [1] Reserve (0), [2] Reserve (0)
## Sonderfall QF_INACTIVITY (224): Position 0 = 0, Level-Wert an Position 2.
static func build_feedback_packet(seq: int, msg_id: int, level: int) -> PackedByteArray:
	var params := PackedByteArray([0, 0, 0])
	var lvl := clampi(level, 0, 3)
	if msg_id == Constants.ResponseId.QF_INACTIVITY:
		params[2] = lvl
	else:
		params[0] = lvl
	return encode_frame(msg_id, seq, params)

## SC_SECURITY_CODE (MsgId 232, 0xE8): Authentifizierungsantwort
## Payload: [0] IsAuthenticated (uint8 bool: 1 oder 0)
static func build_auth_packet(seq: int, is_authenticated: bool) -> PackedByteArray:
	var params := PackedByteArray([1 if is_authenticated else 0])
	return encode_frame(Constants.ResponseId.SC_SECURITY_CODE, seq, params)

## LG_GET_BATTERY_LEVEL (MsgId 140, 0x8C): Akkustand
## Payload: [0] BatteryLevel (uint8 Prozent: 0..100)
static func build_battery_packet(seq: int, level_percent: int) -> PackedByteArray:
	var params := PackedByteArray([clampi(level_percent, 0, 100)])
	return encode_frame(Constants.ResponseId.LG_GET_BATTERY_LEVEL, seq, params)

## QS_DATA (MsgId 208, 0xD0): QCPR-Session-Zusammenfassung (36 Bytes Payload)
static func build_session_data_packet(seq: int, data: Dictionary) -> PackedByteArray:
	var params := PackedByteArray()
	params.resize(36)
	var start_ms := encode_u32_le(int(data.get("session_start_time_ms", 0)))
	var stop_ms := encode_u32_le(int(data.get("session_stop_time_ms", 0)))
	for i in 4:
		params[i] = start_ms[i]
		params[4 + i] = stop_ms[i]
	var start_sec := encode_u16_le(int(data.get("session_start_sec", 0)))
	var stop_sec := encode_u16_le(int(data.get("session_stop_sec", 0)))
	params[8] = start_sec[0]; params[9] = start_sec[1]
	params[10] = stop_sec[0]; params[11] = stop_sec[1]

	var adeq_rate := encode_u16_le(int(data.get("adequate_rate_compressions", 0)))
	params[12] = adeq_rate[0]; params[13] = adeq_rate[1]
	var with_rate := encode_u16_le(int(data.get("compressions_with_rate", 0)))
	params[14] = with_rate[0]; params[15] = with_rate[1]
	var correct_rel := encode_u16_le(int(data.get("correct_release_compressions", 0)))
	params[16] = correct_rel[0]; params[17] = correct_rel[1]
	var adeq_depth := encode_u16_le(int(data.get("adequate_depth_compressions", 0)))
	params[18] = adeq_depth[0]; params[19] = adeq_depth[1]
	var inact_time := encode_u16_le(int(data.get("inactivity_time_sec", 0)))
	params[20] = inact_time[0]; params[21] = inact_time[1]
	var total_comp := encode_u16_le(int(data.get("total_compressions", 0)))
	params[22] = total_comp[0]; params[23] = total_comp[1]
	var inact_periods := encode_u16_le(int(data.get("inactivity_periods", 0)))
	params[24] = inact_periods[0]; params[25] = inact_periods[1]
	var no_errors := encode_u16_le(int(data.get("compressions_no_errors", 0)))
	params[26] = no_errors[0]; params[27] = no_errors[1]

	params[28] = clampi(int(data.get("average_depth_mm", 0)), 0, 255)
	var too_shallow := encode_u16_le(int(data.get("compressions_too_shallow", 0)))
	params[29] = too_shallow[0]; params[30] = too_shallow[1]
	params[31] = clampi(int(data.get("average_rate_bpm", 0)), 0, 255)
	var too_slow := encode_u16_le(int(data.get("compressions_too_slow", 0)))
	params[32] = too_slow[0]; params[33] = too_slow[1]
	var too_fast := encode_u16_le(int(data.get("compressions_too_fast", 0)))
	params[34] = too_fast[0]; params[35] = too_fast[1]

	return encode_frame(Constants.ResponseId.QS_DATA, seq, params)

# --- Spezifische Packet-Decoder (Puppe -> App) ---

static func parse_wave(params: PackedByteArray) -> Dictionary:
	if params.size() < 5:
		return {"valid": false, "session_time_ms": 0, "depth_mm": 0.0}
	var session_time := decode_u32_le(params, 0)
	var depth := float(params[4])
	return {"valid": true, "session_time_ms": session_time, "depth_mm": depth}

static func parse_event(params: PackedByteArray) -> Dictionary:
	if params.size() < 10:
		return {"valid": false}
	return {
		"valid": true,
		"start_time_ms": decode_u32_le(params, 0),
		"time_to_peak_ms": decode_u16_le(params, 4),
		"max_depth_mm": float(params[6]),
		"time_to_stop_ms": decode_u16_le(params, 7),
		"incomplete_release": bool(params[9] != 0)
	}

static func parse_rate(params: PackedByteArray) -> int:
	if params.size() < 2:
		return 0
	return decode_u16_le(params, 0)

static func parse_inactivity(params: PackedByteArray) -> Dictionary:
	if params.size() < 3:
		return {"valid": false, "inactivity_ms": 0, "level": 0}
	return {
		"valid": true,
		"inactivity_ms": decode_u16_le(params, 0),
		"level": int(params[2])
	}

## QF_* Feedback-Frame auslesen (MsgId 224..228, 3-Byte-Payload).
## QF_INACTIVITY (224): Level an Position 2. Alle anderen: Level an Position 0.
static func parse_feedback(params: PackedByteArray, msg_id: int) -> int:
	if msg_id == Constants.ResponseId.QF_INACTIVITY:
		if params.size() < 3:
			return 0
		return int(params[2])
	if params.size() < 1:
		return 0
	return int(params[0])

static func parse_auth(params: PackedByteArray) -> bool:
	if params.is_empty():
		return false
	return bool(params[0] == 1)

static func parse_battery(params: PackedByteArray) -> int:
	if params.is_empty():
		return 0
	return int(params[0])

static func parse_session_data(params: PackedByteArray) -> Dictionary:
	if params.size() < 36:
		return {"valid": false}
	return {
		"valid": true,
		"session_start_time_ms": decode_u32_le(params, 0),
		"session_stop_time_ms": decode_u32_le(params, 4),
		"session_start_sec": decode_u16_le(params, 8),
		"session_stop_sec": decode_u16_le(params, 10),
		"adequate_rate_compressions": decode_u16_le(params, 12),
		"compressions_with_rate": decode_u16_le(params, 14),
		"correct_release_compressions": decode_u16_le(params, 16),
		"adequate_depth_compressions": decode_u16_le(params, 18),
		"inactivity_time_sec": decode_u16_le(params, 20),
		"total_compressions": decode_u16_le(params, 22),
		"inactivity_periods": decode_u16_le(params, 24),
		"compressions_no_errors": decode_u16_le(params, 26),
		"average_depth_mm": int(params[28]),
		"compressions_too_shallow": decode_u16_le(params, 29),
		"average_rate_bpm": int(params[31]),
		"compressions_too_slow": decode_u16_le(params, 32),
		"compressions_too_fast": decode_u16_le(params, 34)
	}
