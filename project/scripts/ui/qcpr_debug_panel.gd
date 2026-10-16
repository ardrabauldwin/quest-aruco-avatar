class_name NaretQcprDebugPanel
extends PanelContainer
## Debug- und Steuerungs-Panel für den Smart-Puppen-Simulator und das QCPR-Backend.
##
## Erlaubt das direkte Umschalten von Presets (Gute CPR, Zu flach, Zu langsam, etc.),
## Steuerung von Frequenz und Tiefe, Wechsel zwischen Auto- und Manuell-Modus sowie
## die Live-Visualisierung von Messwerten und Qualitätsfeedback.

signal preset_selected(preset_index: int)
signal auto_mode_toggled(enabled: bool)
signal rate_changed(rate_bpm: float)
signal depth_changed(depth_mm: float)

const SimBackend = preload("res://scripts/qcpr/simulated_manikin_backend.gd")
const Constants = preload("res://scripts/qcpr/qcpr_constants.gd")

var qcpr_manager: NaretQcprManager

var _preset_buttons: Array[Button] = []
var _auto_button: Button
var _rate_slider: HSlider
var _depth_slider: HSlider
var _rate_value_label: Label
var _depth_value_label: Label
var _live_depth_label: Label
var _live_rate_label: Label
var _feedback_label: Label
var _status_label: Label
var _close_button: Button

func _ready() -> void:
	add_theme_stylebox_override("panel", NaretDashboard.panel_style(Color("10212a"), 14, Color("2d4653")))
	custom_minimum_size = Vector2(360, 480)
	_build_ui()
	if qcpr_manager:
		_bind_manager()

func configure(manager: NaretQcprManager) -> void:
	qcpr_manager = manager
	if is_inside_tree():
		_bind_manager()

func _bind_manager() -> void:
	if not qcpr_manager:
		return
	qcpr_manager.compression_measured.connect(_on_compression_measured)
	qcpr_manager.live_wave_sample.connect(_on_wave_sample)
	qcpr_manager.quality_feedback.connect(_on_feedback)
	qcpr_manager.status_changed.connect(func(msg: String):
		if _status_label: _status_label.text = msg)

func _build_ui() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	add_child(root_vbox)

	# Kopfzeile
	var header := HBoxContainer.new()
	root_vbox.add_child(header)

	var title := NaretDashboard.label("QCPR-SIMULATOR", 14, NaretDashboard.LIME)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_close_button = Button.new()
	_close_button.text = "✕"
	_close_button.flat = true
	_close_button.pressed.connect(func(): visible = false)
	header.add_child(_close_button)

	_status_label = NaretDashboard.label("Bereit · ERC 2021", 11, NaretDashboard.MUTED)
	root_vbox.add_child(_status_label)

	# Modus-Umschalter: Auto vs Manuell
	_auto_button = NaretDashboard.button("Modus: AUTO-CPR (Aktiv)", true)
	_auto_button.pressed.connect(_toggle_auto_mode)
	root_vbox.add_child(_auto_button)

	# Presets
	var preset_title := NaretDashboard.label("Szenario-Presets:", 12, NaretDashboard.MUTED)
	root_vbox.add_child(preset_title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	root_vbox.add_child(grid)

	var presets := [
		{"name": "Gute CPR (ERC)", "idx": SimBackend.Preset.GOOD_CPR},
		{"name": "Zu flach", "idx": SimBackend.Preset.TOO_SHALLOW},
		{"name": "Zu langsam", "idx": SimBackend.Preset.TOO_SLOW},
		{"name": "Zu schnell", "idx": SimBackend.Preset.TOO_FAST},
		{"name": "Unvollst. Release", "idx": SimBackend.Preset.INCOMPLETE_RELEASE},
		{"name": "Erschöpfung", "idx": SimBackend.Preset.EXHAUSTION},
	]

	for item in presets:
		var btn := Button.new()
		btn.text = item.name
		btn.custom_minimum_size = Vector2(165, 34)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_stylebox_override("normal", NaretDashboard.panel_style(Color("1b303a"), 6))
		var idx: int = item.idx
		btn.pressed.connect(func(): _select_preset(idx))
		grid.add_child(btn)
		_preset_buttons.append(btn)

	# Live-Messwerte & Regler
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 12)
	root_vbox.add_child(sep)

	var rate_row := HBoxContainer.new()
	root_vbox.add_child(rate_row)
	rate_row.add_child(NaretDashboard.label("Ziel-Rate:", 12, NaretDashboard.MUTED))
	_rate_value_label = NaretDashboard.label("110 bpm", 12, NaretDashboard.INK)
	rate_row.add_child(_rate_value_label)

	_rate_slider = HSlider.new()
	_rate_slider.min_value = 60.0
	_rate_slider.max_value = 150.0
	_rate_slider.step = 1.0
	_rate_slider.value = 110.0
	_rate_slider.value_changed.connect(_on_rate_slider_changed)
	root_vbox.add_child(_rate_slider)

	var depth_row := HBoxContainer.new()
	root_vbox.add_child(depth_row)
	depth_row.add_child(NaretDashboard.label("Ziel-Tiefe:", 12, NaretDashboard.MUTED))
	_depth_value_label = NaretDashboard.label("55 mm", 12, NaretDashboard.INK)
	depth_row.add_child(_depth_value_label)

	_depth_slider = HSlider.new()
	_depth_slider.min_value = 20.0
	_depth_slider.max_value = 65.0
	_depth_slider.step = 1.0
	_depth_slider.value = 55.0
	_depth_slider.value_changed.connect(_on_depth_slider_changed)
	root_vbox.add_child(_depth_slider)

	# Live-Messwertanzeige
	var monitor_box := PanelContainer.new()
	monitor_box.add_theme_stylebox_override("panel", NaretDashboard.panel_style(Color("0d1a21"), 8))
	root_vbox.add_child(monitor_box)

	var mon_vbox := VBoxContainer.new()
	mon_vbox.add_theme_constant_override("separation", 4)
	monitor_box.add_child(mon_vbox)

	var mon_header := HBoxContainer.new()
	mon_vbox.add_child(mon_header)
	_live_depth_label = NaretDashboard.label("Tiefe: 0 mm", 13, NaretDashboard.LIME)
	_live_depth_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mon_header.add_child(_live_depth_label)

	_live_rate_label = NaretDashboard.label("Rate: 0 bpm", 13, NaretDashboard.LIME)
	mon_header.add_child(_live_rate_label)

	_feedback_label = NaretDashboard.label("Feedback: Bereit", 12, NaretDashboard.MUTED)
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mon_vbox.add_child(_feedback_label)

