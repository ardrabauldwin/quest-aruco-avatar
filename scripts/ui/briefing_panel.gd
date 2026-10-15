class_name NaretBriefingPanel
extends Control

signal closed
signal export_requested
var summary: Dictionary = {}
var language := "de"

const MILESTONE_ORDER := ["check_responsiveness", "call_emergency", "check_breathing", "request_aed", "attach_aed", "clear_patient", "analyze_rhythm", "shock", "resume_cpr", "reassess", "reassure"]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_theme_stylebox_override("panel", NaretDashboard.panel_style(Color("101f29"), 18))
	add_child(background)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	background.add_child(column)
	var heading := NaretDashboard.label(_localized("Dein Training im Rückblick", "Podsumowanie treningu"), 28)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(heading)
	var text := RichTextLabel.new()
	text.name = "SessionFeedback"
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.fit_content = false
	text.scroll_active = true
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.selection_enabled = true
	text.add_theme_font_size_override("normal_font_size", 20)
	text.add_theme_font_size_override("bold_font_size", 21)
	text.add_theme_color_override("default_color", NaretDashboard.INK)
	text.add_theme_constant_override("line_separation", 4)
	column.add_child(text)
	text.text = build_report()
	var scroll_hint := NaretDashboard.label(_localized("Mehr Details: nach unten scrollen", "Więcej szczegółów: przewiń w dół"), 14, NaretDashboard.MUTED)
	column.add_child(scroll_hint)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	var export_button := NaretDashboard.button(_localized("Session-JSON exportieren", "Eksportuj sesję JSON"), true)
	export_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_button.custom_minimum_size.y = 56
	export_button.pressed.connect(func(): export_requested.emit())
	footer.add_child(export_button)
	var close := NaretDashboard.button(_localized("Schließen", "Zamknij"))
	close.custom_minimum_size = Vector2(150, 56)
	close.pressed.connect(func(): closed.emit(); queue_free())
	footer.add_child(close)

