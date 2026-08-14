extends Node
## Copy Paul's latest marker Dictionary and save each new result as one CSV row.

const MARKER_IDS := [0, 1, 2]
const MARKER_NAMES := ["common", "chest", "navel"]
const TEST_TYPES := ["calibration", "stationary", "headmotion", "moving", "hiding"]
# Where the head was standing while the markers stayed put. A marker's pose error is systematic
# per VIEWPOINT, so labelling the viewpoint is what lets the analysis ask whether the offset
# learned from the left of the mannequin agrees with the one learned from the right. Without
# these labels a walk is just an undifferentiated pile of rows.
const CALIBRATION_PHASES := [
	"near", "far", "left_side", "right_side", "crouch", "stand_tall"
]
const STATIONARY_PHASES := ["stationary"]
# How fast the head was moving. Capture latency displaces a marker in proportion to head speed,
# so a recording that never changes speed cannot separate latency from anything else.
const HEADMOTION_PHASES := ["still", "slow", "medium", "fast"]
const MOVING_PHASES := [
	"stationary", "moving_left", "stationary", "moving_right", "stationary"
]
const HIDING_PHASES := [
	"all_visible", "common_hidden", "all_visible", "chest_hidden",
	"all_visible", "navel_hidden", "all_visible"
]
const POSE_SUFFIXES := ["x", "y", "z", "qx", "qy", "qz", "qw"]

@export var detection_source: Node
@export var right_controller: XRController3D
@export var left_controller: XRController3D
# Typed as Node, not Label, so this accepts a Label3D. A CanvasLayer Label does not render
# inside the headset on this setup - only on the mirrored view - which left the recording
# state invisible while wearing it. A Label3D parented to the camera always renders in VR.
# Both node types expose .text, so _update_status works either way.
@export var status_label: Node

var _file: FileAccess
var _recording := false
var _sample_id := 0
var _test_index := 0
var _phase_index := 0
var _recording_start_ms := 0
var _last_result_hash := 0
var _have_result := false


func _ready() -> void:
	# Right A controls the recording; left X marks the next experiment phase.
	if right_controller != null:
		right_controller.button_pressed.connect(_on_right_button)
	if left_controller != null:
		left_controller.button_pressed.connect(_on_left_button)
	_update_status()


func _on_right_button(button: StringName) -> void:
	if button != &"ax_button":
		return
	if _recording:
		_stop_recording()
	else:
		_start_recording()


func _on_left_button(button: StringName) -> void:
	# X marks the next phase, Y picks the test type. Both work whether or not a recording is
	# running. X used to be ignored while stopped, which made it impossible to check the button
	# worked before committing to a take: you pressed it, nothing moved, and the only way to find
	# out whether the press had registered was to record a whole walk and read the file afterwards.
	# A recording always starts at phase 1 (see _start_recording), so pressing X beforehand
	# costs nothing.
	if button == &"ax_button":
		_phase_index = (_phase_index + 1) % _current_phases().size()
		print("ArUco phase: ", _current_phase())
		_update_status()
	elif button == &"by_button":
		_test_index = (_test_index + 1) % TEST_TYPES.size()
		_phase_index = 0
		print("ArUco test type: ", _current_test())
		_update_status()


func _process(_delta: float) -> void:
	var result := _copy_latest_result()
	if result.is_empty():
		return

	# Godot runs faster than OpenCV. Do not write the same stored result twice.
	var result_hash := hash(result)
	if _have_result and result_hash == _last_result_hash:
		return
	_have_result = true
	_last_result_hash = result_hash

	if _recording:
		_write_row(result.markers, result.camera_pose)


func _copy_latest_result() -> Dictionary:
	if detection_source == null:
		return {}

	# Get the same mutex used by the detection worker in main_3d.gd.
	var result_mutex: Mutex = detection_source.get("_detect_mutex")
	if result_mutex == null:
		return {}

	# Lock the result so the worker cannot change it while we copy it.
	result_mutex.lock()
	# Dictionary is reference-based, so make an independent deep copy.
	var markers: Dictionary = detection_source.get("_result_markers").duplicate(true)
	# Transform3D is a value type, so assigning it already makes a copy.
	var camera_pose: Transform3D = detection_source.get("_result_cam_xform")
	result_mutex.unlock()

	if markers.is_empty() and camera_pose == Transform3D.IDENTITY:
		return {}
	return {"markers": markers, "camera_pose": camera_pose}


