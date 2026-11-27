extends "res://tests/suite.gd"
## 20 Nov 2026 (user: "review the entire flow against the agreed teaching protocol: the order
## of steps, instructor dialogue, action detection, response timing, and every menu
## combination ... different wording and actions performed before or after speaking").
##
## The whole training, from Start to the handover, through the app's real handlers
## (main._on_action / _on_transcript / _on_event), for every menu combination: Situation A
## (alone, no AED) and B (helpers, AED), each with and without ventilation, in English,
## German and Polish wordings. Checked against the team's protocol (issue #1 "XR-Szenario 1:
## Ablauf, Gates und Begleitfigur"): who says what at which step, in which order, and that
## nobody says a step's instruction at the wrong moment.
## Not covered here (they need the headset): hand tracking itself, the real microphone, the
## timing of recorded voices, and Marek's walk (tests/test_marek_answer_first.gd and
## test_aed_helper_integration.gd play his errand).

const Speech = preload("res://scripts/scenario/spoken_observation.gd")
const ShoulderCheck = preload("res://scripts/tracking/shoulder_check.gd")

class Audio extends NaretAudioManager:
	var lines: Array = []
	func _ready() -> void: pass
	func set_listening(value: bool) -> void: listening = value
	func set_language(value: String) -> void: language = value
	func stop_speech() -> void: pass
	func is_speaking() -> bool: return false
	func has_line(_text: String) -> bool: return false
	func speak(text: String, _lang: String = "pl", key: String = "calm", speaker: String = "bystander", _keep: bool = false) -> void:
		lines.append({"text": text, "speaker": speaker, "key": key})
	func speak_urgent(text: String, _lang: String, key: String, speaker: String) -> void:
		lines.append({"text": text, "speaker": speaker, "key": key})

class LLM extends NaretLLMOrchestrator:
	var asked: Array = []
	func _ready() -> void: pass
	func cancel_pending() -> void: pass
	func enqueue_transcript(text: String, context: Dictionary) -> void: asked.append({"text": text, "speaker": context.get("speaker", "")})

class Interpreter extends Node:
	var asked: Array = []
	func cancel_pending() -> void: pass
	func interpret(text: String, _language: String, _context := "") -> void: asked.append(text)

## CCBM as it answers a clear spoken report: the action goes back to main as "speech".
class Ccbm extends Node:
	var host: Node
	## The two tasks (112, AED) must not wait for the step model: its answer comes later and
	## is void when another step is accepted meanwhile (headset 21 Nov 2026).
	var tasks_via_model := 0
	func observe_action(action: String) -> bool:
		if action in ["call_emergency", "request_aed"]:
			tasks_via_model += 1
			return true # as on the headset: no answer in this moment
		host._on_action(action, {"source": "speech"})
		return true
	func observe_speech(_text: String) -> bool: return false
	func observe_accepted(_event: Dictionary) -> void: pass
	func observe_breath_pair() -> void:
		for i in 2: host._on_action("ventilation", {"source": "speech"})

class Host extends "res://scripts/main.gd":
	## As on the headset with tracked hands: the shoulder tap and the head tilt are required.
	var gates := true
	func _ready() -> void: set_process(false)
	func _process(_delta: float) -> void: pass
	func _toast(_text: String) -> void: pass
	func _show_reply(_text: String, _source: String = "") -> void: pass
	func _on_tracking_status(_status: String) -> void: pass
	func _on_service_status(_status: String) -> void: pass
	func _show_park() -> void: pass
	func _record_speech_status(_status: String) -> void: pass
	func _dialogue_line(_speaker: String, _text: String) -> void: pass
	func _play_phone_ring() -> void: pass
	func _phone_on_speaker() -> void: pass
	func _shoulder_gate_active() -> bool: return gates
	func _face_gate_active() -> bool: return gates
	func _bvm_gate_active() -> bool: return false
	func _head_scan_gate_active() -> bool: return gates

var host
var audio: Audio
## Every line said in any training: "language|speaker|text|clip key".
var _spoken := {}
var tag := ""

func _text(key: String) -> String:
	return NaretLanguage.text(key, host._language)

