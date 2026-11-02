extends "res://tests/suite.gd"

class Capture extends NaretUniAPIClient:
	var upload := ""
	func is_available(_model: String = "") -> bool:
		return true
	func request_bytes(_service: String, _path: String, body: PackedByteArray, _type: String, _method: HTTPClient.Method = HTTPClient.METHOD_POST) -> Dictionary:
		upload = body.get_string_from_utf8()
		return {"ok": true, "json": {"text": ""}}
	func _transcribe_local(body: PackedByteArray, _type: String) -> Dictionary:
		upload = body.get_string_from_utf8()
		return {"ok": true, "json": {"text": ""}}

func run() -> Array[String]:
	failures.clear()
	var client := Capture.new()
	for local in [false, true]:
		client.local_asr_url = "http://127.0.0.1:8767/inference" if local else ""
		for language in ["en", "de", "pl"]:
			check(str(client.ASR_VOCABULARY[language]).length() <= 512, "expanded hint fits the GPU handler limit: " + language)
			await client.transcribe("WAV_TEST".to_utf8_buffer(), language)
			check('name="prompt"' in client.upload and str(client.ASR_VOCABULARY[language]) in client.upload, "vocabulary is sent to chosen transport: " + language)
			check(('\r\n\r\n' + language + '\r\n') in client.upload, "selected recognition language preserved: " + language)
			check("WAV_TEST" in client.upload, "audio payload preserved")
		await client.transcribe("WAV_TEST".to_utf8_buffer(), "auto")
		check(not 'name="prompt"' in client.upload, "unknown language does not inject guessed vocabulary")
	client.free()
	return failures
