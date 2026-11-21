extends "res://tests/suite.gd"
## Headset, 20 Nov 2026 (user): "I said 'please call 112' and the app did not pick it up".
## A plain request to call 112 is taken directly at the call step, in many wordings; said
## earlier (together with "he is not responding", before the shoulder tap was seen) it is
## kept and taken as soon as the call step comes.

const Speech = preload("res://scripts/scenario/spoken_observation.gd")

const REQUESTS := [
	"Please call 112", "Pls call 112.", "Call one one two!", "You, call 1-1-2 please", "Can you dial 112 now",
	"You in the red jacket, call an ambulance", "Please call the emergency services",
	"Bitte ruf die 112 an", "Rufen Sie den Notruf", "Wähl bitte die eins eins zwei", "Ruf den Rettungsdienst!",
	"Proszę zadzwonić pod 112", "Zadzwoń na pogotowie", "Dzwoń pod jeden jeden dwa",
]
const OTHER := ["Do not call 112", "He is not responding", "Bring the defibrillator", "I check the breathing", ""]

class Audio extends NaretAudioManager:
	var lines: Array = []
	func _ready() -> void: pass
	func set_listening(value: bool) -> void: listening = value
	func set_language(value: String) -> void: language = value
	func stop_speech() -> void: pass
	func is_speaking() -> bool: return false
	func speak(text: String, _lang: String = "pl", _key: String = "calm", speaker: String = "bystander", _keep: bool = false) -> void:
		lines.append({"text": text, "speaker": speaker})

class LLM extends NaretLLMOrchestrator:
	func _ready() -> void: pass
	func cancel_pending() -> void: pass

class Interpreter extends Node:
	var asked: Array = []
	func cancel_pending() -> void: pass
	func interpret(text: String, _language: String, _context := "") -> void: asked.append(text)

## CCBM as it answers an in-order spoken report: it hands the action back to main.
class Ccbm extends Node:
	var host: Node
	func observe_action(action: String) -> bool:
		host._on_action(action, {"source": "speech"})
		return true
	func observe_speech(_text: String) -> bool: return false
	func observe_breath_pair() -> void: pass

class Host extends "res://scripts/main.gd":
	func _ready() -> void: set_process(false)
	func _process(_delta: float) -> void: pass
	func _show_reply(_text: String, _source: String = "") -> void: pass
	func _on_tracking_status(_status: String) -> void: pass
	func _on_service_status(_status: String) -> void: pass
	func _show_park() -> void: pass
	func _record_speech_status(_status: String) -> void: pass
	func _clear_training_session() -> void:
		_safety_asked = false
		_last_coach_step = ""
		_look_hinted = false
		_answer_hinted = false
		_safety_stated = false
		_early_call_request = false
		_early_aed_request = false
		head_scan.reset()
		_scan_done_ms = 0

