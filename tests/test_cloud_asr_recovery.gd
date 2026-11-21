extends "res://tests/suite.gd"

class Client extends NaretUniAPIClient:
	var responses: Array = []
	var uploads: Array[PackedByteArray] = []
	var cancel_during_request := false
	func request_bytes(_service: String, _endpoint: String, body: PackedByteArray, _type: String, _method: HTTPClient.Method = HTTPClient.METHOD_POST) -> Dictionary:
		uploads.append(body.duplicate())
		if cancel_during_request: cancel_speech_requests()
		return responses.pop_front()

func run() -> Array[String]:
	var client := Client.new()
	var audio := PackedByteArray([1, 2, 3, 4])
	var drop := {"ok": false, "transport": HTTPRequest.RESULT_CONNECTION_ERROR, "http_status": 0}
	var good := {"ok": true, "json": {"text": "The scene is safe."}}
	client.responses = [drop, good]
	var result: Dictionary = await client._transcribe_cloud(audio, "audio/wav")
	check(result.get("ok", false) and client.uploads.size() == 2 and client.uploads[0] == client.uploads[1], "a dropped cloud connection retries the same recording")
	for status in [401, 429, 503]:
		client.uploads.clear()
		client.responses = [{"ok": false, "transport": HTTPRequest.RESULT_SUCCESS, "http_status": status}]
		result = await client._transcribe_cloud(audio, "audio/wav")
		check(not result.get("ok", false) and client.uploads.size() == 1 and result.http_status == status, "HTTP errors preserve status without immediate retry: " + str(status))
	client.uploads.clear()
	client.responses = [drop, drop]
	result = await client._transcribe_cloud(audio, "audio/wav")
	check(client.uploads.size() == 2 and not result.get("ok", false), "transport retries are bounded")
	client.uploads.clear()
	client.responses = [drop, good]
	client.cancel_during_request = true
	result = await client._transcribe_cloud(audio, "audio/wav")
	check(result.get("error") == "cancelled" and client.uploads.size() == 1, "restart prevents an old recording from retrying")
	client.free()
	return failures
