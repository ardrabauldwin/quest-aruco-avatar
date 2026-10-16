class_name NaretQcprConstants
extends RefCounted
## QCPR-kompatible Protokoll-Konstanten und GATT-Definitionen.
##
## Definiert GATT-Service- und Characteristic-UUIDs, CPRM-Message-IDs,
## Handshake-Schlüssel sowie medizinische Grenzwerte nach ERC 2021.

# --- GATT UUIDs (128-bit) ---
# Feste GUID-Extension für herstellerspezifische QCPR-Services
const GUID_EXTENSION := "-D746-4092-84E7-DAD34863FE4A"
const SIG_GUID_EXTENSION := "-0000-1000-8000-00805F9B34FB"

# CPRmeter Command Service & Characteristics (Hauptdatenkanal)
const UUID_SERVICE_CPRM_COMMAND := "00001001" + GUID_EXTENSION
const UUID_CHAR_CPRM_COMMAND := "00001002" + GUID_EXTENSION    # Write (App -> Puppe)
const UUID_CHAR_CPRM_RESPONSE := "00001003" + GUID_EXTENSION   # Notify (Puppe -> App)

# CPRmeter Authentication Service & Characteristics
const UUID_SERVICE_CPRM_AUTH := "00001031" + GUID_EXTENSION
const UUID_CHAR_CPRM_AUTH_COMMAND := "00001032" + GUID_EXTENSION   # Write (App -> Puppe)
const UUID_CHAR_CPRM_AUTH_RESPONSE := "00001033" + GUID_EXTENSION  # Notify (Puppe -> App)

# Alternative / Manikin Service UUIDs
const UUID_SERVICE_COMPRESSION := "00000026" + GUID_EXTENSION
const UUID_SERVICE_VENTILATION := "00500050" + GUID_EXTENSION
const UUID_SERVICE_SESSION := "00000126" + GUID_EXTENSION

# Standard Bluetooth SIG Battery Service
const UUID_SERVICE_BATTERY := "0000180F" + SIG_GUID_EXTENSION
const UUID_CHAR_BATTERY_LEVEL := "00002A19" + SIG_GUID_EXTENSION

# --- Authentifizierungs-Schlüssel ---
# CPRM 18-Byte Authentifizierungsschlüssel
const CPRM_AUTH_KEY: PackedByteArray = [
	104, 0, 167, 241, 39, 91, 2, 145, 44, 237,
	225, 53, 255, 154, 59, 202, 80, 98
]

# Standard 20-Byte Manikin Authentifizierungsschlüssel
const MANIKIN_AUTH_KEY: PackedByteArray = [
	92, 14, 185, 190, 3, 210, 96, 9, 109, 62,
	31, 12, 128, 38, 200, 16, 115, 205, 46, 162
]

# --- CPRM Message IDs ---
# Kommandos: App -> Puppe (IDs < 128)
enum CommandId {
	UNKNOWN = 0,
	LG_GET_EPISODE_LIST = 1,
	LG_GET_SUBDIR = 2,
	LG_GET_SINGLE_FILE = 3,
	LG_VALIDATE_EPISODE = 4,
	LG_ERASE_EPISODE = 5,
	LG_ERASE_ALL = 6,
	LG_GET_RTC_TIME = 7,
	LG_SET_RTC_TIME = 8,
	LG_SET_PACKETS_PER_INT = 9,
	LG_DELETE_BONDS = 10,
	LG_SUPPRESS_RT = 11,
	LG_GET_BATTERY_LEVEL = 12,
	LG_GET_RTC_VALID = 13,
	LG_GET_FILE_SYS_CORRUPT = 14,
	LG_FORMAT_IF_CORRUPT = 15,
	LG_RESET_CD_SEQ_BUF = 16,
	LG_RESET_CN_SEQ_BUF = 17,
	LG_GET_ALL_SUMMARY_FILES = 18,
	LG_GET_ALL_SUMMARY_FILES_EX = 19,
	LG_SET_SUBDIR = 20,
	BL_REQUEST = 24,
	BL_PACKET = 25,
	BL_NORDIC = 26,
	BL_LOOPTEST = 27,
	FT_REQUEST_BLOCK = 32,
	FT_REQUEST_SUB_BLOCK = 33,
	FT_ABORT_TRANSFER = 34,
	FT_RE_REQUEST_BLOCK = 35,
	FT_RE_REQUEST_SUB_BLOCK = 36,
	DI_FIRMWARE_VERSION = 48,
	DI_SERIAL_NUMBER = 49,
	DI_MODEL_NUMBER = 50,
	CN_INCOMPLETE = 72,
	CN_COMPLETE = 73,
	SC_SECURITY_CODE = 104,
	SC_RESET_SC_SEQ_BUF = 105,
}

