class_name NaretUniAPIClient
extends Node
## Async Uni-ApphubAI transport. Tokens come only from environment/user storage.

signal status_changed(message: String)
signal request_finished(service: String, success: bool, latency_ms: int)

const DEFAULT_URL := "https://apphubai.wolke.uni-greifswald.de/v1"
const DEFAULT_LLM := "unsloth/Qwen3.8-27B-GGUF:Q4_K_M"
var base_url := DEFAULT_URL
var api_key := ""
var asr_model := "large-v3"
var tts_model := "omnivoice"
var llm_model := DEFAULT_LLM
var tts_voice := "" # ApphubAI omnivoice rejects the OpenAI example voice 'alloy'.
var timeout_s := 2.0
var offline := false
# Optional PC recogniser reached through adb reverse. Never send cloud credentials.
var local_asr_url := ""
var local_ai_url := "" # USB-local dialogue/TTS; separate from university credentials.
var models_verified := false
var available_models: Array[String] = []
var _requests: Dictionary = {}
var _busy: Dictionary = {}


func _ready() -> void:
	configure()
	for service in ["models", "asr", "tts", "llm"]:
		var request := HTTPRequest.new()
		request.name = "HTTP_" + service
		request.use_threads = true
		request.timeout = timeout_s
		request.body_size_limit = 8 * 1024 * 1024
		request.max_redirects = 0 # Never forward authorization to a redirected host.
		add_child(request)
		_requests[service] = request
		_busy[service] = false
	probe_models.call_deferred()


func configure() -> void:
	var settings: Dictionary = {}
	if FileAccess.file_exists("user://config.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://config.json"))
		if parsed is Dictionary:
			var section: Variant = parsed.get("api", parsed)
			if section is Dictionary:
				settings = section
	base_url = str(settings.get("base_url", DEFAULT_URL)).trim_suffix("/")
	local_asr_url = str(settings.get("local_asr_url", ""))
	local_ai_url = str(settings.get("local_ai_url", ""))
	if local_ai_url != "http://127.0.0.1:8768": local_ai_url = ""
	# Only loopback is allowed for this cable-connected development mode.
	if local_asr_url != "http://127.0.0.1:8767/inference":
		local_asr_url = ""
	asr_model = str(settings.get("asr_model", "large-v3"))
	tts_model = str(settings.get("tts_model", "omnivoice"))
	llm_model = str(settings.get("llm_model", DEFAULT_LLM))
	tts_voice = str(settings.get("tts_voice", ""))
	# Runtime fallback deadline is always <= 2 seconds.
	timeout_s = clampf(float(settings.get("timeout_s", 2.0)), 0.1, 2.0)
	api_key = OS.get_environment("UNI_API_KEY")
	if api_key.is_empty():
		api_key = OS.get_environment("API_SECRET")
	if api_key.is_empty():
		api_key = str(settings.get("api_key", ""))
	offline = bool(settings.get("offline", false)) or OS.get_environment("NARET_OFFLINE") == "1"
	if not base_url.begins_with("https://"):
		offline = true
	for request: HTTPRequest in _requests.values():
		request.timeout = timeout_s


func is_available(model: String = "") -> bool:
	if not local_ai_url.is_empty() and model in [llm_model, tts_model]: return true
	return not offline and not api_key.is_empty() and (model.is_empty() or not models_verified or model in available_models)


func probe_models() -> void:
	if not is_available():
		status_changed.emit("local_asr_ready" if not local_asr_url.is_empty() else "offline")
		return
	var result: Dictionary = await request_json("models", "/models", {}, HTTPClient.METHOD_GET)
	if not result.get("ok", false):
		status_changed.emit("models_unverified")
		return
	var data: Variant = result.get("json", {}).get("data", [])
	if not data is Array:
		return
	available_models.clear()
	for item: Variant in data:
		if item is Dictionary and item.get("id") is String:
			available_models.append(item["id"])
	models_verified = true
	status_changed.emit("online" if llm_model in available_models else "llm_model_unavailable")


func request_json(service: String, endpoint: String, payload: Dictionary, method: HTTPClient.Method = HTTPClient.METHOD_POST) -> Dictionary:
	var body := PackedByteArray() if method == HTTPClient.METHOD_GET else JSON.stringify(payload).to_utf8_buffer()
	return await request_bytes(service, endpoint, body, "application/json", method)


func request_bytes(service: String, endpoint: String, body: PackedByteArray, content_type: String, method: HTTPClient.Method = HTTPClient.METHOD_POST) -> Dictionary:
	if not is_available():
		return {"ok": false, "error": "offline", "latency_ms": 0}
	if not _requests.has(service) or _busy.get(service, false):
		return {"ok": false, "error": "busy", "latency_ms": 0}
	_busy[service] = true
	var request: HTTPRequest = _requests[service]
	var start := Time.get_ticks_msec()
	var headers := PackedStringArray(["Authorization: Bearer " + api_key, "Content-Type: " + content_type])
	var error := request.request_raw(base_url + endpoint, headers, method, body)
	if error != OK:
		_busy[service] = false
		request_finished.emit(service, false, Time.get_ticks_msec() - start)
		return {"ok": false, "error": "connection_failed", "latency_ms": Time.get_ticks_msec() - start}
	var response: Array = await request.request_completed
	_busy[service] = false
	var elapsed := Time.get_ticks_msec() - start
	var status: int = response[1]
	var data: PackedByteArray = response[3]
	var success := int(response[0]) == HTTPRequest.RESULT_SUCCESS and status >= 200 and status < 300
	var result := {"ok": success, "status": status, "body": data, "headers": response[2], "latency_ms": elapsed}
	if success and (service != "tts" or data.size() > 0 and data[0] == 123):
		var decoded: Variant = JSON.parse_string(data.get_string_from_utf8())
		if decoded is Dictionary:
			result["json"] = decoded
	if not success:
		result["error"] = "timeout" if int(response[0]) == HTTPRequest.RESULT_TIMEOUT else "request_failed"
	request_finished.emit(service, success, elapsed)
	return result


