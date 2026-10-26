extends "res://tests/suite.gd"

class Client extends NaretUniAPIClient:
	func _ready() -> void: pass # No external configuration or cloud probes.

class UnresponsiveServer extends Node:
	var server := TCPServer.new()
	var peers: Array[StreamPeerTCP] = []
	func _process(_delta: float) -> void:
		while server.is_connection_available(): peers.append(server.take_connection())
		for peer in peers:
			peer.poll()
			if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and peer.get_available_bytes() > 0:
				peer.get_data(peer.get_available_bytes())
		# Intentionally accept uploads but never send a response.
	func _exit_tree() -> void:
		for peer in peers: peer.disconnect_from_host()
		server.stop()

var result := {}
var complete := false

func _voice(client: Client) -> void:
	result = await client._request_local_ai("/audio/speech", {"input": "test"})
	complete = true

func _recognise(client: Client) -> void:
	result = await client._transcribe_local(PackedByteArray([1, 2, 3]), "audio/wav")
	complete = true

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var endpoint := UnresponsiveServer.new()
	check(endpoint.server.listen(0, "127.0.0.1") == OK, "test can open a loopback socket")
	tree.root.add_child(endpoint)
	var client := Client.new()
	tree.root.add_child(client)
	client.local_ai_url = "http://127.0.0.1:" + str(endpoint.server.get_local_port())
	client.local_asr_url = client.local_ai_url + "/inference"
	_voice(client)
	await tree.process_frame
	check(not client._local_tts_requests[0].use_threads, "local voice uses nonblocking I/O")
	var started := Time.get_ticks_msec()
	var previous := started
	var max_gap := 0
	var frames := 0
	while not complete and Time.get_ticks_msec() - started < 10000:
		await tree.process_frame
		var now := Time.get_ticks_msec()
		max_gap = maxi(max_gap, now - previous)
		previous = now
		frames += 1
	check(complete and not result.get("ok", true), "stalled speech returns a failure within its deadline")
	check(frames > 100 and max_gap < 500, "render loop stays responsive during the speech timeout")
	complete = false
	_recognise(client)
	await tree.process_frame
	check(not client._local_asr_request.use_threads, "local recognition uses nonblocking I/O")
	started = Time.get_ticks_msec()
	client.cancel_speech_requests()
	check(Time.get_ticks_msec() - started < 200 and complete, "restart cancels a stalled recognition socket promptly")
	check(result.get("error") == "cancelled" and not client._busy.asr, "cancelled recognition cannot retry or block the next session")
	client.queue_free()
	endpoint.queue_free()
	return failures
