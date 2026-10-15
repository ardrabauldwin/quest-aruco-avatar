class_name NaretDashboard
extends Control

signal action_requested(action: String)
signal language_requested(language: String)
signal mode_requested(mode: String)
signal transcript_submitted(text: String)
signal recording_requested(active: bool)
signal export_requested
signal qcpr_panel_requested

const INK := Color("eef2ee")
const MUTED := Color("82969f")
const LIME := Color("b7f581")
const PANEL := Color("12212a")
var language := "de"
var ekg_view: NaretEKGRenderer
var _instruction: Label
var _state_label: Label
var _title: Label
var _subtitle: Label
var _actions: VBoxContainer
var _dialogue: Label
var _status: Label
var _tracking: Label
var _metrics: Label
var _rhythm: Label
var _timer: Label
var _score: Label
var _counter: Label
var _steps: Array[Panel] = []
var _input: LineEdit
var _talk_button: Button
var _phase := -1
var _last_actions := ""
var _recording := false
var _toast: Label
var _dialogue_title: Label
var _ekg_title: Label
var _mode_button: Button
var _qcpr_button: Button
var mode := "own"
var _export_button: Button
var _hint: Label
var _quality: Label

static func panel_style(color: Color = PANEL, radius: int = 18, border: Color = Color("263841")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = border
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style

static func label(text: String, font_size: int = 18, color: Color = INK) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result

static func button(text: String, primary: bool = false) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 43
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.add_theme_font_size_override("font_size", 17)
	result.add_theme_color_override("font_color", Color("14241d") if primary else INK)
	result.add_theme_color_override("font_hover_color", Color("14241d") if primary else INK)
	result.add_theme_stylebox_override("normal", panel_style(LIME if primary else Color("1b303a"), 9))
	result.add_theme_stylebox_override("hover", panel_style(Color("d0ffa6") if primary else Color("294651"), 9))
	result.add_theme_stylebox_override("pressed", panel_style(Color("96ce69") if primary else Color("10212a"), 9))
	result.add_theme_stylebox_override("focus", panel_style(Color(0,0,0,0), 9, LIME))
	for state in ["normal", "hover", "pressed"]:
		var style := result.get_theme_stylebox(state) as StyleBoxFlat
		style.content_margin_top = 9
		style.content_margin_bottom = 9
	return result

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	set_language(language)

func _place(control: Control, rect: Rect2) -> void:
	add_child(control)
	control.position = rect.position
	control.size = rect.size

func _build() -> void:
	var brand := label("▰  NaReT", 30)
	_place(brand, Rect2(38, 26, 200, 46))
	var brand_detail := label("MANNEQUIN / XR", 12, MUTED)
	_place(brand_detail, Rect2(42, 76, 200, 20))
	_place(label("SIMULATION LAB", 13, LIME), Rect2(274, 44, 190, 25))
	var top_line := ColorRect.new()
	top_line.color = Color("263740")
	_place(top_line, Rect2(40, 112, 1360, 1))
	_qcpr_button = button("QCPR-Sim")
	_qcpr_button.visible = false
	_place(_qcpr_button, Rect2(494, 33, 148, 44))
	_qcpr_button.pressed.connect(func(): qcpr_panel_requested.emit())
	_mode_button = button("")
	_place(_mode_button, Rect2(654, 33, 182, 44))
	_mode_button.pressed.connect(func(): mode_requested.emit("neighbour" if mode == "own" else "own"))
	for i in 3:
		var lang := ["de", "pl", "en"][i] as String
		var lang_button := button(lang.to_upper())
		_place(lang_button, Rect2(1110 + i * 96, 33, 82, 44))
		lang_button.pressed.connect(func(): language_requested.emit(lang))
	_title = label("Üben, wenn es\nwirklich zählt.", 45)
	_place(_title, Rect2(40, 152, 760, 122))
	_subtitle = label("Ein Szenario. Zwei Sprachen. Gemeinsam handeln.", 18, MUTED)
	_place(_subtitle, Rect2(42, 285, 850, 35))
	_tracking = label("●  DESKTOP-VORSCHAU", 12, LIME)
	_place(_tracking, Rect2(44, 341, 810, 28))
	_quality = label("", 18, LIME)
	_place(_quality, Rect2(44, 554, 880, 36))
	_hint = label("Ziehen: Ansicht drehen   ·   Scrollen: Zoom", 13, MUTED)
	_place(_hint, Rect2(44, 651, 820, 28))
	_build_training_panel()
	_build_monitor()
	_status = label("●  Bereit · Offline-Audio verfügbar", 13, MUTED)
	_place(_status, Rect2(42, 872, 850, 22))
	_metrics = label("", 12, MUTED)
	_place(_metrics, Rect2(1020, 873, 370, 20))
	_metrics.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast = label("", 17, LIME)
	_place(_toast, Rect2(44, 600, 890, 38))

func _build_training_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style())
	_place(panel, Rect2(1000, 142, 400, 710))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	_state_label = label("BASIC LIFE SUPPORT", 12, LIME)
	_state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_state_label)
	_timer = label("00:00", 15, MUTED)
	row.add_child(_timer)
	var steps_row := HBoxContainer.new()
	steps_row.add_theme_constant_override("separation", 5)
	column.add_child(steps_row)
	for i in 7:
		var step := Panel.new()
		step.custom_minimum_size = Vector2(0, 4)
		step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		step.add_theme_stylebox_override("panel", panel_style(Color("29404a"), 2))
		steps_row.add_child(step)
		_steps.append(step)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var exercise := VBoxContainer.new()
	exercise.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exercise.add_theme_constant_override("separation", 12)
	scroll.add_child(exercise)
	_instruction = label("", 22)
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instruction.custom_minimum_size.y = 112
	exercise.add_child(_instruction)
	_counter = label("", 15, LIME)
	exercise.add_child(_counter)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	exercise.add_child(_actions)
	var dialogue_panel := PanelContainer.new()
	dialogue_panel.add_theme_stylebox_override("panel", panel_style(Color("1a2c35"), 12))
	column.add_child(dialogue_panel)
	var dialogue_column := VBoxContainer.new()
	dialogue_column.add_theme_constant_override("separation", 8)
	dialogue_panel.add_child(dialogue_column)
	_dialogue_title = label("ANNA  /  NACHBARSPRACHE PL", 11, LIME)
	dialogue_column.add_child(_dialogue_title)
	_dialogue = label("Proszę, pomóż mu! Co mam zrobić?", 18)
	_dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue.custom_minimum_size.y = 66
	dialogue_column.add_child(_dialogue)
	_input = LineEdit.new()
	_input.placeholder_text = "Mit Anna sprechen …"
	_input.custom_minimum_size.y = 42
	_input.add_theme_stylebox_override("normal", panel_style(Color("0d1b23"), 8))
	_input.add_theme_font_size_override("font_size", 15)
	_input.text_submitted.connect(func(text: String):
		if not text.strip_edges().is_empty():
			transcript_submitted.emit(text)
			_input.clear())
	column.add_child(_input)
	_talk_button = button("Mikrofon halten  [T]")
	_talk_button.button_down.connect(func(): set_recording(true); recording_requested.emit(true))
	_talk_button.button_up.connect(func(): set_recording(false); recording_requested.emit(false))
	column.add_child(_talk_button)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	_score = label("TRAINING · ERC 2025", 11, MUTED)
	_score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_score)
	_export_button = Button.new()
	_export_button.text = "Export ↗"
	_export_button.flat = true
	_export_button.add_theme_color_override("font_color", MUTED)
	_export_button.pressed.connect(func(): export_requested.emit())
	footer.add_child(_export_button)

