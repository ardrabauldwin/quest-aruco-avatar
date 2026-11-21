extends "res://tests/suite.gd"
## A threaded HTTPRequest joins its blocking socket worker on timeout or cancel, which froze the
## headset for 53 s after a slow cloud reply (2026-11-03). No service may use one.

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var client := NaretUniAPIClient.new()
	tree.root.add_child(client)
	for service in ["models", "asr", "tts", "llm"]:
		var request := client.get_node_or_null("HTTP_" + service) as HTTPRequest
		check(request != null and not request.use_threads, service + " request has no socket worker thread")
	client.free()
	return failures