func _step_text(key: String) -> String:
	return NaretTrainingCoach.instruction(key, host._language)

func _said(speaker: String, text: String, from: int = 0) -> bool:
	for index in range(from, audio.lines.size()):
		if audio.lines[index].text == text and (speaker.is_empty() or audio.lines[index].speaker == speaker): return true
	return false

func _by(speaker: String, from: int = 0) -> Array:
	var found: Array = []
	for index in range(from, audio.lines.size()):
		if audio.lines[index].speaker == speaker: found.append(audio.lines[index].text)
	return found

func _look_around() -> void:
	for degrees in [0.0, 50.0, -50.0, 0.0]:
		host.xr_camera.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(degrees)), Vector3(0, 1.6, 0))
		host._update_head_scan()

func _tap_shoulders() -> void:
	host.interaction.shoulder_check.active = true
	for i in 60: host.interaction.shoulder_check.observe([ShoulderCheck.zone_centre(1), null], 0.02)

func _check_breathing_by_hand() -> void:
	host.interaction.head_tilt_played = true
	host.interaction.face_check.active = true
	for i in 40: host.interaction.face_check.observe(Vector3(0.0, 0.2, 0.0), 0.02)

func _press(count: int) -> void:
	for i in count: host._on_action("compression", {"source": "hand_tracking", "measurement_verified": false, "rate_bpm": 110.0})

## The dispatcher picks up (in the app: a timer after the call, once nobody speaks).
func _dispatcher_picks_up() -> void:
	host._dispatcher_say("answer")
	host._dispatcher_asked = true

const WORDS := {
	"en": {
		"state_safety": "First, I'll check the surroundings.", "safe": "Yes, it is safe",
		"no_response": "He is not responding", "no": "No", "yes": "Yes",
		"call": "You in the red jacket, please call 112!", "aed": "You with the blue backpack, get the defibrillator!",
		"both_call_first": "No, please call 112 and could you please bring the defibrillator?", "both_aed_first": "You, fetch the defibrillator, and you, call one one two.",
		"early_both": "He is not responding. Call 112 and get the defibrillator!",
		"short": "Hello", "what_where": "A man collapsed and does not respond, we are in the park.",
		"not_breathing": "He is not breathing normally", "two_breaths": "I have given two breaths",
	},
	"de": {
		"state_safety": "Zuerst schaue ich, ob die Umgebung sicher ist.", "safe": "Ja, es ist sicher",
		"no_response": "Er reagiert nicht", "no": "Nein", "yes": "Ja",
		"call": "Du mit der roten Jacke, ruf bitte die 112 an!", "aed": "Du mit dem blauen Rucksack, hol den Defibrillator!",
		"both_call_first": "Du, ruf die 112 an, und du, hol bitte den AED.", "both_aed_first": "Du, hol den Defibrillator, und du, ruf den Notruf.",
		"early_both": "Er reagiert nicht. Ruf die 112 an und hol den Defibrillator!",
		"short": "Hallo", "what_where": "Ein Mann ist zusammengebrochen und reagiert nicht, wir sind im Park.",
		"not_breathing": "Er atmet nicht normal", "two_breaths": "Ich habe zweimal beatmet",
	},
	"pl": {
		"state_safety": "Najpierw sprawdzam otoczenie.", "safe": "Tak, jest bezpiecznie",
		"no_response": "On nie reaguje", "no": "Nie", "yes": "Tak",
		"call": "Pani w czerwonej kurtce, proszę zadzwonić pod 112!", "aed": "Pan z niebieskim plecakiem, proszę przynieść defibrylator!",
		"both_call_first": "Proszę zadzwonić pod 112, a pan niech przyniesie AED.", "both_aed_first": "Proszę przynieść defibrylator, a pani niech zadzwoni pod 112.",
		"early_both": "On nie reaguje. Zadzwoń pod 112 i przynieś defibrylator!",
		"short": "Halo", "what_where": "Mężczyzna upadł i nie reaguje, jesteśmy w parku.",
		"not_breathing": "On nie oddycha prawidłowo", "two_breaths": "Wykonałem dwa oddechy",
	},
}

