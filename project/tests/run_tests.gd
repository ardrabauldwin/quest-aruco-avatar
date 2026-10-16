extends SceneTree
## Run: godot --headless --path . --script tests/run_tests.gd
## Suites are RefCounted scripts named test_*.gd with run() -> Array[String].

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var names: PackedStringArray = DirAccess.get_files_at("res://tests")
	names.sort()
	var failures := 0
	var suites := 0
	for filename: String in names:
		if not filename.begins_with("test_") or not filename.ends_with(".gd"):
			continue
		suites += 1
		var script: GDScript = load("res://tests/" + filename)
		if script == null or not script.can_instantiate():
			printerr("FAIL ", filename, ": cannot compile suite")
			failures += 1
			continue
		var suite: RefCounted = script.new()
		if not suite.has_method("run"):
			printerr("FAIL ", filename, ": missing run()")
			failures += 1
			continue
		var result: Variant = await suite.call("run")
		if not result is Array:
			printerr("FAIL ", filename, ": run() did not return failure array")
			failures += 1
			continue
		for message: String in result:
			printerr("FAIL ", filename, ": ", message)
			failures += 1
		if result.is_empty():
			print("PASS ", filename)
	if suites == 0:
		printerr("FAIL: no test suites found")
		failures += 1
	print("NaReT: ", suites, " suites; ", failures, " failures")
	quit(0 if failures == 0 else 1)
