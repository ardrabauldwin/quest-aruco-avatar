extends "res://tests/suite.gd"
## The whole start, as the trainee does it (19 Nov 2026, user review of the 18 Nov build):
## every wrist key opens a pop-up in front of the eyes, each choice is kept while the others
## are made (and for the next start of the app), and "Start training" on a fresh install
## starts the exercise: the instructor asks the safety question and the steps respond.

class Audio extends NaretAudioManager:
	var lines: Array = []
	func _ready() -> void: pass
	func set_listening(value: bool) -> void: listening = value
	func set_language(value: String) -> void: language = value
	func stop_speech() -> void: pass
	func is_speaking() -> bool: return false
	func speak(text: String, lang: String = "pl", key: String = "calm", speaker: String = "bystander", _keep: bool = false) -> void:
		lines.append({"text": text, "language": lang, "key": key, "speaker": speaker})

class LLM extends NaretLLMOrchestrator:
	func _ready() -> void: pass
	func cancel_pending() -> void: pass

class Interpreter extends Node:
	func cancel_pending() -> void: pass

class Host extends "res://scripts/main.gd":
	func _ready() -> void: set_process(false)
	func _process(_delta: float) -> void: pass
	func _toast(_text: String) -> void: pass
	func _show_reply(_text: String, _source: String = "") -> void: pass
	func _on_tracking_status(_status: String) -> void: pass
	func _on_service_status(_status: String) -> void: pass
	func _clear_training_session() -> void:
		_safety_asked = false
		_last_coach_step = ""

var _interaction: NaretXRInteraction

func _poke(key: Node3D) -> bool:
	## A fingertip of the other hand 3 mm in front of the key's face, pushed in and out.
	## A real reach takes longer than a key's 0.8 s repeat guard; so does this one.
	await (Engine.get_main_loop() as SceneTree).create_timer(0.85).timeout
	var hit := _interaction._poke_panel(key.global_position + key.global_basis.z * 0.003)
	if hit.get("target") != key: return false
	_interaction._click_hit(hit, true, "flow")
	_interaction._click_hit({}, false, "flow")
	return true

func _choose(menu: NaretHandMenu, step: String, value: String) -> void:
	check(await _poke(menu._setup_keys[step]), step + ": its key is reachable")
	check((menu._setup_choices[step] as Node3D).visible and not menu._controls.visible, step + ": the key opens its pop-up and the grid steps aside")
	check(await _poke(menu._setup_option_keys[step][value]), step + ": option " + value + " is reachable in the pop-up")
	check(not menu.popup_open() and menu._controls.visible, step + ": choosing closes the pop-up and brings the grid back")

