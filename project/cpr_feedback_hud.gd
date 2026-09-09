extends Node3D
## Camera-attached practice UI; no claim to measure chest depth or actual breaths.
@export var zone: Node3D
var _title: Label3D
var _counter: Label3D
var _detail: Label3D
var _depth_bar: MeshInstance3D
var _depth_bar_bg: MeshInstance3D
var _hand_guide: Label3D
var _bpm_display: Label3D
var _quality_indicator: Label3D

func _ready() -> void:
	_panel(Vector2(0.36, 0.20), Vector3.ZERO, Color(0.015, 0.045, 0.06, 0.92))
	_title = _label(Vector3(0, 0.068, 0.002), 28)
	_counter = _label(Vector3(0, 0.022, 0.002), 52)
	_detail = _label(Vector3(0, -0.055, 0.002), 20)
	_bpm_display = _label(Vector3(0.125, 0.035, 0.002), 18)
	_quality_indicator = _label(Vector3(-0.125, 0.035, 0.002), 18)

	# Depth bar background (gray)
	_panel(Vector2(0.29, 0.009), Vector3(0, -0.026, 0.002), Color(0.08, 0.18, 0.21))
	# Depth bar foreground (red/green based on quality)
	_depth_bar = _panel(Vector2(0.29, 0.009), Vector3(0, -0.026, 0.003), Color(0.95, 0.2, 0.2))

	# Hand placement guide (shows when waiting)
	_hand_guide = _label(Vector3(0, -0.12, 0.002), 26)
	_hand_guide.text = "Place hands here"
	_hand_guide.modulate = Color(0.2, 0.95, 0.4, 0.7)

	visible = false

func _label(at: Vector3, font: int) -> Label3D:
	var label := Label3D.new()
	label.position = at
	label.font_size = font
	label.pixel_size = 0.00045
	label.outline_size = 4
	label.no_depth_test = true
	label.modulate = Color(0.88, 0.98, 1.0)
	add_child(label)
	return label

func _panel(size_value: Vector2, at: Vector3, colour: Color) -> MeshInstance3D:
	var panel := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size_value
	panel.mesh = mesh
	panel.position = at
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = colour
	panel.material_override = material
	add_child(panel)
	return panel

func _process(_delta: float) -> void:
	visible = zone != null and zone.is_visible_in_tree() and not zone.get("_paused")
	if not visible:
		return
	var session = zone.get("motion_session")

	# Calculate average BPM from last 4 stroke intervals
	var avg_bpm := 0.0
	if session._bpm_samples.size() > 0:
		var sum := 0.0
		for interval in session._bpm_samples:
			sum += interval
		var avg_interval: float = sum / session._bpm_samples.size()
		if avg_interval > 0:
			avg_bpm = 60.0 / avg_interval

	var fraction := 0.0
	if session.phase == "breathing":
		_title.text = "GIVE 2 BREATHS"
		_counter.text = "%.1f s" % session.breathing_remaining_s
		_detail.text = "30/30 compressions\nPractice pause"
		_hand_guide.visible = false
		_bpm_display.text = ""
		_quality_indicator.text = ""
		fraction = session.breathing_remaining_s / maxf(0.1, session.breathing_duration_s)
		_depth_bar.scale.x = 0.001
	else:
		if not session.active:
			_title.text = "LISTEN TO BEEP"
			_counter.text = "0 / 30"
			_detail.text = session.feedback + "\n" + zone.hand_tracking_status
			_hand_guide.visible = true
			_bpm_display.text = ""
			_quality_indicator.text = ""
			fraction = 0.0
			_depth_bar.scale.x = 0.001
		else:
			_title.text = "COMPRESS"
			_counter.text = "%d / 30" % session.count
			_hand_guide.visible = false
			_quality_indicator.text = session.last_stroke_quality.to_upper()
			_bpm_display.text = "%.0f BPM" % avg_bpm if avg_bpm > 0.0 and session.tracking_available else "-- BPM"
			if not session.tracking_available:
				_detail.text = zone.hand_tracking_status
			else:
				var depth_cm: float = session.last_stroke_travel_m * 100.0
				var depth_info := "Estimated hand travel: %.1f cm" % depth_cm
				_detail.text = "%s\n%s" % [session.feedback, depth_info]
			fraction = session.last_stroke_travel_m / 0.08  # Scale to 8cm reference (shows growth for deep presses)

	# Depth bar color: red < 5cm, green >= 5cm (BLS standard)
	var bar_color := Color(0.95, 0.2, 0.2)  # Red for shallow (< 5cm)
	if session.last_stroke_quality == "good":
		bar_color = Color(0.2, 0.95, 0.4)  # Green for >= 5cm
	_depth_bar.material_override.albedo_color = bar_color

	_depth_bar.scale.x = maxf(0.001, clampf(fraction, 0.0, 1.0))
	_depth_bar.position.x = -0.145 + 0.145 * _depth_bar.scale.x