# Antworten / Events: Puppe -> App (IDs >= 128)
enum ResponseId {
	LG_GET_EPISODE_LIST = 129,
	LG_GET_SUBDIR = 130,
	LG_GET_SINGLE_FILE = 131,
	LG_VALIDATE_EPISODE = 132,
	LG_ERASE_EPISODE = 133,
	LG_ERASE_ALL = 134,
	LG_GET_RTC_TIME = 135,
	LG_SET_RTC_TIME = 136,
	LG_SET_PACKETS_PER_INT = 137,
	LG_DELETE_BONDS = 138,
	LG_SUPPRESS_RT = 139,
	LG_GET_BATTERY_LEVEL = 140,
	LG_GET_RTC_VALID = 141,
	LG_GET_FILE_SYS_CORRUPT = 142,
	LG_FORMAT_IF_CORRUPT = 143,
	LG_RESET_CD_SEQ_BUF = 144,
	LG_RESET_CN_SEQ_BUF = 145,
	LG_GET_ALL_SUMMARY_FILES = 146,
	LG_GET_ALL_SUMMARY_FILES_EX = 147,
	LG_SET_SUBDIR = 148,
	BL_REQUEST = 152,
	BL_PACKET = 153,
	BL_NORDIC = 154,
	BL_LOOPTEST = 155,
	FT_REQUEST_BLOCK = 160,
	FT_REQUEST_SUB_BLOCK = 161,
	FT_ABORT_TRANSFER = 162,
	FT_RE_REQUEST_BLOCK = 163,
	FT_RE_REQUEST_SUB_BLOCK = 164,
	DI_FIRMWARE_VERSION = 176,
	DI_SERIAL_NUMBER = 177,
	DI_MODEL_NUMBER = 178,

	# CPR Live-Stream (maßgeblicher Datenkanal)
	CP_WAVE = 192,         # 0xC0: SessionTime (uint32 ms) + Depth (byte mm)
	CP_EVENT = 193,        # 0xC1: Start, TimeToPeak, MaxDepth, TimeToStop, Release
	CP_RATE = 194,         # 0xC2: CompressionRate (uint16 bpm)
	CP_INACTIVITY = 195,   # 0xC3: Inactivity (uint16 ms) + Level (byte)

	CN_INCOMPLETE_RESPONSE = 200,
	CN_COMPLETE_RESPONSE = 201,

	# QCPR Session Data
	QS_DATA = 208,         # 0xD0: 36-Byte Session-Zusammenfassung

	# QCPR Feedback Events (Echtzeit-Bewertung)
	QF_INACTIVITY = 224,     # 0xE0: Inaktivität
	QF_INCOMP_RELEASE = 225, # 0xE1: Unvollständige Entlastung (Leaning)
	QF_COMP_SHALLOW = 226,   # 0xE2: Zu flach (< 50 mm)
	QF_COMP_SLOW = 227,      # 0xE3: Zu langsam (< 100 bpm)
	QF_COMP_FAST = 228,      # 0xE4: Zu schnell (> 120 bpm)

	SC_SECURITY_CODE = 232,  # 0xE8: Auth-Ergebnis (IsAuthenticated)
	SC_RESET_SC_SEQ_BUF = 233,
}

# Feedback-Level für QCPR-Meldungen
enum FeedbackLevel {
	OK = 0,
	WARNING = 1,
	ALERT = 2,
	HIGH_ALERT = 3,
}

# Handpositions-Bewertung
enum HandPosition {
	OK = 0,
	ERROR_LEFT = 1,
	ERROR_RIGHT = 2,
	ERROR_TOO_LOW = 3,
	ERROR_TOO_HIGH = 4,
	ERROR_XIPHOID = 5,
	UNSPECIFIED = 254,
}

# Maximale Sequenznummer vor Überlauf (0..254, danach Wrap auf 0)
const MAX_SEQUENCE_NUMBER := 254

# --- Medizinische Grenzwerte nach ERC Guidelines 2021 (Erwachsene) ---
# https://www.resuscitation.eu/assets/guidelines/European-Resuscitation-Council-Guidelines-2021-Ba.pdf
const ADULT_DEPTH_MIN_MM := 50.0  # 5,0 cm
const ADULT_DEPTH_MAX_MM := 60.0  # 6,0 cm
const ADULT_RATE_MIN_BPM := 100.0
const ADULT_RATE_MAX_BPM := 120.0
const ADULT_VENTILATION_MIN_ML := 400.0
const ADULT_VENTILATION_MAX_ML := 700.0
const MAX_INACTIVITY_WARNING_MS := 5000  # Pause > 5 s löst Warnung aus

# Simulator-Standardwerte für Zielqualität ("Gute CPR")
const TARGET_DEPTH_MM := 55.0     # Mitten im Zielbereich 50-60 mm
const TARGET_RATE_BPM := 110.0    # Mitten im Zielbereich 100-120 bpm
