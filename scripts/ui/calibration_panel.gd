class_name NaretCalibrationPanel
extends Control
## Manual alignment of Denis's patient with the physical mannequin.
## Six fields edit the MODEL offset: X/Y/Z (metres), rotation (degrees).
## The existing model scale is preserved; this panel never edits marker geometry.
## Editing previews immediately; Save persists the offset for later launches.
## This does not change the camera calibration or correct marker detection errors.

signal closed
signal language_requested(value: String)
signal start_requested
signal voice_sample_requested
signal microphone_requested(enabled: bool)
var microphone_enabled := false
var anchor: NaretSpatialAnchor
var language := "de"
var _values: Array[SpinBox] = []
var _message: Label
var _model_scale := Vector3.ONE
var _language_buttons: Dictionary = {}

func _ready() -> void:
	_setup_button_feedback.call_deferred()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.04, 0.06, 0.95)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	column.add_child(NaretDashboard.label(NaretLanguage.ui("Patient ausrichten", "Dopasuj pacjenta", language), 30))
	var explanation := NaretDashboard.label(NaretLanguage.ui("Position in Metern, Rotation in Grad. Vorschau sofort; Speichern dauerhaft.", "Pozycja w metrach, obr?t w stopniach. Podgl?d od razu; Zapisz utrwala zmiany.", language), 18, NaretDashboard.MUTED)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(explanation)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation", 10)
	scroll.add_child(fields)
	if anchor:
		_model_scale = anchor.marker_to_mannequin.basis.get_scale()
	var names := ["X", "Y", "Z", "Pitch °", "Yaw °", "Roll °"]
	var current := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	if anchor:
		var euler := anchor.marker_to_mannequin.basis.orthonormalized().get_euler()
		current = [anchor.marker_to_mannequin.origin.x, anchor.marker_to_mannequin.origin.y, anchor.marker_to_mannequin.origin.z, rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z)]
	for i in names.size():
		# Fields 0..2: translation; 3..5: rotation.
		var row := HBoxContainer.new()
		fields.add_child(row)
		var name_label := NaretDashboard.label(names[i], 22)
		name_label.custom_minimum_size.x = 140
		row.add_child(name_label)
		var spin := SpinBox.new()
		if i < 3:
			spin.min_value = -3
			spin.max_value = 3
			spin.step = 0.005 # 5 mm adjustment.
		else:
			spin.min_value = -180
			spin.max_value = 180
			spin.step = 1.0 # One degree adjustment.
		spin.value = current[i]
		spin.custom_minimum_size = Vector2(200, 48)
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spin)
		_values.append(spin)
		spin.value_changed.connect(func(_v: float): _preview())
		# Large buttons work with the headset pointer; no keyboard entry needed.
		for direction in [-1.0, 1.0]:
			var nudge := Button.new()
			nudge.text = "−" if direction < 0.0 else "+"
			nudge.custom_minimum_size = Vector2(64, 48)
			row.add_child(nudge)
			nudge.pressed.connect(func(): spin.value += direction * spin.step)
			if i == 1 and anchor and anchor.floor_locked:
				nudge.disabled = true
		if i == 1 and anchor and anchor.floor_locked:
			spin.editable = false
			name_label.text = "Y (floor locked)"
	if anchor:
		# Transparency is the amount of passthrough visible through the patient.
		var transparency := SpinBox.new()
		transparency.min_value = 0
		transparency.max_value = 100
		transparency.step = 5
		transparency.suffix = "%"
		transparency.value = (1.0 - anchor.patient_opacity) * 100.0
		fields.add_child(NaretDashboard.label("Body transparency (face stays solid)", 22))
		fields.add_child(transparency)
		transparency.value_changed.connect(func(value: float):
			anchor.patient_opacity = 1.0 - value / 100.0
			var patient := anchor.get_node_or_null("Mannequin") as NaretMannequin
			if patient:
				patient.set_overlay_opacity(anchor.patient_opacity))
		var floor_adjustment := SpinBox.new()
		floor_adjustment.min_value = -30
		floor_adjustment.max_value = 30
		floor_adjustment.step = 0.5
		floor_adjustment.suffix = "cm"
		floor_adjustment.value = anchor.floor_adjustment_m * 100.0
		fields.add_child(NaretDashboard.label("Patient floor height adjustment", 22))
		fields.add_child(floor_adjustment)
		floor_adjustment.value_changed.connect(func(value: float):
			anchor.floor_adjustment_m = value / 100.0
			anchor.refresh())
	_message = NaretDashboard.label("", 18, NaretDashboard.LIME)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_message)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	var save := NaretDashboard.button(NaretLanguage.ui("Kalibrierung speichern", "Zapisz kalibrację", language), true)
	buttons.add_child(save)
	save.pressed.connect(_save_alignment)
	var close := NaretDashboard.button(NaretLanguage.ui("Schließen", "Zamknij", language))
	buttons.add_child(close)
	close.pressed.connect(_close_panel)

func _setup_button_feedback() -> void:
	for node in find_children("*", "Button", true, false):
		var button := node as Button
		var green := StyleBoxFlat.new()
		green.bg_color = Color("16843c")
		button.add_theme_stylebox_override("pressed", green)
		if button in _language_buttons.values():
			continue
		var normal := button.get_theme_stylebox("normal")
		button.pressed.connect(func():
			button.add_theme_stylebox_override("normal", green)
			if button.toggle_mode:
				button.add_theme_stylebox_override("normal", green if button.button_pressed else normal)
			else:
				get_tree().create_timer(0.8).timeout.connect(func():
					if is_instance_valid(button): button.add_theme_stylebox_override("normal", normal)))

func _refresh_language_buttons() -> void:
	for code: String in _language_buttons:
		var button: Button = _language_buttons[code]
		var selected := code == language
		var style := StyleBoxFlat.new()
		style.bg_color = Color("16843c") if selected else Color("283442")
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, style)

func _save_alignment() -> void:
	# Save only after startup has established an anchor. A failed disk write
	# clears the calibrated flag in spatial_anchor.gd, so Start stays blocked.
	if not anchor:
		return
	if not anchor.locked:
		_message.text = "Wait for marker placement / Auf Marker warten"
		return
	anchor.calibrated = true
	if anchor.save_calibration() == OK:
		_message.text = NaretLanguage.ui("Gespeichert", "Zapisano", language)
	else:
		_message.text = "Save failed"

func _close_panel() -> void:
	# Closing keeps the current preview in memory; only Save writes it to disk.
	closed.emit()
	queue_free()

func _preview() -> void:
	if not anchor or _values.size() < 6:
		return
	var position := Vector3(_values[0].value, _values[1].value, _values[2].value)
	var rotation := Vector3(deg_to_rad(_values[3].value), deg_to_rad(_values[4].value), deg_to_rad(_values[5].value))
	var basis := Basis.from_euler(rotation) * Basis.from_scale(_model_scale)
	anchor.marker_to_mannequin = Transform3D(basis, position)
	anchor.refresh()
