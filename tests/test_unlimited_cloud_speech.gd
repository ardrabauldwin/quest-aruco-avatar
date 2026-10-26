extends "res://tests/suite.gd"

class Client extends NaretUniAPIClient:
	func configure() -> void:
		api_key = "loopback-test-placeholder"
		offline = false
	func probe_models() -> void: pass

class DelayedServer extends Node:
	var server := TCPServer.new()
	var peers: Array[StreamPeerTCP] = []
	var respond := false
	func _process(_delta: float) -> void:
		while server.is_connection_available(): peers.append(server.take_connection())
		for peer in peers:
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED: continue
			if peer.get_available_bytes() > 0:
				peer.get_data(peer.get_available_bytes())
				if respond:
					var body := '{"text":"fresh report"}'
					peer.put_data(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [body.length(), body]).to_utf8_buffer())
	func _exit_tree() -> void:
		for peer in peers: peer.disconnect_from_host()
		server.stop()

var complete := false
var result := {}

func _recognise(client: Client) -> void:
	result = await client.transcribe(PackedByteArray([1, 2]), "en")
	complete = true

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var endpoint := DelayedServer.new()
	check(endpoint.server.listen(0, "127.0.0.1") == OK, "cloud-route test opens loopback server")
	tree.root.add_child(endpoint)
	var client := Client.new()
	client.base_url = "http://127.0.0.1:" + str(endpoint.server.get_local_port())
	tree.root.add_child(client)
	check(client._requests.asr.timeout == 0.0, "actual ASR request has no automatic timeout")
	check(not client._requests.asr.use_threads, "cloud recognition remains nonblocking and cancellable")
	_recognise(client)
	await tree.create_timer(2.2).timeout
	check(not complete and client._busy.asr, "slow recognition survives the old two-second cutoff")
	var started := Time.get_ticks_msec()
	client.cancel_speech_requests()
	check(complete and not client._busy.asr and Time.get_ticks_msec() - started < 200, "restart releases an unlimited pending request promptly")
	complete = false
	endpoint.respond = true
	_recognise(client)
	started = Time.get_ticks_msec()
	while not complete and Time.get_ticks_msec() - started < 3000:
		await tree.process_frame
	check(complete and result.get("ok", false) and result.get("json", {}).get("text") == "fresh report", "fresh recognition succeeds after cancelling an unlimited request")
	client.free()
	endpoint.free()
	return failures