func _build_monitor() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style(Color("0e1c23"), 16))
	_place(panel, Rect2(40, 696, 930, 156))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	panel.add_child(row)
	var number_column := VBoxContainer.new()
	number_column.custom_minimum_size.x = 153
	row.add_child(number_column)
	_ekg_title = label("EKG / SIMULATION", 11, MUTED)
	number_column.add_child(_ekg_title)
	_rhythm = label("VF", 44, LIME)
	number_column.add_child(_rhythm)
	number_column.add_child(label("II   ·   25 mm/s", 12, MUTED))
	ekg_view = NaretEKGRenderer.new()
	ekg_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ekg_view)

func set_language(lang: String) -> void:
	language = lang
	_phase = -1
	_last_actions = ""
	if not is_instance_valid(_title): return
	_title.text = NaretLanguage.ui("Üben, wenn es\nwirklich zählt.", "Ćwicz, gdy liczy się\nkażda sekunda.", lang)
	_subtitle.text = NaretLanguage.ui("BLS trainieren. Nachbarsprache sprechen.", "Trening RKO. W języku sąsiada.", lang)
	if _qcpr_button:
		_qcpr_button.text = NaretLanguage.ui("QCPR-Sim", "Sym. QCPR", lang)
	_hint.text = NaretLanguage.ui("Ziehen: Ansicht drehen   ·   Scrollen: Zoom   ·   C: Drücken   ·   V: Beatmen   ·   F2: QCPR", "Przeciągnij: obrót   ·   Kółko: zoom   ·   C: ucisk   ·   V: oddech   ·   F2: QCPR", lang)
	_input.placeholder_text = NaretLanguage.ui("Mit Anna sprechen …", "Porozmawiaj z Anną …", lang)
	_refresh_mode()
	_ekg_title.text = NaretLanguage.ui("EKG / SIMULATION", "EKG / SYMULACJA", lang)
	set_recording(_recording)

