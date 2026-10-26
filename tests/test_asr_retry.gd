extends "res://tests/suite.gd"

class SpeechTransport extends NaretUniAPIClient:
	var responses: Array = []
	var uploads: Array[PackedByteArray] = []
	var cancel_during_upload := false
	func _post_local_asr(body: PackedByteArray, _content_type: String) -> Array:
		uploads.append(body.duplicate())
		if cancel_during_upload: cancel_speech_requests()
		return responses.pop_front()

func run() -> Array[String]:
	failures.clear()
	var connection_error := [HTTPRequest.RESULT_CONNECTION_ERROR, 0, PackedStringArray(), PackedByteArray()]
	var timeout := [HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray()]
	var success := [HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"text":"He is not breathing."}'.to_utf8_buffer()]
	var audio := PackedByteArray([1, 2, 3, 4])
	var client := SpeechTransport.new()
	client.responses = [connection_error, success]
	var result: Dictionary = await client._transcribe_local(audio, "audio/wav")
	check(result.get("ok", false) and result.json.text == "He is not breathing.", "a dropped connection recovers the breathing report")
	check(client.uploads.size() == 2 and client.uploads[0] == audio and client.uploads[1] == audio, "retry reuses the exact recording")
	client.uploads.clear()
	client.responses = [timeout, timeout]
	result = await client._transcribe_local(audio, "audio/wav")
	check(result.get("error") == "local_asr_timeout" and client.uploads.size() == 2 and not client._busy.asr, "two failed attempts stop and release the recognizer")
	client.uploads.clear()
	client.responses = [[HTTPRequest.RESULT_SUCCESS, 500, PackedStringArray(), PackedByteArray()]]
	result = await client._transcribe_local(audio, "audio/wav")
	check(not result.get("ok", false) and client.uploads.size() == 1, "server errors do not trigger transport retries")
	client.uploads.clear()
	client.responses = [connection_error, success]
	client.cancel_during_upload = true
	result = await client._transcribe_local(audio, "audio/wav")
	check(result.get("error") == "cancelled" and client.uploads.size() == 1, "restart cancels the pending retry instead of reviving an old report")
	check(client.LOCAL_ASR_TIMEOUT_S <= 8.0, "each warmed GPU attempt has a short deadline")
	client.free()
	return failures