func _spoke(audio: Audio, text: String) -> bool:
	for line: Dictionary in audio.lines:
		if line.text == text: return true
	return false

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	for path in ["user://test_start_menu_choices.cfg", "user://test_start_menu_calibration.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var host = load("res://scenes/main.tscn").instantiate()
	host.set_script(Host)
	tree.root.add_child(host)
	host.language_file = "user://test_start_menu_choices.cfg"
	host.anchor.calibration_file = "user://test_start_menu_calibration.cfg"
	host.xr = NaretOpenXRSetup.new()
	host.xr.active = true
	# A fresh install of the Szenario 1 app: the patient is placed, nothing was ever saved.
	host.anchor.locked = true
	host.anchor.calibrated = false
	host.scenario = NaretScenario.new()
	host.add_child(host.scenario)
	var audio := Audio.new()
	host.audio_manager = audio
	host.add_child(audio)
	host.llm = LLM.new()
	host.add_child(host.llm)
	host.observation_interpreter = Interpreter.new()
	host.add_child(host.observation_interpreter)
	host.director = load("res://scripts/scenario/single_witness_director.gd").new()
	host.add_child(host.director)
	host.director.configure(host.scenario, host.get_node("Bystanders/Anna"), host.get_node("Bystanders/Marek"), host.mannequin, null)
	host.director.language = func(): return host._language
	host.director.speak = func(key, text, lang, speaker): audio.speak(text, lang, key, speaker)
	host.scenario.event_recorded.connect(func(event):
		if event.get("accepted", false): host._announce_coach_step())

	var origin := XROrigin3D.new()
	tree.root.add_child(origin)
	_interaction = NaretXRInteraction.new()
	tree.root.add_child(_interaction)
	_interaction.set_process(false)
	var menu := NaretHandMenu.new()
	tree.root.add_child(menu)
	menu.configure(origin, 0, _interaction)
	menu.set_process(false)
	menu._rig.visible = true
	menu._controls.position = Vector3(0, 0.3, 0)
	host.hand_menu = menu
	menu.language_requested.connect(host._menu_language)
	menu.mode_requested.connect(host._menu_mode)
	menu.setup_requested.connect(host._menu_setup)
	menu.action_requested.connect(host._on_action)
	# As at the welcome: preset choices, then what was kept from the last start (none yet).
	host.setup.answers = {"language": "de", "mode": "own", "situation": "B", "breaths": "yes"}
	host._load_setup_choices()
	host._set_language("de")
	menu.set_setup(host.setup.answers)

	# 1. Sprache: a pop-up with English, German and Polish, in the room, not on the hand.
	check(await _poke(menu._language_menu), "the Sprache key is reachable")
	check(menu._language_choices.visible and not menu._controls.visible, "Sprache opens its pop-up and the grid steps aside")
	check(menu._language_choices.get_parent() == menu._popup_root and not menu._rig.is_ancestor_of(menu._language_choices), "the pop-up hangs in the room: it does not move with the hand")
	var names: Array = []
	for code in ["en", "de", "pl"]: names.append(menu._language_keys[code].label.text)
	check(names == ["English", "Deutsch", "Polski"], "the pop-up offers English, Deutsch and Polski, got %s" % [names])
	check(menu._language_keys["de"].fill.a > 0.0, "the current language is green in the pop-up")
	check(await _poke(menu._language_keys["pl"]), "Polski is reachable")
	check(host._language == "pl" and not menu.popup_open() and menu._controls.visible, "Polski is chosen and the pop-up closes")
	check(menu._language_menu.label.text == "Język\nPolski", "the key shows the chosen language, got " + menu._language_menu.label.text)

	# 2. The other choices one after the other, at once: none is lost, each stays.
	await _choose(menu, "mode", "neighbour")
	check(host._mode == "neighbour" and host._language == "pl", "a mode chosen right after the language is kept (was dropped within 1.2 s)")
	await _choose(menu, "situation", "A")
	await _choose(menu, "breaths", "no")
	await _choose(menu, "gender", "female")
	var expected := {"language": "pl", "mode": "neighbour", "situation": "A", "breaths": "no", "gender": "female"}
	check(host.setup.answers == expected, "every choice is kept while the others are made, got %s" % [host.setup.answers])
	check(menu._setup_keys["situation"].label.text.contains("A –") and menu._setup_keys["breaths"].label.text.contains("Bez oddechów"), "the keys show what is chosen: " + menu._setup_keys["situation"].label.text + " / " + menu._setup_keys["breaths"].label.text)
	check(await _poke(menu._setup_keys["situation"]), "Situation opens again")
	check(menu._setup_option_keys["situation"]["A"].fill.a > 0.0 and menu._setup_option_keys["situation"]["B"].fill.a == 0.0, "reopened, the pop-up still marks A green")
	check(await _poke(menu._setup_choices["situation"].get_meta("close")), "the pop-up's close key is reachable")
	check(not menu.popup_open() and host.setup.answers == expected, "closing without a choice changes nothing")
	# A language switch keeps the other choices (a second language choice waits out the 1.2 s gap).
	await tree.create_timer(1.3).timeout
	check(await _poke(menu._language_menu) and await _poke(menu._language_keys["de"]), "German again")
	check(host.setup.answers.situation == "A" and host.setup.answers.breaths == "no" and host.setup.answers.gender == "female", "a language switch keeps situation, ventilation and gender")
	check(menu._setup_keys["situation"].label.text.contains("allein"), "the keys follow the language: " + menu._setup_keys["situation"].label.text)
	# And they are there at the next start of the app.
	host.setup.answers = {"language": "de", "mode": "own", "situation": "B", "breaths": "yes"}
	host._load_setup_choices()
	check(host.setup.answers.situation == "A" and host.setup.answers.breaths == "no" and host.setup.answers.gender == "female" and host.situation == "A", "the choices come back at the next app start, got %s" % [host.setup.answers])
	menu.set_setup(host.setup.answers)

	# 2b. A reach that slides across keys fires none of them (headset log 19 Nov 2026: Start,
	# Save calibration and Reposition within 0.1 s); a clean poke still fires.
	var fired: Array = []
	menu.alignment_save_requested.connect(func(): fired.append("save"))
	menu.reposition_requested.connect(func(): fired.append("reposition"))
	var save: Node3D = menu._large_align
	var reposition: Node3D = menu._reposition_key
	var inward := func(key: Node3D, depth: float) -> Vector3: return key.global_position + key.global_basis.z * depth
	_interaction._update_poke(1, inward.call(save, 0.003), "slide")
	_interaction._update_poke(1, save.global_position.lerp(reposition.global_position, 0.5) + save.global_basis.z * 0.003, "slide")
	_interaction._update_poke(1, inward.call(reposition, 0.003), "slide")
	_interaction._update_poke(1, inward.call(reposition, 0.003) + Vector3(0.2, 0, 0), "slide")
	check(fired.is_empty(), "sliding from Save calibration down over Reposition fires nothing, got %s" % [fired])
	_interaction._update_poke(1, inward.call(reposition, 0.003), "slide")
	_interaction._update_poke(1, inward.call(reposition, 0.02), "slide")
	check(fired == ["reposition"], "a clean poke on Reposition still fires it, got %s" % [fired])
	check(menu._language_menu.global_position.distance_to(menu._setup_keys["situation"].global_position) > 0.05, "grid rows are well apart")

	# 3. Start training on a fresh install: the exercise starts, no hidden "save calibration" step.
	menu.update_session(host.scenario)
	check(await _poke(menu._large_start), "Start training is reachable")
	check(host.scenario.state == NaretScenario.State.INTRO, "Start starts the training without a saved alignment (state %s)" % host.scenario.get_state_name())
	check(host.anchor.calibrated and FileAccess.file_exists("user://test_start_menu_calibration.cfg"), "Start saved the current placement as the alignment")
	var safety := NaretTrainingCoach.instruction("safety", "de")
	check(not audio.lines.is_empty() and audio.lines[0].speaker == "instructor" and audio.lines[0].text == safety, "the instructor asks the safety question first, got %s" % [audio.lines])
	check(host._safety_asked, "the safety step's subtitles and hints are running")
	check(host.scenario.alone and host.scenario.compression_only, "the training uses the choices: Situation A, no ventilation")
	menu.update_session(host.scenario)
	check(menu._large_start.label.text == "Restart training", "the start key offers a restart while training")

	# 4. The training responds: safety -> response -> call.
	host.head_scan.update(Vector3.FORWARD)
	host._on_action("begin_check")
	check(host.scenario.state == NaretScenario.State.INTRO and _spoke(audio, NaretLanguage.text("coach.look_left_right", "de")), "'safe' before looking around: the instructor asks to look left and right")
	host.head_scan.update(Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(50)))
	host.head_scan.update(Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(-50)))
	host._on_action("begin_check")
	check(host.scenario.state == NaretScenario.State.CHECK_PATIENT, "looked around and safe: on to the response step (state %s)" % host.scenario.get_state_name())
	check(_spoke(audio, NaretTrainingCoach.instruction("response", "de")), "the instructor gives the response step")
	host._on_action("check_responsiveness")
	check(host.scenario.state == NaretScenario.State.CALL_HELP and _spoke(audio, NaretTrainingCoach.instruction("call_alone", "de")), "no response reported: Situation A asks to call 112 with the phone (state %s)" % host.scenario.get_state_name())

	for path in ["user://test_start_menu_choices.cfg", "user://test_start_menu_calibration.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	host.xr.free()
	host.free()
	menu.free()
	_interaction.free()
	origin.free()
	return failures