func update_session(scenario: NaretScenario) -> void:
	var seconds := int(scenario.elapsed)
	_timer.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	_instruction.text = NaretLanguage.text(scenario.get_instruction_key(), language)
	var available := scenario.get_interface_actions()
	if scenario.state == NaretScenario.State.RECOVERY: available = ["restart", "briefing"]
	var key := str(available) + language
	if key != _last_actions:
		_last_actions = key
		for child in _actions.get_children():
			_actions.remove_child(child)
			child.queue_free()
		# Communication has its own controls; keep clinical choices readable.
		var count := 0
		for action in available:
			if action in ["reassure", "simulate_rosc"]: continue
			var title := action_text(action)
			var btn := button(title, count == 0)
			btn.pressed.connect(func(): action_requested.emit(action))
			_actions.add_child(btn)
			count += 1
	if _phase != scenario.state:
		_phase = scenario.state
		_state_label.text = NaretLanguage.text("state." + scenario.get_state_name(), language).to_upper()
		for i in _steps.size():
			_steps[i].add_theme_stylebox_override("panel", panel_style(LIME if i <= _phase else Color("29404a"), 2))
	_counter.text = ""
	_score.text = "%d %s · %d %s" % [scenario.compressions, NaretLanguage.ui("DRUCK", "UCISK", language), scenario.errors, NaretLanguage.ui("FEHLER", "BŁĘDY", language)] if scenario.state > 0 else "TRAINING · ERC 2025"
	if scenario.state == NaretScenario.State.CPR:
		_counter.text = "%d / 30  %s    ·    %d / 2  %s" % [scenario.cycle_compressions, NaretLanguage.ui("Druck", "ucisk", language), scenario.cycle_ventilations, NaretLanguage.ui("Atem", "oddech", language)]
	if ekg_view.ekg: _rhythm.text = ekg_view.ekg.get_label()

func action_text(action: String) -> String:
	var special := {
		"start": ["Training starten  →", "Rozpocznij trening  →"],
		"restart": ["Neues Training", "Nowy trening"],
		"briefing": ["Nachbesprechung", "Omówienie"],
	}
	if language == "en" and action == "briefing": return "Debrief"
	if language == "en" and action == "restart": return "New training"
	if special.has(action) and language != "en": return special[action][0 if language == "de" else 1]
	return NaretLanguage.text("action." + action, language)

