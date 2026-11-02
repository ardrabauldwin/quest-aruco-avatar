extends RefCounted
## Executes the actual compiled CCBM filter on Quest, off the render thread.
## No network service and no replacement posterior/state-machine approximation.
const MODEL := "res://addons/ccbm_native/model.json"
const ACTIONS := ["begin_check", "check_responsiveness", "call_emergency", "check_breathing", "compression", "compression_only", "ventilation", "handover"]
var _executable := ""
var _states := ""
var last_error := ""

func _unavailable(reason: String) -> bool:
	last_error = reason
	return false

func configure_android() -> bool:
	if not OS.has_feature("android") or not Engine.has_singleton("AndroidRuntime"): return _unavailable("android_runtime")
	if not FileAccess.file_exists(MODEL): return _unavailable("model_missing")
	var model: Variant = JSON.parse_string(FileAccess.get_file_as_string(MODEL))
	if not model is Dictionary or model.get("engine") != "ccbm": return _unavailable("model_format")
	var android := Engine.get_singleton("AndroidRuntime")
	# JavaObject exposes methods, not ApplicationInfo instance fields. Ask
	# Android's application class loader for the packaged native artifact.
	var loader: Variant = android.getApplicationContext().getClassLoader()
	_executable = str(loader.findLibrary("naret_ccbm"))
	# Godot's Android FileAccess existence check does not expose this system-
	# installed path on all runtimes. The class-loader path is authoritative;
	# execution still fails closed if unavailable. APK-internal ! paths cannot
	# be executed and indicate native extraction was not enabled.
	if _executable.is_empty() or not _executable.begins_with("/") or "!" in _executable:
		return _unavailable("native_not_extracted")
	# Extraction must be enabled in the export preset; never copy executable
	# code into writable user data or rely on a PC-provided path.
	var raw := Marshalls.base64_to_raw(str(model.get("states_base64", "")))
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(raw)
	if hash.finish().hex_encode() != model.get("states_sha256"): return _unavailable("states_hash")
	var directory := "user://ccbm_native"
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return _unavailable("cache_directory")
	_states = ProjectSettings.globalize_path(directory.path_join(str(model.states_sha256) + ".states"))
	var file := FileAccess.open(_states, FileAccess.WRITE)
	if file == null: return _unavailable("cache_write")
	file.store_buffer(raw)
	file.close()
	last_error = ""
	return true

func infer(observations: Array) -> Dictionary:
	if _executable.is_empty() or _states.is_empty(): return {"error": "native_unavailable"}
	if observations.is_empty() or observations.size() > 256: return {"error": "invalid_observations"}
	for item: Variant in observations:
		if not item is String or item not in ACTIONS: return {"error": "invalid_observations"}
	var path := ProjectSettings.globalize_path("user://ccbm_native/job_%d.obs" % Time.get_ticks_usec())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return {"error": "input_unavailable"}
	file.store_string("\n".join(observations) + "\n")
	file.close()
	var job := {"executable": _executable, "input": path, "states": _states, "steps": observations.size(), "result": {}}
	var task := WorkerThreadPool.add_task(_execute.bind(job), false, "Quest native CCBM")
	var tree := Engine.get_main_loop() as SceneTree
	while not WorkerThreadPool.is_task_completed(task):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	return job.result

static func _execute(job: Dictionary) -> void:
	var output := []
	var code := OS.execute(job.executable, PackedStringArray([job.input, job.states]), output, false)
	DirAccess.remove_absolute(job.input)
	if code != 0 or output.is_empty():
		job.result = {"error": "native_failed"}
		return
	job.result = parse_posterior(str(output[0]), int(job.steps))

static func parse_posterior(output: String, steps: int) -> Dictionary:
	if output.length() > 4 * 1024 * 1024 or steps < 1 or steps > 256: return {}
	var names := []
	var row := PackedStringArray()
	var token := RegEx.new()
	token.compile("\"([^\"]+)\"|\\S+")
	var spaces := RegEx.new()
	spaces.compile("\\s+")
	for raw: String in output.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("Time"):
			names.clear()
			var tokens := token.search_all(line)
			for index in range(1, tokens.size()):
				names.append(tokens[index].get_string().trim_prefix("\"").trim_suffix("\""))
		elif not names.is_empty():
			var cells := spaces.sub(line, " ", true).split(" ", false)
			if cells.size() == names.size() + 1:
				var valid := true
				for cell: String in cells:
					if not cell.is_valid_float(): valid = false
				if valid: row = cells
	if row.is_empty() or float(row[0]) != steps: return {}
	var masses := {}
	var total := 0.0
	for index in names.size():
		var value := float(row[index + 1])
		if not is_finite(value) or value < 0: return {}
		var action := str(names[index]).trim_prefix("(").trim_suffix(")").split(" ", false)[0]
		if action in ["ventilation_first", "ventilation_second"]: action = "ventilation"
		masses[action] = float(masses.get(action, 0.0)) + value
		total += value
	if total <= 0 or absf(total - 1.0) > 0.01: return {}
	var winner := ""
	var probability := -1.0
	for action: String in masses:
		if float(masses[action]) > probability:
			winner = action
			probability = masses[action]
	# Keep BLOCKED/FINISHED mass; the existing bridge rejects an unavailable
	# winning action. Do not force/renormalize it into the expected report.
	return {"engine": "ccbm", "action": winner, "probability": probability / total}
