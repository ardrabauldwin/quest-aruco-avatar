extends SceneTree
## Real rendered desktop baseline. This does not measure Quest performance.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Use a real renderer for performance measurements")
		quit(1)
		return
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for action in ["start", "begin_check", "check_responsiveness", "call_emergency", "check_breathing", "request_aed"]:
		scene._on_action(action)
	scene.audio_manager.stop_speech()
	# Warm caches, then sample a representative animated CPR sequence.
	await create_timer(2.0).timeout
	scene.performance.samples.clear()
	for i in 30:
		scene._on_action("compression")
		await create_timer(60.0 / 110.0).timeout
	var report: Dictionary = scene.performance.get_summary()
	report["engine"] = Engine.get_version_info().string
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["quest_measurement"] = false
	report["viewport"] = str(root.size)
	report["samples"] = scene.performance.samples
	var file := FileAccess.open("res://docs/desktop_benchmark.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("BENCHMARK ", JSON.stringify(scene.performance.get_summary()))
	scene.audio_manager.stop_speech()
	scene.queue_free()
	await process_frame
	quit()