## One training from Start to the handover. `variant` chooses the order of saying and doing
## and the wording of the two tasks (0..3).
func _train(language: String, situation: String, breaths: String, variant: int, first: bool) -> void:
	var words: Dictionary = WORDS[language]
	tag = "%s %s/%s v%d: " % [language, situation, "breaths" if breaths == "yes" else "no-breaths", variant]
	host._menu_choice_ms.clear()
	host._set_language(language)
	host._menu_setup("situation", situation)
	host._menu_setup("breaths", breaths)
	audio.lines.clear()
	host.interaction.shoulder_check.reset()
	host.interaction.face_check.reset()
	host.interaction.head_tilt_played = false
	host._on_action("start" if first else "restart")
	host.xr_camera.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	var scenario: NaretScenario = host.scenario
	host._announce_coach_step()
	check(scenario.state == NaretScenario.State.INTRO and _said("instructor", _step_text("safety")), tag + "2. the instructor asks what to do first")

	# 2. Safety: say it and look, in either order; then "is it safe?" and yes.
	if variant % 2 == 0:
		host._on_transcript(words.state_safety)
		check(not _said("instructor", _text("coach.tell_if_safe")), tag + "2. said but not looked yet: no question yet")
		_look_around()
	else:
		_look_around()
		host._on_transcript(words.state_safety)
	check(_said("instructor", _text("coach.tell_if_safe")) and scenario.state == NaretScenario.State.INTRO, tag + "2. said and looked (either order): 'is it safe?'")
	host._on_transcript(words.safe)
	check(scenario.state == NaretScenario.State.CHECK_PATIENT, tag + "2. 'safe' goes on to the response check (state %s)" % scenario.get_state_name())
	check(_said("instructor", _step_text("response")), tag + "3. the instructor asks to check the response")

	# 3. Response: the report counts only with the shoulder tap, in either order.
	var mark := audio.lines.size()
	var early := situation == "B" and variant == 3
	if variant % 2 == 0:
		host._on_transcript(words.early_both if early else words.no_response)
		check(scenario.state == NaretScenario.State.CHECK_PATIENT and _said("instructor", _text("error.shoulders_not_seen"), mark), tag + "3. report without the tap: asked to tap, got %s" % [_by("instructor", mark)])
		# The report is remembered: with the tap the step goes on, nothing is asked again.
		check(host._response_reported, tag + "3. the report is kept while the tap is missing")
		host._report_hinted = false
		host._voice_end_ms = -100000
		host._response_asked = true
		host._response_asked_ms = -100000
		host._update_response_hint()
		check(not _said("instructor", _text("coach.report_response"), mark), tag + "3. 'Does he respond?' is NOT asked after the trainee has said it")
		_tap_shoulders()
		host._update_remembered_reports()
		check(scenario.state == NaretScenario.State.CALL_HELP and not _said("instructor", _text("coach.tap_seen_ask"), mark), tag + "3. reported before the tap: on to the next step, no question, got %s" % [_by("instructor", mark)])
	else:
		# The user's exact sequence (21 Nov 2026): the tap is seen -> "I saw you tap their
		# shoulders. Are they responding? Please say yes or no." -> the answer.
		_tap_shoulders()
		host._response_asked = true
		host._response_asked_ms = -100000
		host._voice_end_ms = -100000
		host._update_response_hint()
		check(_by("instructor", mark).is_empty() and scenario.state == NaretScenario.State.CHECK_PATIENT, tag + "3. while the hands are still tapping: nothing yet")
		host._shoulders_seen_ms = Time.get_ticks_msec() - host.TAP_QUESTION_DELAY_MS - 10
		host._update_response_hint()
		check(_by("instructor", mark) == [_text("coach.tap_seen_ask")], tag + "3. the tap is seen: 'Is the person responding? Please say yes or no.', got %s" % [_by("instructor", mark)])
		for i in 3: host._update_response_hint()
		check(_by("instructor", mark).size() == 1 and scenario.state == NaretScenario.State.CHECK_PATIENT, tag + "3. asked once; he waits for the answer")
		if variant == 1:
			# "Yes" is corrected: this patient does not respond. The question stays open.
			host._on_transcript(words.yes)
			check(_said("instructor", _text("coach.patient_unresponsive"), mark) and scenario.state == NaretScenario.State.CHECK_PATIENT, tag + "3. 'yes' is corrected and the step stays")
			mark = audio.lines.size()
		host._on_transcript(words.early_both if early else words.no) # "No" answers his question
	check(scenario.state == NaretScenario.State.CALL_HELP, tag + "3. tap and report (either order): on to the call (state %s)" % scenario.get_state_name())
	check(not _said("", _text("coach.patient_unresponsive"), mark), tag + "3. 'not responding' is never corrected as 'responding'")

	# 4. Call for help.
	mark = audio.lines.size()
	var call_text := _step_text("call_alone" if situation == "A" else "call_aed")
	if situation == "A":
		check(_said("instructor", call_text), tag + "4. alone: call 112 yourself on the phone")
		host._on_action("call_emergency", {"source": "phone"})
	elif early:
		host._take_early_call() # deferred in the app
		check(not _said("instructor", call_text) and not _said("instructor", _step_text("call")), tag + "4. both tasks were given early: the instructor does not ask for them again")
	else:
		check(_said("instructor", call_text), tag + "4. helpers and AED: the instructor asks for BOTH tasks, got %s" % [_by("instructor", mark - 1)])
		match variant:
			0:
				host._on_transcript(words.call)
				check(scenario.emergency_called and not scenario.aed_requested, tag + "4. the call is taken from '%s'" % words.call)
				host._on_transcript(words.aed)
			1:
				host._on_transcript(words.aed)
				check(scenario.aed_requested and not scenario.emergency_called, tag + "4. the AED is taken from '%s'" % words.aed)
				host._on_transcript(words.call)
			2:
				host._on_transcript(words.both_call_first)
			_:
				host._on_transcript(words.both_aed_first)
	check(scenario.emergency_called, tag + "4. 112 is called")
	if situation == "B":
		check(scenario.aed_requested, tag + "4. somebody is sent for the AED")
		check(_said("bystander", _text("anna.calling_112"), mark), tag + "4. Anna says she is calling")
		check(not _said("instructor", _text("coach.who_gets_aed"), mark) and not _said("instructor", _text("coach.who_calls_112"), mark), tag + "4. no 'who gets the AED?' / 'who calls?' after both were asked")
	check(host._dispatcher_step == 1, tag + "4. the emergency call is connecting")
	# While it connects nobody gives the breathing instruction, whatever is said.
	var after_call := audio.lines.size()
	host._on_transcript(words.short)
	check(_by("instructor", after_call).is_empty() and _by("dispatcher", after_call).is_empty(), tag + "4. while the phone rings an unclear word gets no step instruction, got %s" % [audio.lines.slice(after_call)])
	_dispatcher_picks_up()
	check(_said("dispatcher", host.DISPATCHER.answer[language], after_call), tag + "4. the dispatcher asks what happened and where")
	host._on_transcript(words.short)
	check(_said("dispatcher", host.DISPATCHER.again[language], after_call) and host._dispatcher_step == 1, tag + "4. a one-word answer: SHE asks again (not the instructor)")
	host._on_transcript(words.what_where)
	check(host._dispatcher_step == 2 and _said("dispatcher", host.DISPATCHER.speaker[language], after_call), tag + "4. what and where: she stays on the line")
	check(_said("dispatcher", _step_text("dispatcher_breathing"), after_call), tag + "5. the DISPATCHER asks for the breathing check")
	check(_by("instructor", after_call).is_empty(), tag + "5. the instructor says nothing during the call, got %s" % [_by("instructor", after_call)])

	# 5. Breathing: head tilt and ear at the mouth, then the report.
	mark = audio.lines.size()
	if variant % 2 == 0:
		host._on_transcript(words.not_breathing)
		check(scenario.state == NaretScenario.State.CALL_HELP and _said("dispatcher", _text("coach.tilt_head"), mark), tag + "5. report without the head tilt: the dispatcher asks for it, got %s" % [audio.lines.slice(mark)])
		_check_breathing_by_hand()
		host._on_transcript(words.not_breathing)
	else:
		_check_breathing_by_hand()
		host._on_transcript(words.not_breathing)
	check(scenario.state == NaretScenario.State.CPR, tag + "5. tilt, ear at the mouth and report: on to CPR (state %s)" % scenario.get_state_name())
	var cpr_text := _step_text("dispatcher_compression_only" if breaths == "no" else "dispatcher_compressions")
	check(_said("dispatcher", cpr_text, mark), tag + "6. the dispatcher says to start compressions (%s)" % ("without breaths" if breaths == "no" else "30:2"))

	# 6. Compressions, and the breaths when chosen.
	mark = audio.lines.size()
	_press(30)
	if breaths == "yes":
		check(_said("dispatcher", _step_text("dispatcher_breaths"), mark), tag + "6. after 30: the dispatcher asks for two breaths")
		host._on_transcript(words.two_breaths)
		check(scenario.cycles == 1 and _said("dispatcher", _step_text("dispatcher_resume_compressions"), mark), tag + "6. two breaths: next 30 (cycles %d)" % scenario.cycles)
	else:
		check(scenario.cycle_ventilations == 0 and not _said("", _step_text("dispatcher_breaths"), mark) and not _said("", _step_text("breaths"), mark), tag + "6. without ventilation nobody asks for breaths")
		_press(10)
		check(scenario.compressions == 40, tag + "6. compressions go on without a 30 gate")
	check(_by("instructor", mark).is_empty(), tag + "6. the instructor leaves CPR to the dispatcher, got %s" % [_by("instructor", mark)])

	# 7. AED (Situation B only).
	mark = audio.lines.size()
	if situation == "A":
		check(not "request_aed" in scenario.get_available_actions() and not scenario.aed_available, tag + "7. alone: no AED in this training")
	else:
		scenario.aed_available = true # Marek has set it down
		host._announce_coach_step()
		check(scenario.submit_action("attach_aed"), tag + "7. the pads go on")
		for action in ["clear_patient", "analyze_rhythm", "clear_patient", "shock", "resume_cpr"]:
			if scenario.state != NaretScenario.State.AED: break
			if action in scenario.get_available_actions(): scenario.submit_action(action)
		check(scenario.state == NaretScenario.State.CPR, tag + "7. after the AED's decision CPR goes on (state %s, actions %s)" % [scenario.get_state_name(), scenario.get_available_actions()])
		_press(5)
		check(not _said("instructor", _step_text("breathing"), mark) and not _said("instructor", _step_text("call_aed"), mark), tag + "7. no earlier step's instruction comes back")

	# 8. Handover.
	check("handover" in scenario.get_available_actions(), tag + "8. the handover is possible")
	scenario.submit_action("handover")
	check(scenario.state == NaretScenario.State.RECOVERY, tag + "8. the training ends with the handover (state %s)" % scenario.get_state_name())
	for line: Dictionary in audio.lines:
		_spoken[language + "|" + str(line.speaker) + "|" + str(line.text) + "|" + str(line.key)] = true
	if OS.has_environment("NARET_FLOW_DUMP"):
		for line: Dictionary in audio.lines: print("FLOWLINE %s| %-10s | %s" % [tag, line.speaker, str(line.text).left(150)])
	# The whole training: the instructor never says the breathing or compression instructions
	# (after the call they are the dispatcher's), and no line is said twice in a row.
	for own: String in ["breathing", "compressions", "compression_only", "breaths", "resume_compressions"]:
		check(not _said("instructor", _step_text(own)), tag + "the instructor never says the '%s' instruction: it is the dispatcher's" % own)
	for index in range(1, audio.lines.size()):
		check(audio.lines[index].text != audio.lines[index - 1].text or audio.lines[index].speaker != audio.lines[index - 1].speaker, tag + "no line twice in a row: " + str(audio.lines[index].text).left(60))

