extends "res://tests/suite.gd"
## 20 Nov 2026 (user): in the safety step the trainee SAYS that they check the surroundings,
## in any similar wording, and LOOKS to the left and right, in either order. Once both are
## there the instructor asks whether the surroundings are safe; "yes" goes on to the next
## step.

const Speech = preload("res://scripts/scenario/spoken_observation.gd")

## Statements that count, in many wordings and all three languages.
const STATEMENTS := [
	"First, I'll check the surroundings.",
	"I check whether the area is safe",
	"I am looking around for dangers",
	"Let me make sure the scene is safe first",
	"I look around",
	"First I look for hazards",
	"I'm checking my environment",
	"Zuerst schaue ich, ob die Umgebung sicher ist.",
	"Ich prüfe die Umgebung",
	"Ich schaue mich um",
	"Ich achte auf Gefahren",
	"Erst mal gucke ich, ob es hier gefährlich ist",
	"Eigenschutz zuerst",
	"Ich sehe nach, ob Gefahr besteht",
	"Ich kontrolliere, ob alles sicher ist",
	"Najpierw sprawdzam otoczenie",
	"Rozglądam się",
	"Sprawdzam, czy jest bezpiecznie",
	"Upewniam się, że nie ma zagrożenia",
]
## Not a statement of this step.
const OTHER := [
	"Should I check the surroundings?",
	"Soll ich die Umgebung prüfen?",
	"He is not responding",
	"I call 112",
	"Ich fange mit der Herzdruckmassage an",
	"Hello, can you hear me",
	"Dzwonię pod 112",
	"",
]

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
		head_scan.reset()
		_scan_done_ms = 0

func _look_around(host) -> void:
	for degrees in [0.0, 50.0, -50.0, 0.0]:
		host.xr_camera.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(degrees)), Vector3(0, 1.6, 0))
		host._update_head_scan()

func _count(audio: Audio, text: String) -> int:
	var n := 0
	for line: Dictionary in audio.lines:
		if line.text == text: n += 1
	return n

func run() -> Array[String]:
	failures.clear()
	for sentence: String in STATEMENTS:
		check(Speech.states_safety_check(sentence), "counts as the safety statement: " + sentence)
	for sentence: String in OTHER:
		check(not Speech.states_safety_check(sentence), "is not the safety statement: " + sentence)

	var tree := Engine.get_main_loop() as SceneTree
	for path in ["user://test_safety_choices.cfg", "user://test_safety_calibration.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var host = load("res://scenes/main.tscn").instantiate()
	host.set_script(Host)
	tree.root.add_child(host)
	host.language_file = "user://test_safety_choices.cfg"
	host.anchor.calibration_file = "user://test_safety_calibration.cfg"
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
	var ask_safe := NaretLanguage.text("coach.tell_if_safe", "en")
	var ask_look := NaretLanguage.text("coach.look_left_right", "en")

	# 1. Statement first, then the look.
	host._on_action("start")
	host.xr_camera.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	host._on_transcript("First, I'll check the surroundings.")
	check(host._safety_stated and host.scenario.state == NaretScenario.State.INTRO, "said first: the statement is noted, the step is still open")
	check(_count(audio, ask_safe) == 0 and interpreter.asked.is_empty(), "no question yet, and no clarification from the cloud, got %s" % [audio.lines])
	_look_around(host)
	check(_count(audio, ask_safe) == 1, "then the look: the instructor asks whether it is safe, at once")
	host._on_transcript("Yes")
	check(host.scenario.state == NaretScenario.State.CHECK_PATIENT, "'yes' goes on to the next step (state %s)" % host.scenario.get_state_name())

	# 2. The look first, then the statement.
	audio.lines.clear()
	host._on_action("restart")
	_look_around(host)
	check(_count(audio, ask_safe) == 0, "looked first, nothing said yet: no question at once")
	host._on_transcript("Ich schaue zuerst, ob die Umgebung sicher ist.")
	check(_count(audio, ask_safe) == 1 and host.scenario.state == NaretScenario.State.INTRO, "then the statement (in German): the instructor asks whether it is safe")
	host._on_transcript("It is safe")
	check(host.scenario.state == NaretScenario.State.CHECK_PATIENT, "'it is safe' goes on to the next step")

	# 3. "It is safe" before looking: asked to look, then asked again, then on.
	audio.lines.clear()
	host._on_action("restart")
	host.xr_camera.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	host._on_transcript("The scene is safe")
	check(host.scenario.state == NaretScenario.State.INTRO and _count(audio, ask_look) == 1, "'safe' before looking is not enough: he asks for the look")
	_look_around(host)
	check(_count(audio, ask_safe) == 1, "after the look he asks whether it is safe")
	host._on_transcript("Yes, it is safe")
	check(host.scenario.state == NaretScenario.State.CHECK_PATIENT, "and 'yes' goes on")

	# 4. The old way still works: look, then report "safe" without any other sentence.
	audio.lines.clear()
	host._on_action("restart")
	_look_around(host)
	host._on_transcript("The scene is safe")
	check(host.scenario.state == NaretScenario.State.CHECK_PATIENT and _count(audio, ask_safe) == 0, "looked and reported safe: straight on, without the extra question")

	# 5. The statement recognised by the cloud classifier counts the same.
	audio.lines.clear()
	host._on_action("restart")
	_look_around(host)
	host._safety_statement("cloud")
	check(_count(audio, ask_safe) == 1, "a statement understood by the cloud asks the question too")
	host._safety_statement("cloud")
	check(_count(audio, ask_safe) == 1, "the question is asked once, not for every sentence")

	for path in ["user://test_safety_choices.cfg", "user://test_safety_calibration.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	host.xr.free()
	host.free()
	return failures
