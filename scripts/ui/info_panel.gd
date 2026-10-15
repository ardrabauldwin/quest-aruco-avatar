class_name NaretXRInfo
extends Control
## Patient-side readout: current instruction, bystander speech and the ECG trace.
## It carries no buttons, so it stays legible while both hands are on the chest.

var language := "de"
var ekg_view: NaretEKGRenderer
var _instruction: Label
var _dialogue: Label
var _status: Label
var _tracking: Label
var _qcpr_label: Label
var _rate_meter: ProgressBar

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", NaretDashboard.panel_style(Color("101f29"), 24))
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	_instruction = NaretDashboard.label("", 34)
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instruction.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_instruction)
	_dialogue = NaretDashboard.label("", 26, NaretDashboard.LIME)
	_dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue.custom_minimum_size.y = 72
	column.add_child(_dialogue)
	_qcpr_label = NaretDashboard.label("", 20, NaretDashboard.LIME)
	column.add_child(_qcpr_label)
	_rate_meter = ProgressBar.new()
	_rate_meter.max_value = 160.0
	_rate_meter.show_percentage = false
	_rate_meter.custom_minimum_size.y = 18
	column.add_child(_rate_meter)
	ekg_view = NaretEKGRenderer.new()
	ekg_view.custom_minimum_size.y = 150
	column.add_child(ekg_view)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 18)
	column.add_child(footer)
	_status = NaretDashboard.label("", 18, NaretDashboard.MUTED)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_status)
	_tracking = NaretDashboard.label("", 18, NaretDashboard.MUTED)
	footer.add_child(_tracking)

func update_session(scenario: NaretScenario) -> void:
	_instruction.text = NaretLanguage.text(scenario.get_instruction_key(), language)
	if language != "en": return
	var prompts := {
		"begin_check": "NEXT: Check scene safety.\nSay: The scene is safe.",
		"check_responsiveness": "NEXT: Check patient responsiveness.\nAsk: Are you okay? Can you hear me?\nReport: He is not responding.",
		"call_emergency": "NEXT: Ask Anna to call for help.\nSay: Anna, please call 112.",
		"check_breathing": "NEXT: Open the airway and check breathing.\nReport your finding: He is not breathing normally.",
		"compression": "NEXT: Perform compressions.\nCount: %d / 30. Watch your CPR gauges." % scenario.cycle_compressions,
		"ventilation": "NEXT: Give rescue breath %d of 2.\nThen say: I have given one rescue breath." % (scenario.cycle_ventilations + 1)
	}
	var allowed := scenario.get_available_actions()
	for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing", "compression", "ventilation"]:
		if action in allowed:
			_instruction.text = prompts[action]
			return

func set_language(value: String) -> void:
	language = value

func show_reply(text: String, _source: String = "") -> void:
	_dialogue.text = text

func set_status(text: String) -> void:
	_status.text = text

func set_tracking(text: String) -> void:
	_tracking.text = text

func toast(text: String) -> void:
	_status.text = text

func show_qcpr_compression(depth_mm: float, rate_bpm: float, recoil_ok: bool, quality: Dictionary) -> void:
	if not _qcpr_label: return
	var recoil_text := "" if recoil_ok else " · LEANING"
	var eval_text := "OPTIMAL" if quality.get("is_good", false) else ""
	if not quality.get("depth_ok", true):
		eval_text = "ZU FLACH" if depth_mm < 50.0 else "ZU TIEF"
		if language == "pl": eval_text = "ZA PŁYTKO" if depth_mm < 50.0 else "ZA GŁĘBOKO"
	elif not quality.get("rate_ok", true):
		eval_text = "ZU LANGSAM" if rate_bpm < 100.0 else "ZU SCHNELL"
		if language == "pl": eval_text = "ZA WOLNO" if rate_bpm < 100.0 else "ZA SZYBKO"

	_qcpr_label.text = "QCPR: %.0f mm   ·   %.0f /min   ·   %s%s" % [depth_mm, rate_bpm, eval_text, recoil_text]
	_qcpr_label.add_theme_color_override("font_color", NaretDashboard.LIME if quality.get("is_good", false) else Color("f3c57b"))

func set_qcpr_status(text: String) -> void:
	if _status: _status.text = text

func show_compression(rate_bpm: float, depth_m: float, source: String) -> void:
	# Hand excursion is an estimate; only a mannequin sensor measures chest depth.
	if not _qcpr_label: return
	_qcpr_label.text = "%.0f /min | Hand movement: %.1f cm (estimated)" % [rate_bpm, depth_m * 100.0]
	if source != "hand_tracking":
		_qcpr_label.text = "%.0f /min | Simulated compression" % rate_bpm
	_rate_meter.value = rate_bpm
	_qcpr_label.add_theme_color_override("font_color", NaretDashboard.LIME if rate_bpm >= 100.0 and rate_bpm <= 120.0 else Color("f3c57b"))
