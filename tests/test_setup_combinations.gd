extends "res://tests/suite.gd"
## 20 Nov 2026 (user: "do the options in the hand menu actually control the training? Do all
## combinations work?"): every combination of Situation (A alone, no AED / B other people,
## AED) and Beatmung (with / without), started one after the other in an order that crosses
## every change, so nothing of one training is left over in the next. For each start:
## what the scenario was given, which instruction the call step gets, how the 30:2 cycle
## behaves, and whether an AED can be used.
## Marek's errand is not played here: the AED's arrival is set by hand where he would.

class Audio extends NaretAudioManager:
	func _ready() -> void: pass
	func set_listening(value: bool) -> void: listening = value
	func set_language(value: String) -> void: language = value
	func stop_speech() -> void: pass
	func is_speaking() -> bool: return false
	func speak(_text: String, _lang: String = "pl", _key: String = "calm", _speaker: String = "bystander", _keep: bool = false) -> void: pass

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
	func _show_park() -> void: pass
	func _clear_training_session() -> void:
		_safety_asked = false
		_last_coach_step = ""

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	for path in ["user://test_combinations_choices.cfg", "user://test_combinations_calibration.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var host = load("res://scenes/main.tscn").instantiate()
	host.set_script(Host)
	tree.root.add_child(host)
	host.language_file = "user://test_combinations_choices.cfg"
	host.anchor.calibration_file = "user://test_combinations_calibration.cfg"
	host.xr = NaretOpenXRSetup.new()
	host.anchor.locked = true
	host.scenario = NaretScenario.new()
	host.add_child(host.scenario)
	host.audio_manager = Audio.new()
	host.add_child(host.audio_manager)
	host.llm = LLM.new()
	host.add_child(host.llm)
	host.observation_interpreter = Interpreter.new()
	host.add_child(host.observation_interpreter)
	# The app's own director (Anna the witness, Marek who brings the AED).
	host.director = load("res://scripts/scenario/aed_helper_director.gd").new()
	host.add_child(host.director)
	host.director.configure(host.scenario, host.get_node("Bystanders/Anna"), host.get_node("Bystanders/Marek"), host.mannequin, null)
	host.director.language = func(): return host._language
	host.director.speak = func(_key, _text, _lang, _speaker): pass
	host.setup.answers = {"language": "de", "mode": "own", "situation": "B", "breaths": "yes"}
	host._set_language("de")

	# Every pair of consecutive trainings differs in a new way; the first is run twice at
	# the end, after its opposite.
	var order := [["B", "yes"], ["A", "no"], ["B", "no"], ["A", "yes"], ["B", "yes"], ["A", "no"], ["A", "yes"], ["B", "no"], ["B", "yes"]]
	for index in order.size():
		var situation: String = order[index][0]
		var breaths: String = order[index][1]
		var tag := "run %d, Situation %s, ventilation %s: " % [index + 1, situation, breaths]
		# As the menu's keys do it (main._menu_setup, without its 1.2 s double-tap guard).
		host._menu_choice_ms.clear()
		host._menu_setup("situation", situation)
		host._menu_setup("breaths", breaths)
		host._on_action("start" if index == 0 else "restart")
		var scenario: NaretScenario = host.scenario
		check(scenario.state == NaretScenario.State.INTRO, tag + "the training starts")
		check(scenario.alone == (situation == "A"), tag + "alone is %s" % scenario.alone)
		check(scenario.compression_only == (breaths == "no"), tag + "compression-only is %s" % scenario.compression_only)
		check(not scenario.aed_available, tag + "no AED lies there at the start")
		check((host.director.process_mode == Node.PROCESS_MODE_DISABLED) == (situation == "A"), tag + "Anna and Marek take part only in Situation B")
		check(scenario.compressions == 0 and scenario.ventilations == 0 and scenario.cycles == 0 and not scenario.aed_requested and not scenario.aed_attached, tag + "nothing is left over from the training before")

		for action in ["begin_check", "check_responsiveness"]:
			check(scenario.submit_action(action), tag + action)
		check(NaretTrainingCoach.current_key(scenario) == ("call_alone" if situation == "A" else "call_aed"), tag + "the call step is '%s'" % NaretTrainingCoach.current_key(scenario))
		for action in ["call_emergency", "check_breathing"]:
			check(scenario.submit_action(action), tag + action)
		check(scenario.state == NaretScenario.State.CPR, tag + "CPR begins")
		check(NaretTrainingCoach.step(scenario) == ("compression_only" if breaths == "no" else "compressions"), tag + "the CPR step is '%s'" % NaretTrainingCoach.step(scenario))

		# The 30:2 cycle.
		var press := {"source": "hand_tracking", "measurement_verified": false}
		check(not scenario.submit_action("ventilation"), tag + "no breath before 30 compressions")
		for i in 30:
			scenario.submit_action("compression", press)
		check(scenario.compressions == 30, tag + "30 compressions counted, got %d" % scenario.compressions)
		if breaths == "yes":
			check(not scenario.submit_action("compression", press), tag + "after 30 the breaths come first")
			check(scenario.submit_action("ventilation") and scenario.submit_action("ventilation"), tag + "two breaths are taken")
			check(scenario.cycles == 1 and scenario.submit_action("compression", press), tag + "then the next cycle of compressions")
		else:
			check(scenario.submit_action("compression", press), tag + "compressions go on without a pause")
			check(not scenario.submit_action("ventilation") and scenario.ventilations == 0, tag + "no breaths are asked for or counted")

		# The AED.
		if situation == "A":
			check(not scenario.get_available_actions().has("request_aed") and not scenario.get_available_actions().has("attach_aed"), tag + "no AED actions are offered")
			check(not scenario.submit_action("attach_aed") and scenario.state == NaretScenario.State.CPR, tag + "an AED cannot be attached")
		else:
			check(scenario.submit_action("request_aed"), tag + "the AED can be sent for")
			check(not scenario.submit_action("attach_aed"), tag + "it cannot be attached before it is there")
			scenario.aed_available = true # where Marek puts it down
			check(scenario.submit_action("attach_aed") and scenario.state == NaretScenario.State.AED, tag + "the AED is attached once it is there")
			check(scenario.get_available_actions().has("clear_patient") or scenario.get_available_actions().has("analyze_rhythm"), tag + "the AED's own steps follow, got %s" % [scenario.get_available_actions()])
		check(NaretTrainingCoach.step(scenario) != "", tag + "a step is always named")

	# The choices are also kept for the next start of the app.
	host.setup.answers = {"language": "de", "mode": "own", "situation": "A", "breaths": "no"}
	host._load_setup_choices()
	check(host.setup.answers.situation == "B" and host.setup.answers.breaths == "yes" and host.situation == "B", "the last choices come back at the next app start, got %s" % [host.setup.answers])

	for path in ["user://test_combinations_choices.cfg", "user://test_combinations_calibration.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	host.xr.free()
	host.free()
	return failures