func complete(messages: Array) -> Dictionary:
	if not local_ai_url.is_empty():
		return await _request_local_ai("/chat/completions", {"messages": messages})
	if not is_available(llm_model):
		return {"ok": false, "error": "llm_model_unavailable"}
	return await request_json("llm", "/chat/completions", {
		"model": llm_model, "messages": messages,
		"temperature": 0.3, "max_tokens": 160, "stream": false,
		"chat_template_kwargs": {"enable_thinking": false},
	})


func synthesize(text: String, language: String = "en", speaker: String = "bystander") -> Dictionary:
	if not local_ai_url.is_empty():
		return await _request_local_ai("/audio/speech", {"input": text.left(1000), "language": language, "speaker": speaker})
	if not is_available(tts_model):
		return {"ok": false, "error": "tts_unavailable"}
	var payload := {"model": tts_model, "input": text.left(1000), "response_format": "wav"}
	if not tts_voice.is_empty():
		payload["voice"] = tts_voice
	return await request_json("tts", "/audio/speech", payload)

func _request_local_ai(path: String, payload: Dictionary) -> Dictionary:
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = 45.0
	request.max_redirects = 0
	request.body_size_limit = 8 * 1024 * 1024
	add_child(request)
	var error := request.request(local_ai_url + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		request.queue_free()
		return {"ok": false, "error": "local_ai_unavailable"}
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		return {"ok": false, "error": "local_ai_unavailable"}
	var result := {"ok": true, "body": response[3], "source": "local"}
	if path == "/chat/completions":
		var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
		if not parsed is Dictionary: return {"ok": false, "error": "invalid_local_reply"}
		result["json"] = parsed
	return result


func transcribe(wav: PackedByteArray, language: String) -> Dictionary:
	if local_asr_url.is_empty() and not is_available(asr_model):
		return {"ok": false, "error": "asr_unavailable"}
	var boundary := "NaretAudio" + str(Time.get_ticks_usec())
	var body := PackedByteArray()
	var fields := {"model": asr_model, "response_format": "json"}
	# Each microphone recording is a separate report. Whisper's previous-audio
	# context can otherwise repeat an earlier sentence instead of the new report.
	if not local_asr_url.is_empty():
		fields["no_context"] = "true"
	if language in ["de", "pl", "en"]:
		fields["language"] = language
	for name: String in fields:
		body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [boundary, name, fields[name]]).to_utf8_buffer())
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n" % boundary).to_utf8_buffer())
	body.append_array(wav)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	if not local_asr_url.is_empty():
		return await _transcribe_local(body, "multipart/form-data; boundary=" + boundary)
	return await request_bytes("asr", "/audio/transcriptions", body, "multipart/form-data; boundary=" + boundary)


func _transcribe_local(body: PackedByteArray, content_type: String) -> Dictionary:
	# Separate request preserves the cloud timeout/authentication policy.
	if _busy.get("asr", false):
		return {"ok": false, "error": "busy"}
	_busy["asr"] = true
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = 90.0 # Large-v3 on this CPU needs longer for complete sentences.
	request.body_size_limit = 1024 * 1024
	request.max_redirects = 0
	add_child(request)
	var err := request.request_raw(local_asr_url, ["Content-Type: " + content_type], HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy["asr"] = false
		request.queue_free()
		return {"ok": false, "error": "local_asr_connection_failed"}
	var response: Array = await request.request_completed
	_busy["asr"] = false
	request.queue_free()
	if response[0] == HTTPRequest.RESULT_TIMEOUT:
		return {"ok": false, "error": "local_asr_timeout"}
	var success := int(response[0]) == HTTPRequest.RESULT_SUCCESS and int(response[1]) == 200
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8()) if success else null
	if parsed is Dictionary and parsed.get("text") is String:
		return {"ok": true, "json": parsed}
	return {"ok": false, "error": "local_asr_failed"}


static func encode_wav(recording: AudioStreamWAV) -> PackedByteArray:
	# PCM16 from AudioEffectRecord, built in memory: no speech file is ever stored.
	var data := recording.data
	var channels := 2 if recording.stereo else 1
	var wav := StreamPeerBuffer.new()
	wav.put_data("RIFF".to_ascii_buffer())
	wav.put_u32(36 + data.size())
	wav.put_data("WAVEfmt ".to_ascii_buffer())
	wav.put_u32(16)
	wav.put_u16(1)
	wav.put_u16(channels)
	wav.put_u32(recording.mix_rate)
	wav.put_u32(recording.mix_rate * channels * 2)
	wav.put_u16(channels * 2)
	wav.put_u16(16)
	wav.put_data("data".to_ascii_buffer())
	wav.put_u32(data.size())
	wav.put_data(data)
	return wav.data_array


static func decode_audio(bytes: PackedByteArray) -> AudioStream:
	# The TTS request asks for WAV; anything else is rejected.
	if bytes.size() < 12 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return null
	return AudioStreamWAV.load_from_buffer(bytes)