func show_reply(text: String, source: String = "") -> void:
	_dialogue.text = text
	if not source.is_empty(): set_status(source)

func set_status(text: String) -> void:
	if _status: _status.text = "●  " + text

func set_tracking(text: String) -> void:
	_tracking.text = "●  " + text.to_upper()

func set_mode(value: String) -> void:
	mode = value
	_refresh_mode()

func _refresh_mode() -> void:
	if not is_instance_valid(_mode_button): return
	# The button offers the other mode; the dialogue title states the current one.
	_mode_button.text = NaretLanguage.text("mode.neighbour" if mode == "own" else "mode.own", language)
	var spoken := NaretLanguage.text("mode.own" if mode == "own" else "mode.neighbour", language)
	_dialogue_title.text = "ANNA  /  " + spoken.to_upper()

func set_recording(active: bool) -> void:
	_recording = active
	if _talk_button:
		if language == "en":
			_talk_button.text = "Recording" if active else "Automatic microphone [T]"
			return
		_talk_button.text = ("●  Aufnahme läuft" if active else "Mikrofon automatisch  [T]") if language == "de" else ("●  Nagrywanie" if active else "Mikrofon automatyczny  [T]")

func set_performance(metrics: Dictionary) -> void:
	_metrics.text = "%d FPS  /  %d DRAWS  /  %d MB" % [metrics.fps, metrics.draw_calls, metrics.memory_mb]

func toast(text: String) -> void:
	_toast.text = text
	var timer := get_tree().create_timer(4)
	timer.timeout.connect(func():
		if _toast.text == text: _toast.text = "")

func has_text_focus() -> bool:
	return _input.has_focus()

func show_compression(rate: float, depth: float, source: String) -> void:
	var rate_text := "%d /min" % rate if rate > 0 and rate < 400 else "— /min"
	var origin := "Handbewegung: %.1f cm (Schätzung)" % (depth * 100) if source == "hand_tracking" else "Tastatur-Simulation"
	if language == "en": origin = "Hand movement: %.1f cm (estimate)" % (depth * 100) if source == "hand_tracking" else "Keyboard simulation"
	if language == "pl": origin = "Ruch dłoni: %.1f cm (szacunek)" % (depth * 100) if source == "hand_tracking" else "Symulacja klawiaturą"
	_quality.text = rate_text + "   ·   " + origin
	_quality.add_theme_color_override("font_color", LIME if rate >= 100 and rate <= 120 else Color("f3c57b"))

func show_qcpr_compression(depth_mm: float, rate_bpm: float, recoil_ok: bool, quality: Dictionary) -> void:
	var rate_text := "%d /min" % rate_bpm if rate_bpm > 0 and rate_bpm < 400 else "— /min"
	var depth_text := "%.1f mm" % depth_mm
	var recoil_text := "" if recoil_ok else (NaretLanguage.ui(" · Unvollst. Entlastung", " · Niepełne zwolnienie", language))
	var eval_text := "Optimal (ERC)" if quality.get("is_good", false) else ""
	if not quality.get("depth_ok", true):
		eval_text = "Zu flach (<50 mm)" if depth_mm < 50.0 else "Zu tief (>60 mm)"
		if language == "pl": eval_text = "Za płytko (<50 mm)" if depth_mm < 50.0 else "Za głęboko (>60 mm)"
	elif not quality.get("rate_ok", true):
		eval_text = "Zu langsam (<100/min)" if rate_bpm < 100.0 else "Zu schnell (>120/min)"
		if language == "pl": eval_text = "Za wolno (<100/min)" if rate_bpm < 100.0 else "Za szybko (>120/min)"

	var origin := "QCPR: %s · %s%s" % [depth_text, eval_text, recoil_text] if language == "de" else "QCPR: %s · %s%s" % [depth_text, eval_text, recoil_text]
	_quality.text = rate_text + "   ·   " + origin
	_quality.add_theme_color_override("font_color", LIME if quality.get("is_good", false) else Color("f3c57b"))

func set_qcpr_status(text: String) -> void:
	if _status: _status.text = "●  " + text
