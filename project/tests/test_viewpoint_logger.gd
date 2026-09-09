extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var logger = preload("res://aruco_csv_logger.gd").new()
	var label := Label.new()
	logger.status_label = label
	root.add_child(label)
	root.add_child(logger)
	logger.set_process(false)
	assert(logger._current_test() == "viewpoint")
	# Use an isolated test file rather than a real recording filename.
	var path := "res://tests/test_viewpoint_logger_output.csv"
	logger._file = FileAccess.open(path, FileAccess.WRITE)
	logger._file.store_line(",".join(logger._make_header()))
	logger._recording = true
	for phase in logger.VIEWPOINT_PHASES:
		assert(logger._current_phase() == phase)
		logger._write_row({}, Transform3D.IDENTITY)
		logger._on_left_button(&"by_button")
		assert(logger._current_test() == "viewpoint")
		logger._on_left_button(&"ax_button")
	assert(logger._current_phase() == "front_return")
	assert("finish recording" in label.text)
	logger._stop_recording()
	var file := FileAccess.open(path, FileAccess.READ)
	file.get_csv_line()
	for phase in logger.VIEWPOINT_PHASES:
		var row := file.get_csv_line()
		assert(row[3] == "viewpoint")
		assert(row[4] == phase)
	file.close()
	DirAccess.remove_absolute(path)
	assert(logger._current_phase() == "front")
	logger.free()
	label.free()
	print("viewpoint logger tests: PASS")
	quit()
