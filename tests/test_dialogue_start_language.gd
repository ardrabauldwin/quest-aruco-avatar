extends "res://tests/suite.gd"

class Audio extends NaretAudioManager:
	var lines: Array = []
	func _ready() -> void: pass
	func set_listening(value: bool) -> void: listening = value
	func set_language(value: String) -> void: language = value
	func stop_speech() -> void: lines.clear()
	func speak(text: String, lang: String = "pl", key: String = "calm", speaker: String = "bystander") -> void:
		lines.append({"text":text,"language":lang,"key":key,"speaker":speaker})

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
	func _clear_training_session() -> void: audio_manager.stop_speech()

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	var host = load("res://scenes/main.tscn").instantiate()
	host.set_script(Host)
	tree.root.add_child(host)
	host.xr = NaretOpenXRSetup.new()
	host.xr.active = true
	host.anchor.locked = false
	host.anchor.calibrated = true
	host.scenario = NaretScenario.new()
	host.add_child(host.scenario)
	host.audio_manager = Audio.new()
	host.add_child(host.audio_manager)
	host.llm = LLM.new()
	host.add_child(host.llm)
	host.observation_interpreter = Interpreter.new()
	host.add_child(host.observation_interpreter)
	host.director = load("res://scripts/scenario/single_witness_director.gd").new()
	host.add_child(host.director)
	host.director.configure(host.scenario,host.get_node("Bystanders/Anna"),host.get_node("Bystanders/Marek"),host.mannequin,null)
	host.director.language = func(): return host._language
	host.director.speak = func(key, text, lang, speaker): host.audio_manager.speak(text,lang,key,speaker)
	host.scenario.event_recorded.connect(func(event):
		if event.get("accepted",false): host._announce_coach_step())
	host._on_action("start")
	check(host._pending_training_action=="start" and host.scenario.state==NaretScenario.State.IDLE, "early Start waits without starting an unplaced exercise")
	host._try_pending_training_start()
	check(host.audio_manager.lines.is_empty(), "waiting for placement does not speak the exercise prematurely")
	host.anchor.locked = true
	host._try_pending_training_start()
	check(host._pending_training_action.is_empty() and host.scenario.state==NaretScenario.State.INTRO, "accepted placement consumes the pending Start")
	check(host.audio_manager.lines.size()==2 and host.audio_manager.lines[0].key=="anna_arrive" and host.audio_manager.lines[1].speaker=="instructor", "queued start triggers Anna's opening and the instructor's safety instruction")
	host._try_pending_training_start()
	check(host.audio_manager.lines.size()==2, "later frames cannot restart or duplicate the opening dialogue")
	host._set_language("en")
	check(host.audio_manager.lines.size()==2 and host.audio_manager.lines[0].key=="anna_arrive" and host.audio_manager.lines[0].language=="en" and host.audio_manager.lines[1].language=="en" and host.audio_manager.lines[1].speaker=="instructor", "language switch restores interrupted Anna introduction then instructor guidance in the selected language")
	host._announce_coach_step()
	check(host.audio_manager.lines.size()==2, "ordinary updates still deduplicate the current instruction")
	host.scenario.submit_action("begin_check")
	host._set_language("de")
	check(host.audio_manager.lines.size()==1 and host.audio_manager.lines[0].speaker=="instructor" and host.audio_manager.lines[0].language=="de", "later language switches repeat current guidance without replaying Anna's arrival or changing the scenario")
	host._on_action("reset")
	host.anchor.locked = false
	host._on_action("start")
	host._on_action("reset")
	host.anchor.locked = true
	host._try_pending_training_start()
	check(host.scenario.state==NaretScenario.State.IDLE and host._pending_training_action.is_empty(), "reset cancels a queued start so dialogue cannot unexpectedly restart")
	host._set_language("pl")
	check(host.audio_manager.lines.is_empty(), "language changes during setup do not start the exercise or invent dialogue")
	host.xr.free()
	host.free()
	return failures