func _toggle_auto_mode() -> void:
	if not qcpr_manager or not qcpr_manager.sim_backend:
		return
	var is_auto: bool = (qcpr_manager.sim_backend.control_mode == SimBackend.ControlMode.AUTO_CPR)
	var new_auto: bool = not is_auto
	qcpr_manager.set_simulator_auto_mode(new_auto)
	_auto_button.text = "Modus: %s" % ("AUTO-CPR (Aktiv)" if new_auto else "MANUELL (Hand-Tracking)")
	auto_mode_toggled.emit(new_auto)

func _select_preset(idx: int) -> void:
	if not qcpr_manager:
		return
	qcpr_manager.select_simulator_preset(idx)
	if qcpr_manager.sim_backend:
		_rate_slider.value = qcpr_manager.sim_backend.target_rate_bpm
		_depth_slider.value = qcpr_manager.sim_backend.target_depth_mm
		_rate_value_label.text = "%.0f bpm" % _rate_slider.value
		_depth_value_label.text = "%.0f mm" % _depth_slider.value
	preset_selected.emit(idx)

func _on_rate_slider_changed(val: float) -> void:
	_rate_value_label.text = "%.0f bpm" % val
	if qcpr_manager and qcpr_manager.sim_backend:
		qcpr_manager.sim_backend.target_rate_bpm = val
	rate_changed.emit(val)

func _on_depth_slider_changed(val: float) -> void:
	_depth_value_label.text = "%.0f mm" % val
	if qcpr_manager and qcpr_manager.sim_backend:
		qcpr_manager.sim_backend.target_depth_mm = val
	depth_changed.emit(val)

func _on_compression_measured(depth_mm: float, rate_bpm: float, recoil_ok: bool, quality: Dictionary) -> void:
	var depth_str := "Tiefe: %.1f mm" % depth_mm
	var rate_str := "Rate: %.0f bpm" % rate_bpm
	if not recoil_ok:
		depth_str += " (!)"

	_live_depth_label.text = depth_str
	_live_rate_label.text = rate_str

	var is_good: bool = quality.get("is_good", false)
	_live_depth_label.add_theme_color_override("font_color", NaretDashboard.LIME if is_good else Color("f3c57b"))
	_live_rate_label.add_theme_color_override("font_color", NaretDashboard.LIME if is_good else Color("f3c57b"))

func _on_wave_sample(_time_ms: int, depth_mm: float) -> void:
	if _live_depth_label and depth_mm > 0.5:
		_live_depth_label.text = "Tiefe: %.1f mm" % depth_mm

func _on_feedback(_type: String, msg_de: String, _msg_pl: String, is_good: bool) -> void:
	if _feedback_label:
		_feedback_label.text = "Feedback: " + msg_de
		_feedback_label.add_theme_color_override("font_color", NaretDashboard.LIME if is_good else Color("f3766a"))