func run() -> Array[String]:
	failures.clear()
	for sentence: String in REQUESTS:
		check(Speech.infer_action(sentence) == "call_emergency", "is a request to call: " + sentence)
	for sentence: String in ["He is not responding. Please call 112!", "He does not react, call an ambulance", "Er reagiert nicht. Ruf bitte die 112 an!", "Nie reaguje, zadzwoń pod 112"]:
		check(Speech.requests_emergency_call(sentence), "holds a request to call: " + sentence)
	for sentence: String in ["Hey, could you please call 112 and could you please ring the defibrillator?", "Can you call 112 and can you get the AED?", "Kannst du bitte den Notruf rufen und du den Defi holen?", "Czy może pani zadzwonić pod 112, a pan przynieść defibrylator?"]:
		check(Speech.requests_emergency_call(sentence) and Speech.requests_aed_fetch(sentence), "both tasks in one polite sentence: " + sentence)
	for sentence: String in ["Should I get the AED?", "Do not get the AED", "Soll ich den Defibrillator holen?"]:
		check(not Speech.requests_aed_fetch(sentence), "no request for the AED: " + sentence)
	for sentence: String in ["Do not call 112", "Should I call 112?", "He is not responding", "I'll check the breathing and then the pulse"]:
		check(not Speech.requests_emergency_call(sentence), "holds no request to call: " + sentence)
	for sentence: String in OTHER:
		check(Speech.infer_action(sentence) != "call_emergency", "is not a request to call: " + sentence)

	var tree := Engine.get_main_loop() as SceneTree
	for path in ["user://test_call_choices.cfg", "user://test_call_calibration.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var host = load("res://scenes/main.tscn").instantiate()
	host.set_script(Host)
	tree.root.add_child(host)
	host.language_file = "user://test_call_choices.cfg"
	host.anchor.calibration_file = "user://test_call_calibration.cfg"
	host.xr = NaretOpenXRSetup.new()
	host.xr.active = true
	host.anchor.locked = true
	host.anchor.calibrated = true
	host.scenario = NaretScenario.new()
	host.add_child(host.scenario)
	var audio := Audio.new()
	host.audio_manager = audio
	host.add_child(audio)
	host.llm = LLM.new()
	host.add_child(host.llm)
	var interpreter := Interpreter.new()
	host.observation_interpreter = interpreter
	host.add_child(interpreter)
	var ccbm := Ccbm.new()
	ccbm.host = host
	host.ccbm = ccbm
	host.add_child(ccbm)
	host.director = load("res://scripts/scenario/single_witness_director.gd").new()
	host.add_child(host.director)
	host.director.configure(host.scenario, host.get_node("Bystanders/Anna"), host.get_node("Bystanders/Marek"), host.mannequin, null)
	host.director.language = func(): return host._language
	host.director.speak = func(_key, _text, _lang, _speaker): pass
	host.setup.answers = {"language": "en", "mode": "own", "situation": "B", "breaths": "yes"}
	host._set_language("en")

	# 1. At the call step the plain request is taken directly.
	host._on_action("start")
	for action in ["begin_check", "check_responsiveness"]: host.scenario.submit_action(action)
	check(host.scenario.state == NaretScenario.State.CALL_HELP and not host.scenario.emergency_called, "at the call step, nobody called yet")
	host._on_transcript("Please call one one two.")
	check(host.scenario.emergency_called and interpreter.asked.is_empty(), "'please call 112' starts the call at once, without the cloud's reading")

	# 2. Said before the step is due: kept, and taken when the step comes.
	host._on_action("restart")
	host.scenario.submit_action("begin_check")
	check(host.scenario.state == NaretScenario.State.CHECK_PATIENT, "at the response step")
	host._on_transcript("He is not responding. Please call 112!")
	check(host._early_call_request and not host.scenario.emergency_called, "the request is kept while the response step is open")
	host.scenario.submit_action("check_responsiveness")
	host._take_early_call()
	check(host.scenario.emergency_called and not host._early_call_request, "and taken as soon as the call step comes")

	# 2b. The defibrillator asked early is kept too, and both are taken in the order said.
	host._on_action("restart")
	host.scenario.submit_action("begin_check")
	host._on_transcript("He is not responding. You, call 112, and you, get the defibrillator!")
	check(host._early_call_request and host._early_aed_request and not host._early_aed_first, "both tasks are kept, the call first")
	host.scenario.submit_action("check_responsiveness")
	host._take_early_call()
	check(host.scenario.emergency_called and host.scenario.aed_requested, "both are taken at the call step: nobody asks 'who gets the defibrillator?'")
	host._on_action("restart")
	host.scenario.submit_action("begin_check")
	host._on_transcript("Bring the AED please")
	check(host._early_aed_request and host._early_aed_first, "the device alone is kept")
	# 2c. At the call step a plain request in free wording sends Marek directly.
	host._on_action("restart")
	for action in ["begin_check", "check_responsiveness"]: host.scenario.submit_action(action)
	host._on_transcript("You with the backpack, can you go and fetch a defibrillator.")
	check(host.scenario.aed_requested, "a free wording of the request sends him")

	# 3. A question is not a request, and a restart forgets a kept one.
	host._on_action("restart")
	host.scenario.submit_action("begin_check")
	host._on_transcript("Should I call 112?")
	check(not host._early_call_request, "a question is not kept as a request")
	host._early_call_request = true
	host._clear_training_session()
	check(not host._early_call_request, "a restart forgets it")

	for path in ["user://test_call_choices.cfg", "user://test_call_calibration.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	host.xr.free()
	host.free()
	return failures
