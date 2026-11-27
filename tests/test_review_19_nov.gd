extends "res://tests/suite.gd"
## Headset review 19 Nov 2026: smaller head turns count for the safety check, the instructor's
## card reads "NARET Instructor", the dispatcher alone leads the CPR cycles after the call
## (no instructor repeating her), the AED helper never walks or kneels on the patient, and
## "I'm tired, take over" before the ambulance crew is there does not end the training.

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
	var asked: Array = []
	func _ready() -> void: pass
	func cancel_pending() -> void: pass
	func enqueue_transcript(text: String, context: Dictionary) -> void: asked.append({"text": text, "context": context})

class Interpreter extends Node:
	func cancel_pending() -> void: pass

class Host extends "res://scripts/main.gd":
	func _ready() -> void: set_process(false)
	func _process(_delta: float) -> void: pass
	func _toast(_text: String) -> void: pass
	func _show_reply(_text: String, _source: String = "") -> void: pass
	func _on_tracking_status(_status: String) -> void: pass
	func _on_service_status(_status: String) -> void: pass
	func _clear_training_session() -> void: _last_coach_step = ""

func run() -> Array[String]:
	failures.clear()
	# 1. The safety check's head turn: 25 degrees each way now counts.
	var scan := NaretHeadScan.new()
	scan.update(Vector3.FORWARD)
	scan.update(Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(25)))
	scan.update(Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(-25)))
	check(scan.done(), "a 25 degree turn to each side completes the look-around")
	var small := NaretHeadScan.new()
	small.update(Vector3.FORWARD)
	small.update(Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(10)))
	small.update(Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(-10)))
	check(not small.done(), "a 10 degree wobble is not a look-around")

	var tree := Engine.get_main_loop() as SceneTree
	var host = load("res://scenes/main.tscn").instantiate()
	host.set_script(Host)
	tree.root.add_child(host)
	# 2. The instructor's name card.
	for lang in ["de", "pl", "en"]:
		check(host.NAME_TAGS.Instructor.name[lang] == "NARET Instructor", "instructor card in " + lang)

	host.xr = NaretOpenXRSetup.new()
	host.xr.active = false
	host.scenario = NaretScenario.new()
	host.add_child(host.scenario)
	var audio := Audio.new()
	host.audio_manager = audio
	host.add_child(audio)
	var llm := LLM.new()
	host.llm = llm
	host.add_child(llm)
	host.observation_interpreter = Interpreter.new()
	host.add_child(host.observation_interpreter)
	host._language = "en"
	host.scenario.start()
	for action in ["begin_check", "check_responsiveness", "call_emergency", "check_breathing"]:
		host.scenario.submit_action(action)
	check(host.scenario.state == NaretScenario.State.CPR, "in CPR (state %s)" % host.scenario.get_state_name())

	# 3. After the call the dispatcher leads: she answers questions, and a generated answer
	# that only repeats the instruction is not spoken.
	host._dispatcher_step = 2
	check(host._guide_speaker() == "dispatcher", "the dispatcher leads the compressions")
	host._queue_coach_question("what do I do now?")
	check(not llm.asked.is_empty() and llm.asked.back().context.speaker == "dispatcher", "help questions during CPR go to the dispatcher")
	var system: String = NaretLLMOrchestrator.build_messages("what now", {"speaker": "dispatcher"}, "en")[0].content
	check(system.contains("emergency dispatcher") and not system.contains("Passantin"), "the dispatcher has her own role, not the witness's")
	var step := NaretTrainingCoach.step(host.scenario)
	audio.lines.clear()
	host._on_reply({"speaker": "dispatcher", "next_step": step, "text": "Start chest compressions. Place your hands in the middle of the chest, on the green box.", "language": "en"})
	check(audio.lines.is_empty(), "an answer repeating the compression instruction is dropped, got %s" % [audio.lines])
	host._on_reply({"speaker": "dispatcher", "next_step": step, "text": "You are doing well, keep the rhythm: about two per second.", "language": "en"})
	check(audio.lines.size() == 1 and audio.lines[0].speaker == "dispatcher", "a real answer is spoken by the dispatcher, got %s" % [audio.lines])

	# 6. "I'm tired, take over" before the crew is there: the training goes on.
	audio.lines.clear()
	host._on_action("handover", {"source": "speech"})
	check(host.scenario.state == NaretScenario.State.CPR, "an early handover request does not end the training (state %s)" % host.scenario.get_state_name())
	# 26 Nov 2026: no spoken "keep going" any more; the request is simply ignored.
	check(audio.lines.is_empty(), "an early handover request is ignored silently, got %s" % [audio.lines])
	host._ems_state = 2
	host._on_action("handover", {"source": "ems"})
	check(host.scenario.state == NaretScenario.State.RECOVERY, "with the crew there the handover ends the training")

	# 7. "Is it safe?" comes only after a quiet while once the instructor has finished, even if
	# the look-around was complete during his question (19 Nov 2026).
	host._ems_state = 0
	host.scenario.start()
	host.head_scan.reset()
	host.head_scan.update(Vector3.FORWARD)
	host.head_scan.update(Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(30)))
	host.head_scan.update(Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(-30)))
	var now := Time.get_ticks_msec()
	host._safety_asked = true
	host._safety_asked_ms = now - 20000
	host._scan_done_ms = now - 20000
	host._answer_hinted = false
	host._voice_end_ms = now - 2000
	audio.lines.clear()
	host._safety_hints()
	check(audio.lines.is_empty(), "2 s after the instructor finished: no 'is it safe?' yet")
	host._voice_end_ms = now - 9000
	audio.recording = true
	host._safety_hints()
	check(audio.lines.is_empty(), "not while the trainee is speaking")
	audio.recording = false
	host._safety_hints()
	check(audio.lines.size() == 1 and audio.lines[0].text == NaretLanguage.text("coach.tell_if_safe", "en"), "after 8 quiet seconds the question comes, got %s" % [audio.lines])
	host.xr.free()
	host.free()

	# 4. The AED helper never crosses the patient, and comes to the chest from his own side.
	var patient: NaretMannequin = load("res://scenes/mannequin.tscn").instantiate()
	tree.root.add_child(patient)
	var helper: NaretBystander = load("res://scenes/bystander_male.tscn").instantiate()
	tree.root.add_child(helper)
	helper.patient = patient
	helper.set_process(false)
	var feet_side := patient.to_global(Vector3(0.9, 0, 1.30))
	var other_side := patient.to_global(Vector3(-0.9, 0, 1.30))
	helper.global_position = feet_side
	var route: Array[Vector3] = helper._around_patient(feet_side, other_side)
	check(not route.is_empty(), "from one side to the other, level with the feet, he goes round them")
	for point in route:
		var local := patient.to_local(point)
		check(local.z > 1.55 or local.z < -0.75 or absf(local.x) > 0.55, "every waypoint is off the body, got %s" % [local])
	var chest_spot := patient.to_global(Vector3(0.40, 0, 0))
	var near_route: Array[Vector3] = helper._around_patient(patient.to_global(Vector3(1.0, 0, 0.7)), chest_spot)
	check(near_route.is_empty(), "to his place beside the chest from the same side: straight there, no walk round the head or feet")
	# Beside his goal the patient is still solid: he stops at the body's edge.
	helper.global_position = patient.to_global(Vector3(0.9, 0, 0))
	helper.obstacles = func(): return [{"point": Vector2(patient.global_position.x, patient.global_position.z), "radius": 0.28, "patient": true}]
	helper.walk_to(patient.to_global(Vector3(0.20, 0, 0)))
	for i in 300:
		if not helper.is_walking(): break
		helper._walk(0.02)
	var gap := Vector2(helper.global_position.x - patient.global_position.x, helper.global_position.z - patient.global_position.z).length()
	check(gap >= NaretBystander.PATIENT_SOLID_M - 0.02, "he never comes onto the patient, even with a goal on the body (%.2f m from the middle line)" % gap)
	helper.free()
	patient.free()
	return failures