func _start_recording() -> void:
	# The timestamp prevents a later recording from overwriting an earlier one.
	var path := "user://aruco_%s_%d.csv" % [
		_current_test(), int(Time.get_unix_time_from_system())
	]
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_error("Could not create %s" % path)
		return

	_file.store_line(",".join(_make_header()))
	_file.flush()
	_sample_id = 0
	# Always begin at phase 1, whatever X was pressed beforehand while stopped.
	_phase_index = 0
	_recording_start_ms = Time.get_ticks_msec()
	_recording = true
	print("ArUco logger started: ", path, "  phase=", _current_phase())
	_update_status()


func _stop_recording() -> void:
	_recording = false
	_file.flush()
	_file.close()
	_file = null
	print("ArUco logger stopped after ", _sample_id, " samples.")
	# The test type deliberately does NOT advance here. It used to, which meant the name a file
	# got depended on how many recordings preceded it rather than on what was in it - every file
	# from a session came out mislabelled. Y chooses the type; stopping only rewinds the phase.
	_phase_index = 0
	_update_status()


func _write_row(markers: Dictionary, camera_pose: Transform3D) -> void:
	var row := PackedStringArray([
		str(_sample_id),
		str(Time.get_ticks_msec()),
		str(Time.get_ticks_msec() - _recording_start_ms),
		_current_test(),
		_current_phase(),
	])
	_add_pose(row, camera_pose)
	for marker_id in MARKER_IDS:
		# get() gives null when the marker was not seen in this frame.
		_add_pose(row, markers.get(marker_id))

	_file.store_line(",".join(row))
	_file.flush()
	_sample_id += 1


# Adds one Transform3D pose to the current CSV row.
# The pose position is saved as x, y, and z.
# The pose rotation is converted to a quaternion and saved as qx, qy, qz, and qw.
# Each value is converted to text with 9 digits after the decimal point.
# A null pose means the marker was not seen, so the same columns are left empty
# and the row still matches the header.
func _add_pose(row: PackedStringArray, pose: Variant) -> void:
	if pose == null:
		for _unused in POSE_SUFFIXES.size():
			row.append("")
		return

	var transform: Transform3D = pose
	var q := transform.basis.get_rotation_quaternion()
	for value in [
		transform.origin.x, transform.origin.y, transform.origin.z,
		q.x, q.y, q.z, q.w,
	]:
		row.append("%.9f" % value)


func _make_header() -> PackedStringArray:
	var header := PackedStringArray([
		"sample_id", "logger_ms", "recording_ms", "test_type", "phase_label"
	])
	_add_pose_names(header, "camera")
	for marker_name in MARKER_NAMES:
		_add_pose_names(header, marker_name)
	return header


func _add_pose_names(header: PackedStringArray, name: String) -> void:
	for suffix in POSE_SUFFIXES:
		header.append(name + "_" + suffix)


func _current_test() -> String:
	return TEST_TYPES[_test_index]


func _current_phases() -> Array:
	match _current_test():
		"calibration":
			return CALIBRATION_PHASES
		"headmotion":
			return HEADMOTION_PHASES
		"moving":
			return MOVING_PHASES
		"hiding":
			return HIDING_PHASES
		_:
			return STATIONARY_PHASES


func _current_phase() -> String:
	return _current_phases()[_phase_index]


func _update_status() -> void:
	if status_label == null:
		return
	var state := "RECORDING" if _recording else "STOPPED"
	# Which phase number it is matters while recording: the label alone does not say whether the
	# press registered when two phases in a row carry the same name.
	status_label.text = "%s - %s\nPhase %d/%d: %s\nA: start/stop   X: next phase   Y: test type" % [
		state, _current_test(),
		_phase_index + 1, _current_phases().size(), _current_phase()
	]


func _exit_tree() -> void:
	if _recording:
		_stop_recording()