func run() -> Array[String]:
	failures.clear()
	var tree := Engine.get_main_loop() as SceneTree
	for path in ["user://test_flow_choices.cfg", "user://test_flow_calibration.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	host = load("res://scenes/main.tscn").instantiate()
	host.set_script(Host)
	tree.root.add_child(host)
	host.language_file = "user://test_flow_choices.cfg"
	host.anchor.calibration_file = "user://test_flow_calibration.cfg"
	host.xr = NaretOpenXRSetup.new()
	host.xr.active = true
	host.anchor.locked = true
	host.anchor.calibrated = true
	host.scenario = NaretScenario.new()
	host.add_child(host.scenario)
	host.scenario.event_recorded.connect(host._on_event)
	host.scenario.state_changed.connect(host._on_state_changed)
	audio = Audio.new()
	host.audio_manager = audio
	host.add_child(audio)
	host.llm = LLM.new()
	host.add_child(host.llm)
	host.observation_interpreter = Interpreter.new()
	host.add_child(host.observation_interpreter)
	var ccbm := Ccbm.new()
	ccbm.host = host
	host.ccbm = ccbm
	host.add_child(ccbm)
	host.interaction = NaretXRInteraction.new()
	if host.ekg == null:
		host.ekg = NaretEKG.new()
		host.add_child(host.ekg)
	host.director = load("res://scripts/scenario/aed_helper_director.gd").new()
	host.add_child(host.director)
	host.director.configure(host.scenario, host.get_node("Bystanders/Anna"), host.get_node("Bystanders/Marek"), host.mannequin, null)
	host.director.language = func(): return host._language
	host.director.speak = func(key, text, _lang, speaker): audio.lines.append({"text": text, "speaker": speaker, "key": key})
	host.setup.answers = {"language": "en", "mode": "own", "situation": "B", "breaths": "yes"}
	host._set_language("en")

	var first := true
	for language: String in ["en", "de", "pl"]:
		for situation: String in ["B", "A"]:
			for breaths: String in ["yes", "no"]:
				for variant in (4 if situation == "B" else 2):
					_train(language, situation, breaths, variant, first)
					first = false

	# The audio: every line said in these trainings has a recorded voice in the app, so
	# none of them waits for (or is lost with) the cloud voice.
	var voices := NaretAudioManager.new()
	tree.root.add_child(voices)
	var silent: Array[String] = []
	for entry: String in _spoken:
		var part := entry.split("|")
		var speaker := "bystander" if part[1] == "anna" else part[1]
		var recorded: bool = voices._coach_clips.get(part[0] + ":" + speaker + ":" + part[2]) is AudioStream
		if not recorded and not part[3].is_empty():
			recorded = voices._clips.get(part[0] + "/" + part[3]) is AudioStream and str(voices._clip_texts.get(part[0] + "/" + part[3], "")) == part[2]
		# Shortened on 26 Nov 2026 and waiting to be re-recorded (cloud voice until then).
		if not recorded and part[2] in [NaretTrainingCoach.instruction("dispatcher_breathing", part[0]), NaretTrainingCoach.instruction("call_aed", part[0]), NaretLanguage.text("coach.who_calls_112", part[0]), NaretLanguage.text("coach.phone_speaker", part[0]), NaretLanguage.text("coach.tap_seen_ask", part[0]), NaretLanguage.text("error.shoulders_not_seen", part[0]), NaretLanguage.text("coach.phone_tap_112", part[0]), NaretLanguage.text("coach.look_left_right", part[0]), NaretHandover.crew_line("take_over", part[0]), NaretHandover.crew_line("arrive", part[0]), NaretHandover.crew_line("arrive_aed", part[0])]: recorded = true
		if not recorded: silent.append("%s %s: %s" % [part[0], part[1], part[2].left(70)])
	voices.free()
	check(silent.is_empty(), "every spoken line has a recorded voice; without one: %s" % [silent])
	check(_spoken.size() > 40, "the trainings said %d different lines" % _spoken.size())
	check(ccbm.tasks_via_model == 0, "the 112 and AED tasks are taken directly, never through the step model (%d times)" % ccbm.tasks_via_model)
	for path in ["user://test_flow_choices.cfg", "user://test_flow_calibration.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	host.interaction.free()
	host.xr.free()
	host.free()
	return failures