func build_report() -> String:
	var score: Dictionary = summary.get("score", {})
	var session: Dictionary = summary.get("scenario", {})
	var milestones: Dictionary = score.get("milestones_s", {})
	var review: Array = score.get("review", [])
	var outcome := str(session.get("outcome", "ongoing"))
	var content := "[color=#b7f581]BLS · ERC 2025 · " + _localized("Übungsdaten", "Dane treningowe") + "[/color]\n"
	match outcome:
		"simulated_handover":
			content += _localized("Simulation beendet: Übergabe an den Rettungsdienst.", "Symulacja zakończona: przekazanie zespołowi ratownictwa.")
		"trainer_simulated_rosc":
			content += _localized("Die Trainingsleitung hat Lebenszeichen simuliert. Dies ist keine vorhergesagte Schockwirkung.", "Instruktor zasymulował oznaki życia. To nie jest prognozowany efekt wyładowania.")
		_:
			content += _localized("Zwischenstand dieser Trainingssession.", "Bieżący stan tej sesji treningowej.")
	content += "\n\n"
	content += _localized("Dauer: %.0f s   ·   Akzeptierte Aktionen: %d\nKompressionen: %d   ·   Beatmungen: %d\nAED-Schocks: %d   ·   Abgelehnte Aktionen: %d", "Czas: %.0f s   ·   Przyjęte działania: %d\nUciśnięcia: %d   ·   Oddechy: %d\nWyładowania AED: %d   ·   Odrzucone działania: %d") % [session.get("elapsed_s", 0), score.get("accepted_actions", 0), session.get("compressions", 0), session.get("ventilations", 0), session.get("shocks", 0), score.get("rejected_actions", session.get("errors", 0))]
	if float(session.get("simulation_speed", 1.0)) != 1.0:
		content += "\n" + _localized("Übungsuhr: %.0f× beschleunigt", "Zegar treningu: przyspieszenie %.0f×") % float(session.simulation_speed)
	content += "\n\n[b]" + _localized("Das hat im Ablauf geklappt", "Co udało się w przebiegu") + "[/b]\n"
	var confirmed := 0
	for action: String in MILESTONE_ORDER:
		if not milestones.has(action):
			continue
		confirmed += 1
		content += "[color=#b7f581]✓[/color] " + _action_label(action) + "  [color=#82969f]" + _time_label(float(milestones[action])) + "[/color]\n"
	if confirmed == 0:
		content += _localized("Noch keine bestätigten BLS-Meilensteine aufgezeichnet.", "Nie zapisano jeszcze potwierdzonych etapów BLS.") + "\n"
	if int(session.get("cycles", 0)) > 0:
		if bool(session.get("compression_only", false)):
			content += _localized("Kontinuierliche Kompressionen wurden gewählt; keine Beatmungen vorgeschrieben.", "Wybrano ciągłe uciskanie; oddechy nie były wymagane.") + "\n"
		else:
			content += _localized("Vollständige 30:2-Zyklen: %d.", "Pełne cykle 30:2: %d.") % int(session.cycles) + "\n"
	content += "\n[b]" + _localized("Daran könnt ihr arbeiten", "Nad czym możecie popracować") + "[/b]\n"
	if review.is_empty():
		content += _localized("Keine abgelehnten Aktionen im Ablauf protokolliert. Das bestätigt die Bedienreihenfolge, nicht die Qualität realer CPR.", "Nie zapisano odrzuconych działań. Potwierdza to kolejność obsługi, a nie jakość rzeczywistej RKO.") + "\n"
	else:
		var grouped: Dictionary = {}
		for item: Dictionary in review:
			var action := str(item.get("action", ""))
			var reason := str(item.get("reason", "error.invalid_action"))
			var group_key := action + ":" + reason
			if not grouped.has(group_key):
				grouped[group_key] = {"action": action, "reason": reason, "count": 0, "first_s": item.get("elapsed_s", 0.0)}
			grouped[group_key].count += 1
		var shown := 0
		for group_key: String in grouped:
			if shown >= 8:
				content += _localized("Weitere Fehlergruppen stehen im JSON-Export.", "Pozostałe grupy błędów są w eksporcie JSON.") + "\n"
				break
			shown += 1
			var item: Dictionary = grouped[group_key]
			var reason := NaretLanguage.text(str(item.reason), language)
			if reason == str(item.reason):
				reason = NaretLanguage.text("error.invalid_action", language)
			content += "[color=#f4c98a]• " + _action_label(str(item.action)) + " · %d×[/color]" % int(item.count)
			content += "  [color=#82969f]" + _localized("zuerst ", "pierwszy raz ") + _time_label(float(item.first_s)) + "[/color]\n"
			content += reason + "\n\n"
	var missing: Array[String] = []
	for action: String in ["check_responsiveness", "call_emergency", "check_breathing", "request_aed", "reassure"]:
		if action == "request_aed" and session.get("scenario") == "cpr_single_witness_practice":
			continue
		if not milestones.has(action):
			missing.append(_action_label(action))
	if not missing.is_empty():
		content += "\n" + _localized("Nicht protokolliert: ", "Nie zapisano: ") + "; ".join(missing) + ".\n"
		content += _localized("Besprecht, was im gewählten Szenario noch erforderlich war.", "Omówcie, co było jeszcze potrzebne w wybranym scenariuszu.") + "\n"
	content += "\n[b]" + _localized("Messung und Einordnung", "Pomiar i interpretacja") + "[/b]\n"
	var depth_samples := int(score.get("verified_depth_samples", 0))
	var rate_samples := int(score.get("verified_rate_samples", 0))
	if depth_samples > 0:
		content += _localized("Verifizierte Drucktiefen: %d/%d im Zielbereich 5–6 cm.", "Zweryfikowana głębokość: %d/%d w zakresie 5–6 cm.") % [score.get("depth_in_range", 0), depth_samples] + "\n"
	else:
		content += _localized("Keine verifizierte Drucktiefe gemessen. Tastatur und Hand-Tracking bestätigen ausschließlich simulierte Handlungen.", "Nie zmierzono zweryfikowanej głębokości. Klawiatura i śledzenie dłoni potwierdzają jedynie działania symulowane.") + "\n"
	if rate_samples > 0:
		content += _localized("Verifizierte Frequenzen: %d/%d im Zielbereich 100–120/min.", "Zweryfikowane tempo: %d/%d w zakresie 100–120/min.") % [score.get("rate_in_range", 0), rate_samples] + "\n"
	content += NaretLanguage.text("score.notice", language) + "\n"
	content += "\n[b]" + _localized("Für den nächsten Durchlauf", "Na kolejny przebieg") + "[/b]\n"
	content += _localized("Bei fehlender Reaktion normale Atmung höchstens 10 s prüfen. 112 und AED organisieren. 30:2, 100–120/min, 5–6 cm und vollständige Entlastung. Nach AED-Schock oder Entscheidung gegen einen Schock sofort weiterdrücken.", "Przy braku reakcji oceniaj prawidłowy oddech najwyżej 10 s. Wezwij 112 i AED. 30:2, 100–120/min, 5–6 cm i pełne odciążenie. Po wyładowaniu AED lub decyzji o jego braku natychmiast kontynuuj uciskanie.")
	if session.get("scenario") == "cpr_single_witness_practice":
		# This focused practice has no AED stage.
		var last_heading := content.rfind("[/b]\n")
		content = content.left(last_heading + 5) + NaretLanguage.text("instruction.cpr", language)
	return content

func _action_label(action: String) -> String:
	var key := "action." + action
	var result := NaretLanguage.text(key, language)
	if result == key:
		return _localized("Nicht passender Schritt", "Niewłaściwy krok")
	return result

func _time_label(seconds: float) -> String:
	var whole := maxi(0, int(seconds))
	return "%02d:%02d" % [whole / 60, whole % 60]

func _localized(german: String, polish: String) -> String:
	return NaretLanguage.ui(german, polish, language)
