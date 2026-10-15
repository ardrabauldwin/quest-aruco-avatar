class_name NaretSessionLogger
extends RefCounted
## Local JSON export contains structured training events, no raw audio or transcripts.

const MAX_EVENTS := 20000
var events: Array[Dictionary] = []
var session_id := ""
var started_at := ""
var dropped_events := 0
var last_error := ""

func _init() -> void:
	reset()

func reset() -> void:
	events.clear()
	dropped_events = 0
	last_error = ""
	started_at = Time.get_datetime_string_from_system(true)
	session_id = str(Time.get_unix_time_from_system()).replace(".", "-") + "-" + str(Time.get_ticks_usec())

func record(event: Dictionary) -> void:
	if event.get("action", "") == "start":
		reset()
	if events.size() >= MAX_EVENTS:
		dropped_events += 1
		return
	var clean: Dictionary = {}
	for key: String in ["sequence", "elapsed_s", "action", "accepted", "state", "reason", "details"]:
		if event.has(key):
			clean[key] = event[key]
	events.append(clean.duplicate(true))

func build_document(summary: Dictionary = {}) -> Dictionary:
	return {
		"schema_version": 1, "application": "NaReT Mannequin-XR",
		"session_id": session_id, "started_at_utc": started_at,
		"exported_at_utc": Time.get_datetime_string_from_system(true),
		"simulation_only": true, "clinically_validated": false,
		"dropped_events": dropped_events, "summary": summary.duplicate(true), "events": events.duplicate(true),
	}

func save(summary: Dictionary = {}, destination: String = "") -> String:
	last_error = ""
	var path := destination
	if path.is_empty():
		path = "user://sessions/session-" + session_id + ".json"
	var absolute := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error != OK:
		last_error = error_string(directory_error)
		return ""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_error = error_string(FileAccess.get_open_error())
		return ""
	file.store_string(JSON.stringify(build_document(summary), "\t", true))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_error = error_string(write_error)
		return ""
	return absolute
